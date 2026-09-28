local T = require("tests.t")
local fmt = require("src.fmt")

return {
    times = function()
        T.eq(fmt.time(0), "0:00.000")
        T.eq(fmt.time(61234), "1:01.234")
        T.eq(fmt.time(599999), "9:59.999")
        T.eq(fmt.time(nil), "-:--.---")
        T.eq(fmt.time(-5), "-:--.---")
    end,
    kmh = function()
        T.eq(fmt.kmh(0), 0); T.eq(fmt.kmh(10), 36); T.eq(fmt.kmh(62.5), 225)
        T.eq(math.type(fmt.kmh(33.3)), "integer")
    end,
}
