-- The chase camera (pure Lua). The eye sits behind the ship along the
-- track (so it follows bends and crests instead of cutting through them),
-- held as a sprung offset from the ship; it looks ahead along the ship's
-- heading, rolls with the track's banked up vector and widens its field of
-- view with speed. A jolt (a wall hit, a shove) shakes the eye up and down
-- on alternate frames, dying away in about half a second.
local track = require("src.track")

local M = {}

local exp, sqrt, sin, cos = math.exp, math.sqrt, math.sin, math.cos

-- update() reads these as VM constants, not by hashing into M.
local BACK <const> = 9         -- m behind the ship, along the track
local HEIGHT <const> = 3.2     -- m above the surface
local FOLLOW_U <const> = 0.7   -- how far the eye follows the ship's lateral offset
local AHEAD <const> = 14       -- m ahead of the ship along its heading: the look target
local LOOK_H <const> = 1.0     -- m above the ship: the look target
local SPRING <const> = 8       -- 1/s: how fast the eye offset settles
local UP_SPRING <const> = 4    -- 1/s: how fast the camera rolls to the track
local FOV <const> = 1.0        -- rad, standing still
local FOV_SPEED <const> = 0.25 -- rad added at V_REF
local V_REF <const> = 70       -- m/s
local JOLT <const> = 0.03      -- m of shake per m/s of hit
local MAX_SHAKE <const> = 0.5  -- m
local SHAKE_DECAY <const> = 10 -- 1/s
local SHAKE_MIN <const> = 0.005 -- m: smaller shakes stop
M.BACK, M.HEIGHT, M.FOLLOW_U, M.AHEAD, M.LOOK_H = BACK, HEIGHT, FOLLOW_U, AHEAD, LOOK_H
M.SPRING, M.UP_SPRING, M.FOV, M.FOV_SPEED, M.V_REF = SPRING, UP_SPRING, FOV, FOV_SPEED, V_REF
M.JOLT, M.MAX_SHAKE, M.SHAKE_DECAY, M.SHAKE_MIN = JOLT, MAX_SHAKE, SHAKE_DECAY, SHAKE_MIN

function M.new()
    return { ex = 0, ey = 0, ez = 0, tx = 0, ty = 0, tz = -1,
        ux = 0, uy = 1, uz = 0, ox = 0, oy = 0, oz = 0, fov = FOV, ready = false,
        shake = 0, flip = 1, dt = nil, k_eye = 0, k_up = 0, k_shake = 0,
        -- the followed ship's pose this frame, for render to reuse
        sx = 0, sy = 0, sz = 0, sfx = 0, sfy = 0, sfz = 0, sux = 0, suy = 0, suz = 0 }
end

-- The ship's world position, forward vector (heading psi off the track)
-- and up vector. Lerps the ring frames without renormalising: neighbouring
-- rings differ by a few degrees, so the vectors are within 0.5% of unit
-- length, and gfx3d.drawBasis normalises them anyway. It runs for every
-- ship in view every frame, so it avoids track.frame's extra work.
function M.ship_pose(tr, s)
    local seg, t = s.seg, s.t
    local j, f = seg % tr.n + 1, 1 - t
    local a = tr.px
    local px = a[seg] * f + a[j] * t
    a = tr.py
    local py = a[seg] * f + a[j] * t
    a = tr.pz
    local pz = a[seg] * f + a[j] * t
    a = tr.tx
    local tx = a[seg] * f + a[j] * t
    a = tr.ty
    local ty = a[seg] * f + a[j] * t
    a = tr.tz
    local tz = a[seg] * f + a[j] * t
    a = tr.ux
    local ux = a[seg] * f + a[j] * t
    a = tr.uy
    local uy = a[seg] * f + a[j] * t
    a = tr.uz
    local uz = a[seg] * f + a[j] * t
    a = tr.rx
    local rx = a[seg] * f + a[j] * t
    a = tr.ry
    local ry = a[seg] * f + a[j] * t
    a = tr.rz
    local rz = a[seg] * f + a[j] * t
    local c, sn, u, h = cos(s.psi), sin(s.psi), s.u, s.h
    return px + rx * u + ux * h, py + ry * u + uy * h, pz + rz * u + uz * h,
        tx * c + rx * sn, ty * c + ry * sn, tz * c + rz * sn, ux, uy, uz
end

-- A hit of `impact` m/s (speed lost to a wall, sideways speed from a shove).
function M.jolt(cam, impact)
    local a = cam.shake + impact * JOLT
    cam.shake = a < MAX_SHAKE and a or MAX_SHAKE
end

function M.update(cam, tr, s, dt)
    local sx, sy, sz, fx, fy, fz, ux, uy, uz = M.ship_pose(tr, s)
    cam.sx, cam.sy, cam.sz, cam.sfx, cam.sfy, cam.sfz = sx, sy, sz, fx, fy, fz
    cam.sux, cam.suy, cam.suz = ux, uy, uz
    local bseg, bt = track.advance(tr, s.seg, s.t, -BACK)
    local ex, ey, ez = track.point(tr, bseg, bt, s.u * FOLLOW_U, HEIGHT)
    local ox, oy, oz = ex - sx, ey - sy, ez - sz
    if cam.dt ~= dt then -- the spring factors depend only on dt, which is fixed
        cam.dt, cam.k_eye, cam.k_up = dt, 1 - exp(-SPRING * dt), 1 - exp(-UP_SPRING * dt)
        cam.k_shake = exp(-SHAKE_DECAY * dt)
    end
    if not cam.ready then
        cam.ox, cam.oy, cam.oz = ox, oy, oz
        cam.ux, cam.uy, cam.uz = ux, uy, uz
        cam.ready = true
    else
        local k = cam.k_eye
        local cx, cy, cz = cam.ox, cam.oy, cam.oz
        cam.ox = cx + (ox - cx) * k
        cam.oy = cy + (oy - cy) * k
        cam.oz = cz + (oz - cz) * k
        k = cam.k_up
        cx, cy, cz = cam.ux, cam.uy, cam.uz
        local nx = cx + (ux - cx) * k
        local ny = cy + (uy - cy) * k
        local nz = cz + (uz - cz) * k
        local l = 1 / sqrt(nx * nx + ny * ny + nz * nz)
        cam.ux, cam.uy, cam.uz = nx * l, ny * l, nz * l
    end
    local cex, cey, cez = sx + cam.ox, sy + cam.oy, sz + cam.oz
    local shake = cam.shake
    if shake > 0 then
        local a = shake * cam.flip
        cex, cey, cez = cex + cam.ux * a, cey + cam.uy * a, cez + cam.uz * a
        cam.flip = -cam.flip
        shake = shake * cam.k_shake
        cam.shake = shake < SHAKE_MIN and 0 or shake
    end
    cam.ex, cam.ey, cam.ez = cex, cey, cez
    local lx, ly, lz = sx + ux * LOOK_H, sy + uy * LOOK_H, sz + uz * LOOK_H
    cam.tx, cam.ty, cam.tz = lx + fx * AHEAD, ly + fy * AHEAD, lz + fz * AHEAD
    local f = s.v / V_REF
    cam.fov = FOV + FOV_SPEED * (f < 1 and f or 1)
end

return M
