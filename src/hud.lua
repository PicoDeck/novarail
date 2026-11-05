-- The race HUD: a panel under the 3D viewport, and overlays drawn into the
-- viewport (the countdown's big digits, the finish banner).
--
-- The display is double-buffered and flushed once per frame, so each
-- buffer comes round every other frame. The panel keeps, per buffer, the
-- text it last drew in each field and redraws only fields that changed:
-- drawText costs ~76 us on the device (several times that inside a busy
-- frame) and a full panel ~3.6 ms a frame. The text is refreshed on two
-- frames out of every EVERY (one per buffer), so speed and times update
-- 7.5 times a second; the energy bar follows every frame, and turns white
-- for FLASH frames after a hit that costs energy.
local fmt = require("src.fmt")
local sevenseg = require("src.sevenseg")

local M = {}

local disp = picocalc.display
local rgb = disp.rgb
local drawText, fillRect = disp.drawText, disp.fillRect
local format = string.format

local Y = 240
-- The neon palette: a dark navy panel under a magenta edge, cyan accents.
local BG, FG, DIM, HI = rgb(10, 12, 34), rgb(220, 230, 255), rgb(110, 120, 170), rgb(0, 220, 250)
local EDGE = rgb(255, 60, 200)
local BAR_X, BAR_Y, BAR_W, BAR_H = 224, Y + 42, 88, 8
local BAR_BG = rgb(34, 36, 70)
local E_HIGH, E_MID, E_LOW = rgb(0, 210, 245), rgb(255, 60, 200), rgb(255, 70, 60)
local BIG = rgb(255, 60, 200)
local FLASH_COL = rgb(255, 255, 255)

local EVERY <const> = 4
M.EVERY = EVERY
M.FLASH = 8

function M.new()
    return { frame = 0, cache = { {}, {} }, rects = {}, flash = 0 }
end

-- Forget what the buffers hold (after a full-screen page such as results).
function M.reset(h)
    h.frame, h.cache[1], h.cache[2], h.flash = 0, {}, {}, 0
end

-- The energy bar flashes: a hit just cost energy.
function M.flash(h)
    h.flash = M.FLASH
end

-- Whether this frame's draw() refreshes the text: the caller need not work
-- out the values on the frames it does not.
function M.text_due(h)
    local frame = h.frame
    return frame % EVERY < 2 or not h.cache[frame % 2 + 1].fresh
end

-- st: { v, lap, laps, pos, n, lap_ms, last_ms, best_ms, energy (0..100) }; all
-- but energy only matter on a frame text_due() says so. Each field compares
-- the value behind its text, so an unchanged field builds no string.
function M.draw(h, st)
    local frame = h.frame
    local c = h.cache[frame % 2 + 1]
    h.frame = frame + 1
    if not c.panel then
        fillRect(0, Y, 320, 80, BG)
        fillRect(0, Y, 320, 2, EDGE)
        drawText(168, Y + 42, "ENERGY", DIM, BG)
        c.panel = true
    end
    local fresh = c.fresh
    if not fresh or frame % EVERY < 2 then
        local kmh = fmt.kmh(st.v)
        if c.spd ~= kmh then
            drawText(8, Y + 6, format("%3d km/h", kmh), HI, BG)
            c.spd = kmh
        end
        if c.lap ~= st.lap then
            drawText(8, Y + 22, format("LAP %d/%d", st.lap, st.laps), FG, BG)
            c.lap = st.lap
        end
        if c.pos ~= st.pos then
            drawText(8, Y + 38, format("POS %d/%d", st.pos, st.n), FG, BG)
            c.pos = st.pos
        end
        -- the three times can be nil: `fresh` draws their first text
        local ms = st.lap_ms
        if not fresh or c.time ~= ms then
            drawText(8, Y + 54, "TIME " .. fmt.time(ms), FG, BG)
            c.time = ms
        end
        ms = st.last_ms
        if not fresh or c.last ~= ms then
            drawText(168, Y + 6, "LAST " .. fmt.time(ms), DIM, BG)
            c.last = ms
        end
        ms = st.best_ms
        if not fresh or c.best ~= ms then
            drawText(168, Y + 22, "BEST " .. fmt.time(ms), DIM, BG)
            c.best = ms
        end
        c.fresh = true
    end
    local e = st.energy
    local fill = (e * BAR_W + 50) // 100
    local col = e > 50 and E_HIGH or (e > 25 and E_MID or E_LOW)
    local flash = h.flash
    if flash > 0 then
        col = FLASH_COL
        h.flash = flash - 1
    end
    if c.bar ~= fill or c.bar_col ~= col then
        if fill > 0 then fillRect(BAR_X, BAR_Y, fill, BAR_H, col) end
        if fill < BAR_W then fillRect(BAR_X + fill, BAR_Y, BAR_W - fill, BAR_H, BAR_BG) end
        c.bar, c.bar_col = fill, col
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
