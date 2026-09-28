-- The greybox race: one ship on track 1, a chase camera, a HUD, a locked
-- 30 fps loop. /data/<APP_ID>/dev.json switches on test modes:
--   autolap = true   the autopilot drives; the game exits after `laps` laps
--                    (default 1) and writes perf.json (the hardware gate)
--   bench_audio = true  play APP_DIR/bench/music.wav and bench/sfx1-6.wav
--   telemetry = true    write telemetry.json every 15 frames
local trackgen = require("src.trackgen")
local physics = require("src.physics")
local autopilot = require("src.autopilot")
local camera = require("src.camera")
local perflog = require("src.perflog")
local render = require("src.render")
local hud = require("src.hud")
local controls = require("src.controls")

local M = {}

local pc = picocalc
local disp, input, sys, perf, fs, json = pc.display, pc.input, pc.sys, pc.perf, pc.fs, pc.json

M.SEG_LEN = 8
M.FPS = 30
M.SUBSTEPS = 2
M.WARMUP = 60         -- frames left out of the perf log (loading, spin-up)
M.LOG_FRAMES = 30 * 600 -- ten minutes of frames

local DATA = "/data/" .. APP_ID

-- dev.json as a table; a missing or malformed file means no test modes.
local function read_dev()
    local text = fs.readFile(DATA .. "/dev.json")
    if not text then return {} end
    local ok, v = pcall(json.decode, text)
    if ok and type(v) == "table" then return v end
    sys.log("dev.json ignored: not a JSON object")
    return {}
end

local function write_json(name, value)
    local f = fs.open(DATA .. "/" .. name, "w")
    if not f then
        sys.log("cannot write " .. name)
        return
    end
    fs.write(f, json.encode(value))
    fs.close(f)
end

-- Music plus six looping voices, for the audio-headroom measurement. The
-- music is a WAV streamed by a fileplayer: MP3 decoding on Core 1 contends
-- with the game's core for the shared flash/PSRAM cache (PicoDeck's
-- docs/API-Audio-and-Sound.md).
local function start_bench_audio()
    local dir = APP_DIR .. "/bench"
    local music = pc.sound.fileplayer()
    if not (music and music:load(dir .. "/music.wav")) then
        sys.log("bench audio: no " .. dir .. "/music.wav")
        return nil
    end
    music:setVolume(50)
    music:play(0)
    local voices = {}
    for i = 1, 6 do
        local p = pc.sound.sampleplayer(dir .. "/sfx" .. i .. ".wav")
        if p then
            p:setVolume(30)
            p:play(0)
            voices[#voices + 1] = p
        end
    end
    return { music = music, voices = voices }
end

local function loading(text)
    disp.clear(disp.BLACK)
    disp.drawText(160 - disp.textWidth(text) // 2, 150, text, disp.WHITE)
    disp.flush()
end

function M.run()
    collectgarbage("generational")
    loading("Building track...")
    local dev = read_dev()
    local tr = trackgen.generate(require("data.track1"), M.SEG_LEN)
    local scene = render.init(tr)
    local audio = dev.bench_audio == true and start_bench_audio() or nil

    local auto = dev.autolap == true
    local laps = math.max(1, math.tointeger(dev.laps) or (auto and 1 or 3))
    local ship, cam, ctl = physics.new_ship(), camera.new(), {}
    local log = perflog.new(M.LOG_FRAMES)
    local g = { geom = 0, raster = 0, drawn = 0, drawn_max = 0, tris_max = 0, n = 0 }
    local lap_times, best_ms, last_ms = {}, nil, nil
    local hud_state = { v = 0, lap = 1, laps = laps, lap_ms = 0, fps = 0, work_us = 0, drawn = 0 }
    local dt = 1 / M.FPS
    local now = sys.getTimeUs
    local frame, lap_start, prev_t0, work = 0, 0, nil, 0
    local st = {} -- gfx3d.getStats fills this table every frame

    input.clearState()
    perf.setTargetFPS(M.FPS)
    while true do
        local t0 = now()
        perf.beginFrame()
        input.update()
        if input.getButtonsPressed() & input.BTN_ESC ~= 0 then break end

        if auto then autopilot.controls(tr, ship, physics.P, ctl)
        else controls.read(ctl, true) end
        local lap_before = ship.lap
        for _ = 1, M.SUBSTEPS do physics.step(tr, ship, ctl, dt / M.SUBSTEPS) end
        frame = frame + 1
        if ship.lap > lap_before then
            last_ms = (frame - lap_start) * 1000 // M.FPS
            lap_times[#lap_times + 1] = last_ms
            if not best_ms or last_ms < best_ms then best_ms = last_ms end
            lap_start = frame
        end
        if auto and ship.lap >= laps then break end

        camera.update(cam, tr, ship, dt)
        render.draw(scene, tr, ship, cam)
        st = pc.gfx3d.getStats(st)
        hud_state.v, hud_state.lap = ship.v, math.min(ship.lap + 1, laps)
        hud_state.lap_ms = (frame - lap_start) * 1000 // M.FPS
        hud_state.last_ms, hud_state.best_ms = last_ms, best_ms
        hud_state.fps = math.floor(perf.getFPS() + 0.5)
        hud_state.work_us, hud_state.drawn = work, st.drawn
        hud.draw(hud_state)

        local t1 = now()
        work = t1 - t0 -- integer subtraction: right across the 32-bit wrap
        if prev_t0 and frame > M.WARMUP then
            perflog.add(log, work, t0 - prev_t0)
            g.geom, g.raster, g.drawn = g.geom + st.us_geom, g.raster + st.us_raster, g.drawn + st.drawn
            g.drawn_max = math.max(g.drawn_max, st.drawn)
            g.tris_max = math.max(g.tris_max, st.tris_in)
            g.n = g.n + 1
        end
        prev_t0 = t0
        if dev.telemetry == true and frame % 15 == 0 then
            write_json("telemetry.json", { frame = frame, seg = ship.seg, t = ship.t, u = ship.u,
                v = ship.v, h = ship.h, psi = ship.psi, lap = ship.lap })
        end
        perf.endFrame()
        disp.flush()
    end
    perf.setTargetFPS(0)
    if audio then
        audio.music:stop()
        for _, p in ipairs(audio.voices) do p:stop() end
    end
    if auto then
        local out = { laps = ship.lap, lap_ms = lap_times, frames = frame,
            bench_audio = audio ~= nil }
        if log.n > 0 then
            local s = perflog.summary(log)
            out.logged, out.missed, out.work_us, out.interval_us = s.frames, s.missed, s.work_us, s.interval_us
            out.gfx3d = { us_geom_avg = g.geom // g.n, us_raster_avg = g.raster // g.n,
                drawn_avg = g.drawn // g.n, drawn_max = g.drawn_max, tris_in_max = g.tris_max }
        end
        write_json("perf.json", out)
    end
end

return M
