local T = require("tests.t")
local F = require("tests.fixtures")
local ai = require("src.ai")
local race = require("src.race")
local physics = require("src.physics")
local collide = require("src.collide")
local P = physics.P

local tr = F.track1()
local line = ai.prepare(tr, P)
local DT = 1 / 30

-- A whole race with every ship (the player too) driven by the AI.
local function run_race(n, laps, skills)
    local r, ships = race.new(tr, n, laps)
    local drivers, ctl = {}, {}
    local lanes = { 0, -2.5, 2.5, -1, 1, 0 }
    for i = 1, n do drivers[i] = ai.new_driver(skills and skills[i] or 1, lanes[i]); ctl[i] = {} end
    local order, lead_changes, prev_leader = {}, 0, nil
    local hits, walled, frames = 0, {}, 0
    for i = 1, n do walled[i] = 0 end
    while r.phase ~= "results" and r.frame < 30 * 60 * 5 do
        for i = 1, n do
            local s = ships[i]
            if race.can_drive(r) then
                local lead = (race.progress(tr, s) - race.progress(tr, ships[1])) * tr.total
                ai.controls(tr, line, ships, i, drivers[i], P, lead, ctl[i])
            else
                ctl[i].steer, ctl[i].thrust, ctl[i].brake = 0, false, false
            end
            physics.step(tr, s, ctl[i], DT)
            if s.hit then hits = hits + 1 end
            if s.scrape > 0 and not r.finish[i] then walled[i] = walled[i] + 1 end
        end
        collide.resolve(tr, ships)
        race.update(r, ships)
        frames = frames + 1
        race.standings(r, tr, ships, order)
        if race.can_drive(r) and prev_leader and order[1] ~= prev_leader then lead_changes = lead_changes + 1 end
        prev_leader = order[1]
    end
    return r, ships, hits, lead_changes, walled
end

