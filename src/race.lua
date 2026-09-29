-- Race rules (pure Lua): the starting grid, the countdown, lap and finish
-- timing, standings and results. Time is counted in frames of the fixed
-- 30 Hz step. Ship 1 is the player.
--
-- The grid is behind the start line, so every ship starts on lap -1: its
-- first crossing starts lap 1, and it finishes when its lap count reaches
-- the race's laps.
local physics = require("src.physics")

local M = {}

M.FPS = 30
M.COUNTDOWN = 3 * M.FPS -- "3", "2", "1", then GO
M.GRACE = 20 * M.FPS    -- once the player is done, the others get this long
M.ROW_GAP = 2           -- segments between grid rows
M.LANE = 4              -- m either side of the centre line

-- Grid slot k (1 = pole): staggered rows of two behind the start line, the
-- left-hand slot half a segment ahead, so no two slots tie.
function M.grid(tr, k)
    local row = (k - 1) // 2
    local seg = (tr.n - row * M.ROW_GAP - 1) % tr.n + 1
    if k % 2 == 1 then return seg, 0.5, -M.LANE end
    return seg, 0, M.LANE
end

-- Grid orders for new(): ship k's slot. PLAYER_LAST puts the player (ship
-- 1) at the back and the rivals, in order, in front of it.
function M.PLAYER_LAST(k, n)
    if k == 1 then return n end
    return k - 1
end

-- A race of `nships` ships over `laps` laps; returns the race and the
-- ships, placed on the grid: ship k in slot slot_of(k, nships), or slot k.
function M.new(tr, nships, laps, slot_of)
    local r = { phase = "countdown", frame = 0, start = nil, laps = laps, n = nships,
        seen = {}, lap_start = {}, last = {}, best = {}, times = {}, finish = {}, out = {},
        order = {}, done = nil, key = {}, tier = {}, scratch = {} }
    local ships = {}
    for k = 1, nships do
        ships[k] = physics.new_ship(M.grid(tr, slot_of and slot_of(k, nships) or k))
        ships[k].lap = -1
        r.seen[k], r.lap_start[k], r.key[k], r.times[k] = -1, 0, 0, {}
    end
    return r, ships
end

-- Ships may thrust once the countdown is over.
function M.can_drive(r)
    return r.phase ~= "countdown"
end

-- 3, 2, 1 during the countdown; 0 ("GO") for a second after it; else nil.
function M.countdown(r)
    if r.phase == "countdown" then return 3 - r.frame // M.FPS end
    if r.frame - r.start < M.FPS then return 0 end
    return nil
end

-- The lap ship i is on, 1..laps.
function M.lap_of(r, ships, i)
    local lap = ships[i].lap + 1
    if lap < 1 then return 1 elseif lap > r.laps then return r.laps end
    return lap
end

-- Frames to milliseconds (nil stays nil).
function M.ms(frames)
    return frames and frames * 1000 // M.FPS
end

-- Call once per frame, after the physics and collisions.
function M.update(r, ships)
    r.frame = r.frame + 1
    if r.phase == "countdown" then
        if r.frame >= M.COUNTDOWN then
            r.phase, r.start = "racing", r.frame
            for i = 1, r.n do r.lap_start[i] = r.frame end
        end
        return
    end
    for i = 1, r.n do
        local s = ships[i]
        if not r.finish[i] and not r.out[i] then
            if s.lap > r.seen[i] then
                if s.lap >= 1 then
                    local lt = r.frame - r.lap_start[i]
                    r.last[i] = lt
                    r.times[i][#r.times[i] + 1] = lt
                    if not r.best[i] or lt < r.best[i] then r.best[i] = lt end
                end
                r.lap_start[i], r.seen[i] = r.frame, s.lap
                if s.lap >= r.laps then
                    r.finish[i] = r.frame - r.start
                    r.order[#r.order + 1] = i
                end
            elseif s.dnf then
                r.out[i] = true
            end
        end
    end
    if r.phase == "racing" and (r.finish[1] or r.out[1]) then
        r.phase, r.done = "finished", r.frame
    end
    if r.phase == "finished" then
        local all = true
        for i = 1, r.n do
            if not r.finish[i] and not r.out[i] then all = false end
        end
        if all or r.frame - r.done >= M.GRACE then r.phase = "results" end
    end
end

-- How far ship s is into the race, in laps.
local function progress(tr, s)
    return s.lap + (s.seg - 1 + s.t) / tr.n
end
M.progress = progress

-- Fills `out` with ship indices, leader first: finishers in finishing
-- order, then running ships by progress, then retired ones by progress.
-- Ranks by an integer tier, then by progress within it: a single blended
-- key (progress - 1e6) would lose the fraction in 32-bit floats. Allocates
-- nothing when `out` is reused.
function M.standings(r, tr, ships, out)
    local key, tier = r.key, r.tier
    for i = 1, r.n do
        key[i] = progress(tr, ships[i])
        tier[i] = r.out[i] and 0 or 1
        out[i] = i
    end
    for pos, i in ipairs(r.order) do key[i], tier[i] = -pos, 2 end
    for a = 2, r.n do -- insertion sort, descending by (tier, key), stable
        local v = out[a]
        local tv, kv = tier[v], key[v]
        local b = a - 1
        while b >= 1 do
            local u = out[b]
            local tu = tier[u]
            if tu > tv or (tu == tv and key[u] >= kv) then break end
            out[b + 1] = u
            b = b - 1
        end
        out[b + 1] = v
    end
    return out
end

-- Ship i's position, 1..n.
function M.position(r, tr, ships, i)
    local out = M.standings(r, tr, ships, r.scratch)
    for pos = 1, r.n do
        if out[pos] == i then return pos end
    end
end

-- The final table: { idx, pos, time (ms or nil), best (ms or nil), dnf }.
function M.results(r, tr, ships)
    local out = M.standings(r, tr, ships, {})
    local res = {}
    for pos, i in ipairs(out) do
        res[pos] = { idx = i, pos = pos, time = M.ms(r.finish[i]), best = M.ms(r.best[i]),
            dnf = r.out[i] == true }
    end
    return res
end

return M
