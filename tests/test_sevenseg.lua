local T = require("tests.t")
local sevenseg = require("src.sevenseg")

local function rects(ch)
    local out = {}
    local n = sevenseg.rects(ch, 10, 20, 60, 100, 12, out)
    return n, out
end

return {
    segment_counts = function()
        local want = { ["0"] = 6, ["1"] = 2, ["2"] = 5, ["3"] = 5, ["4"] = 4, ["5"] = 5,
            ["6"] = 6, ["7"] = 3, ["8"] = 7, ["9"] = 6, G = 5, O = 6 }
        for ch, n in pairs(want) do T.eq((rects(ch)), n, "segments in " .. ch) end
    end,
    unknown_characters_draw_nothing = function()
        T.eq((rects("?")), 0)
    end,
    rects_stay_inside_the_box = function()
        local n, out = rects("8")
        for k = 0, n - 1 do
            local x, y, w, h = out[4 * k + 1], out[4 * k + 2], out[4 * k + 3], out[4 * k + 4]
            T.ok(x >= 10 and y >= 20 and x + w <= 70 and y + h <= 120, "segment " .. k)
            T.ok(w > 0 and h > 0)
            T.eq(math.type(x), "integer"); T.eq(math.type(h), "integer")
        end
    end,
    one_is_the_right_side = function()
        local n, out = rects("1")
        for k = 0, n - 1 do T.eq(out[4 * k + 1] + out[4 * k + 3], 70, "right-aligned") end
    end,
}
