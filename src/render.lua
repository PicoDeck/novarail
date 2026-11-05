-- gfx3d glue: builds the meshes once, then submits each frame.
local trackmesh = require("src.trackmesh")
local models = require("src.models")
local camera = require("src.camera")

local M = {}

local g3 = picocalc.gfx3d
local rgb = picocalc.display.rgb
-- The per-frame calls, as upvalues: gfx3d is a table of 20-odd entries.
local setProjection, lookAt, beginScene, endScene = g3.setProjection, g3.lookAt, g3.beginScene, g3.endScene
local drawBackground, drawBasis, drawList = g3.drawBackground, g3.drawBasis, g3.drawList
local ship_pose = camera.ship_pose

M.VIEW_W, M.VIEW_H = 320, 240 -- the HUD panel takes the bottom 80 rows
local NEAR <const>, FAR <const> = 0.5, 260
M.NEAR, M.FAR = NEAR, FAR
M.FOG_NEAR, M.FOG_FAR = 70, 250
local GROUND_BIAS <const> = 60 -- m: the ground sorts behind the road beside it
local BEHIND <const> = 30      -- m: a ship further behind the camera's ship is not drawn
local SHIP_FAR <const> = 160   -- m: nor one further ahead (fog has it down to a speck)
M.GROUND_BIAS, M.BEHIND, M.SHIP_FAR = GROUND_BIAS, BEHIND, SHIP_FAR

local FOG = rgb(70, 24, 100) -- the night haze; glowing parts ignore it

-- The ships, player first: { model, team colour }. The player flies the
-- Needle; the rivals alternate Twin-pods and Darts. No engine-flare sprites:
-- on the device six of them cost 1.4 ms of the heaviest frames, and the
-- glowing exhausts already mark the engines.
M.SHIPS = {
    { "needle", rgb(240, 200, 40) },
    { "twin_pod", rgb(230, 50, 70) },
    { "dart", rgb(60, 220, 110) },
    { "twin_pod", rgb(250, 130, 30) },
    { "dart", rgb(160, 80, 240) },
    { "twin_pod", rgb(40, 200, 240) },
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
    local glow = g3.UNLIT | g3.NO_FOG
    for i, sh in ipairs(M.SHIPS) do
        local v, t, c, f = models[sh[1]](sh[2], g3.DOUBLE_SIDED, glow)
        ships[i] = g3.newMesh(v, t, c, f)
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
    setProjection(cam.fov, NEAR, FAR)
    lookAt(cam.ex, cam.ey, cam.ez, cam.tx, cam.ty, cam.tz, cam.ux, cam.uy, cam.uz)
    beginScene()
    drawBackground(scene.skyline)
    local me = ships[1]
    local mseg, mt = me.seg, me.t
    local len, total = tr.len, tr.total
    local half = total * 0.5
    local meshes = scene.ships
    local nm = #meshes
    -- The camera already worked out the followed ship's pose this frame.
    drawBasis(meshes[1], cam.sx, cam.sy, cam.sz, cam.sfx, cam.sfy, cam.sfz,
        cam.sux, cam.suy, cam.suz, 1, 0, true)
    for i = 2, #ships do
        local s = ships[i]
        local ds = ((s.seg - mseg) + (s.t - mt)) * len
        if ds > half then ds = ds - total elseif ds < -half then ds = ds + total end
        if ds > -BEHIND and ds < SHIP_FAR then
            local sx, sy, sz, fx, fy, fz, ux, uy, uz = ship_pose(tr, s)
            drawBasis(meshes[(i - 1) % nm + 1], sx, sy, sz, fx, fy, fz, ux, uy, uz, 1, 0, true)
        end
    end
    -- Every chunk, nearest first: from the one behind the ship's, forwards,
    -- in one drawList call per mesh set (a draw() per chunk cost ~4.7 ms a
    -- frame in Lua->C calls). gfx3d culls those outside the view or beyond FAR.
    local roads = scene.roads
    local first = (scene.of[mseg] - 2) % #roads + 1
    drawList(roads, 0, first)
    drawList(scene.grounds, GROUND_BIAS, scene.gfirst[first])
    endScene()
end

return M
