-- Ship physics in track space (pure Lua). A ship is a place on the track
-- (seg, t), a lateral offset u (metres, + = right), a hover height h over
-- the surface with its rate vh, a speed v (m/s) and a heading psi relative
-- to the track (radians, + = right), and an energy store that walls and
-- collisions drain and the recharge strip refills; at zero the ship is out
-- of the race (dnf) and gets no more thrust. One call steps one fixed dt.
--
-- Grip caps how hard steering can turn the ship at speed (a lateral
-- acceleration, A_GRIP): too fast for a bend and the track turns away
-- faster than the ship can follow, so it runs wide. Airbrakes turn it
-- beyond that cap, at the cost of drag: the cornering skill.
--
-- A ship also slides sideways at vs m/s (a shove from another ship, a
-- bounce off a wall), which grip bleeds away. A wall bounces the ship back
-- towards the middle and costs speed and energy by how hard it was hit;
-- scraping along it keeps costing, and a hard hit stuns the steering.
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
    A_GRIP = 34,       -- m/s^2: steering turns at most A_GRIP / v rad/s
    ALIGN = 0.6,       -- 1/s: with no steering, the heading eases back to the track's
    PSI_MAX = 1.1,     -- rad: the heading never turns further from the track than this
    AB_YAW = 0.25,     -- rad/s of extra turn from one airbrake, past the grip cap
    AB_DRAG = 0.15,    -- 1/s, times v, per airbrake
    SHIP_HALF_W = 1.2, -- m
    A_SLIP = 20,       -- m/s^2: grip bleeds a sideways slide away at this rate
    WALL_LOSS = 0.8,   -- speed lost on a wall hit, per m/s of speed into the wall
    WALL_BOUNCE = 0.3, -- the heading reflects off a wall, scaled by this
    E_WALL = 0.35,     -- bounce: the speed into the wall comes back out times this
    SCRAPE_DECEL = 12, -- m/s^2 while scraping (touched the wall in the last SCRAPE_HOLD)
    SCRAPE_ENERGY = 6, -- energy per second while scraping
    SCRAPE_HOLD = 0.25, -- s
    SCRAPE_WN = 2,     -- m/s into the wall a scrape absorbs before it is a fresh hit
    STUN_WN = 8,       -- m/s into the wall: a harder hit stuns
    STUN_TIME = 0.4,   -- s
    STUN_STEER = 0.5,  -- steering is scaled by this while stunned
    HOVER_H = 1.0,     -- m: the hover spring's rest height
    HOVER_RANGE = 2.5, -- m: above this the spring lets go (airborne)
    HOVER_K = 60,      -- 1/s^2
    HOVER_C = 11,      -- 1/s
    H_MIN = 0.35,      -- m: the hull never goes lower
    PAD_KICK = 12,     -- m/s added by a speed pad (once per pad)
    V_BOOST = 85,      -- m/s: a pad never lifts the speed above this
    ENERGY = 100,      -- a full energy store
    WALL_DAMAGE = 1.5, -- energy lost per m/s of speed into the wall
    WALL_HIT_MAX = 25, -- the most energy one wall hit costs
    RECHARGE = 15,     -- energy per second on the recharge strip
}

function M.new_ship(seg, t, u)
    return { seg = seg or 1, t = t or 0, u = u or 0, h = M.P.HOVER_H, vh = 0,
        v = 0, psi = 0, vs = 0, lap = 0, laps = 0, hit = false, pad = 0, air = false,
        energy = M.P.ENERGY, dnf = false, impact = 0, stun = 0, scrape = 0 }
end

