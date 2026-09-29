-- Track generation (pure Lua, no picocalc): a closed Catmull-Rom spline
-- through the control points, resampled into equal-length segments. Each
-- segment start (a "ring") gets an upright frame turned by the bank angle:
-- forward T, up U, right R = T x U. Curvature is measured in that frame.
local M = {}

local sqrt, sin, cos, floor, abs = math.sqrt, math.sin, math.cos, math.floor, math.abs

M.SUB = 32 -- dense samples per control span, for the arc-length table

local function cr(a, b, c, d, t)
    local t2 = t * t
    local t3 = t2 * t
    return 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2
        + (3 * b - a - 3 * c + d) * t3)
end

-- The spline as a dense closed polyline: arrays x, y, z, w, b of k samples,
-- and s[i] = arc length at sample i (s[k + 1] = the whole loop).
local function dense(points)
    local n = #points
    local x, y, z, w, b = {}, {}, {}, {}, {}
    local k = 0
    for i = 1, n do
        local p0, p1 = points[(i - 2) % n + 1], points[i]
        local p2, p3 = points[i % n + 1], points[(i + 1) % n + 1]
        for j = 0, M.SUB - 1 do
            local t = j / M.SUB
            k = k + 1
            x[k] = cr(p0[1], p1[1], p2[1], p3[1], t)
            y[k] = cr(p0[2], p1[2], p2[2], p3[2], t)
            z[k] = cr(p0[3], p1[3], p2[3], p3[3], t)
            w[k] = cr(p0[4], p1[4], p2[4], p3[4], t)
            b[k] = cr(p0[5], p1[5], p2[5], p3[5], t)
        end
    end
    local s = { 0 }
    for i = 2, k + 1 do
        local a, c = i - 1, (i - 1) % k + 1
        local dx, dy, dz = x[c] - x[a], y[c] - y[a], z[c] - z[a]
        s[i] = s[a] + sqrt(dx * dx + dy * dy + dz * dz)
    end
    return x, y, z, w, b, s, k
end

-- A number that is neither NaN nor infinite (Catmull-Rom turns an infinite
-- control value into NaN geometry: inf - inf).
local function finite(v)
    return type(v) == "number" and v > -math.huge and v < math.huge
end

local function check_points(points)
    assert(type(points) == "table" and #points >= 4,
        "trackgen: a track needs at least 4 control points")
    local n = #points
    for i = 1, n do
        local p = points[i]
        assert(type(p) == "table", "trackgen: point " .. i .. " is not a table")
        for c = 1, 5 do
            assert(finite(p[c]), "trackgen: point " .. i .. " field " .. c .. " is not a finite number")
        end
        assert(p[4] > 4, "trackgen: point " .. i .. " is narrower than 4 m")
    end
    for i = 1, n do
        local p, q = points[i], points[i % n + 1]
        local dx, dy, dz = q[1] - p[1], q[2] - p[2], q[3] - p[3]
        assert(dx * dx + dy * dy + dz * dz >= 1,
            "trackgen: points " .. i .. " and " .. (i % n + 1) .. " are under 1 m apart")
    end
end

local function frames(tr)
    local n, px, py, pz = tr.n, tr.px, tr.py, tr.pz
    local tx, ty, tz, ux, uy, uz, rx, ry, rz = {}, {}, {}, {}, {}, {}, {}, {}, {}
    for i = 1, n do
        local a, c = (i - 2) % n + 1, i % n + 1
        local dx, dy, dz = px[c] - px[a], py[c] - py[a], pz[c] - pz[a]
        local l = sqrt(dx * dx + dy * dy + dz * dz)
        dx, dy, dz = dx / l, dy / l, dz / l
        if abs(dy) >= 0.9 then
            local sp, np = tr.span[i], #tr.span_of
            error(string.format("trackgen: between points %d and %d the track is too steep (segment %d)",
                sp, sp % np + 1, i), 0)
        end
        -- upright: world up with its component along T removed
        local bux, buy, buz = -dy * dx, 1 - dy * dy, -dy * dz
        local bl = sqrt(bux * bux + buy * buy + buz * buz)
        bux, buy, buz = bux / bl, buy / bl, buz / bl
        local brx, bry, brz = dy * buz - dz * buy, dz * bux - dx * buz, dx * buy - dy * bux
        local cb, sb = cos(tr.bank[i]), sin(tr.bank[i])
        tx[i], ty[i], tz[i] = dx, dy, dz
        ux[i], uy[i], uz[i] = bux * cb + brx * sb, buy * cb + bry * sb, buz * cb + brz * sb
        rx[i], ry[i], rz[i] = brx * cb - bux * sb, bry * cb - buy * sb, brz * cb - buz * sb
    end
    local kr, ku, inv = {}, {}, 1 / (2 * tr.len)
    for i = 1, n do
        local a, c = (i - 2) % n + 1, i % n + 1
        local dtx, dty, dtz = (tx[c] - tx[a]) * inv, (ty[c] - ty[a]) * inv, (tz[c] - tz[a]) * inv
        kr[i] = dtx * rx[i] + dty * ry[i] + dtz * rz[i] -- > 0: bends right
        ku[i] = dtx * ux[i] + dty * uy[i] + dtz * uz[i] -- < 0: a crest
    end
    tr.tx, tr.ty, tr.tz, tr.ux, tr.uy, tr.uz = tx, ty, tz, ux, uy, uz
    tr.rx, tr.ry, tr.rz, tr.kr, tr.ku = rx, ry, rz, kr, ku
