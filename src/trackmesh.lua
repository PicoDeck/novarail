-- Track chunk meshes as plain data (pure Lua): for each run of CHUNK
-- segments, a road mesh (road, pads, start line, centre dashes, the low
-- glowing barriers, pylons and gantries) and a ground mesh (squares of a
-- flat checkered grid far below). Every road vertex is in world coordinates,
-- computed from the track's ring arrays, so neighbouring chunks share their
-- seam vertices bit for bit. render.lua turns the data into gfx3d meshes.
local M = {}

local floor, sqrt, min = math.floor, math.sqrt, math.min

M.CHUNK = 8          -- segments per chunk
M.BARRIER_H = 0.6    -- m
M.CHEVRON_K = 0.008  -- 1/m: bends tighter than this (radius ~125 m) get chevrons outside
-- The centre dash: one thin triangle every other segment, DASH_LEN long
-- from the segment's first ring. It stays inside the road triangle that
-- starts at that ring and is submitted after it, so it sorts on top.
M.DASH_W = 0.35      -- m
M.DASH_LEN = 3.5     -- m (under half the segment)
M.DASH_H = 0.02      -- m above the road
-- The ground: a flat world-aligned grid of CELL-metre squares at GROUND_Y,
-- under the road and out to GROUND_W beyond each barrier.
M.GROUND_Y = -18     -- m
M.GROUND_W = 60      -- m
M.CELL = 96          -- m
-- Pylons under the road centre, where the road is high enough to show one.
-- Pylons and gantries come every 16 and 32 segments: at 8 and 16 the
-- device's heaviest frames ran 0.9 ms over budget.
M.PYLON_EVERY = 16   -- segments
M.PYLON_MIN_H = 6    -- m of road above the ground
M.PYLON_W = 1.6      -- m
M.PYLON_TOP = 0.3    -- m under the road surface
-- Gantries over the road: two legs and a glowing beam.
M.GANTRY_EVERY = 32  -- segments
M.GANTRY_H = 7.5     -- m: the beam's underside
M.START_H = 9        -- m: the start gantry is taller
M.BEAM = 0.5         -- m: beam depth
M.LEG = 0.8          -- m: leg width
M.LEG_GAP = 0.3      -- m between a leg and its barrier

