-- Seven-segment characters as rectangles (pure Lua), for the countdown's
-- big digits: fillRect is cheap and needs no big font.
local M = {}

-- Segments a b c d e f g for each character.
local SEGS = {
    ["0"] = "abcdef", ["1"] = "bc", ["2"] = "abged", ["3"] = "abgcd", ["4"] = "fgbc",
    ["5"] = "afgcd", ["6"] = "afgedc", ["7"] = "abc", ["8"] = "abcdefg", ["9"] = "abcdfg",
    G = "afedc", O = "abcdef",
}

-- Fills out with x, y, w, h (four integers per segment) for character ch in
-- the box (x, y, w, h) with stroke thickness t; returns the segment count.
function M.rects(ch, x, y, w, h, t, out)
    local segs = SEGS[ch]
    if not segs then return 0 end
    local hh = h // 2
    local n = 0
    for i = 1, #segs do
        local s = segs:sub(i, i)
        local rx, ry, rw, rh
        if s == "a" then rx, ry, rw, rh = x, y, w, t
        elseif s == "b" then rx, ry, rw, rh = x + w - t, y, t, hh
        elseif s == "c" then rx, ry, rw, rh = x + w - t, y + hh, t, h - hh
        elseif s == "d" then rx, ry, rw, rh = x, y + h - t, w, t
        elseif s == "e" then rx, ry, rw, rh = x, y + hh, t, h - hh
        elseif s == "f" then rx, ry, rw, rh = x, y, t, hh
        else rx, ry, rw, rh = x, y + hh - t // 2, w, t end
        out[4 * n + 1], out[4 * n + 2], out[4 * n + 3], out[4 * n + 4] = rx, ry, rw, rh
        n = n + 1
    end
    return n
end

return M