end

-- The recharge strip: def.recharge = { from, to }, fractions of the lap in
-- [0, 1) (it may wrap past the start line). tr.recharge[seg] is true on it.
local function place_recharge(tr, rc)
    tr.recharge = {}
    if not rc then return end
    assert(type(rc) == "table" and finite(rc.from) and finite(rc.to)
        and rc.from >= 0 and rc.from < 1 and rc.to >= 0 and rc.to < 1,
        "trackgen: recharge needs `from` and `to` in [0, 1)")
    local first = floor(rc.from * tr.n) % tr.n + 1
    local last = floor(rc.to * tr.n) % tr.n + 1
    local seg = first
    while true do
        tr.recharge[seg] = true
        if seg == last then break end
        seg = seg % tr.n + 1
    end
end

-- Pads cover M.PAD_SEGS segments from floor(at * n) + 1. padid[seg] is the
-- pad's index, padlo/padhi[seg] its lateral range.
M.PAD_SEGS = 2

local function place_pads(tr, pads)
    tr.padid, tr.padlo, tr.padhi = {}, {}, {}
    for id, p in ipairs(pads or {}) do
        assert(type(p) == "table", "trackgen: pad " .. id .. " is not a table")
        for _, f in ipairs({ "at", "u", "half" }) do
            assert(finite(p[f]), "trackgen: pad " .. id .. " field '" .. f .. "' is not a finite number")
        end
        assert(p.half > 0, "trackgen: pad " .. id .. " field 'half' must be positive")
        assert(p.at >= 0 and p.at < 1, "trackgen: pad " .. id .. " `at` must be in [0, 1)")
        local first = floor(p.at * tr.n) % tr.n + 1
        for k = 0, M.PAD_SEGS - 1 do
            local seg = (first - 1 + k) % tr.n + 1
            assert(abs(p.u) + p.half <= tr.w[seg] * 0.5 - 1,
                "trackgen: pad " .. id .. " does not fit the road")
            assert(not tr.padid[seg], "trackgen: pads " .. id .. " and "
                .. tostring(tr.padid[seg]) .. " overlap")
            tr.padid[seg], tr.padlo[seg], tr.padhi[seg] = id, p.u - p.half, p.u + p.half
        end
    end
end

-- def = { name, points = {{x, y, z, width, bank}, ...}, pads = {...} }.
-- Returns the track: n segments of length len (total / n); per-ring arrays
-- px py pz (centre), tx ty tz / ux uy uz / rx ry rz (frame), w (width),
-- bank, kr (1/m, > 0 bends right), ku (1/m, < 0 crest); pad arrays.
function M.generate(def, seg_len)
    assert(finite(seg_len) and seg_len > 0, "trackgen: seg_len must be a positive number")
    check_points(def.points)
    local x, y, z, w, b, s, k = dense(def.points)
    local total = s[k + 1]
    local n = floor(total / seg_len + 0.5)
    assert(n >= 8, "trackgen: the track is shorter than 8 segments")
    local tr = { name = def.name, n = n, len = total / n, total = total,
        px = {}, py = {}, pz = {}, w = {}, bank = {}, span = {}, span_of = def.points }
    local j = 1
    for i = 1, n do
        local si = (i - 1) * tr.len
        while s[j + 1] < si do j = j + 1 end
        local c = j % k + 1
        local f = (si - s[j]) / (s[j + 1] - s[j])
        tr.px[i] = x[j] + (x[c] - x[j]) * f
        tr.py[i] = y[j] + (y[c] - y[j]) * f
        tr.pz[i] = z[j] + (z[c] - z[j]) * f
        tr.w[i] = w[j] + (w[c] - w[j]) * f
        tr.bank[i] = b[j] + (b[c] - b[j]) * f
        tr.span[i] = (j - 1) // M.SUB + 1 -- the control span this ring lies in
    end
    frames(tr)
    place_pads(tr, def.pads)
    place_recharge(tr, def.recharge)
    return tr
end

return M
