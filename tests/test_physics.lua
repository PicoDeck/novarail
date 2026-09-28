local T = require("tests.t")
local F = require("tests.fixtures")
local physics = require("src.physics")
local P = physics.P

local circle = F.circle(1000, 16)
local DT = 1 / 60

local function run(tr, s, c, seconds, each)
    for _ = 1, math.floor(seconds / DT + 0.5) do
        physics.step(tr, s, c, DT)
        if each then each(s) end
    end
    return s
end

local THRUST = { steer = 0, thrust = true }

return {
    accelerates_to_top_speed = function()
        local s = run(circle, physics.new_ship(), THRUST, 5)
        T.ok(s.v > 40, "5 s: " .. s.v)
        run(circle, s, THRUST, 40)
        T.ok(s.v > 55 and s.v < 64, "top speed " .. s.v)
    end,
    brakes = function()
        local s = run(circle, physics.new_ship(), THRUST, 20)
        run(circle, s, { steer = 0, brake = true }, 2)
        T.ok(s.v < 15, "after 2 s braking: " .. s.v)
    end,
    never_reverses = function()
        local s = run(circle, physics.new_ship(), { steer = 0, brake = true }, 2)
        T.eq(s.v, 0)
    end,
    hovers_at_rest = function()
        local s = run(circle, physics.new_ship(), { steer = 0 }, 3)
        T.near(s.h, P.HOVER_H - P.G / P.HOVER_K, 0.02, "hover height")
        T.eq(s.air, false)
    end,
    steering_right_moves_right = function()
        local s = physics.new_ship()
        s.v = 30
        run(circle, s, { steer = 1 }, 0.5)
        T.ok(s.psi > 0 and s.u > 0, "psi " .. s.psi .. " u " .. s.u)
    end,
    heading_eases_back_without_steering = function()
        local s = physics.new_ship()
        s.v, s.psi = 30, 0.5
        run(circle, s, { steer = 0 }, 3)
        T.ok(math.abs(s.psi) < 0.2, "psi " .. s.psi)
    end,
    wall_clamps_and_slows = function()
        local s = physics.new_ship()
        s.v = 40
        local hits = 0
        run(circle, s, { steer = 1 }, 3, function(st) if st.hit then hits = hits + 1 end end)
        T.ok(hits > 0, "hit the wall")
        T.near(s.u, circle.w[s.seg] * 0.5 - P.SHIP_HALF_W, 0.05, "clamped at the wall")
        local free = physics.new_ship()
        free.v = 40
        run(circle, free, { steer = 0 }, 3)
        T.ok(s.v < free.v, "scraping costs speed")
    end,
    airbrake_turns_and_drags = function()
        local a, b = physics.new_ship(), physics.new_ship()
        a.v, b.v = 40, 40
        run(circle, a, { steer = 0, abR = true }, 1)
        run(circle, b, { steer = 0 }, 1)
        T.ok(a.psi > b.psi, "right airbrake turns right")
        T.ok(a.v < b.v, "airbrake drags")
    end,
    pad_kicks_once = function()
        local tr = F.track1()
        local seg
        for i = 1, tr.n do if tr.padid[i] == 1 then seg = i; break end end
        local s = physics.new_ship(seg - 1, 0.5, (tr.padlo[seg] + tr.padhi[seg]) * 0.5)
        s.v = 30
        local kicks, last, top = 0, 0, 0
        run(tr, s, { steer = 0 }, 1.5, function(st)
            if st.pad ~= 0 and st.pad ~= last then kicks = kicks + 1 end
            last, top = st.pad, math.max(top, st.v)
        end)
        T.eq(kicks, 1, "entered the pad once")
        T.ok(top > 30 + P.PAD_KICK * 0.9, "boosted: " .. top)
    end,
    counts_laps = function()
        local s = physics.new_ship(circle.n, 0.99, 0)
        s.v = 30
        physics.step(circle, s, { steer = 0 }, DT)
        T.eq(s.lap, 1); T.eq(s.laps, 1); T.eq(s.seg, 1)
        physics.step(circle, s, { steer = 0 }, DT)
        T.eq(s.laps, 0, "laps is per step")
    end,
    crest_lifts_at_speed_only = function()
        local tr = F.track1()
        local crest, best = 1, 0
        for i = 1, tr.n do if tr.py[i] > 15 and tr.ku[i] < best then best, crest = tr.ku[i], i end end
        local function peak(v)
            local s = physics.new_ship(crest - 12, 0, 0)
            s.v, s.h = v, P.HOVER_H - P.G / P.HOVER_K
            local top = 0
            for _ = 1, 90 do
                s.v = v -- hold the speed: this measures the lift alone
                physics.step(tr, s, { steer = 0 }, DT)
                top = math.max(top, s.h)
            end
            return top
        end
        T.ok(peak(80) > P.HOVER_H + 0.1, "80 m/s lifts over the crest: " .. peak(80))
        T.ok(peak(20) < P.HOVER_H + 0.05, "20 m/s stays down: " .. peak(20))
    end,
    missing_steer_means_straight = function()
        local s = physics.new_ship()
        s.v = 30
        physics.step(circle, s, { thrust = true }, DT)
        T.ok(s.psi <= 0, "no steering input: psi " .. s.psi)
    end,
}
