local T = require("tests.t")
local F = require("tests.fixtures")
local trackmesh = require("src.trackmesh")

-- Distinct colours, so a test can tell the triangle kinds apart.
local PAL = { road = { 1, 2 }, line = 3, pad = 4, barrier = { 5, 6 }, ground = { 7, 8 },
    recharge = { 9, 10 }, dash = 11, chevron = { 12, 13 }, pylon = 14, gantry = 15, beam = 16,
    start_beam = 17 }
local DOUBLE, GLOW = 16, 3

local tr = F.track1()
local mesh = trackmesh.build(tr, PAL, DOUBLE, GLOW)

local UP = { [1] = true, [2] = true, [3] = true, [4] = true, [9] = true, [10] = true, [11] = true }
local BARRIER = { [5] = true, [6] = true, [12] = true, [13] = true }
local GLOWS = { [3] = true, [4] = true, [5] = true, [6] = true, [9] = true, [10] = true, [11] = true,
    [12] = true, [13] = true, [16] = true, [17] = true }

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

local function count(colour)
    local n = 0
    for _, ch in ipairs(mesh.chunks) do
        each_tri(ch.road, function(_, _, _, _, col) if col == colour then n = n + 1 end end)
    end
    return n
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
    road_faces_up_furniture_is_double_sided = function()
        for _, ch in ipairs(mesh.chunks) do
            local r = ch.first
            each_tri(ch.road, function(v, a, b, c, col, flag)
                if UP[col] then
                    local nx, ny, nz = normal(v, a, b, c)
                    T.ok(nx * tr.ux[r] + ny * tr.uy[r] + nz * tr.uz[r] > 0, "road faces up")
                    T.eq(flag & DOUBLE, 0, "the road is one-sided")
                else
                    T.eq(flag & DOUBLE, DOUBLE, "colour " .. col .. " is double-sided")
                end
            end)
        end
    end,
    glow_where_it_should = function()
        for _, ch in ipairs(mesh.chunks) do
            each_tri(ch.road, function(_, _, _, _, col, flag)
                if GLOWS[col] then
                    T.eq(flag & GLOW, GLOW, "colour " .. col .. " glows")
                else
                    T.eq(flag & GLOW, 0, "colour " .. col .. " is lit")
                end
            end)
        end
    end,
    pads_and_start_line = function()
        local pad_segs = 0
        for seg = 1, tr.n do if tr.padid[seg] then pad_segs = pad_segs + 1 end end
        T.eq(count(PAL.pad), 2 * pad_segs)
        T.eq(count(PAL.line), 2 + (tr.padid[1] and 2 or 0))
    end,
    recharge_strip_has_its_own_colours = function()
        for _, ch in ipairs(mesh.chunks) do
            local t, c = ch.road[2], ch.road[3]
            for k = 1, #t // 3 do
                -- which segment: the ring of the triangle's first vertex (4 per ring, first)
                local ring = (t[3 * k - 2] - 1) // 4
                local seg = ch.first + ring
                if seg <= ch.last and (c[k] == 1 or c[k] == 2) then
                    T.ok(not tr.recharge[seg], "plain stripe on recharge segment " .. seg)
                end
                if c[k] == 9 or c[k] == 10 then
                    T.ok(tr.recharge[seg], "recharge colour off the strip at " .. seg)
                end
            end
        end
    end,
    centre_dashes_every_other_segment = function()
        local want = 0 -- none on a pad, which marks the middle itself
        for seg = 1, tr.n do if seg % 2 == 0 and not tr.padid[seg] then want = want + 1 end end
        T.eq(count(PAL.dash), want)
    end,
    chevrons_only_outside_tight_bends = function()
        local seen = 0
        for _, ch in ipairs(mesh.chunks) do
            local t, c = ch.road[2], ch.road[3]
            for k = 1, #t // 3 do
                if BARRIER[c[k]] then
                    local v1 = t[3 * k - 2]
                    local seg = ch.first + (v1 - 1) // 4
                    local side = (v1 - 1) % 4 == 0 and -1 or 1 -- L or E ring vertex
                    local kr = tr.kr[seg]
                    local outside = math.abs(kr) > trackmesh.CHEVRON_K and (kr > 0) == (side < 0)
                    local chevron = c[k] >= 12
                    T.eq(chevron, outside, "segment " .. seg .. " side " .. side)
                    if chevron then seen = seen + 1 end
                end
            end
        end
        T.ok(seen > 0, "track 1 has chevrons")
    end,
    gantries_span_the_track = function()
        local rings = 0
        for r = 1, tr.n do if (r - 1) % trackmesh.GANTRY_EVERY == 0 then rings = rings + 1 end end
        T.eq(count(PAL.beam), 2 * (rings - 1), "a lit beam on every gantry but the start")
        T.eq(count(PAL.start_beam), 2, "the start gantry's white beam")
        T.eq(count(PAL.gantry), 4 * rings, "two legs each")
    end,
    pylons_only_where_the_road_is_high = function()
        local want = 0
        for r = 1, tr.n do
            if (r - 1) % trackmesh.PYLON_EVERY == trackmesh.PYLON_EVERY // 2
                and tr.py[r] - trackmesh.GROUND_Y >= trackmesh.PYLON_MIN_H then
                want = want + 1
            end
        end
        T.ok(want > 0)
        T.eq(count(PAL.pylon), 4 * want, "two crossed quads per pylon")
        for _, ch in ipairs(mesh.chunks) do
            each_tri(ch.road, function(v, a, b, c, col)
                if col == PAL.pylon then
                    local low = math.huge
                    for _, i in ipairs({ a, b, c }) do
                        local _, y = vert(v, i)
                        low = math.min(low, y)
                    end
                    T.ok(low >= trackmesh.GROUND_Y - 1e-3, "no pylon below the ground")
                end
            end)
        end
    end,
    ground_is_a_flat_grid_under_and_beside_the_road = function()
        local cells = {}
        for _, ch in ipairs(mesh.chunks) do
            local v = ch.ground[1]
            for i = 1, #v // 3 do T.eq(select(2, vert(v, i)), trackmesh.GROUND_Y, "flat") end
            each_tri(ch.ground, function(gv, a, b, c)
                local _, ny = normal(gv, a, b, c)
                T.ok(ny > 0, "ground faces up")
                local x0, _, z0 = vert(gv, a)
                local x1, _, z1 = vert(gv, b)
                local x2, _, z2 = vert(gv, c)
                local cx = math.floor((math.min(x0, x1, x2) + 1e-3) / trackmesh.CELL)
                local cz = math.floor((math.min(z0, z1, z2) + 1e-3) / trackmesh.CELL)
                cells[cx .. "," .. cz] = true
            end)
        end
        local function covered(x, z)
            return cells[math.floor(x / trackmesh.CELL) .. "," .. math.floor(z / trackmesh.CELL)]
        end
        for r = 1, tr.n do
            local hw = tr.w[r] * 0.5 + trackmesh.GROUND_W
            T.ok(covered(tr.px[r], tr.pz[r]), "under ring " .. r)
            for _, s in ipairs({ -1, 1 }) do
                T.ok(covered(tr.px[r] + tr.rx[r] * s * hw, tr.pz[r] + tr.rz[r] * s * hw),
                    "beside ring " .. r)
            end
        end
    end,
    triangle_budget = function()
        local total = 0
        for _, ch in ipairs(mesh.chunks) do total = total + #ch.road[2] // 3 + #ch.ground[2] // 3 end
        T.ok(total / tr.n <= 8, "triangles per segment " .. total / tr.n)
    end,
}
