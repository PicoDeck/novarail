-- Ship-to-ship contact in track space (pure Lua). Each ship is a box LEN
-- metres along the track and WID across. An overlapping pair separates
-- along the axis it overlaps less on: side by side, both move apart
-- sideways, and a ship heading into the other bounces off it as off a
-- wall; nose to tail, the one behind is set back and, if it was the faster,
-- passes part of the difference to the one ahead. Energy is lost by the
-- closing speed above MIN_CLOSING, so jostling in a pack costs none, and a ship takes
-- contact damage at most once per COOLDOWN frames (a bump, not a grind).
-- Call once per frame. Sets s.bump on every ship that touched another.
local track = require("src.track")
local physics = require("src.physics")

local M = {}

local abs, sin = math.abs, math.sin

M.LEN = 4.0          -- m along the track
M.WID = 2.4          -- m across
M.SHARE = 0.5        -- of the closing speed, taken from the ship behind
M.PASS = 0.3         -- of the closing speed, given to the ship ahead
M.DAMAGE = 1.0       -- energy per m/s of closing speed, nose to tail
M.SIDE_DAMAGE = 1.0  -- energy per m/s of closing speed, side by side
M.BOUNCE = 0.3       -- a heading into the other ship reflects, scaled by this
M.COOLDOWN = 15      -- frames between contact damage to one ship
M.MAX_HIT = 8        -- the most energy one contact can cost
M.MIN_CLOSING = 3    -- m/s: slower contact (pack jostling) costs no energy

local function clamp_u(tr, s)
    local lim = tr.w[s.seg] * 0.5 - physics.P.SHIP_HALF_W
    if s.u > lim then s.u = lim elseif s.u < -lim then s.u = -lim end
end

local function hurt(s, e)
    if (s.cooldown or 0) > 0 then return end
    s.energy = s.energy - (e < M.MAX_HIT and e or M.MAX_HIT)
    s.cooldown = M.COOLDOWN
    if s.energy <= 0 then s.energy, s.dnf = 0, true end
end

function M.resolve(tr, ships)
    local n, len, total, half = #ships, tr.len, tr.total, tr.total * 0.5
    for i = 1, n do
        local s = ships[i]
        s.bump = false
        if (s.cooldown or 0) > 0 then s.cooldown = s.cooldown - 1 end
    end
    for i = 1, n - 1 do
        local a = ships[i]
        for j = i + 1, n do
            local b = ships[j]
            local ds = ((b.seg - a.seg) + (b.t - a.t)) * len
            if ds > half then ds = ds - total elseif ds < -half then ds = ds + total end
            local du = b.u - a.u
            local ox, oy = M.LEN - abs(ds), M.WID - abs(du)
            if ox > 0 and oy > 0 then
                a.bump, b.bump = true, true
                if oy <= ox then
                    -- side by side: apart sideways, half each
                    local d = oy * 0.5
                    if du >= 0 then a.u, b.u = a.u - d, b.u + d else a.u, b.u = a.u + d, b.u - d end
                    clamp_u(tr, a)
                    clamp_u(tr, b)
                    -- closing: a moving towards b plus b moving towards a
                    local la, lb = a.v * sin(a.psi), b.v * sin(b.psi)
                    local closing = du >= 0 and la - lb or lb - la
                    if closing > 0 then
                        if closing > M.MIN_CLOSING then
                            hurt(a, closing * M.SIDE_DAMAGE)
                            hurt(b, closing * M.SIDE_DAMAGE)
                        end
                        local towards = du >= 0 and 1 or -1 -- the side b is on, seen from a
                        if a.psi * towards > 0 then a.psi = -a.psi * M.BOUNCE end
                        if b.psi * towards < 0 then b.psi = -b.psi * M.BOUNCE end
                    end
                else
                    -- nose to tail: the one behind is set back
                    local back, front = a, b
                    if ds < 0 then back, front = b, a end
                    local seg, t, laps = track.advance(tr, back.seg, back.t, -ox)
                    back.seg, back.t, back.lap = seg, t, back.lap + laps
                    local closing = back.v - front.v
                    if closing > 0 then
                        back.v = back.v - closing * M.SHARE
                        front.v = front.v + closing * M.PASS
                        if closing > M.MIN_CLOSING then
                            hurt(back, closing * M.DAMAGE)
                            hurt(front, closing * M.DAMAGE)
                        end
                    end
                end
            end
        end
    end
end

return M
