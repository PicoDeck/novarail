-- Ship physics in track space (pure Lua). A ship is a place on the track
-- (seg, t), a lateral offset u (metres, + = right), a hover height h over
-- the surface with its rate vh, a speed v (m/s) and a heading psi relative
-- to the track (radians, + = right). One call steps one fixed dt.
local track = require("src.track")

local M = {}

local sin, cos, abs, min = math.sin, math.cos, math.abs, math.min

M.P = {
    THRUST = 20,       -- m/s^2 while thrusting and within hover range
    DRAG = 0.005,      -- 1/m, times v^2 (top speed ~ sqrt(THRUST / DRAG))
    ROLL = 0.02,       -- 1/s, times v
    BRAKE = 25,        -- m/s^2
    G = 9.81,
    STEER_RATE = 1.7,  -- rad/s of heading change at full lock
    ALIGN = 0.6,       -- 1/s: with no steering, the heading eases back to the track's
    PSI_MAX = 1.1,     -- rad: the heading never turns further from the track than this
    AB_YAW = 0.7,      -- rad/s of extra turn from one airbrake
    AB_DRAG = 0.35,    -- 1/s, times v, per airbrake
    SHIP_HALF_W = 1.2, -- m
    WALL_LOSS = 0.5,   -- speed lost on a wall hit, times |sin(psi)|
    WALL_BOUNCE = 0.3, -- the heading reflects off a wall, scaled by this
    HOVER_H = 1.0,     -- m: the hover spring's rest height
    HOVER_RANGE = 2.5, -- m: above this the spring lets go (airborne)
    HOVER_K = 60,      -- 1/s^2
    HOVER_C = 11,      -- 1/s
    H_MIN = 0.35,      -- m: the hull never goes lower
    PAD_KICK = 12,     -- m/s added by a speed pad (once per pad)
    V_BOOST = 85,      -- m/s: a pad never lifts the speed above this
}

function M.new_ship(seg, t, u)
    return { seg = seg or 1, t = t or 0, u = u or 0, h = M.P.HOVER_H, vh = 0,
        v = 0, psi = 0, lap = 0, laps = 0, hit = false, pad = 0, air = false }
end

-- c = { steer = -1..1 (+ = right), thrust, brake, abL, abR }. Sets s.hit
-- (touched a wall this step), s.pad (id of the pad under the ship, or 0),
-- s.air (above hover range) and s.laps (start-line crossings this step).
function M.step(tr, s, c, dt)
    local P = M.P
    local seg, t = s.seg, s.t
    local ty = track.lerp(tr.ty, tr, seg, t)
    local uy = track.lerp(tr.uy, tr, seg, t)
    local kr = track.lerp(tr.kr, tr, seg, t)
    local ku = track.lerp(tr.ku, tr, seg, t)
    local w = track.lerp(tr.w, tr, seg, t)
    local v, psi, h, vh = s.v, s.psi, s.h, s.vh
    local air = h >= P.HOVER_RANGE

    local a = -P.DRAG * v * v - P.ROLL * v - P.G * ty
    if c.thrust and not air then a = a + P.THRUST end
    if c.brake then a = a - P.BRAKE end
    local abl, abr = c.abL and 1 or 0, c.abR and 1 or 0
    a = a - (abl + abr) * P.AB_DRAG * v
    v = v + a * dt
    if v < 0 then v = 0 end

    local steer = c.steer or 0
    local yaw = steer * P.STEER_RATE + (abr - abl) * P.AB_YAW
    if steer == 0 then yaw = yaw - psi * P.ALIGN end
    local vf = v * cos(psi)
    psi = psi + (yaw - kr * vf) * dt
    if psi > P.PSI_MAX then psi = P.PSI_MAX elseif psi < -P.PSI_MAX then psi = -P.PSI_MAX end

    local u = s.u + v * sin(psi) * dt
    local lim = w * 0.5 - P.SHIP_HALF_W
    local hit = false
    if u > lim or u < -lim then
        u = u > 0 and lim or -lim
        v = v * (1 - P.WALL_LOSS * abs(sin(psi)))
        psi = -psi * P.WALL_BOUNCE
        hit = true
    end

    local laps
    seg, t, laps = track.advance(tr, seg, t, vf * dt)

    local ah = -P.G * uy - v * v * ku
    if not air then ah = ah + P.HOVER_K * (P.HOVER_H - h) - P.HOVER_C * vh end
    vh = vh + ah * dt
    h = h + vh * dt
    if h < P.H_MIN then
        h = P.H_MIN
        if vh < 0 then vh = 0 end
    end

    local id = tr.padid[seg]
    if id and u >= tr.padlo[seg] and u <= tr.padhi[seg] then
        if s.pad ~= id then v = min(v + P.PAD_KICK, P.V_BOOST) end
        s.pad = id
    else
        s.pad = 0
    end

    s.seg, s.t, s.u, s.h, s.vh, s.v, s.psi = seg, t, u, h, vh, v, psi
    s.hit, s.air, s.laps = hit, h >= P.HOVER_RANGE, laps
    s.lap = s.lap + laps
end

return M