return {
    line_stays_inside_the_walls = function()
        for i = 1, tr.n do
            T.ok(math.abs(line.u[i]) <= tr.w[i] * 0.5 - ai.MARGIN + 1e-6, "segment " .. i)
        end
    end,
    line_takes_the_inside_of_the_tightest_bend = function()
        local best, at = 0, 1
        for i = 1, tr.n do if math.abs(tr.kr[i]) > best then best, at = math.abs(tr.kr[i]), i end end
        T.ok(line.u[at] * tr.kr[at] > 0, "inside: u " .. line.u[at] .. " kr " .. tr.kr[at])
        T.ok(math.abs(line.u[at]) > 2, "well off the centre line")
        T.ok(math.abs(line.u[at]) <= tr.w[at] * 0.5 - ai.APEX_MARGIN + 1e-6, "but clear of the inside wall")
    end,
    lane_offsets_keep_clear_of_the_inside_wall = function()
        local best, at = 0, 1
        for i = 1, tr.n do if math.abs(tr.kr[i]) > best then best, at = math.abs(tr.kr[i]), i end end
        local inside = tr.kr[at] > 0 and 1 or -1
        local seg = (at - 1 - ai.AHEAD) % tr.n + 1 -- reads the line at `at`
        local s = physics.new_ship(seg, 0, line.u[at])
        s.v = 30
        local d = ai.new_driver(1, 3 * inside) -- a lane 3 m further in
        local c = ai.controls(tr, line, { s }, 1, d, P, 0, {})
        local lim = tr.w[at] * 0.5 - ai.APEX_MARGIN
        T.ok(math.abs(line.u[at]) <= lim + 1e-6)
        -- held at the apex limit: it steers no harder inwards than for the line itself
        local plain = ai.controls(tr, line, { s }, 1, ai.new_driver(1, 0), P, 0, {})
        T.near(c.steer, plain.steer, 1e-6, "the lane offset is clamped at the apex margin")
    end,
    speed_profile_respects_grip = function()
        for i = 1, tr.n do
            T.ok(line.v[i] * line.v[i] * math.abs(tr.kr[i]) <= P.A_GRIP * ai.GRIP_MARGIN + 1e-3,
                "segment " .. i .. " asks for more than grip: " .. line.v[i])
        end
        local best, at = 0, 1
        for i = 1, tr.n do if math.abs(tr.kr[i]) > best then best, at = math.abs(tr.kr[i]), i end end
        T.ok(line.v[at] < 52, "slows for the tightest bend: " .. line.v[at])
    end,
    speed_profile_brakes_in_time = function()
        local tight = F.circle(20, 8) -- grip allows about 25 m/s round it
        local l = ai.prepare(tight, P)
        for i = 1, tight.n do
            T.ok(l.v[i] <= ai.V_CAP + 1e-6)
            local nx = l.v[i % tight.n + 1]
            T.ok(l.v[i] <= math.sqrt(nx * nx + 2 * ai.BRAKE_A * tight.len) + 1e-3, "brakes in time at " .. i)
        end
        T.ok(l.v[1] < 40, "a 20 m circle is well below the cap: " .. l.v[1])
    end,
    avoids_a_slower_ship_in_its_lane = function()
        local lane = line.u[(40 - 1 + ai.AHEAD) % tr.n + 1]
        local s, slow = physics.new_ship(40, 0, lane), physics.new_ship(41, 0, lane)
        s.v, slow.v = 50, 20
        local free = ai.controls(tr, line, { s }, 1, ai.new_driver(1, 0), P, 0, {}).steer
        local c = ai.controls(tr, line, { s, slow }, 1, ai.new_driver(1, 0), P, 0, {})
        T.ok(math.abs(c.steer - free) > 0.2, "steers round: " .. c.steer .. " vs " .. free)
    end,
    rubber_band_slows_the_leader_and_helps_the_last = function()
        local s = physics.new_ship(40, 0, 0)
        s.v = 30
        local d = ai.new_driver(0.95, 0)
        local ahead = ai.controls(tr, line, { s }, 1, d, P, 400, {}).thrust_scale
        local level = ai.controls(tr, line, { s }, 1, d, P, 0, {}).thrust_scale
        local behind = ai.controls(tr, line, { s }, 1, d, P, -400, {}).thrust_scale
        T.near(level, 0.95, 1e-6)
        T.ok(ahead < level and behind > level)
        T.near(ahead, 0.95 * (1 - ai.RB_MAX), 1e-6, "capped")
    end,
    six_ships_finish_a_race = function()
        -- the fastest drivers start at the back, so the race needs overtaking
        local r, ships, hits, changes, walled = run_race(6, 3, { 0.95, 0.96, 0.97, 0.98, 0.99, 1 })
        T.eq(r.phase, "results")
        for i = 1, 6 do
            T.ok(r.finish[i], "ship " .. i .. " finished")
            T.eq(ships[i].dnf, false, "ship " .. i .. " still running")
        end
        local first, last = math.huge, 0
        for i = 1, 6 do first, last = math.min(first, r.finish[i]), math.max(last, r.finish[i]) end
        T.ok(last - first < 20 * race.FPS, "the pack finished within 20 s: " .. (last - first) / race.FPS)
        T.ok(changes > 0, "the lead changed hands")
        local order = race.standings(r, tr, ships, {})
        local pos6
        for p = 1, 6 do if order[p] == 6 then pos6 = p end end
        T.ok(pos6 <= 3, "the fastest, from last on the grid, finished " .. pos6)
        local fast, slow = math.huge, 0
        for i = 1, 6 do
            local laps_frames = r.finish[i]
            T.ok(walled[i] < 0.02 * laps_frames, "ship " .. i .. " on a wall for " .. walled[i] .. " frames")
            local best = r.best[i] / race.FPS
            T.ok(best >= 38 and best <= 48, "ship " .. i .. " best lap " .. best)
            fast, slow = math.min(fast, best), math.max(slow, best)
        end
        T.ok(slow <= fast * 1.12, "best laps " .. fast .. " to " .. slow)
    end,
    controls_allocate_nothing = function()
        local _, ships = race.new(tr, 6, 3)
        local d, out = ai.new_driver(1, 0), {}
        ai.controls(tr, line, ships, 2, d, P, 0, out)
        local before = collectgarbage("count")
        for _ = 1, 500 do ai.controls(tr, line, ships, 2, d, P, 0, out) end
        T.ok(collectgarbage("count") - before < 1)
    end,
}