-- pal: colours (integers): road = {a, b} (alternating bands), line (the
-- start segment), pad, recharge = {a, b}, dash, barrier = {a, b},
-- chevron = {a, b}, ground = {a, b}, pylon, gantry (legs), beam, start_beam.
-- double: the flag for double-sided triangles (gfx3d.DOUBLE_SIDED); glow:
-- the flags for unlit, unfogged triangles (gfx3d.UNLIT + gfx3d.NO_FOG).
-- Returns { chunks = { {first, last, road = {verts, tris, cols, flags},
-- ground = {verts, tris, cols}}, ... }, of = {[seg] = chunk index} }. A
-- chunk's ground can be empty (its lists hold nothing).
function M.build(tr, pal, double, glow)
    local n = tr.n
    local px, py, pz, ux, uy, uz = tr.px, tr.py, tr.pz, tr.ux, tr.uy, tr.uz
    local rx, ry, rz, w, kr = tr.rx, tr.ry, tr.rz, tr.w, tr.kr
    local out = { chunks = {}, of = {} }
    local dglow = double | glow

    -- The point on ring r, u metres right of centre and h above it.
    local function at(r, u, h)
        return px[r] + rx[r] * u + ux[r] * h, py[r] + ry[r] * u + uy[r] * h,
            pz[r] + rz[r] * u + uz[r] * h
    end

    -- The ground squares: every one a ring's cross-section reaches, keyed
    -- "cx,cz". Each goes to the chunk of the ring nearest its centre, so
    -- gfx3d culls it with the road around it; a chunk can end up with none.
    local seen, cells_of = {}, {}
    for r = 1, n do
        local reach = w[r] * 0.5 + M.GROUND_W
        local steps = 2 * floor(reach / (M.CELL * 0.5)) + 2
        for k = 0, steps do
            local x, _, z = at(r, -reach + 2 * reach * k / steps, 0)
            local cx, cz = floor(x / M.CELL), floor(z / M.CELL)
            local key = cx .. "," .. cz
            if not seen[key] then
                seen[key] = true
                local mx, mz = (cx + 0.5) * M.CELL, (cz + 0.5) * M.CELL
                local best, near = math.huge, 1
                for q = 1, n do
                    local dx, dz = px[q] - mx, pz[q] - mz
                    local d = dx * dx + dz * dz
                    if d < best then best, near = d, q end
                end
                local c = (near - 1) // M.CHUNK + 1
                local list = cells_of[c] or {}
                list[#list + 1] = cx
                list[#list + 1] = cz
                cells_of[c] = list
            end
        end
    end

    for first = 1, n, M.CHUNK do
        local last = min(first + M.CHUNK - 1, n)
        local rv, rt, rc, rf, rn = {}, {}, {}, {}, 0
        local gv, gt, gc, gn = {}, {}, {}, 0

        local function rvert(x, y, z)
            rv[#rv + 1] = x; rv[#rv + 1] = y; rv[#rv + 1] = z
            rn = rn + 1
            return rn
        end
        local function rtri(a, b, c, col, flag)
            rt[#rt + 1] = a; rt[#rt + 1] = b; rt[#rt + 1] = c
            rc[#rc + 1] = col; rf[#rf + 1] = flag
        end
        local function rquad(a, b, c, d, col, flag)
            rtri(a, b, c, col, flag); rtri(a, c, d, col, flag)
        end
        local function gvert(x, z)
            gv[#gv + 1] = x; gv[#gv + 1] = M.GROUND_Y; gv[#gv + 1] = z
            gn = gn + 1
            return gn
        end

        -- Ring vertices for rings first .. last + 1 (the last wraps to 1).
        local L, E, Lt, Et = {}, {}, {}, {}
        for i = first, last + 1 do
            local r = (i - 1) % n + 1
            local hw = w[r] * 0.5
            L[i] = rvert(at(r, -hw, 0))
            E[i] = rvert(at(r, hw, 0))
            Lt[i] = rvert(at(r, -hw, M.BARRIER_H))
            Et[i] = rvert(at(r, hw, M.BARRIER_H))
        end

        for i = first, last do
            local seg, j = i, i + 1
            local r0, r1 = seg, seg % n + 1
            out.of[seg] = #out.chunks + 1
            local band, flag = pal.road[seg % 2 + 1], 0
            if tr.recharge[seg] then band, flag = pal.recharge[seg % 2 + 1], glow end
            if seg == 1 then band, flag = pal.line, glow end
            local id = tr.padid[seg]
            if id then
                -- road | pad | road across the segment
                local lo, hi = tr.padlo[seg], tr.padhi[seg]
                local a0, a1 = rvert(at(r0, lo, 0)), rvert(at(r1, lo, 0))
                local b0, b1 = rvert(at(r0, hi, 0)), rvert(at(r1, hi, 0))
                rtri(L[i], a0, a1, band, flag); rtri(L[i], a1, L[j], band, flag)
                rquad(a0, b0, b1, a1, pal.pad, glow)
                rtri(b0, E[i], E[j], band, flag); rtri(b0, E[j], b1, band, flag)
            else
                rtri(L[i], E[i], E[j], band, flag); rtri(L[i], E[j], L[j], band, flag)
                if seg % 2 == 0 then
                    -- inside the triangle L[i], E[i], E[j], and after it
                    local f = M.DASH_LEN / tr.len
                    local ax, ay, az = at(r0, 0, M.DASH_H)
                    local bx, by, bz = at(r1, 0, M.DASH_H)
                    local d = M.DASH_W * 0.5
                    rtri(rvert(at(r0, -d, M.DASH_H)), rvert(at(r0, d, M.DASH_H)),
                        rvert(ax + (bx - ax) * f, ay + (by - ay) * f, az + (bz - az) * f), pal.dash, glow)
                end
            end
            -- the barriers; chevrons on the outside of a tight bend
            local k = kr[seg]
            local lc, rcol = pal.barrier[seg % 2 + 1], pal.barrier[seg % 2 + 1]
            if k > M.CHEVRON_K then lc = pal.chevron[seg % 2 + 1] end
            if k < -M.CHEVRON_K then rcol = pal.chevron[seg % 2 + 1] end
            rtri(L[i], L[j], Lt[j], lc, dglow); rtri(L[i], Lt[j], Lt[i], lc, dglow)
            rtri(E[i], Et[i], Et[j], rcol, dglow); rtri(E[i], Et[j], E[j], rcol, dglow)

            -- a pylon from under the road centre down to the ground
            if (seg - 1) % M.PYLON_EVERY == M.PYLON_EVERY // 2 and py[r0] - M.GROUND_Y >= M.PYLON_MIN_H then
                local tx, ty, tz = at(r0, 0, -M.PYLON_TOP)
                local s = M.PYLON_W * 0.5
                for _, d in ipairs({ { rx[r0], rz[r0] }, { tr.tx[r0], tr.tz[r0] } }) do
                    local l = s / sqrt(d[1] * d[1] + d[2] * d[2])
                    local dx, dz = d[1] * l, d[2] * l
                    rquad(rvert(tx - dx, M.GROUND_Y, tz - dz), rvert(tx + dx, M.GROUND_Y, tz + dz),
                        rvert(tx + dx, ty, tz + dz), rvert(tx - dx, ty, tz - dz), pal.pylon, double)
                end
            end

            -- a gantry across the start of the segment
            if (seg - 1) % M.GANTRY_EVERY == 0 then
                local hw = w[r0] * 0.5
                local h = seg == 1 and M.START_H or M.GANTRY_H
                local inner, outer = hw + M.LEG_GAP, hw + M.LEG_GAP + M.LEG
                for _, side in ipairs({ -1, 1 }) do
                    rquad(rvert(at(r0, side * inner, 0)), rvert(at(r0, side * outer, 0)),
                        rvert(at(r0, side * outer, h + M.BEAM)), rvert(at(r0, side * inner, h + M.BEAM)),
                        pal.gantry, double)
                end
                rquad(rvert(at(r0, -outer, h)), rvert(at(r0, outer, h)), rvert(at(r0, outer, h + M.BEAM)),
                    rvert(at(r0, -outer, h + M.BEAM)), seg == 1 and pal.start_beam or pal.beam, dglow)
            end
        end

        -- Ground squares, checkered by their grid position.
        local cells = cells_of[#out.chunks + 1] or {}
        for c = 1, #cells, 2 do
            local cx, cz = cells[c], cells[c + 1]
            local x0, z0 = cx * M.CELL, cz * M.CELL
            local x1, z1 = x0 + M.CELL, z0 + M.CELL
            local a, b, cc, d = gvert(x0, z0), gvert(x0, z1), gvert(x1, z1), gvert(x1, z0)
            local col = pal.ground[(cx + cz) % 2 + 1]
            gt[#gt + 1] = a; gt[#gt + 1] = b; gt[#gt + 1] = cc
            gt[#gt + 1] = a; gt[#gt + 1] = cc; gt[#gt + 1] = d
            gc[#gc + 1] = col; gc[#gc + 1] = col
        end

        out.chunks[#out.chunks + 1] = { first = first, last = last,
            road = { rv, rt, rc, rf }, ground = { gv, gt, gc } }
    end
    return out
end

return M
