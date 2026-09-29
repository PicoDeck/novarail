local T = require("tests.t")
local engine = require("src.engine")

return {
    pitch_rises_with_speed_and_is_capped = function()
        T.near(engine.rate(0), engine.RATE_IDLE, 1e-6)
        T.ok(engine.rate(30) > engine.rate(10))
        T.near(engine.rate(1000), engine.RATE_IDLE + engine.RATE_SPAN * engine.OVER, 1e-6)
    end,
    volume_is_an_integer_in_range = function()
        for _, v in ipairs({ 0, 20, 60, 90, 1000 }) do
            local vol = engine.volume(v)
            T.eq(math.type(vol), "integer")
            T.ok(vol >= 0 and vol <= 100)
        end
        T.ok(engine.volume(60) > engine.volume(0))
    end,
    negative_or_nan_speed_is_idle = function()
        T.near(engine.rate(-5), engine.RATE_IDLE, 1e-6)
        T.near(engine.rate(0 / 0), engine.RATE_IDLE, 1e-6)
        T.eq(engine.volume(0 / 0), engine.VOL_IDLE)
    end,
}
