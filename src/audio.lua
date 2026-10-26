-- Race music and the engine note. The music is the tracks in assets/music,
-- one per race in turn, looping 44.1 kHz stereo QOA through a fileplayer
-- (a fifth the size of WAV and cheaper to stream: tools/prep_audio.sh). The engine is a
-- looping sample whose rate and volume follow the player's speed
-- (src/engine.lua). A missing file means silence, not an error.
local engine = require("src.engine")

local M = {}

local sound, fs = picocalc.sound, picocalc.fs

-- track01 is left out: its master clips.
M.TRACKS = { "track02.qoa" }
M.MUSIC_VOL = 55

function M.new()
    return { music = nil, eng = nil, track = 0 }
end

-- Starts the next track, and the engine note on its first call.
function M.start_race(a)
    a.track = a.track % #M.TRACKS + 1
    if a.music then a.music:stop() end
    local path = APP_DIR .. "/assets/music/" .. M.TRACKS[a.track]
    if fs.exists(path) then
        a.music = a.music or sound.fileplayer()
        if a.music and a.music:load(path) then
            a.music:setVolume(M.MUSIC_VOL)
            a.music:play(0)
        end
    end
    if not a.eng then
        local p = APP_DIR .. "/assets/sfx/engine.wav"
        if fs.exists(p) then
            a.eng = sound.sampleplayer(p)
            if a.eng then
                a.eng:setVolume(0)
                a.eng:play(0)
            end
        end
    end
end

-- Call every frame; the engine note follows speed v (m/s), updated every
-- other frame (each update is two Lua->C calls).
function M.update(a, v, frame)
    if a.eng and frame % 2 == 0 then
        a.eng:setRate(engine.rate(v))
        a.eng:setVolume(engine.volume(v))
    end
end

-- The results page: music keeps playing, the engine goes quiet.
function M.quiet(a)
    if a.eng then a.eng:setVolume(0) end
end

-- Whether the music and the engine note are playing, and the track number
-- (telemetry).
function M.playing(a)
    return (a.music and a.music:isPlaying()) == true, (a.eng and a.eng:isPlaying()) == true, a.track
end

function M.stop(a)
    if a.music then a.music:stop() end
    if a.eng then a.eng:stop() end
end

return M
