local T = require("tests.t")
local models = require("src.models")

local function vert(v, i) return v[3 * i - 2], v[3 * i - 1], v[3 * i] end

local function normal_and_centroid(v, a, b, c)
    local ax, ay, az = vert(v, a)
    local bx, by, bz = vert(v, b)
    local cx, cy, cz = vert(v, c)
    local ux, uy, uz = bx - ax, by - ay, bz - az
    local wx, wy, wz = cx - ax, cy - ay, cz - az
    return uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx,
        (ax + bx + cx) / 3, (ay + by + cy) / 3, (az + bz + cz) / 3
end

return {
    ship_faces_outwards = function()
        local v, t, c = models.ship(1, 2)
        local n = #v // 3
        local mx, my, mz = 0, 0, 0
        for i = 1, n do
            local x, y, z = vert(v, i)
            mx, my, mz = mx + x / n, my + y / n, mz + z / n
        end
        T.eq(#c, #t // 3)
        for k = 1, #t // 3 do
            local nx, ny, nz, gx, gy, gz = normal_and_centroid(v, t[3 * k - 2], t[3 * k - 1], t[3 * k])
            T.ok(nx * (gx - mx) + ny * (gy - my) + nz * (gz - mz) > 0, "triangle " .. k .. " faces out")
        end
    end,
    ship_nose_points_minus_z = function()
        local v = models.ship(1, 2)
        local minz, at = math.huge, 0
        for i = 1, #v // 3 do
            local _, _, z = vert(v, i)
            if z < minz then minz, at = z, i end
        end
        T.eq(at, 1, "the nose is vertex 1"); T.ok(minz < -2)
    end,
    skyline_faces_the_centre = function()
        local UNLIT = 8
        local v, t, c, f = models.skyline(500, 40, { 60, 90, 45 }, { 10, 11 }, 12, UNLIT)
        local towers, lit = 40, (40 + 2) // 3 -- a lit band on every third tower
        T.eq(#t // 3, 2 * towers + 2 * lit); T.eq(#c, #t // 3); T.eq(#f, #t // 3)
        local windows = 0
        for k = 1, #t // 3 do
            local nx, ny, nz, gx, gy, gz = normal_and_centroid(v, t[3 * k - 2], t[3 * k - 1], t[3 * k])
            T.ok(nx * gx + ny * gy + nz * gz < 0, "triangle " .. k .. " faces in")
            T.eq(f[k], UNLIT, "flat silhouettes, unlit")
            if c[k] == 12 then windows = windows + 1 end
        end
        T.eq(windows, 2 * lit)
        local top = -math.huge
        for i = 1, 4 do
            local _, y = vert(v, i)
            top = math.max(top, y)
        end
        T.eq(top, 60, "first tower height")
    end,
}
