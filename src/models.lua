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
