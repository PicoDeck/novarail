-- gfx3d glue: builds the meshes once, then submits each frame.
local trackmesh = require("src.trackmesh")
local models = require("src.models")
local camera = require("src.camera")

local M = {}

local g3 = picocalc.gfx3d
local rgb = picocalc.display.rgb

M.VIEW_W, M.VIEW_H = 320, 240 -- the HUD panel takes the bottom 80 rows
M.NEAR, M.FAR = 0.5, 260
M.FOG_NEAR, M.FOG_FAR = 70, 250
M.GROUND_BIAS = 60 -- m: the ground sorts behind the road beside it
M.BEHIND = 30      -- m: a ship further behind the camera's ship is not drawn
M.SHIP_FAR = 160   -- m: nor one further ahead (fog has it down to a speck)

local FOG = rgb(70, 24, 100) -- the night haze; glowing parts ignore it

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
        road = { rgb(34, 36, 58), rgb(40, 43, 68) },
        line = rgb(240, 240, 255),
        pad = rgb(255, 230, 60),
        recharge = { rgb(120, 40, 150), rgb(95, 30, 125) },
        dash = rgb(255, 60, 200),
        barrier = { rgb(0, 210, 245), rgb(0, 190, 230) },
        chevron = { rgb(255, 60, 200), rgb(60, 20, 70) },
        ground = { rgb(18, 16, 44), rgb(26, 22, 60) },
        pylon = rgb(50, 50, 90),
        gantry = rgb(60, 60, 100),
        beam = rgb(255, 60, 200),
        start_beam = rgb(240, 240, 255),
    }
end

-- Returns the scene: gfx3d meshes for the track chunks, the ships (one per
-- colour) and the mountain ring, with the chunk index of every segment.
function M.init(tr)
    local data = trackmesh.build(tr, palette(), g3.DOUBLE_SIDED, g3.UNLIT | g3.NO_FOG)
    local roads, grounds, gidx = {}, {}, {}
    for i, ch in ipairs(data.chunks) do
        roads[i] = g3.newMesh(ch.road[1], ch.road[2], ch.road[3], ch.road[4])
        if #ch.ground[2] > 0 then -- gfx3d has no empty meshes
            grounds[#grounds + 1] = g3.newMesh(ch.ground[1], ch.ground[2], ch.ground[3])
            gidx[i] = #grounds
        end
    end
    -- gfirst[c]: chunk c's ground in `grounds`, or the next chunk's that has one
    local gfirst, nxt = {}, 1
    for i = #data.chunks, 1, -1 do
        nxt = gidx[i] or nxt
        gfirst[i] = nxt
    end
    local ships = {}
    for i, col in ipairs(M.SHIP_COLOURS) do
        local v, t, c = models.ship(col[1], col[2])
        ships[i] = g3.newMesh(v, t, c)
    end
    local v, t, c, f = models.skyline(600, 40, { 40, 70, 55, 95, 35, 120, 60, 80 },
        { rgb(30, 20, 60), rgb(38, 26, 72), rgb(24, 16, 50) }, rgb(255, 120, 220), g3.UNLIT)
    local skyline = g3.newMesh(v, t, c, f)

    g3.setViewport(0, 0, M.VIEW_W, M.VIEW_H)
    g3.setLight(0.4, 1, 0.3, 0.45)
    g3.setSky({ { -1.2, rgb(14, 12, 36) }, { 0, rgb(200, 50, 150) }, { 0.03, rgb(110, 30, 120) },
        { 0.12, rgb(45, 20, 90) }, { 0.35, rgb(12, 10, 40) } })
    g3.setFog(M.FOG_NEAR, M.FOG_FAR, FOG)
    return { roads = roads, grounds = grounds, gfirst = gfirst, of = data.of, ships = ships,
        skyline = skyline }
end

-- One frame into the back buffer's viewport (the caller flushes). ships[1]
-- is the one the camera follows; a ship further than BEHIND behind it or
-- SHIP_FAR ahead is skipped before any pose maths.
function M.draw(scene, tr, ships, cam)
    g3.setProjection(cam.fov, M.NEAR, M.FAR)
    g3.lookAt(cam.ex, cam.ey, cam.ez, cam.tx, cam.ty, cam.tz, cam.ux, cam.uy, cam.uz)
    g3.beginScene()
    g3.drawBackground(scene.skyline)
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
    g3.drawList(scene.grounds, M.GROUND_BIAS, scene.gfirst[first])
    g3.endScene()
end

return M
