-- The race: the player and up to five rivals on track 1, a chase camera, a
-- HUD and a locked 30 fps loop; then the results page (A or Start races
-- again, Esc quits). /data/<APP_ID>/dev.json switches on test modes:
--   autolap = true      the AI drives the player too; the app exits at the
--                       results and writes perf.json (the hardware gate)
--   stay = true         with autolap: show the results page and wait for a key
--                       instead of exiting
--   laps = n            race length (default 3; 1 with autolap)
--   rivals = n          rival ships, 0..5 (default 5)
--   bench_sfx = true    play APP_DIR/bench/sfx1-6.wav as six looping voices
--                       over the game's music and engine (the gate's
--                       stand-in for the effects P4b and P5 add)
--   mute = true         no music and no engine note
--   telemetry = true    write telemetry.json every 15 frames (the player's
--                       ship, the race phase, the music track and whether
--                       music and engine play)
local trackgen = require("src.trackgen")
local physics = require("src.physics")
local ai = require("src.ai")
local race = require("src.race")
local collide = require("src.collide")
local camera = require("src.camera")
local perflog = require("src.perflog")
local render = require("src.render")
local hud = require("src.hud")
local results = require("src.results")
local controls = require("src.controls")
local audio = require("src.audio")

local M = {}

local pc = picocalc
local disp, input, sys, perf, fs, json = pc.display, pc.input, pc.sys, pc.perf, pc.fs, pc.json

M.SEG_LEN = 8
M.FPS = 30
M.SUBSTEPS = 2        -- physics steps per frame for the player (rivals take one)
M.WARMUP = 60         -- frames left out of the perf log (loading, spin-up)
M.LOG_FRAMES = 30 * 600 -- ten minutes of frames
-- Rival skills, ships 2..6: pole first, the strongest just ahead of the
-- player, who starts last.
M.RIVAL_SKILL = { 0.94, 0.95, 0.96, 0.97, 0.98 }
-- Each rival's offset from the racing line (m), so the pack spreads out.
M.RIVAL_LANE = { -2.5, 2.5, -1, 1, 0 }

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

