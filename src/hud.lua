-- The race HUD: a panel under the 3D viewport, and overlays drawn into the
-- viewport (the countdown's big digits, the finish banner).
--
-- The display is double-buffered and flushed once per frame, so each
-- buffer comes round every other frame. The panel keeps, per buffer, the
-- text it last drew in each field and redraws only fields that changed:
-- drawText costs ~76 us on the device (several times that inside a busy
-- frame) and a full panel ~3.6 ms a frame. The text is refreshed on two
-- frames out of every EVERY (one per buffer), so speed and times update
-- 7.5 times a second; the energy bar follows every frame.
local fmt = require("src.fmt")
local sevenseg = require("src.sevenseg")

local M = {}

local disp = picocalc.display
local rgb = disp.rgb

local Y = 240
-- The neon palette: a dark navy panel under a magenta edge, cyan accents.
local BG, FG, DIM, HI = rgb(10, 12, 34), rgb(220, 230, 255), rgb(110, 120, 170), rgb(0, 220, 250)
local EDGE = rgb(255, 60, 200)
local BAR_X, BAR_Y, BAR_W, BAR_H = 224, Y + 42, 88, 8
local BAR_BG = rgb(34, 36, 70)
local E_HIGH, E_MID, E_LOW = rgb(0, 210, 245), rgb(255, 60, 200), rgb(255, 70, 60)
local BIG = rgb(255, 60, 200)

M.EVERY = 4

function M.new()
    return { frame = 0, cache = { {}, {} }, rects = {} }
end

-- Forget what the buffers hold (after a full-screen page such as results).
function M.reset(h)
    h.frame, h.cache[1], h.cache[2] = 0, {}, {}
end

local function field(c, key, x, y, text, fg)
    if c[key] ~= text then
        disp.drawText(x, y, text, fg, BG)
        c[key] = text
    end
end

-- st: { v, lap, laps, pos, n, lap_ms, last_ms, best_ms, energy (0..100) }.
function M.draw(h, st)
    local c = h.cache[h.frame % 2 + 1]
    h.frame = h.frame + 1
    if not c.panel then
        disp.fillRect(0, Y, 320, 80, BG)
        disp.fillRect(0, Y, 320, 2, EDGE)
        disp.drawText(168, Y + 42, "ENERGY", DIM, BG)
        c.panel = true
    end
    if not c.fresh or (h.frame - 1) % M.EVERY < 2 then
        field(c, "spd", 8, Y + 6, string.format("%3d km/h", fmt.kmh(st.v)), HI)
        field(c, "lap", 8, Y + 22, string.format("LAP %d/%d", st.lap, st.laps), FG)
        field(c, "pos", 8, Y + 38, string.format("POS %d/%d", st.pos, st.n), FG)
        field(c, "time", 8, Y + 54, "TIME " .. fmt.time(st.lap_ms), FG)
        field(c, "last", 168, Y + 6, "LAST " .. fmt.time(st.last_ms), DIM)
        field(c, "best", 168, Y + 22, "BEST " .. fmt.time(st.best_ms), DIM)
        c.fresh = true
    end
    local e = st.energy
    local fill = (e * BAR_W + 50) // 100
    if c.bar ~= fill then
        local col = e > 50 and E_HIGH or (e > 25 and E_MID or E_LOW)
        if fill > 0 then disp.fillRect(BAR_X, BAR_Y, fill, BAR_H, col) end
        if fill < BAR_W then disp.fillRect(BAR_X + fill, BAR_Y, BAR_W - fill, BAR_H, BAR_BG) end
        c.bar = fill
    end
end

local function big(h, ch, x)
    local r = h.rects
    local n = sevenseg.rects(ch, x, 72, 56, 96, 12, r)
    for k = 0, n - 1 do
        disp.fillRect(r[4 * k + 1], r[4 * k + 2], r[4 * k + 3], r[4 * k + 4], BIG)
    end
end

-- The countdown: 3, 2, 1 (value > 0) or GO (value 0), over the viewport.
function M.countdown(h, value)
    if value > 0 then
        big(h, tostring(value), 132)
    else
        big(h, "G", 96)
        big(h, "O", 168)
    end
end

-- A one-line banner across the middle of the viewport.
function M.banner(text)
    local w = disp.textWidth(text)
    disp.fillRect(160 - w // 2 - 10, 108, w + 20, 24, BG)
    disp.drawText(160 - w // 2, 116, text, BIG, BG)
end

return M
