local T = require("tests.t")
local F = require("tests.fixtures")
local trackmesh = require("src.trackmesh")

-- Distinct colours, so a test can tell the triangle kinds apart.
local PAL = { road = { 1, 2 }, line = 3, pad = 4, wall = { 5, 6 }, ground = { 7, 8 } }
local DOUBLE = 16

local tr = F.track1()
local mesh = trackmesh.build(tr, PAL, DOUBLE)

local function vert(v, i) return v[3 * i - 2], v[3 * i - 1], v[3 * i] end

local function normal(v, a, b, c)
    local ax, ay, az = vert(v, a)
    local bx, by, bz = vert(v, b)
    local cx, cy, cz = vert(v, c)
    local ux, uy, uz = bx - ax, by - ay, bz - az
    local wx, wy, wz = cx - ax, cy - ay, cz - az
    return uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
end

local function each_tri(m, fn)
    local v, t, c, f = m[1], m[2], m[3], m[4]
    for k = 1, #t // 3 do
        fn(v, t[3 * k - 2], t[3 * k - 1], t[3 * k], c[k], f and f[k])
    end
end

return {
    chunks_cover_every_segment = function()
        T.eq(#mesh.chunks, (tr.n + trackmesh.CHUNK - 1) // trackmesh.CHUNK)
        for seg = 1, tr.n do
            local ch = mesh.chunks[mesh.of[seg]]
            T.ok(seg >= ch.first and seg <= ch.last, "segment " .. seg)
        end
    end,
    within_gfx3d_limits = function()
        for i, ch in ipairs(mesh.chunks) do
            for _, m in ipairs({ ch.road, ch.ground }) do
                local nv, nt = #m[1] // 3, #m[2] // 3
                T.ok(nv <= 4096 and nt <= 8192, "chunk " .. i)
                T.eq(#m[1] % 3, 0); T.eq(#m[2] % 3, 0)
                T.eq(#m[3], nt, "one colour per triangle")
                if m[4] then T.eq(#m[4], nt, "one flag per triangle") end
                for _, idx in ipairs(m[2]) do T.ok(idx >= 1 and idx <= nv, "index " .. idx) end
            end
        end
    end,
    seams_are_bit_identical = function()
        -- Ring vertices come first, four per ring (L, E, Lt, Et): the last
        -- ring of a chunk and the first ring of the next are the same ring.
        for i, ch in ipairs(mesh.chunks) do
            local nxt = mesh.chunks[i % #mesh.chunks + 1]
            local rings = ch.last - ch.first + 1
            for k = 1, 4 do
                local a = { vert(ch.road[1], 4 * rings + k) }
                local b = { vert(nxt.road[1], k) }
                T.ok(a[1] == b[1] and a[2] == b[2] and a[3] == b[3], "seam after chunk " .. i)
            end
        end
    end,
    road_faces_up_walls_face_in = function()
        for _, ch in ipairs(mesh.chunks) do
            local r = ch.first
            each_tri(ch.road, function(v, a, b, c, col, flag)
                local nx, ny, nz = normal(v, a, b, c)
                local up = nx * tr.ux[r] + ny * tr.uy[r] + nz * tr.uz[r]
                if col <= 4 then
                    T.ok(up > 0, "road faces up")
                    T.eq(flag, 0)
                else
                    T.eq(flag, DOUBLE, "walls are double-sided")
                end
            end)
            each_tri(ch.ground, function(v, a, b, c)
                local _, ny = normal(v, a, b, c)
                T.ok(ny > 0, "ground faces up")
            end)
        end
    end,
    pads_and_start_line = function()
        local pad_tris, line_tris = 0, 0
        for _, ch in ipairs(mesh.chunks) do
            each_tri(ch.road, function(_, _, _, _, col)
                if col == PAL.pad then pad_tris = pad_tris + 1 end
                if col == PAL.line then line_tris = line_tris + 1 end
            end)
        end
        local pad_segs = 0
        for seg = 1, tr.n do if tr.padid[seg] then pad_segs = pad_segs + 1 end end
        T.eq(pad_tris, 2 * pad_segs)
        T.eq(line_tris, 2 + (tr.padid[1] and 2 or 0))
    end,
    triangle_budget = function()
        local total = 0
        for _, ch in ipairs(mesh.chunks) do total = total + #ch.road[2] // 3 + #ch.ground[2] // 3 end
        T.ok(total / tr.n <= 8.5, "triangles per segment " .. total / tr.n)
    end,
}
