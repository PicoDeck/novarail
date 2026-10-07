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
    grip_caps_the_turn_rate_at_speed = function()
        local slow, fast = physics.new_ship(), physics.new_ship()
        slow.v, fast.v = 10, 60
        physics.step(circle, slow, { steer = 1 }, 0.1)
        physics.step(circle, fast, { steer = 1 }, 0.1)
        -- the step slows the ship (drag) before it turns; the bend itself
        -- turns the heading back by kr * v
        local k = circle.kr[1]
        T.near(slow.psi, (P.STEER_RATE - k * slow.v) * 0.1, 1e-3, "full lock at 10 m/s")
        T.near(fast.psi, (P.A_GRIP / fast.v - k * fast.v) * 0.1, 1e-3, "grip-capped at 60 m/s")
        T.ok(fast.psi < 0.5 * P.STEER_RATE * 0.1, "well under full lock")
    end,
    too_fast_for_a_bend_runs_wide = function()
        local tight = F.circle(60, 16) -- a right-hand bend: the outside is u < 0
        local function outside_hits(v, c)
            local s = physics.new_ship(1, 0, 0)
            s.v = v
            local hits = 0
            run(tight, s, c, 2, function(st)
                st.v = v -- hold the speed: this measures the turn alone
                if st.hit and st.u < 0 then hits = hits + 1 end
            end)
            return hits
        end
        T.eq(outside_hits(40, { steer = 1 }), 0, "40 m/s holds the 60 m bend")
        T.ok(outside_hits(55, { steer = 1 }) > 0, "55 m/s runs wide into the outside wall")
    end,
    airbrake_turns_past_the_grip_limit = function()
        local tight = F.circle(60, 16)
        local function outside_hits(c)
            local s = physics.new_ship(1, 0, 0)
            s.v = 50
            local hits = 0
            run(tight, s, c, 2, function(st)
                st.v = 50
                if st.hit and st.u < 0 then hits = hits + 1 end
            end)
            return hits
        end
        T.ok(outside_hits({ steer = 1 }) > 0, "50 m/s on steering alone runs wide")
        T.eq(outside_hits({ steer = 1, abR = true }), 0, "the inside airbrake holds the bend")
    end,
    both_airbrakes_slow_without_turning = function()
        local a, b = physics.new_ship(), physics.new_ship()
        a.v, b.v = 40, 40
        run(circle, a, { steer = 0, abL = true, abR = true }, 1)
        run(circle, b, { steer = 0 }, 1)
        T.near(a.psi, b.psi, 0.02, "the two turns cancel")
        T.ok(a.v < b.v - 6, "double the drag: " .. a.v .. " vs " .. b.v)
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
    walls_cost_energy_by_the_speed_lost = function()
        local s = physics.new_ship()
        s.v = 50
        local lost = 0
        run(circle, s, { steer = 1 }, 2, function(st) lost = lost + st.impact end)
        T.ok(lost > 0, "the wall took speed")
        T.near(s.energy, P.ENERGY - lost * P.WALL_DAMAGE, 1e-2, "energy")
    end,
    no_energy_means_out_of_the_race = function()
        local s = physics.new_ship()
        s.v, s.energy = 50, 0.5
        run(circle, s, { steer = 1, thrust = true }, 3)
        T.eq(s.dnf, true); T.eq(s.energy, 0)
        local v = s.v
        run(circle, s, { steer = 0, thrust = true }, 3)
        T.ok(s.v < v, "no thrust once out: " .. s.v)
    end,
    recharge_strip_restores_energy = function()
        local tr = F.track1()
        local seg
        for i = 1, tr.n do if tr.recharge[i] then seg = i; break end end
        T.ok(seg, "track 1 has a recharge strip")
        local s = physics.new_ship(seg, 0, 0)
        s.v, s.energy = 10, 50
        physics.step(tr, s, { steer = 0 }, 1 / 60)
        T.near(s.energy, 50 + P.RECHARGE / 60, 1e-3)
        s.energy = P.ENERGY - 0.01
        physics.step(tr, s, { steer = 0 }, 1 / 60)
        T.eq(s.energy, P.ENERGY, "capped")
    end,
    no_recharge_once_out = function()
        local tr = F.track1()
        local seg
        for i = 1, tr.n do if tr.recharge[i] then seg = i; break end end
        local s = physics.new_ship(seg, 0, 0)
        s.v, s.energy, s.dnf = 10, 0, true
        physics.step(tr, s, { steer = 0 }, 1 / 60)
        T.eq(s.energy, 0, "a retired ship does not recharge")
    end,
    thrust_scale_scales_the_push = function()
        local a, b = physics.new_ship(), physics.new_ship()
        run(circle, a, { steer = 0, thrust = true, thrust_scale = 1.1 }, 2)
        run(circle, b, { steer = 0, thrust = true }, 2)
        T.ok(a.v > b.v, "more thrust, more speed")
    end,
    missing_steer_means_straight = function()
        local s = physics.new_ship()
        s.v = 30
        physics.step(circle, s, { thrust = true }, DT)
        T.ok(s.psi <= 0, "no steering input: psi " .. s.psi)
    end,
}
