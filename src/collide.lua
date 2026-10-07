-- Ship-to-ship contact in track space (pure Lua). Each ship is a box LEN
-- metres along the track and WID across. An overlapping pair separates
-- along the axis it overlaps less on: side by side, both move apart
-- sideways and trade sideways momentum (equal masses, restitution E), so
-- both slide apart (physics' vs) until grip takes the slide, and each
-- heading twitches away from the hit; nose to tail, the one behind is set
-- back and, if it was the faster, passes part of the difference to the one
-- ahead, and an off-centre hit twitches the two headings apart. Energy is lost by the
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
M.E = 0.5            -- side contact: restitution of the sideways speeds
M.K_YAW = 0.01       -- rad of heading twitch per m/s of shove (bumps over MIN_CLOSING)
M.MAX_TWITCH = 0.1   -- rad: the most one contact twitches a heading
M.COOLDOWN = 15      -- frames between contact damage to one ship
M.MAX_HIT = 8        -- the most energy one contact can cost
M.MIN_CLOSING = 3    -- m/s: slower contact (pack jostling) costs no energy
M.WALL_GAP = 0.05    -- m: a ship this close to a wall is against it

local function clamp_u(tr, s)
    local lim = tr.w[s.seg] * 0.5 - physics.P.SHIP_HALF_W
    if s.u > lim then s.u = lim elseif s.u < -lim then s.u = -lim end
end

-- True if ship s is against the wall on `side` (+1 right, -1 left), so a
-- push that way cannot move it.
local function walled(tr, s, side)
    local lim = tr.w[s.seg] * 0.5 - physics.P.SHIP_HALF_W - M.WALL_GAP
    if side > 0 then return s.u >= lim end
    return s.u <= -lim
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
                    local towards = du >= 0 and 1 or -1 -- the side b is on, seen from a
                    -- A ship against the wall behind it cannot give way: the
                    -- other takes the whole push and bounces off it as off a
                    -- wall, and pays for the contact alone.
                    local free, fixed
                    if walled(tr, b, towards) and not walled(tr, a, -towards) then free, fixed = a, b
                    elseif walled(tr, a, -towards) and not walled(tr, b, towards) then free, fixed = b, a end
                    local away = free == a and -towards or towards -- the way the free ship is pushed
                    if free then
                        free.u = free.u + away * oy
                        clamp_u(tr, free)
                    else -- side by side: apart sideways, half each
                        local d = oy * 0.5
                        a.u, b.u = a.u - towards * d, b.u + towards * d
                        clamp_u(tr, a)
                        clamp_u(tr, b)
                    end
                    -- closing: a moving towards b plus b moving towards a,
                    -- heading and slide together
                    local la, lb = a.v * sin(a.psi) + a.vs, b.v * sin(b.psi) + b.vs
                    local closing = towards * (la - lb)
                    if closing > 0 and free then
                        local P = physics.P
                        if free.psi * away < 0 then free.psi = -free.psi * P.WALL_BOUNCE end
                        local lf = fixed == a and la or lb
                        free.vs = lf + away * P.E_WALL * closing - free.v * sin(free.psi)
                        if closing > M.MIN_CLOSING then hurt(free, closing * M.SIDE_DAMAGE) end
                    elseif closing > 0 then
                        if closing > M.MIN_CLOSING then
                            hurt(a, closing * M.SIDE_DAMAGE)
                            hurt(b, closing * M.SIDE_DAMAGE)
                        end
                        local j = (1 + M.E) * 0.5 * closing  -- each ship's change of sideways speed
                        a.vs, b.vs = a.vs - towards * j, b.vs + towards * j
                        if closing > M.MIN_CLOSING then
                            -- a real bump: twitch the headings apart. Not
                            -- for jostling, where a twitch in a tight pack
                            -- turns forward speed into the next contact.
                            local tw = M.K_YAW * j
                            if tw > M.MAX_TWITCH then tw = M.MAX_TWITCH end
                            a.psi, b.psi = a.psi - towards * tw, b.psi + towards * tw
                        end
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
                            -- off-centre: the headings twitch apart, by the offset
                            local tw = M.K_YAW * closing * (front.u - back.u) / M.WID
                            if tw > M.MAX_TWITCH then tw = M.MAX_TWITCH
                            elseif tw < -M.MAX_TWITCH then tw = -M.MAX_TWITCH end
                            front.psi, back.psi = front.psi + tw, back.psi - tw
                        end
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
