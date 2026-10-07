-- A scripted pilot for track tests: it holds the centre line and drives a
-- stretch of track in one of four ways, to show what each corner demands.
--   "flat"      full thrust, never slows
--   "lift"      lets off the thrust above each segment's grip speed, never brakes
--   "brake"     brakes down to each segment's grip speed in time
--   "airbrake"  as "brake", plus the inside airbrake wherever grip alone
--               cannot hold the line, so its speeds are higher
local physics = require("src.physics")

local M = {}

local sqrt, abs = math.sqrt, math.abs

M.MARGIN = 0.92  -- of the grip the pilot plans with
M.DECEL = 18     -- m/s^2 the pilot plans its braking with (the brake is 25)
M.LOOK = 2       -- segments ahead the pilot reads its target speed

-- Target speeds per segment for a mode.
function M.plan(tr, mode)
    local P = physics.P
    local n, v = tr.n, {}
    for i = 1, n do
        local k = math.max(abs(tr.kr[i]), 1e-4)
        local a = P.A_GRIP * M.MARGIN
        if mode == "airbrake" then
            -- k v^2 = a + AB_YAW v: grip plus one airbrake
            v[i] = (P.AB_YAW + sqrt(P.AB_YAW * P.AB_YAW + 4 * k * a)) / (2 * k)
        else
            v[i] = sqrt(a / k)
        end
    end
    for _ = 1, 2 do -- back from each bend, twice round
        for i = n, 1, -1 do
            local nx = v[i % n + 1]
            local lim = sqrt(nx * nx + 2 * M.DECEL * tr.len)
            if v[i] > lim then v[i] = lim end
        end
    end
    return v
end

-- Controls for ship s, into out = { steer, thrust, brake, abL, abR }.
local function controls(tr, mode, plan, s, out)
    local P = physics.P
    local kr = tr.kr[s.seg]
    -- feed the bend forward, steer back to the centre line
    local want = kr * s.v - 0.6 * s.u - 3 * s.psi
    local steer = want / P.STEER_RATE
    out.steer = steer > 1 and 1 or (steer < -1 and -1 or steer)
    local vt = plan and plan[(s.seg - 1 + M.LOOK) % tr.n + 1] or math.huge
    out.thrust = s.v < vt
    out.brake = (mode == "brake" or mode == "airbrake") and s.v > vt + 1
    local over = abs(kr) * s.v * s.v > P.A_GRIP * 0.95
    out.abR = mode == "airbrake" and over and kr > 0
    out.abL = mode == "airbrake" and over and kr < 0
    return out
end

-- Drives from segment `from` (at speed v0, centred) until past segment
-- `to`. Returns { time (s), hits (wall hits), vmin (m/s), light = { first
-- and last segment where the ship rose above its hover height } or nil }.
function M.drive(tr, mode, from, to, v0)
    local s = physics.new_ship(from, 0, 0)
    s.v = v0
    local plan = mode ~= "flat" and M.plan(tr, mode) or nil
    local out, dt = {}, 1 / 60
    local res = { time = 0, hits = 0, vmin = v0 }
    local span = (to - from) % tr.n
    for _ = 1, 60 * 120 do
        controls(tr, mode, plan, s, out)
        physics.step(tr, s, out, dt)
        res.time = res.time + dt
        if s.hit then res.hits = res.hits + 1 end
        if s.v < res.vmin then res.vmin = s.v end
        if s.h > physics.P.HOVER_H then
            res.light = res.light or { first = s.seg }
            res.light.last = s.seg
        end
        if (s.seg - from) % tr.n > span then return res end
    end
    error("pilot: never got past segment " .. to)
end

return M
