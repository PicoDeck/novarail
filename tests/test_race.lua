local T = require("tests.t")
local F = require("tests.fixtures")
local race = require("src.race")
local physics = require("src.physics")

local tr = F.track1()

-- A race of n ships, run past the countdown.
local function started(n, laps)
    local r, ships = race.new(tr, n, laps)
    for _ = 1, race.COUNTDOWN do race.update(r, ships) end
    return r, ships
end

-- Put ship i just short of the line so the next update sees it cross.
local function cross(ships, i)
    local s = ships[i]
    s.lap = s.lap + 1
    s.seg, s.t = 1, 0.01
end

return {
    grid_is_behind_the_line_in_pairs = function()
        local _, ships = race.new(tr, 6, 3)
        T.eq(#ships, 6)
        for k, s in ipairs(ships) do
            T.eq(s.lap, -1, "behind the start line: lap -1")
            T.ok(s.seg > tr.n - 8, "grid slot " .. k .. " at segment " .. s.seg)
            T.ok(math.abs(s.u) > 2, "off the centre line")
        end
        T.ok(ships[1].seg > ships[3].seg and ships[3].seg > ships[5].seg, "rows go backwards")
        T.ok(ships[1].u * ships[2].u < 0, "a row has one ship each side")
        T.ok(race.progress(tr, ships[1]) > race.progress(tr, ships[2]), "staggered: the left slot is ahead")
    end,
    player_can_start_at_the_back = function()
        local _, ships = race.new(tr, 6, 3, race.PLAYER_LAST)
        local back = ships[1]
        for k = 2, 6 do
            local d = race.progress(tr, ships[k]) - race.progress(tr, back)
            T.ok(d >= 0, "ship " .. k .. " starts ahead of the player")
        end
        T.eq(select(1, race.grid(tr, 6)), back.seg, "the player takes the last slot")
        local order = race.standings(race.new(tr, 6, 3, race.PLAYER_LAST), tr, ships, {})
        T.eq(order[6], 1, "and is last in the standings, no tie")
    end,
    countdown_holds_then_goes = function()
        local r, ships = race.new(tr, 2, 3)
        T.eq(race.can_drive(r), false)
        T.eq(race.countdown(r), 3)
        for _ = 1, race.FPS do race.update(r, ships) end
        T.eq(race.countdown(r), 2)
        for _ = race.FPS + 1, race.COUNTDOWN do race.update(r, ships) end
        T.eq(race.can_drive(r), true); T.eq(r.phase, "racing")
        T.eq(race.countdown(r), 0, "GO")
        for _ = 1, race.FPS do race.update(r, ships) end
        T.eq(race.countdown(r), nil, "GO has gone")
    end,
    first_crossing_starts_lap_one = function()
        local r, ships = started(2, 3)
        cross(ships, 1)                        -- lap -1 -> 0: lap 1 begins
        race.update(r, ships)
        T.eq(race.lap_of(r, ships, 1), 1)
        T.eq(r.best[1], nil, "no lap completed yet")
    end,
    lap_times_and_best = function()
        local r, ships = started(2, 3)
        cross(ships, 1); race.update(r, ships)
        for _ = 1, 300 do race.update(r, ships) end
        cross(ships, 1); race.update(r, ships)
        T.eq(r.last[1], 301); T.eq(r.best[1], 301)
        for _ = 1, 250 do race.update(r, ships) end
        cross(ships, 1); race.update(r, ships)
        T.eq(r.last[1], 251); T.eq(r.best[1], 251)
        T.eq(#r.times[1], 2); T.eq(r.times[1][1], 301); T.eq(r.times[1][2], 251)
        T.eq(race.lap_of(r, ships, 1), 3)
    end,
    finishing_records_time_and_order = function()
        local r, ships = started(3, 1)
        cross(ships, 2); race.update(r, ships)        -- ship 2 starts lap 1
        cross(ships, 1); race.update(r, ships)
        for _ = 1, 100 do race.update(r, ships) end
        cross(ships, 2); race.update(r, ships)        -- ship 2 finishes first
        cross(ships, 1); race.update(r, ships)        -- then the player
        T.eq(r.order[1], 2); T.eq(r.order[2], 1)
        T.ok(r.finish[2] < r.finish[1])
        T.eq(r.phase, "finished", "the player is done")
    end,
    results_after_grace_or_everyone_done = function()
        local r, ships = started(2, 1)
        cross(ships, 1); race.update(r, ships)
        cross(ships, 1); race.update(r, ships)        -- player finished
        T.eq(r.phase, "finished")
        for _ = 1, race.GRACE do race.update(r, ships) end
        T.eq(r.phase, "results", "the grace period ran out")
        local res = race.results(r, tr, ships)
        T.eq(res[1].idx, 1); T.eq(res[1].pos, 1); T.ok(res[1].time)
        T.eq(res[2].idx, 2); T.eq(res[2].time, nil, "did not finish in time")
    end,
    retirement_is_last_and_ends_the_players_race = function()
        local r, ships = started(3, 3)
        ships[1].dnf = true
        race.update(r, ships)
        T.eq(r.phase, "finished")
        local order = race.standings(r, tr, ships, {})
        T.eq(order[3], 1, "retired ships go to the back")
        local res = race.results(r, tr, ships)
        T.eq(res[3].idx, 1); T.eq(res[3].dnf, true)
    end,
    standings_follow_progress = function()
        local r, ships = started(3, 3)
        for i, s in ipairs(ships) do s.lap, s.seg, s.t = 0, 10 * i, 0.5 end   -- ship 3 furthest on
        local order = race.standings(r, tr, ships, {})
        T.eq(order[1], 3); T.eq(order[2], 2); T.eq(order[3], 1)
        T.eq(race.position(r, tr, ships, 1), 3)
        ships[1].lap = 1
        race.standings(r, tr, ships, order)
        T.eq(order[1], 1, "a lap ahead leads")
    end,
    standings_allocate_nothing_when_reused = function()
        local r, ships = started(6, 3)
        local order = {}
        race.standings(r, tr, ships, order)
        local before = collectgarbage("count")
        for _ = 1, 200 do race.standings(r, tr, ships, order) end
        T.ok(collectgarbage("count") - before < 1, "grew by " .. (collectgarbage("count") - before) .. " KB")
    end,
    a_lap_recrossed_after_a_set_back_counts_once = function()
        -- a collision can push a ship back over the line (collide.lua takes a
        -- lap off it); crossing again must not count the lap twice
        local r, ships = started(2, 3)
        cross(ships, 1); race.update(r, ships)          -- lap 1 begins
        for _ = 1, 100 do race.update(r, ships) end
        cross(ships, 1); race.update(r, ships)          -- lap 1 done: 101 frames
        ships[1].lap = ships[1].lap - 1                 -- set back over the line
        race.update(r, ships)
        cross(ships, 1); race.update(r, ships)          -- and over it again
        T.eq(#r.times[1], 1, "one lap, counted once")
        T.eq(r.last[1], 101)
        T.eq(race.lap_of(r, ships, 1), 2)
    end,
    finishing_as_the_energy_runs_out_counts_as_finished = function()
        local r, ships = started(2, 1)
        cross(ships, 1); race.update(r, ships)          -- lap 1 begins
        cross(ships, 1)
        ships[1].dnf = true                             -- the last hit on the line
        race.update(r, ships)
        T.ok(r.finish[1], "finished"); T.eq(r.out[1], nil)
        T.eq(race.results(r, tr, ships)[1].dnf, false)
    end,
    retired_ships_keep_their_order_in_32_bit_floats = function()
        -- two retired ships 0.8 m apart: the one further on ranks higher (a
        -- key of progress - 1e6 loses that in single precision)
        local r, ships = started(3, 3)
        ships[1].seg, ships[1].t = 100, 0.30
        ships[2].seg, ships[2].t = 100, 0.40
        ships[3].seg, ships[3].t = 50, 0
        ships[1].dnf, ships[2].dnf = true, true
        race.update(r, ships)
        T.eq(r.out[1], true); T.eq(r.out[2], true)
        local order = race.standings(r, tr, ships, {})
        T.eq(order[1], 3, "the running ship leads")
        T.eq(order[2], 2, "the retired ship further on")
        T.eq(order[3], 1)
    end,
    ms_from_frames = function()
        T.eq(race.ms(30), 1000); T.eq(race.ms(45), 1500); T.eq(race.ms(nil), nil)
    end,
}
