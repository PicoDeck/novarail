-- Model data (pure Lua): flat vertex, triangle, colour and flag lists for
-- gfx3d.newMesh. Models face -z (gfx3d's convention); triangles run
-- counter-clockwise seen from outside. Colours are RGB565 numbers.
local M = {}

local sin, cos, pi = math.sin, math.cos, math.pi

-- RGB565 from 8-bit channels, as picocalc.display.rgb (this module stays
-- free of picocalc).
local function rgb(r, g, b)
    return (r >> 3) << 11 | (g >> 2) << 5 | b >> 3
end

-- Ship colours that do not depend on the team.
local HULL, DARK, UNDER, DECK = rgb(110, 116, 150), rgb(40, 42, 66), rgb(26, 26, 44), rgb(30, 32, 52)
local HOT, CYAN = rgb(255, 240, 255), rgb(120, 240, 255)

-- Builds one model: vertex, triangle, colour and flag lists for
-- gfx3d.newMesh. double and glow are the gfx3d flags (DOUBLE_SIDED, and
-- UNLIT + NO_FOG) the caller passes in, so this module needs no picocalc.
local function builder(double, glow)
    local b = { v = {}, t = {}, c = {}, f = {}, double = double, glow = glow }
    function b.vert(x, y, z)
        local v = b.v
        v[#v + 1] = x; v[#v + 1] = y; v[#v + 1] = z
        return #v // 3
    end
    function b.tri(i, j, k, col, flag)
        local t = b.t
        t[#t + 1] = i; t[#t + 1] = j; t[#t + 1] = k
        b.c[#b.c + 1] = col; b.f[#b.f + 1] = flag or 0
    end
    -- A thin double-sided triangle from three points.
    function b.sheet(p, q, r, col, flag)
        b.tri(b.vert(p[1], p[2], p[3]), b.vert(q[1], q[2], q[3]), b.vert(r[1], r[2], r[3]), col,
            (flag or 0) | double)
    end
    -- A closed hull lofted from a nose point back through rings of (x, y)
    -- points at increasing z, each ring counter-clockwise seen from behind
    -- (+z), so every face winds outwards; the last ring is capped with
    -- cap_col/cap_flag (the engine).
    function b.loft(nose, rings, col, cap_col, cap_flag)
        local n0 = b.vert(nose[1], nose[2], nose[3])
        local prev
        for _, ring in ipairs(rings) do
            local z, pts, idx = ring[1], ring[2], {}
            for k, p in ipairs(pts) do idx[k] = b.vert(p[1], p[2], z) end
            local m = #idx
            for k = 1, m do
                local k1 = k % m + 1
                if prev then
                    b.tri(prev[k], idx[k1], idx[k], col)
                    b.tri(prev[k], prev[k1], idx[k1], col)
                else
                    b.tri(n0, idx[k1], idx[k], col)
                end
            end
            prev = idx
        end
        for k = 2, #prev - 1 do b.tri(prev[1], prev[k], prev[k + 1], cap_col, cap_flag) end
    end
    -- Mirrors the triangles from number `from` on across x = 0 (new
    -- vertices, winding reversed so they still face out).
    function b.mirror(from)
        local last, map = #b.t // 3, {}
        local function m(q)
            if not map[q] then map[q] = b.vert(-b.v[3 * q - 2], b.v[3 * q - 1], b.v[3 * q]) end
            return map[q]
        end
        for k = from, last do
            local i, j, l = b.t[3 * k - 2], b.t[3 * k - 1], b.t[3 * k]
            b.tri(m(i), m(l), m(j), b.c[k], b.f[k])
        end
    end
    function b.done() return b.v, b.t, b.c, b.f end
    return b
end

-- The player's ship: a long needle nose, swept wings with team-colour
-- upturned tips, twin team-colour fins and a glowing engine. 22 triangles.
-- No glowing edge slivers: anything much under 0.2 m across rasterises to
-- a different scatter of pixels every frame and sparkles.
function M.needle(body, double, glow)
    local b = builder(double, glow)
    b.loft({ 0, 0.2, -3.0 }, {
        { -1.1, { { -0.36, 0.1 }, { 0, -0.15 }, { 0.36, 0.1 }, { 0, 0.46 } } },
        { 1.2, { { -0.46, 0.1 }, { 0, -0.2 }, { 0.46, 0.1 }, { 0, 0.5 } } },
    }, HULL, HOT, glow)
    local side = #b.t // 3 + 1
    b.sheet({ 0.33, 0.08, -0.9 }, { 1.95, 0, 1.05 }, { 0.46, 0.08, 1.2 }, DARK)
    b.sheet({ 1.95, 0, 1.05 }, { 1.75, 0, 0.45 }, { 1.95, 0.55, 1.25 }, body)
    b.sheet({ 1.95, 0, 1.05 }, { 1.95, 0.55, 1.25 }, { 1.9, 0, 1.25 }, body)
    b.sheet({ 0.28, 0.4, 0.5 }, { 0.3, 0.42, 1.2 }, { 0.42, 1.05, 1.35 }, body)
    b.mirror(side)
    return b.done()
end

-- A rival: a slim grey fuselage with a glowing cyan canopy between two
-- team-colour engine pods on a dark wing, and three glowing exhausts.
-- 40 triangles.
function M.twin_pod(body, double, glow)
    local b = builder(double, glow)
    b.loft({ 0, 0.28, -2.5 }, {
        { -1.0, { { -0.5, 0.02 }, { 0.5, 0.02 }, { 0.32, 0.5 }, { -0.32, 0.5 } } },
        { 1.3, { { -0.55, 0.02 }, { 0.55, 0.02 }, { 0.36, 0.55 }, { -0.36, 0.55 } } },
    }, HULL, HOT, glow)
    b.sheet({ -0.3, 0.52, -0.9 }, { 0.3, 0.52, -0.9 }, { 0.2, 0.62, 0 }, CYAN, glow)
    b.sheet({ -0.3, 0.52, -0.9 }, { 0.2, 0.62, 0 }, { -0.2, 0.62, 0 }, CYAN, glow)
    local side = #b.t // 3 + 1
    b.loft({ 1.5, 0.12, -1.7 }, {
        { -0.3, { { 1.28, -0.02 }, { 1.72, -0.02 }, { 1.5, 0.38 } } },
        { 1.45, { { 1.24, -0.02 }, { 1.76, -0.02 }, { 1.5, 0.46 } } },
    }, body, HOT, glow)
    b.sheet({ 0.5, 0.15, -0.5 }, { 1.3, 0.12, -0.1 }, { 1.26, 0.12, 1.2 }, DARK)
    b.sheet({ 0.5, 0.15, -0.5 }, { 1.26, 0.12, 1.2 }, { 0.55, 0.15, 1.2 }, DARK)
    b.mirror(side)
    return b.done()
end

-- A rival: the greybox dart, re-lit: a team-colour top over a dark
-- underside and a white-hot engine plate. 10 triangles.
function M.dart(body, double, glow)
    local b = builder(double, glow)
    local v = { { 0, 0.35, -2.4 }, { -1.3, 0, 1.2 }, { 1.3, 0, 1.2 }, { 0, 0.9, 0.9 },
        { 0, -0.25, 1.0 }, { -0.45, 0.2, 1.3 }, { 0.45, 0.2, 1.3 } }
    for _, p in ipairs(v) do b.vert(p[1], p[2], p[3]) end
    b.tri(1, 2, 4, body); b.tri(1, 4, 3, body)         -- upper hull
    b.tri(1, 5, 2, UNDER); b.tri(1, 3, 5, UNDER)       -- lower hull
    b.tri(2, 6, 4, body); b.tri(3, 4, 7, body)         -- rear upper wings
    b.tri(4, 6, 7, DECK)                               -- rear deck
    b.tri(2, 5, 6, UNDER); b.tri(3, 7, 5, UNDER)       -- rear lower wings
    b.tri(6, 5, 7, HOT, glow)                          -- engine plate
    return b.done()
end

-- A city skyline: a ring of `count` towers at `radius`, for
-- drawBackground. Each tower is one quad facing the centre, its width and
-- height varied so neighbours do not line up; every third tower carries a
-- lit band of windows near its top. heights and colours are cycled; lit is
-- the window colour; unlit is the flag (gfx3d.UNLIT) every triangle gets:
-- the towers are flat silhouettes against the sky.
M.SKYLINE_BASE = -30 -- m: below the horizon, so no gap shows under the towers

function M.skyline(radius, count, heights, colours, lit, unlit)
    local verts, tris, cols, flags = {}, {}, {}, {}
    local step = 2 * pi / count
    local function quad(a0, a1, y0, y1, col)
        local base = #verts // 3
        for _, p in ipairs({ { a0, y0 }, { a1, y0 }, { a1, y1 }, { a0, y1 } }) do
            verts[#verts + 1] = radius * sin(p[1])
            verts[#verts + 1] = p[2]
            verts[#verts + 1] = -radius * cos(p[1])
        end
        for _, t in ipairs({ 1, 2, 3, 1, 3, 4 }) do tris[#tris + 1] = base + t end
        cols[#cols + 1] = col; cols[#cols + 1] = col
        flags[#flags + 1] = unlit; flags[#flags + 1] = unlit
    end
    for k = 0, count - 1 do
        local a = k * step
        local w = step * (0.55 + 0.35 * ((k * 7) % 5) / 4)
        local h = heights[(k * 3) % #heights + 1]
        local a0, a1 = a - w / 2, a + w / 2
        quad(a0, a1, M.SKYLINE_BASE, h, colours[k % #colours + 1])
        if k % 3 == 0 then
            local inset = w * 0.15
            quad(a0 + inset, a1 - inset, h * 0.82, h * 0.86, lit)
        end
    end
    return verts, tris, cols, flags
end

return M
