-- gfx3d glue: builds the meshes once, then submits each frame.
local trackmesh = require("src.trackmesh")
local models = require("src.models")
local camera = require("src.camera")

local M = {}

local g3 = picocalc.gfx3d
local rgb = picocalc.display.rgb

M.VIEW_W, M.VIEW_H = 320, 240 -- the HUD panel takes the bottom 80 rows
M.NEAR, M.FAR = 0.5, 260
M.FOG_NEAR, M.FOG_FAR = 90, 250
M.GROUND_BIAS = 60 -- m: the ground sorts behind the road beside it
M.BEHIND = 30      -- m: a ship further behind the camera's ship is not drawn
M.SHIP_FAR = 160   -- m: nor one further ahead (fog has it down to a speck)

local HORIZON = rgb(236, 170, 120)

-- Ship colours, player first: { body, trim } per ship.
M.SHIP_COLOURS = {
    { rgb(240, 200, 40), rgb(40, 60, 160) },
    { rgb(220, 60, 60), rgb(250, 250, 250) },
    { rgb(60, 200, 90), rgb(20, 40, 30) },
    { rgb(230, 120, 30), rgb(40, 40, 40) },
    { rgb(150, 80, 220), rgb(240, 220, 90) },
    { rgb(60, 190, 230), rgb(20, 30, 90) },
}

local function palette()
    return {
        road = { rgb(88, 92, 108), rgb(104, 108, 124) },
        line = rgb(235, 235, 235),
        pad = rgb(40, 220, 240),
        wall = { rgb(210, 60, 70), rgb(235, 235, 235) },
        ground = { rgb(60, 120, 70), rgb(50, 102, 60) },
        recharge = { rgb(200, 80, 200), rgb(170, 60, 180) },
    }
end

-- Returns the scene: gfx3d meshes for the track chunks, the ships (one per
-- colour) and the mountain ring, with the chunk index of every segment.
function M.init(tr)
    local data = trackmesh.build(tr, palette(), g3.DOUBLE_SIDED)
    local roads, grounds = {}, {}
    for i, ch in ipairs(data.chunks) do
        roads[i] = g3.newMesh(ch.road[1], ch.road[2], ch.road[3], ch.road[4])
        grounds[i] = g3.newMesh(ch.ground[1], ch.ground[2], ch.ground[3])
    end
    local ships = {}
    for i, col in ipairs(M.SHIP_COLOURS) do
        local v, t, c = models.ship(col[1], col[2])
        ships[i] = g3.newMesh(v, t, c)
    end
    local v, t, c = models.mountains(600, 28, { 70, 110, 55, 90, 130, 60, 85 },
        { rgb(96, 84, 130), rgb(84, 74, 118), rgb(108, 94, 140) })
    local mountains = g3.newMesh(v, t, c)

    g3.setViewport(0, 0, M.VIEW_W, M.VIEW_H)
    g3.setLight(0.4, 1, 0.3, 0.35)
    g3.setSky({ { -1.2, rgb(58, 110, 66) }, { 0, HORIZON },
        { 0.06, rgb(130, 150, 220) }, { 0.35, rgb(50, 60, 150) } })
    g3.setFog(M.FOG_NEAR, M.FOG_FAR, HORIZON)
    return { roads = roads, grounds = grounds, of = data.of, ships = ships, mountains = mountains }
end

-- One frame into the back buffer's viewport (the caller flushes). ships[1]
-- is the one the camera follows; a ship further than BEHIND behind it or
-- SHIP_FAR ahead is skipped before any pose maths.
function M.draw(scene, tr, ships, cam)
    g3.setProjection(cam.fov, M.NEAR, M.FAR)
    g3.lookAt(cam.ex, cam.ey, cam.ez, cam.tx, cam.ty, cam.tz, cam.ux, cam.uy, cam.uz)
    g3.beginScene()
    g3.drawBackground(scene.mountains)
    local me = ships[1]
    local len, half, total = tr.len, tr.total * 0.5, tr.total
    for i = 1, #ships do
        local s = ships[i]
        local ds = ((s.seg - me.seg) + (s.t - me.t)) * len
        if ds > half then ds = ds - total elseif ds < -half then ds = ds + total end
        if ds > -M.BEHIND and ds < M.SHIP_FAR then
            local sx, sy, sz, fx, fy, fz, ux, uy, uz = camera.ship_pose(tr, s)
            g3.drawBasis(scene.ships[(i - 1) % #scene.ships + 1], sx, sy, sz, fx, fy, fz, ux, uy, uz, 1, 0, true)
        end
    end
    -- Every chunk, nearest first: from the one behind the ship's, forwards,
    -- in one drawList call per mesh set (a draw() per chunk cost ~4.7 ms a
    -- frame in Lua->C calls). gfx3d culls those outside the view or beyond FAR.
    local first = (scene.of[me.seg] - 2) % #scene.roads + 1
    g3.drawList(scene.roads, 0, first)
    g3.drawList(scene.grounds, M.GROUND_BIAS, first)
    g3.endScene()
end

return M
