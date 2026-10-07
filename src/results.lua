-- The results page after a race: positions, pilots, race and best-lap times.
local fmt = require("src.fmt")
local controls = require("src.controls")

local M = {}

local disp = picocalc.display
local rgb = disp.rgb

-- Pilot names, in ship order (ship 1 is the player); they match the ship
-- colours in render.SHIP_COLOURS.
M.NAMES = { "YOU", "RED", "GREEN", "ORANGE", "VIOLET", "CYAN" }

local BG, FG, DIM, HI = rgb(16, 18, 30), rgb(230, 230, 240), rgb(130, 134, 160), rgb(250, 200, 60)

-- Draws the page into the back buffer (the caller flushes). res comes from
-- race.results().
function M.draw(res)
    disp.fillRect(0, 0, 320, 320, BG)
    disp.drawText(112, 24, "RACE RESULTS", HI, BG)
    disp.drawText(16, 60, "POS PILOT   TIME      BEST LAP", DIM, BG)
    for pos, row in ipairs(res) do
        local time = row.dnf and "  OUT   " or fmt.time(row.time)
        local line = string.format("%2d  %-6s  %s  %s", pos, M.NAMES[row.idx] or "?", time, fmt.time(row.best))
        disp.drawText(16, 64 + pos * 20, line, row.idx == 1 and HI or FG, BG)
    end
    local again = controls.label(picocalc.gamepad.PAD_A) .. "  race again    ESC  quit"
    disp.drawText(160 - disp.textWidth(again) // 2, 290, again, DIM, BG)
end

return M
