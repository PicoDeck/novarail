-- The engine note (pure Lua): the playback rate and volume of the looping
-- engine sample for a ship speed.
local M = {}

local floor = math.floor

M.V_REF = 70        -- m/s at which the note reaches RATE_IDLE + RATE_SPAN
M.RATE_IDLE = 0.7   -- sample rate multiplier at a standstill
M.RATE_SPAN = 0.9   -- added by V_REF
M.OVER = 1.2        -- the note keeps rising a little past V_REF (pads)
M.VOL_IDLE = 20     -- 0..100
M.VOL_SPAN = 25     -- added by V_REF

local function frac(v)
    if not (v > 0) then return 0 end -- also catches NaN
    local f = v / M.V_REF
    return f < M.OVER and f or M.OVER
end

function M.rate(v)
    return M.RATE_IDLE + M.RATE_SPAN * frac(v)
end

function M.volume(v)
    local f = frac(v)
    return floor(M.VOL_IDLE + M.VOL_SPAN * (f < 1 and f or 1) + 0.5)
end

return M
