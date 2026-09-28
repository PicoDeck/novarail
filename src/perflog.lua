-- Frame-time log (pure Lua). Records each frame's work time (update and
-- draw, before the pacing wait) and interval (start to start), in integer
-- microseconds, into preallocated arrays; summary() gives the gate figures.
local M = {}

local floor, ceil = math.floor, math.ceil

-- A frame whose work runs past the deadline misses it.
M.DEADLINE_US = 33333

function M.new(capacity)
    local log = { n = 0, cap = capacity, work = {}, interval = {} }
    for i = 1, capacity do log.work[i] = 0; log.interval[i] = 0 end
    return log
end

-- Returns false once full (later frames are not recorded).
function M.add(log, work_us, interval_us)
    if log.n >= log.cap then return false end
    local i = log.n + 1
    log.work[i], log.interval[i], log.n = work_us, interval_us, i
    return true
end

-- min / avg / p95 (nearest rank) / max of the first n values, integers.
function M.stats(values, n)
    assert(n > 0, "perflog.stats: no values")
    local sorted, sum = {}, 0
    for i = 1, n do
        local v = values[i]
        sorted[i] = v
        sum = sum + v
    end
    table.sort(sorted)
    return { min = sorted[1], avg = floor(sum / n + 0.5),
        p95 = sorted[ceil(n * 0.95)], max = sorted[n] }
end

function M.summary(log)
    local missed = 0
    for i = 1, log.n do
        if log.work[i] > M.DEADLINE_US then missed = missed + 1 end
    end
    return { frames = log.n, missed = missed,
        work_us = M.stats(log.work, log.n),
        interval_us = M.stats(log.interval, log.n) }
end

return M
