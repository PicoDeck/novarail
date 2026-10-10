-- Track 1 as a circuit: what each corner demands with the grip limit,
-- driven by the scripted pilot (tests/pilot.lua) from top speed.
local T = require("tests.t")
local F = require("tests.fixtures")
local pilot = require("tests.pilot")

local tr = F.track1()
local n = tr.n

-- Stretches of the lap, as fractions of it.
local HAIRPIN = { 0.10, 0.22 }
local CHICANE = { 0.52, 0.66 } -- the left flick, the right flick and the right after
local SWEEPERS = { easy_left = { 0.22, 0.30 }, fast_right = { 0.32, 0.40 }, final_right = { 0.72, 0.82 } }

local function segs(w) return math.floor(w[1] * n) + 1, math.floor(w[2] * n) end

-- The sharpest bend in a stretch: its segment and radius, from the
-- curvature averaged over five segments (one segment's own is spiky).
local function sharpest(w)
    local a, b = segs(w)
    local best, at = 0, a
    for i = a, b do
        local k = 0
        for d = -2, 2 do k = k + tr.kr[(i - 1 + d) % n + 1] end
        k = math.abs(k) / 5
        if k > best then best, at = k, i end
    end
    return at, 1 / best
end

local function move(seg, m) return (seg - 1 + math.floor(m / tr.len)) % n + 1 end

-- The first segment of a stretch that bends tighter than 150 m.
local function first_bend(w)
    local a, b = segs(w)
    for i = a, b do
        local k = 0
        for d = -2, 2 do k = k + tr.kr[(i - 1 + d) % n + 1] end
        if math.abs(k) / 5 > 1 / 150 then return i end
    end
end

-- Drives a stretch from `lead` m before it (150 by default) to 100 m
-- after it, from top speed.
local function drive(mode, w, lead)
    local a, b = segs(w)
    return pilot.drive(tr, mode, move(a, -(lead or 150)), move(b, 100), 61)
end

-- No wall, and the speed it took: a corner that needs braking is braked
-- for; airbrakes carry more speed through it.
local function braking_corner(w, vmax)
    local flat, brake, air = drive("flat", w), drive("brake", w), drive("airbrake", w)
    T.ok(flat.hits > 0, "flat out reaches the wall")
    T.eq(brake.hits, 0, "braking gets round clean")
    T.ok(brake.vmin < vmax, "braking down to " .. brake.vmin)
    T.eq(air.hits, 0, "airbrakes get round clean")
    T.ok(air.time < brake.time, "airbrakes are faster: " .. air.time .. " vs " .. brake.time)
    T.ok(air.vmin > brake.vmin * 1.08, "and carry more speed: " .. air.vmin .. " vs " .. brake.vmin)
end

return {
    lap_and_heights = function()
        T.ok(tr.total > 2200 and tr.total < 2300, "lap " .. tr.total)
        local lo, hi = math.huge, -math.huge
        for i = 1, n do lo, hi = math.min(lo, tr.py[i]), math.max(hi, tr.py[i]) end
        T.ok(hi > 30 and hi < 45, "the hill " .. hi)
        T.ok(lo < -5, "the dip " .. lo)
    end,
    hairpin_is_a_hard_stop = function()
        local _, r = sharpest(HAIRPIN)
        T.ok(r > 35 and r < 45, "hairpin radius " .. r)
        braking_corner(HAIRPIN, 40)
    end,
    chicane_is_a_braking_complex = function()
        local _, r = sharpest(CHICANE)
        T.ok(r > 50 and r < 65, "tightest flick radius " .. r)
        braking_corner(CHICANE, 50)
    end,
    sweepers_need_no_brake = function()
        for name, w in pairs(SWEEPERS) do
            local _, r = sharpest(w)
            T.ok(r > 90, name .. " radius " .. r)
            local lift = drive("lift", w, 0) -- from top speed at its start
            T.eq(lift.hits, 0, name .. ": lifting is enough")
            T.ok(lift.vmin > 50, name .. ": no braking needed, " .. lift.vmin)
        end
    end,
    crest_lightens_the_ship_and_settles_before_the_chicane = function()
        local crest, low = 1, 0
        for i = 1, n do
            if tr.py[i] > 20 and tr.ku[i] < low then crest, low = i, tr.ku[i] end
        end
        local chicane = first_bend(CHICANE)
        local res = pilot.drive(tr, "brake", move(crest, -300), chicane, 61)
        T.ok(res.light, "the ship rises over the crest at speed")
        local gap = ((chicane - res.light.last) % n) * tr.len
        T.ok(gap >= 100, "settled " .. gap .. " m before the chicane")
    end,
}
