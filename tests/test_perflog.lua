local T = require("tests.t")
local perflog = require("src.perflog")

return {
    stats_of_one_to_a_hundred = function()
        local v = {}
        for i = 1, 100 do v[i] = 101 - i end
        local s = perflog.stats(v, 100)
        T.eq(s.min, 1); T.eq(s.max, 100); T.eq(s.p95, 95); T.eq(s.avg, 51)
        T.eq(math.type(s.avg), "integer")
    end,
    stats_of_one_value = function()
        local s = perflog.stats({ 33000 }, 1)
        T.eq(s.min, 33000); T.eq(s.p95, 33000); T.eq(s.max, 33000); T.eq(s.avg, 33000)
    end,
    stats_needs_values = function()
        T.raises(function() perflog.stats({}, 0) end, "no values")
    end,
    summary_counts_missed_deadlines = function()
        local log = perflog.new(4)
        perflog.add(log, 20000, 33333)
        perflog.add(log, 33334, 33400)
        perflog.add(log, 33333, 33333)
        local s = perflog.summary(log)
        T.eq(s.frames, 3); T.eq(s.missed, 1)
        T.eq(s.work_us.max, 33334); T.eq(s.interval_us.min, 33333)
    end,
    summary_counts_late_intervals = function()
        -- a frame can finish its work in time and still be shown late (a stall
        -- in the flush or between frames): the interval catches it
        local log = perflog.new(4)
        perflog.add(log, 20000, 33333)
        perflog.add(log, 20000, 34001)
        perflog.add(log, 20000, 40000)
        local s = perflog.summary(log)
        T.eq(s.missed, 0); T.eq(s.late, 2)
    end,
    add_stops_when_full = function()
        local log = perflog.new(2)
        T.eq(perflog.add(log, 1, 1), true); T.eq(perflog.add(log, 2, 2), true)
        T.eq(perflog.add(log, 3, 3), false)
        T.eq(log.n, 2); T.eq(#log.work, 2)
    end,
    whole_lap_sums_fit_32_bit_integers = function()
        local log = perflog.new(3000)
        for _ = 1, 3000 do perflog.add(log, 33000, 33333) end
        local s = perflog.summary(log)
        T.eq(s.interval_us.avg, 33333)
    end,
}
