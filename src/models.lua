-- Model data (pure Lua): flat vertex, triangle and colour lists for
-- gfx3d.newMesh. Models face -z (gfx3d's convention); triangles run
-- counter-clockwise seen from outside.
local M = {}

local sin, cos, pi = math.sin, math.cos, math.pi

-- The player's ship: a flat dart, nose at -z. body/trim are colours.
function M.ship(body, trim)
    local verts = {
        0, 0.35, -2.4,   -- 1 nose
        -1.3, 0, 1.2,    -- 2 left tail
        1.3, 0, 1.2,     -- 3 right tail
        0, 0.9, 0.9,     -- 4 fin top
        0, -0.25, 1.0,   -- 5 keel
        -0.45, 0.2, 1.3, -- 6 left engine
        0.45, 0.2, 1.3,  -- 7 right engine
    }
    local tris = {
        1, 2, 4,   1, 4, 3,     -- upper hull
        1, 5, 2,   1, 3, 5,     -- lower hull
        2, 6, 4,   3, 4, 7,     -- rear upper wings
        4, 6, 7,                -- rear deck
        2, 5, 6,   3, 7, 5,     -- rear lower wings
        6, 5, 7,                -- engine plate
    }
    local cols = { body, body, trim, trim, body, body, trim, trim, trim, trim }
    return verts, tris, cols
end

-- A ring of `count` mountain peaks at `radius`, for drawBackground: each is
-- one triangle facing the centre, overlapping its neighbours. heights and
-- colours are lists cycled around the ring.
function M.mountains(radius, count, heights, colors)
    local verts, tris, cols = {}, {}, {}
    local step = 2 * pi / count
    for k = 0, count - 1 do
        local a = k * step
        local a0, a1 = a - step * 0.9, a + step * 0.9
        local h = heights[k % #heights + 1]
        local base = #verts // 3
        verts[#verts + 1] = radius * sin(a0); verts[#verts + 1] = -radius * 0.05
        verts[#verts + 1] = -radius * cos(a0)
        verts[#verts + 1] = radius * sin(a1); verts[#verts + 1] = -radius * 0.05
        verts[#verts + 1] = -radius * cos(a1)
        verts[#verts + 1] = radius * sin(a); verts[#verts + 1] = h
        verts[#verts + 1] = -radius * cos(a)
        tris[#tris + 1] = base + 1; tris[#tris + 1] = base + 2; tris[#tris + 1] = base + 3
        cols[#cols + 1] = colors[k % #colors + 1]
    end
    return verts, tris, cols
end

return M
