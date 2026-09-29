local T = require("tests.t")
local F = require("tests.fixtures")
local physics = require("src.physics")
local ai = require("src.ai")
local camera = require("src.camera")

local DT = 1 / 30

local function sub(ax, ay, az, bx, by, bz) return ax - bx, ay - by, az - bz end
local function dot(ax, ay, az, bx, by, bz) return ax * bx + ay * by + az * bz end

return {
    snaps_behind_and_above_on_first_update = function()
        local tr = F.track1()
        local s = physics.new_ship(10, 0, 0)
        local cam = camera.new()
        camera.update(cam, tr, s, DT)
        local sx, sy, sz, fx, fy, fz = camera.ship_pose(tr, s)
        local bx, by, bz = sub(sx, sy, sz, cam.ex, cam.ey, cam.ez)
        T.ok(dot(bx, by, bz, fx, fy, fz) > camera.BACK * 0.8, "behind")
        T.ok(cam.ey > sy + 1.5, "above")
        local ax, ay, az = sub(cam.tx, cam.ty, cam.tz, sx, sy, sz)
        T.ok(dot(ax, ay, az, fx, fy, fz) > camera.AHEAD * 0.8, "looks ahead")
    end,
    ship_pose_matches_the_track_frame = function()
        local tr = F.track1()
        local track = require("src.track")
        local s = physics.new_ship(123, 0.37, 3.5)
        s.h, s.psi = 1.1, 0.2
        local x, y, z, fx, fy, fz, ux, uy, uz = camera.ship_pose(tr, s)
        local wx, wy, wz = track.point(tr, 123, 0.37, 3.5, 1.1)
        T.near(x, wx, 0.05); T.near(y, wy, 0.05); T.near(z, wz, 0.05)
        local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
        T.near(fl, 1, 0.01, "forward is near unit length")
        local _, _, _, tx, ty, tz, _, _, _, rx, ry, rz = track.frame(tr, 123, 0.37)
        local want = { tx * math.cos(0.2) + rx * math.sin(0.2), ty * math.cos(0.2) + ry * math.sin(0.2),
            tz * math.cos(0.2) + rz * math.sin(0.2) }
        T.near(fx / fl, want[1], 0.01); T.near(fy / fl, want[2], 0.01); T.near(fz / fl, want[3], 0.01)
    end,
    fov_widens_with_speed_and_caps = function()
        local tr = F.track1()
        local cam, s = camera.new(), physics.new_ship(10, 0, 0)
        camera.update(cam, tr, s, DT)
        T.near(cam.fov, camera.FOV, 1e-6)
        s.v = 1000
        camera.update(cam, tr, s, DT)
        T.near(cam.fov, camera.FOV + camera.FOV_SPEED, 1e-6)
    end,
    eye_offset_is_sprung = function()
        local tr = F.track1()
        local cam, s = camera.new(), physics.new_ship(10, 0, 0)
        camera.update(cam, tr, s, DT)
        local ox = cam.ox
        s.u = 8
        camera.update(cam, tr, s, DT)
        local moved = math.abs(cam.ox - ox)
        for _ = 1, 60 do camera.update(cam, tr, s, DT) end
        local settled = math.abs(cam.ox - ox)
        T.ok(moved > 0 and moved < settled * 0.5, "one frame moves part of the way")
    end,
    lookat_stays_valid_for_a_whole_lap = function()
        -- gfx3d.lookAt raises when eye == target or up is parallel to the
        -- view direction: neither may happen anywhere on the lap.
        local tr = F.track1()
        local line = ai.prepare(tr, physics.P)
        local s, c, cam, d = physics.new_ship(), {}, camera.new(), ai.new_driver(1, 0)
        local frames = 0
        while s.lap < 1 and frames < 30 * 90 do
            ai.controls(tr, line, { s }, 1, d, physics.P, 0, c)
            physics.step(tr, s, c, DT / 2)
            physics.step(tr, s, c, DT / 2)
            camera.update(cam, tr, s, DT)
            local dx, dy, dz = sub(cam.tx, cam.ty, cam.tz, cam.ex, cam.ey, cam.ez)
            local d = math.sqrt(dot(dx, dy, dz, dx, dy, dz))
            T.ok(d > 5, "eye to target " .. d)
            T.ok(math.abs(dot(dx / d, dy / d, dz / d, cam.ux, cam.uy, cam.uz)) < 0.9, "up vs view")
            T.near(dot(cam.ux, cam.uy, cam.uz, cam.ux, cam.uy, cam.uz), 1, 1e-4, "|up|")
            frames = frames + 1
        end
        T.eq(s.lap, 1)
    end,
}
