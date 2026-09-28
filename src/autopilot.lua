-- A centre-line driver (pure Lua): steers back towards u = 0 while feeding
-- forward the curvature just ahead. Drives the hardware gate lap; the P4 AI
-- replaces the centre line with a racing line.
local M = {}

local atan, abs = math.atan, math.abs

M.LOOK = 25     -- m: rejoin the centre line over this distance
M.GAIN = 3.0    -- 1/s: heading error to yaw rate
M.AHEAD = 2     -- segments: where the curvature feed-forward reads

-- Fills out = { steer, thrust, brake, abL, abR } for ship s.
function M.controls(tr, s, P, out)
    local k = tr.kr[(s.seg - 1 + M.AHEAD) % tr.n + 1]
    local want = (atan(-s.u, M.LOOK) - s.psi) * M.GAIN + k * s.v
    local steer = want / P.STEER_RATE
    if steer > 1 then steer = 1 elseif steer < -1 then steer = -1 end
    out.steer = steer
    out.thrust = true
    out.brake = abs(k) * s.v > P.STEER_RATE * 0.9
    out.abL, out.abR = false, false
    return out
end

return M
