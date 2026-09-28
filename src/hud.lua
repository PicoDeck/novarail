-- The greybox HUD: a panel under the 3D viewport.
local fmt = require("src.fmt")

local M = {}

local disp = picocalc.display
local rgb = disp.rgb

local Y = 240
local BG, FG, DIM, HI = rgb(16, 18, 30), rgb(230, 230, 240), rgb(130, 134, 160), rgb(250, 200, 60)

-- st: { v, lap, laps, lap_ms, last_ms, best_ms, fps, work_us, drawn }
function M.draw(st)
    disp.fillRect(0, Y, 320, 80, BG)
    disp.drawText(8, Y + 8, string.format("%3d km/h", fmt.kmh(st.v)), HI, BG)
    disp.drawText(8, Y + 26, string.format("LAP %d/%d", st.lap, st.laps), FG, BG)
    disp.drawText(8, Y + 44, "TIME " .. fmt.time(st.lap_ms), FG, BG)
    disp.drawText(168, Y + 8, "LAST " .. fmt.time(st.last_ms), DIM, BG)
    disp.drawText(168, Y + 26, "BEST " .. fmt.time(st.best_ms), DIM, BG)
    disp.drawText(168, Y + 44, string.format("%2d fps %4.1f ms", st.fps, st.work_us / 1000), DIM, BG)
    disp.drawText(168, Y + 60, string.format("%4d tris", st.drawn), DIM, BG)
end

return M
