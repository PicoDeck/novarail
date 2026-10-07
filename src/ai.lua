-- Rival drivers (pure Lua). prepare() works out, once per track, a racing
-- line (a lateral target per segment, towards the inside of each bend but
-- APEX_MARGIN clear of the inside wall, within bounds lo..hi that the lane
-- offsets and passing keep to as well) and
-- a speed profile (the most each segment's grip allows, braking early
-- enough for the next bend). controls() drives one ship along them: it steers for a
-- point a little ahead on the line, pulls out round a slower ship in its
-- lane, keeps a lane's width from a ship alongside, and scales its thrust by its skill and its distance to the player
-- (rubber-banding: the leader eases off, the last pushes harder).
local M = {}

local abs, atan, sqrt, min, max = math.abs, math.atan, math.sqrt, math.min, math.max

M.SMOOTH = 4        -- segments either side, curvature smoothing
M.LEAD = 3          -- segments the line leads the bend by
M.LINE_GAIN = 900   -- m of lateral offset per 1/m of curvature
M.MARGIN = 2.5      -- m kept from the walls
M.APEX_MARGIN = 4   -- m kept from the inside wall of a bend
M.GRIP_MARGIN = 0.95 -- of the grip limit (physics A_GRIP) a bend may take
M.V_CAP = 70        -- m/s: the profile never asks for more
M.BRAKE_A = 20      -- m/s^2: the braking the profile plans with (the brake is 25)
M.LOOK = 25         -- m: rejoin the target over this distance
M.GAIN = 3.0        -- 1/s: heading error to yaw rate
M.AHEAD = 2         -- segments: where the line and curvature are read
M.AVOID_DIST = 22   -- m: a slower ship this close ahead...
M.AVOID_LANE = 3    -- m: ...and this close to the target lane is avoided
M.AVOID_SHIFT = 4.5 -- m: pass it this far to the side
M.SIDE_GAP = 4.0    -- m: a ship alongside closer than this is steered away from
M.RB_DIST = 250     -- m of lead (or lag) for the full rubber-band effect
M.RB_MAX = 0.10     -- thrust fraction rubber-banding adds or takes

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- Returns line = { u, v, lo, hi }: per segment the lateral target, the
-- target speed and the lateral bounds.
function M.prepare(tr, P)
    local n, kr, w = tr.n, tr.kr, tr.w
    local line = { u = {}, v = {}, lo = {}, hi = {} }
    for i = 1, n do
        local sum = 0
        for d = -M.SMOOTH, M.SMOOTH do sum = sum + kr[(i - 1 + d + M.LEAD) % n + 1] end
        local k = sum / (2 * M.SMOOTH + 1)
        local out, apex = w[i] * 0.5 - M.MARGIN, w[i] * 0.5 - M.APEX_MARGIN
        -- k > 0 bends right: the inside is to the right
        line.lo[i] = k < 0 and -apex or -out
        line.hi[i] = k > 0 and apex or out
        line.u[i] = clamp(k * M.LINE_GAIN, line.lo[i], line.hi[i])
        line.v[i] = min(M.V_CAP, sqrt(P.A_GRIP * M.GRIP_MARGIN / max(abs(kr[i]), 1e-4)))
    end
    for _ = 1, 2 do -- twice round, so braking carries over the start line
        for i = n, 1, -1 do
            local nx = line.v[i % n + 1]
            local lim = sqrt(nx * nx + 2 * M.BRAKE_A * tr.len)
            if line.v[i] > lim then line.v[i] = lim end
        end
    end
    return line
end

-- skill (0..1] scales thrust and target speed; bias shifts the line (m).
function M.new_driver(skill, bias)
    return { skill = skill, bias = bias or 0 }
end

-- Fills out = { steer, thrust, brake, abL, abR, thrust_scale } for
-- ships[i]. lead is how far that ship is ahead of the player, in metres
-- (negative when behind).
function M.controls(tr, line, ships, i, d, P, lead, out)
    local s = ships[i]
    local n, len, half = tr.n, tr.len, tr.total * 0.5
    local ahead = (s.seg - 1 + M.AHEAD) % n + 1
    local lo, hi = line.lo[ahead], line.hi[ahead]
    local target = clamp(line.u[ahead] + d.bias, lo, hi)
    for j = 1, #ships do
        local o = ships[j]
        if j ~= i and o.v < s.v + 1 then
            local ds = ((o.seg - s.seg) + (o.t - s.t)) * len
            if ds > half then ds = ds - 2 * half elseif ds < -half then ds = ds + 2 * half end
            if ds > 0 and ds < M.AVOID_DIST and abs(o.u - target) < M.AVOID_LANE then
                target = clamp(o.u > 0 and o.u - M.AVOID_SHIFT or o.u + M.AVOID_SHIFT, lo, hi)
            elseif ds > -5 and ds < 5 and abs(o.u - s.u) < M.SIDE_GAP then
                -- alongside: keep a lane's width from it
                target = clamp(o.u > s.u and o.u - M.SIDE_GAP or o.u + M.SIDE_GAP, lo, hi)
            end
        end
    end
    local want = (atan(target - s.u, M.LOOK) - s.psi) * M.GAIN + tr.kr[ahead] * s.v
    out.steer = clamp(want / P.STEER_RATE, -1, 1)
    local vt = line.v[ahead] * d.skill
    out.thrust = s.v < vt
    out.brake = s.v > vt + 2
    out.abL, out.abR = false, false
    out.thrust_scale = d.skill * (1 + clamp(-lead / M.RB_DIST, -1, 1) * M.RB_MAX)
    return out
end

return M
