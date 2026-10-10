-- The chase camera (pure Lua). The eye sits behind the ship along the
-- track (so it follows bends and crests instead of cutting through them),
-- held as a sprung offset from the ship; it looks ahead along the ship's
-- heading, rolls with the track's banked up vector and widens its field of
-- view with speed. A jolt (a wall hit, a shove) shakes the eye up and down
-- on alternate frames, dying away in about half a second.
local track = require("src.track")

local M = {}

local exp, sqrt, sin, cos, min = math.exp, math.sqrt, math.sin, math.cos, math.min

M.BACK = 9         -- m behind the ship, along the track
M.HEIGHT = 3.2     -- m above the surface
M.FOLLOW_U = 0.7   -- how far the eye follows the ship's lateral offset
M.AHEAD = 14       -- m ahead of the ship along its heading: the look target
M.LOOK_H = 1.0     -- m above the ship: the look target
M.SPRING = 8       -- 1/s: how fast the eye offset settles
M.UP_SPRING = 4    -- 1/s: how fast the camera rolls to the track
M.FOV = 1.0        -- rad, standing still
M.FOV_SPEED = 0.25 -- rad added at V_REF
M.V_REF = 70       -- m/s
M.JOLT = 0.03      -- m of shake per m/s of hit
M.MAX_SHAKE = 0.5  -- m
M.SHAKE_DECAY = 10 -- 1/s
M.SHAKE_MIN = 0.005 -- m: smaller shakes stop

function M.new()
    return { ex = 0, ey = 0, ez = 0, tx = 0, ty = 0, tz = -1,
        ux = 0, uy = 1, uz = 0, ox = 0, oy = 0, oz = 0, fov = M.FOV, ready = false,
        shake = 0, flip = 1 }
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
    local a = cam.shake + impact * M.JOLT
    cam.shake = a < M.MAX_SHAKE and a or M.MAX_SHAKE
end

function M.update(cam, tr, s, dt)
    local sx, sy, sz, fx, fy, fz, ux, uy, uz = M.ship_pose(tr, s)
    local bseg, bt = track.advance(tr, s.seg, s.t, -M.BACK)
    local ex, ey, ez = track.point(tr, bseg, bt, s.u * M.FOLLOW_U, M.HEIGHT)
    local ox, oy, oz = ex - sx, ey - sy, ez - sz
    if not cam.ready then
        cam.ox, cam.oy, cam.oz = ox, oy, oz
        cam.ux, cam.uy, cam.uz = ux, uy, uz
        cam.ready = true
    else
        local k = 1 - exp(-M.SPRING * dt)
        cam.ox = cam.ox + (ox - cam.ox) * k
        cam.oy = cam.oy + (oy - cam.oy) * k
        cam.oz = cam.oz + (oz - cam.oz) * k
        k = 1 - exp(-M.UP_SPRING * dt)
        local nx = cam.ux + (ux - cam.ux) * k
        local ny = cam.uy + (uy - cam.uy) * k
        local nz = cam.uz + (uz - cam.uz) * k
        local l = 1 / sqrt(nx * nx + ny * ny + nz * nz)
        cam.ux, cam.uy, cam.uz = nx * l, ny * l, nz * l
    end
    cam.ex, cam.ey, cam.ez = sx + cam.ox, sy + cam.oy, sz + cam.oz
    if cam.shake > 0 then
        local a = cam.shake * cam.flip
        cam.ex, cam.ey, cam.ez = cam.ex + cam.ux * a, cam.ey + cam.uy * a, cam.ez + cam.uz * a
        cam.flip = -cam.flip
        cam.shake = cam.shake * exp(-M.SHAKE_DECAY * dt)
        if cam.shake < M.SHAKE_MIN then cam.shake = 0 end
    end
    local lx, ly, lz = sx + ux * M.LOOK_H, sy + uy * M.LOOK_H, sz + uz * M.LOOK_H
    cam.tx, cam.ty, cam.tz = lx + fx * M.AHEAD, ly + fy * M.AHEAD, lz + fz * M.AHEAD
    cam.fov = M.FOV + M.FOV_SPEED * min(1, s.v / M.V_REF)
end

return M
