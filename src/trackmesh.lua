-- Track chunk meshes as plain data (pure Lua): for each run of CHUNK
-- segments, a road mesh (road, pads, start line, walls) and a ground mesh
-- (checkered strips beside the walls). Every vertex is in world coordinates,
-- computed from the track's ring arrays, so neighbouring chunks share their
-- seam vertices bit for bit. render.lua turns the data into gfx3d meshes.
local M = {}

M.CHUNK = 8        -- segments per chunk
M.WALL_H = 1.2     -- m
M.GROUND_W = 40    -- m of ground beside each wall
M.GROUND_DROP = 0.3 -- m: the ground sits this far below the road edge

-- pal: colours (integers): road = {a, b} (alternating stripes), line (the
-- start segment), pad, wall = {a, b}, ground = {a, b}, recharge = {a, b}
-- (the recharge strip's stripes). double: the flag value
-- for double-sided triangles (gfx3d.DOUBLE_SIDED), used on walls.
-- Returns { chunks = { {first, last, road = {verts, tris, cols, flags},
-- ground = {verts, tris, cols}}, ... }, of = {[seg] = chunk index} }.
function M.build(tr, pal, double)
    local n = tr.n
    local px, py, pz, ux, uy, uz = tr.px, tr.py, tr.pz, tr.ux, tr.uy, tr.uz
    local rx, ry, rz, w = tr.rx, tr.ry, tr.rz, tr.w
    local out = { chunks = {}, of = {} }

    for first = 1, n, M.CHUNK do
        local last = math.min(first + M.CHUNK - 1, n)
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
        local function gvert(x, y, z)
            gv[#gv + 1] = x; gv[#gv + 1] = y; gv[#gv + 1] = z
            gn = gn + 1
            return gn
        end
        local function gtri(a, b, c, col)
            gt[#gt + 1] = a; gt[#gt + 1] = b; gt[#gt + 1] = c
            gc[#gc + 1] = col
        end
        -- The point on ring r, u metres right of centre and h above it.
        local function at(r, u, h)
            return px[r] + rx[r] * u + ux[r] * h, py[r] + ry[r] * u + uy[r] * h,
                pz[r] + rz[r] * u + uz[r] * h
        end

        -- Ring vertices for rings first .. last + 1 (the last wraps to 1).
        local L, E, Lt, Et, Lg, Eg, Li, Ei = {}, {}, {}, {}, {}, {}, {}, {}
        for i = first, last + 1 do
            local r = (i - 1) % n + 1
            local hw = w[r] * 0.5
            L[i] = rvert(at(r, -hw, 0))
            E[i] = rvert(at(r, hw, 0))
            Lt[i] = rvert(at(r, -hw, M.WALL_H))
            Et[i] = rvert(at(r, hw, M.WALL_H))
            local x, y, z = at(r, -hw, 0)
            Li[i] = gvert(x, y - M.GROUND_DROP, z)
            x, y, z = at(r, -hw - M.GROUND_W, 0)
            Lg[i] = gvert(x, y - M.GROUND_DROP, z)
            x, y, z = at(r, hw, 0)
            Ei[i] = gvert(x, y - M.GROUND_DROP, z)
            x, y, z = at(r, hw + M.GROUND_W, 0)
            Eg[i] = gvert(x, y - M.GROUND_DROP, z)
        end

        for i = first, last do
            local seg, j = i, i + 1
            out.of[seg] = #out.chunks + 1
            local stripe = pal.road[seg % 2 + 1]
            if tr.recharge[seg] then stripe = pal.recharge[seg % 2 + 1] end
            if seg == 1 then stripe = pal.line end
            local id = tr.padid[seg]
            if id then
                -- road | pad | road across the segment
                local r0, r1 = seg, seg % n + 1
                local lo, hi = tr.padlo[seg], tr.padhi[seg]
                local a0, a1 = rvert(at(r0, lo, 0)), rvert(at(r1, lo, 0))
                local b0, b1 = rvert(at(r0, hi, 0)), rvert(at(r1, hi, 0))
                rtri(L[i], a0, a1, stripe, 0); rtri(L[i], a1, L[j], stripe, 0)
                rtri(a0, b0, b1, pal.pad, 0); rtri(a0, b1, a1, pal.pad, 0)
                rtri(b0, E[i], E[j], stripe, 0); rtri(b0, E[j], b1, stripe, 0)
            else
                rtri(L[i], E[i], E[j], stripe, 0); rtri(L[i], E[j], L[j], stripe, 0)
            end
            local wall = pal.wall[seg % 2 + 1]
            rtri(L[i], L[j], Lt[j], wall, double); rtri(L[i], Lt[j], Lt[i], wall, double)
            rtri(E[i], Et[i], Et[j], wall, double); rtri(E[i], Et[j], E[j], wall, double)
        end

        -- Ground: one quad per four segments on each side, checkered.
        local i = first
        while i <= last do
            local j = math.min(i + 4, last + 1)
            local q = (i - 1) // 4
            local ca, cb = pal.ground[q % 2 + 1], pal.ground[(q + 1) % 2 + 1]
            gtri(Lg[i], Li[i], Li[j], ca); gtri(Lg[i], Li[j], Lg[j], ca)
            gtri(Ei[i], Eg[i], Eg[j], cb); gtri(Ei[i], Eg[j], Ei[j], cb)
            i = j
        end

        out.chunks[#out.chunks + 1] = { first = first, last = last,
            road = { rv, rt, rc, rf }, ground = { gv, gt, gc } }
    end
    return out
end

return M
