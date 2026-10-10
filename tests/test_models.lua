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

local DOUBLE, GLOW = 16, 3
local BODY = 101
local SHIPS = { needle = 22, twin_pod = 40, dart = 10 }
-- A triangle narrower than this (about 3.5 pixels at the chase camera's
-- 9 m) rasterises to a different scatter of pixels every frame: it sparkles.
local SLIVER = 0.18 -- m

-- The model's parts: groups of triangles joined by shared vertices.
local function parts(t)
    local up = {}
    local function find(i)
        while up[i] and up[i] ~= i do i = up[i] end
        return i
    end
    for k = 1, #t // 3 do
        local a = find(t[3 * k - 2])
        for d = 1, 2 do
            local b = find(t[3 * k - 2 + d])
            if a ~= b then up[b] = a end
        end
    end
    return find
end

return {
    ships_have_their_triangle_counts = function()
        for name, want in pairs(SHIPS) do
            local v, t, c, f = models[name](BODY, DOUBLE, GLOW)
            T.eq(#t // 3, want, name)
            T.eq(#c, want, name .. " colours"); T.eq(#f, want, name .. " flags")
            T.eq(#v % 3, 0)
            for _, i in ipairs(t) do T.ok(i >= 1 and i <= #v // 3, name .. " index " .. i) end
        end
    end,
    ship_noses_point_minus_z = function()
        for name in pairs(SHIPS) do
            local v = models[name](BODY, DOUBLE, GLOW)
            local minz, x = math.huge, nil
            for i = 1, #v // 3 do
                local vx, _, z = vert(v, i)
                if z < minz then minz, x = z, vx end
            end
            T.ok(minz < -2, name .. " nose " .. minz); T.eq(x, 0, name .. " nose on the centre line")
        end
    end,
    ship_hulls_are_closed_and_face_out = function()
        for name in pairs(SHIPS) do
            local v, t, _, f = models[name](BODY, DOUBLE, GLOW)
            local find = parts(t)
            -- each part's centroid, over its one-sided triangles' vertices
            local sum, edges = {}, {}
            for k = 1, #t // 3 do
                if f[k] & DOUBLE == 0 then
                    local p = find(t[3 * k - 2])
                    local s_ = sum[p] or { 0, 0, 0, 0 }
                    for d = 0, 2 do
                        local x, y, z = vert(v, t[3 * k - 2 + d])
                        s_[1], s_[2], s_[3], s_[4] = s_[1] + x, s_[2] + y, s_[3] + z, s_[4] + 1
                        local a, b = t[3 * k - 2 + d], t[3 * k - 2 + (d + 1) % 3]
                        local key = a .. ">" .. b
                        T.ok(not edges[key], name .. ": edge " .. key .. " used twice the same way")
                        edges[key] = true
                    end
                    sum[p] = s_
                end
            end
            for key in pairs(edges) do
                local a, b = key:match("(%d+)>(%d+)")
                T.ok(edges[b .. ">" .. a], name .. ": open edge " .. key)
            end
            for k = 1, #t // 3 do
                if f[k] & DOUBLE == 0 then
                    local s_ = sum[find(t[3 * k - 2])]
                    local nx, ny, nz, gx, gy, gz = normal_and_centroid(v, t[3 * k - 2], t[3 * k - 1], t[3 * k])
                    local d = nx * (gx - s_[1] / s_[4]) + ny * (gy - s_[2] / s_[4]) + nz * (gz - s_[3] / s_[4])
                    T.ok(d > 0, name .. " triangle " .. k .. " faces out")
                end
            end
        end
    end,
    ships_wear_the_team_colour_and_a_glowing_engine = function()
        for name in pairs(SHIPS) do
            local _, t, c, f = models[name](BODY, DOUBLE, GLOW)
            local body, glow = 0, 0
            for k = 1, #t // 3 do
                if c[k] == BODY then body = body + 1 end
                if f[k] & GLOW == GLOW then glow = glow + 1 end
            end
            T.ok(body >= 2, name .. " body " .. body)
            T.ok(glow >= 1, name .. ": the engine glows")
        end
    end,
    no_ship_triangle_is_a_sliver = function()
        for name in pairs(SHIPS) do
            local v, t = models[name](BODY, DOUBLE, GLOW)
            for k = 1, #t // 3 do
                local nx, ny, nz = normal_and_centroid(v, t[3 * k - 2], t[3 * k - 1], t[3 * k])
                local longest = 0
                for d = 0, 2 do
                    local ax, ay, az = vert(v, t[3 * k - 2 + d])
                    local bx, by, bz = vert(v, t[3 * k - 2 + (d + 1) % 3])
                    longest = math.max(longest, math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2 + (bz - az) ^ 2))
                end
                local height = math.sqrt(nx * nx + ny * ny + nz * nz) / longest
                T.ok(height >= SLIVER, name .. " triangle " .. k .. " is a sliver, " .. height .. " m across")
            end
        end
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
        -- every lit band at least 2 pixels tall at the camera's widest view
        -- (fovY 1.25 rad over 240 rows), or it sparkles as the view turns
        local px_per_m = 120 / math.tan(1.25 / 2) / 500
        for k = 1, #t // 3 do
            if c[k] == 12 then
                local lo, hi = math.huge, -math.huge
                for d = 0, 2 do
                    local _, y = vert(v, t[3 * k - 2 + d])
                    lo, hi = math.min(lo, y), math.max(hi, y)
                end
                T.ok((hi - lo) * px_per_m >= 2, "window band " .. k .. ": " .. (hi - lo) * px_per_m .. " px")
            end
        end
        local top = -math.huge
        for i = 1, 4 do
            local _, y = vert(v, i)
            top = math.max(top, y)
        end
        T.eq(top, 60, "first tower height")
    end,
}