-- c = { steer = -1..1 (+ = right), thrust, brake, abL, abR, thrust_scale }.
-- Sets s.hit (hit a wall this step), s.impact (speed the wall took, scraping
-- included),
-- s.pad (id of the pad under the ship, or 0), s.air (above hover range) and
-- s.laps (start-line crossings this step).
function M.step(tr, s, c, dt)
    local P = M.P
    local seg, t = s.seg, s.t
    -- per-ring values at (seg, t), lerped inline (this runs 7 times a frame)
    local j, f = seg % tr.n + 1, 1 - t
    local arr = tr.ty
    local ty = arr[seg] * f + arr[j] * t
    arr = tr.uy
    local uy = arr[seg] * f + arr[j] * t
    arr = tr.kr
    local kr = arr[seg] * f + arr[j] * t
    arr = tr.ku
    local ku = arr[seg] * f + arr[j] * t
    arr = tr.w
    local w = arr[seg] * f + arr[j] * t
    local v, psi, h, vh, vs, stun, scrape = s.v, s.psi, s.h, s.vh, s.vs, s.stun, s.scrape
    local air = h >= P.HOVER_RANGE

    local a = -P.DRAG * v * v - P.ROLL * v - P.G * ty
    if c.thrust and not air and not s.dnf then a = a + P.THRUST * (c.thrust_scale or 1) end
    if c.brake then a = a - P.BRAKE end
    local abl, abr = c.abL and 1 or 0, c.abR and 1 or 0
    a = a - (abl + abr) * P.AB_DRAG * v
    v = v + a * dt
    if v < 0 then v = 0 end

    local steer = c.steer or 0
    if stun > 0 then
        steer = steer * P.STUN_STEER
        stun = stun - dt
        if stun < 0 then stun = 0 end
    end
    local yaw = steer * P.STEER_RATE
    if steer == 0 then yaw = -psi * P.ALIGN end
    local cap = P.A_GRIP / (v > 1 and v or 1)
    if yaw > cap then yaw = cap elseif yaw < -cap then yaw = -cap end
    yaw = yaw + (abr - abl) * P.AB_YAW
    local vf = v * cos(psi)
    psi = psi + (yaw - kr * vf) * dt
    if psi > P.PSI_MAX then psi = P.PSI_MAX elseif psi < -P.PSI_MAX then psi = -P.PSI_MAX end

    if vs > 0 then
        vs = vs - P.A_SLIP * dt
        if vs < 0 then vs = 0 end
    elseif vs < 0 then
        vs = vs + P.A_SLIP * dt
        if vs > 0 then vs = 0 end
    end
    local u = s.u + (v * sin(psi) + vs) * dt
    local lim = w * 0.5 - P.SHIP_HALF_W
    local hit, impact, damage = false, 0, 0
    if u > lim or u < -lim then
        local side = u > 0 and 1 or -1
        u = side * lim
        local wn = (v * sin(psi) + vs) * side -- speed into the wall
        if wn > 0 then
            hit = true
            -- Steering into the wall turns the ship back into it every
            -- step: while already scraping, only speed into the wall over
            -- SCRAPE_WN is a fresh hit (the scrape itself is billed below).
            local fresh = scrape > 0 and wn - P.SCRAPE_WN or wn
            if fresh > 0 then
                impact = P.WALL_LOSS * fresh
                if impact > v then impact = v end
                v = v - impact
                damage = P.WALL_DAMAGE * fresh
                if damage > P.WALL_HIT_MAX then damage = P.WALL_HIT_MAX end
                if fresh > P.STUN_WN then stun = P.STUN_TIME end
            end
            if psi * side > 0 then psi = -psi * P.WALL_BOUNCE end
            vs = -side * P.E_WALL * wn - v * sin(psi)
            scrape = P.SCRAPE_HOLD
        end
    end
    if scrape > 0 then
        local d = P.SCRAPE_DECEL * dt
        if d > v then d = v end
        v = v - d
        impact = impact + d
        damage = damage + P.SCRAPE_ENERGY * dt
        scrape = scrape - dt
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

    local energy = s.energy - damage
    if tr.recharge[seg] and not s.dnf then energy = min(P.ENERGY, energy + P.RECHARGE * dt) end
    if energy <= 0 then energy, s.dnf = 0, true end

    s.seg, s.t, s.u, s.h, s.vh, s.v, s.psi, s.vs = seg, t, u, h, vh, v, psi, vs
    s.stun, s.scrape = stun, scrape
    s.hit, s.impact, s.air, s.laps, s.energy = hit, impact, h >= P.HOVER_RANGE, laps, energy
    s.lap = s.lap + laps
end

return M
