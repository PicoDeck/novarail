-- gfx3d glue: builds the meshes once, then submits each frame.
local trackmesh = require("src.trackmesh")
local models = require("src.models")
local camera = require("src.camera")

local M = {}

local g3 = picocalc.gfx3d
local rgb = picocalc.display.rgb

M.VIEW_W, M.VIEW_H = 320, 240 -- the HUD panel takes the bottom 80 rows
M.NEAR, M.FAR = 0.5, 340
M.FOG_NEAR, M.FOG_FAR = 120, 330
M.GROUND_BIAS = 60 -- m: the ground sorts behind the road beside it

local HORIZON = rgb(236, 170, 120)

local function palette()
    return {
        road = { rgb(88, 92, 108), rgb(104, 108, 124) },
        line = rgb(235, 235, 235),
        pad = rgb(40, 220, 240),
        wall = { rgb(210, 60, 70), rgb(235, 235, 235) },
        ground = { rgb(60, 120, 70), rgb(50, 102, 60) },
    }
end

-- Returns the scene: gfx3d meshes for the track chunks, the ship and the
-- mountain ring, with the chunk index of every segment.
function M.init(tr)
    local data = trackmesh.build(tr, palette(), g3.DOUBLE_SIDED)
    local chunks = {}
    for i, ch in ipairs(data.chunks) do
        chunks[i] = {
            road = g3.newMesh(ch.road[1], ch.road[2], ch.road[3], ch.road[4]),
            ground = g3.newMesh(ch.ground[1], ch.ground[2], ch.ground[3]),
        }
    end
    local v, t, c = models.ship(rgb(240, 200, 40), rgb(40, 60, 160))
    local ship = g3.newMesh(v, t, c)
    v, t, c = models.mountains(600, 28, { 70, 110, 55, 90, 130, 60, 85 },
        { rgb(96, 84, 130), rgb(84, 74, 118), rgb(108, 94, 140) })
    local mountains = g3.newMesh(v, t, c)

    g3.setViewport(0, 0, M.VIEW_W, M.VIEW_H)
    g3.setLight(0.4, 1, 0.3, 0.35)
    g3.setSky({ { -1.2, rgb(58, 110, 66) }, { 0, HORIZON },
        { 0.06, rgb(130, 150, 220) }, { 0.35, rgb(50, 60, 150) } })
    g3.setFog(M.FOG_NEAR, M.FOG_FAR, HORIZON)
    return { chunks = chunks, of = data.of, ship = ship, mountains = mountains }
end

-- One frame into the back buffer's viewport (the caller flushes).
function M.draw(scene, tr, s, cam)
    g3.setProjection(cam.fov, M.NEAR, M.FAR)
    g3.lookAt(cam.ex, cam.ey, cam.ez, cam.tx, cam.ty, cam.tz, cam.ux, cam.uy, cam.uz)
    g3.beginScene()
    g3.drawBackground(scene.mountains)
    local sx, sy, sz, fx, fy, fz, ux, uy, uz = camera.ship_pose(tr, s)
    g3.drawBasis(scene.ship, sx, sy, sz, fx, fy, fz, ux, uy, uz, 1, 0, true)
    -- Every chunk, nearest first: from the one behind the ship's, forwards.
    -- gfx3d culls the ones outside the view or beyond FAR.
    local chunks = scene.chunks
    local n = #chunks
    local first = scene.of[s.seg] - 2
    for k = 0, n - 1 do
        local ch = chunks[(first + k) % n + 1]
        g3.draw(ch.road, 0, 0, 0, 0, 0, 0)
        g3.draw(ch.ground, 0, 0, 0, 0, 0, 0, 1, M.GROUND_BIAS)
    end
    g3.endScene()
end

return M
