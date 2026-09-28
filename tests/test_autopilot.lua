local T = require("tests.t")
local F = require("tests.fixtures")
local physics = require("src.physics")
local autopilot = require("src.autopilot")

local DT = 1 / 60

local function lap_from(u)
    local tr = F.track1()
    local s = physics.new_ship(1, 0, u)
    local c, steps, hits = {}, 0, 0
    while s.lap < 1 and steps < 60 * 90 do
        autopilot.controls(tr, s, physics.P, c)
        physics.step(tr, s, c, DT)
        steps = steps + 1
        if s.hit then hits = hits + 1 end
    end
    return s, steps * DT, hits
end

return {
    laps_track1_cleanly = function()
        local s, secs, hits = lap_from(0)
        T.eq(s.lap, 1, "finished a lap")
        T.ok(secs > 25 and secs < 50, "lap time " .. secs)
        T.eq(hits, 0, "wall hits")
    end,
    recovers_from_either_side = function()
        for _, u in ipairs({ -8, 8 }) do
            local s, _, hits = lap_from(u)
            T.eq(s.lap, 1, "finished from u = " .. u)
            T.ok(hits <= 2, "wall hits from u = " .. u .. ": " .. hits)
        end
    end,
    steer_is_clamped = function()
        local tr = F.track1()
        local s = physics.new_ship(1, 0, 11)
        s.psi = -1
        local c = autopilot.controls(tr, s, physics.P, {})
        T.ok(c.steer >= -1 and c.steer <= 1)
        T.eq(c.thrust, true)
    end,
}
