-- Text for the HUD (pure Lua).
local M = {}

-- Integer milliseconds as "m:ss.mmm"; nil or negative as "-:--.---".
function M.time(ms)
    if not ms or ms < 0 then return "-:--.---" end
    return string.format("%d:%02d.%03d", ms // 60000, ms // 1000 % 60, ms % 1000)
end

-- Metres per second as whole km/h.
function M.kmh(v)
    return math.floor(v * 3.6 + 0.5)
end

return M
