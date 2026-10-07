-- Nova Rail: an anti-gravity racer for PicoDeck.
local pc = picocalc

-- Firmware before 0.5.0 has no gfx3d (or gfx3d.drawList), require,
-- getTimeUs or gamepad: say so, rather than fail with a Lua error.
if not (pc.gfx3d and pc.gfx3d.drawList) or type(require) ~= "function" or not pc.sys.getTimeUs
    or not pc.gamepad then
    local d = pc.display
    d.clear(d.BLACK)
    d.drawText(16, 136, "Nova Rail needs PicoDeck", d.WHITE)
    d.drawText(16, 152, "firmware 0.5.0 or newer.", d.WHITE)
    d.drawText(16, 184, "Press any key to exit.", d.WHITE)
    d.flush()
    pc.input.clearState()
    repeat
        pc.input.update()
        pc.sys.sleep(20)
    until pc.input.getButtonsPressed() ~= 0 or pc.input.getChar()
    return
end

require("src.game").run()