-- Six looping voices over the game's own audio: the gate's stand-in for
-- the effects P4b and P5 add.
local function start_bench_sfx()
    local voices = {}
    for i = 1, 6 do
        local p = pc.sound.sampleplayer(APP_DIR .. "/bench/sfx" .. i .. ".wav")
        if p then
            p:setVolume(30)
            p:play(0)
            voices[#voices + 1] = p
        end
    end
    return voices
end

local function loading(text)
    disp.clear(disp.BLACK)
    disp.drawText(160 - disp.textWidth(text) // 2, 150, text, disp.WHITE)
    disp.flush()
end

-- The perf.json summary of a logged run. bat0 and usb0 are the battery level
-- and USB power at the start (the level reads -1 only before the first
-- reading). `audio` records what was playing at the end, so the gate can
-- tell a run with audio from a silent one.
local function summary(log, g, sec, r, ships, env, frames, bat0, usb0)
    local music, eng = false, false
    if env.sound then music, eng = audio.playing(env.sound) end
    local out = { laps = #r.times[1], lap_ms = {}, frames = frames, bench_sfx = env.bench ~= nil,
        battery = { start = bat0, finish = sys.getBattery(), usb_start = usb0,
            usb_finish = sys.isUSBPowered() },
        audio = { music = music, engine = eng, voices = env.bench and #env.bench or 0 },
        rivals = #ships - 1, results = {} }
    for k, lt in ipairs(r.times[1]) do out.lap_ms[k] = race.ms(lt) end
    for _, row in ipairs(race.results(r, r.tr, ships)) do
        out.results[#out.results + 1] = { idx = row.idx, pos = row.pos, time = row.time, dnf = row.dnf }
    end
    if log.n > 0 then
        local s = perflog.summary(log)
        out.logged, out.missed, out.late = s.frames, s.missed, s.late
        out.work_us, out.interval_us = s.work_us, s.interval_us
        out.gfx3d = { us_geom_avg = g.geom // g.n, us_raster_avg = g.raster // g.n,
            drawn_avg = g.drawn // g.n, drawn_max = g.drawn_max, tris_in_max = g.tris_max,
            overflow = g.overflow }
        out.sections = { input = sec.input // g.n, sim = sec.sim // g.n, camera = sec.camera // g.n,
            draw = sec.draw // g.n, hud = sec.hud // g.n }
    end
    return out
end

local FINISHED = {}
for p = 1, 6 do FINISHED[p] = string.format("FINISHED  P%d", p) end

-- One race, countdown to results. Returns "again" or "quit", and in autolap
-- mode the perf.json summary.
local function race_once(env)
    local tr, dev, h = env.tr, env.dev, env.hud
    local n = 1 + env.rivals
    local r, ships = race.new(tr, n, env.laps, race.PLAYER_LAST)
    r.tr = tr
    local drivers, ctl = { ai.new_driver(1, 0) }, { {} }
    for i = 2, n do
        drivers[i] = ai.new_driver(M.RIVAL_SKILL[i - 1], M.RIVAL_LANE[i - 1])
        ctl[i] = {}
    end
    local me, cam = ships[1], camera.new()
    local log = env.log -- set only with autolap
    if log then perflog.reset(log) end
    local g = { geom = 0, raster = 0, drawn = 0, drawn_max = 0, tris_max = 0, n = 0, overflow = 0 }
    local sec = { input = 0, sim = 0, camera = 0, draw = 0, hud = 0 }
    local st, hs = {}, { laps = env.laps, n = n }
    local P, dt, now = physics.P, 1 / M.FPS, sys.getTimeUs
    local sub_dt = dt / M.SUBSTEPS
    local frame, prev_t0 = 0, nil
    -- The section timers and gfx3d's stats feed only the perf log (autolap):
    -- a normal race makes none of their C calls.
    local timed = log ~= nil
    local telemetry = dev.telemetry == true
    -- no key for accelerate (unbound in Settings -> Controls): thrust on its own
    local auto_thrust = not controls.bound(pc.gamepad.PAD_A)
    local bat0 = sys.getBattery()
    local usb0 = sys.isUSBPowered()
    local begin_frame, end_frame, flush = perf.beginFrame, perf.endFrame, disp.flush
    local input_update, get_pressed, BTN_ESC = input.update, input.getButtonsPressed, input.BTN_ESC
    local get_stats = pc.gfx3d.getStats
    local step, resolve, progress, ai_controls = physics.step, collide.resolve, race.progress, ai.controls
    local line, total = env.line, tr.total
    local c1, sound = ctl[1], env.sound

    if sound then audio.start_race(sound) end
    hud.reset(h)
    input.clearState()
    perf.setTargetFPS(M.FPS)
    while true do
        local t0 = timed and now()
        begin_frame()
        input_update()
        if get_pressed() & BTN_ESC ~= 0 then
            perf.setTargetFPS(0)
            return "quit", nil
        end
        if r.phase ~= "countdown" then -- race.can_drive, without the call
            if env.auto or r.finish[1] or r.out[1] then
                ai_controls(tr, line, ships, 1, drivers[1], P, 0, c1)
            else
                controls.read(c1, auto_thrust)
                c1.thrust_scale = 1
            end
            -- Each rival re-plans every other frame (half of them per frame):
            -- the ships whose index has this frame's parity. The physics still
            -- steps all of them every frame.
            local pp = progress(tr, me)
            for i = 2 + frame % 2, n, 2 do
                local lead = (progress(tr, ships[i]) - pp) * total
                ai_controls(tr, line, ships, i, drivers[i], P, lead, ctl[i])
            end
        else
            for i = 1, n do -- on the grid: hover, no thrust
                local c = ctl[i]
                c.steer, c.thrust, c.brake, c.abL, c.abR, c.thrust_scale = 0, false, false, false, false, 1
            end
        end
        local tsim = timed and now()
        local e0, hit = me.energy, 0
        for _ = 1, M.SUBSTEPS do
            step(tr, me, c1, sub_dt)
            hit = hit + me.impact
        end
        for i = 2, n do step(tr, ships[i], ctl[i], dt) end
        local vs0 = me.vs
        resolve(tr, ships)
        local shove = me.vs - vs0
        hit = hit + (shove < 0 and -shove or shove)
        if hit > 0 then camera.jolt(cam, hit) end
        if me.energy < e0 - 0.5 then hud.flash(h) end
        race.update(r, ships)
        frame = frame + 1
        if r.phase == "results" then break end

        local tc = timed and now()
        camera.update(cam, tr, me, dt)
        local td = timed and now()
        render.draw(env.scene, tr, ships, cam)
        local te = timed and now()
        if timed then st = get_stats(st) end
        local cd = race.countdown(r)
        if cd then
            hud.countdown(h, cd)
        elseif r.finish[1] then
            hud.banner(FINISHED[race.position(r, tr, ships, 1)])
        elseif r.out[1] then
            hud.banner("OUT OF ENERGY")
        end
        hs.energy = me.energy
        if hud.text_due(h) then -- the panel's text, one frame in two
            hs.v, hs.lap, hs.pos = me.v, race.lap_of(r, ships, 1), race.position(r, tr, ships, 1)
            if r.finish[1] then hs.lap_ms = race.ms(r.finish[1])
            elseif r.phase ~= "countdown" then hs.lap_ms = race.ms(r.frame - r.lap_start[1])
            else hs.lap_ms = 0 end
            hs.last_ms, hs.best_ms = race.ms(r.last[1]), race.ms(r.best[1])
        end
        hud.draw(h, hs)
        if sound then audio.update(sound, me.v, frame) end

        if timed then
            local t1 = now()
            -- integer subtraction: right across the 32-bit wrap
            g.overflow = g.overflow + st.overflow -- every frame, warm-up included: the gate wants none
            if prev_t0 and frame > M.WARMUP then
                perflog.add(log, t1 - t0, t0 - prev_t0)
                g.geom, g.raster, g.drawn = g.geom + st.us_geom, g.raster + st.us_raster, g.drawn + st.drawn
                g.drawn_max = math.max(g.drawn_max, st.drawn)
                g.tris_max = math.max(g.tris_max, st.tris_in)
                g.n = g.n + 1
                sec.input, sec.sim, sec.camera = sec.input + (tsim - t0), sec.sim + (tc - tsim), sec.camera + (td - tc)
                sec.draw, sec.hud = sec.draw + (te - td), sec.hud + (t1 - te)
            end
            prev_t0 = t0
        end
        if telemetry and frame % 15 == 0 then
            local music, eng, track = false, false, 0
            if sound then music, eng, track = audio.playing(sound) end
            write_json("telemetry.json", { frame = frame, seg = me.seg, t = me.t, u = me.u,
                v = me.v, h = me.h, psi = me.psi, lap = me.lap, energy = me.energy, phase = r.phase,
                music = music, engine = eng, track = track })
        end
        end_frame()
        flush()
    end
    perf.setTargetFPS(0)
    if env.auto and not env.stay then return "quit", summary(log, g, sec, r, ships, env, frame, bat0, usb0) end

    if sound then audio.quiet(sound) end
    hud.reset(h)
    local res = race.results(r, tr, ships)
    for _ = 1, 2 do -- both buffers
        results.draw(res)
        disp.flush()
    end
    input.clearState()
    controls.arm_again()
    while true do
        input.update()
        if controls.again_pressed() then return "again" end
        if input.getButtonsPressed() & input.BTN_ESC ~= 0 then return "quit" end
        sys.sleep(20)
    end
end

function M.run()
    collectgarbage("generational")
    loading("Building track...")
    local dev = read_dev()
    local tr = trackgen.generate(require("data.track1"), M.SEG_LEN)
    local auto = dev.autolap == true
    local env = {
        tr = tr, dev = dev, auto = auto, stay = dev.stay == true, hud = hud.new(),
        scene = render.init(tr),
        line = ai.prepare(tr, physics.P),
        laps = math.max(1, math.tointeger(dev.laps) or (auto and 1 or 3)),
        rivals = math.min(5, math.max(0, math.tointeger(dev.rivals) or 5)),
    }
    if auto then env.log = perflog.new(M.LOG_FRAMES) end
    if dev.mute ~= true then env.sound = audio.new() end
    if dev.bench_sfx == true then env.bench = start_bench_sfx() end
    local out
    repeat
        local result, stats = race_once(env)
        out = stats
    until (auto and not env.stay) or result == "quit"
    if env.bench then
        for _, p in ipairs(env.bench) do p:stop() end
    end
    if env.sound then audio.stop(env.sound) end
    if auto and out then write_json("perf.json", out) end
end

return M
