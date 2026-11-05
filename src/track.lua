-- Track queries (pure Lua). A place on the track is (seg, t): segment 1..n
-- and the fraction 0 <= t < 1 along it. Segment seg runs from ring seg to
-- ring seg % n + 1; the start line is ring 1.
local M = {}

local sqrt = math.sqrt

-- Moves ds metres along the centre line. Returns seg, t and the number of
-- times the start line was crossed (+1 forwards, -1 backwards).
function M.advance(tr, seg, t, ds)
    -- not assert(): every ship calls this every frame, and each C call counts
    local total = tr.total
    if not (ds < total and ds > -total) then error("track.advance: bad distance", 0) end
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
    local a = tr.px
    local px = a[seg] * f + a[j] * t
    a = tr.py
    local py = a[seg] * f + a[j] * t
    a = tr.pz
    local pz = a[seg] * f + a[j] * t
    a = tr.tx
    local tx = a[seg] * f + a[j] * t
    a = tr.ty
    local ty = a[seg] * f + a[j] * t
    a = tr.tz
    local tz = a[seg] * f + a[j] * t
    a = tr.ux
    local ux = a[seg] * f + a[j] * t
    a = tr.uy
    local uy = a[seg] * f + a[j] * t
    a = tr.uz
    local uz = a[seg] * f + a[j] * t
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
