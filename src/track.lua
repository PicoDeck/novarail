-- Track queries (pure Lua). A place on the track is (seg, t): segment 1..n
-- and the fraction 0 <= t < 1 along it. Segment seg runs from ring seg to
-- ring seg % n + 1; the start line is ring 1.
local M = {}

local sqrt, abs = math.sqrt, math.abs

-- Moves ds metres along the centre line. Returns seg, t and the number of
-- times the start line was crossed (+1 forwards, -1 backwards).
function M.advance(tr, seg, t, ds)
    assert(ds == ds and abs(ds) < tr.total, "track.advance: bad distance")
    local n = tr.n
    local laps = 0
    t = t + ds / tr.len
    while t >= 1 do
        t = t - 1
        seg = seg + 1
        if seg > n then seg, laps = 1, laps + 1 end
    end
    while t < 0 do
        t = t + 1
        seg = seg - 1
        if seg < 1 then seg, laps = n, laps - 1 end
    end
    return seg, t, laps
end

-- A per-ring array read at (seg, t), interpolated linearly.
function M.lerp(arr, tr, seg, t)
    return arr[seg] + (arr[seg % tr.n + 1] - arr[seg]) * t
end

-- The frame at (seg, t): centre, forward T and up U (renormalised), right R.
function M.frame(tr, seg, t)
    local j = seg % tr.n + 1
    local f = 1 - t
    local px = tr.px[seg] * f + tr.px[j] * t
    local py = tr.py[seg] * f + tr.py[j] * t
    local pz = tr.pz[seg] * f + tr.pz[j] * t
    local tx = tr.tx[seg] * f + tr.tx[j] * t
    local ty = tr.ty[seg] * f + tr.ty[j] * t
    local tz = tr.tz[seg] * f + tr.tz[j] * t
    local ux = tr.ux[seg] * f + tr.ux[j] * t
    local uy = tr.uy[seg] * f + tr.uy[j] * t
    local uz = tr.uz[seg] * f + tr.uz[j] * t
    local l = 1 / sqrt(tx * tx + ty * ty + tz * tz)
    tx, ty, tz = tx * l, ty * l, tz * l
    l = 1 / sqrt(ux * ux + uy * uy + uz * uz)
    ux, uy, uz = ux * l, uy * l, uz * l
    return px, py, pz, tx, ty, tz, ux, uy, uz,
        ty * uz - tz * uy, tz * ux - tx * uz, tx * uy - ty * ux
end

-- The world point u metres right of the centre line and h metres above it.
function M.point(tr, seg, t, u, h)
    local px, py, pz, _, _, _, ux, uy, uz, rx, ry, rz = M.frame(tr, seg, t)
    return px + rx * u + ux * h, py + ry * u + uy * h, pz + rz * u + uz * h
end

return M
