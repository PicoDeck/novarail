local T = require("tests.t")

-- A fake gamepad: the PAD_* bits and labels of PicoDeck's gamepad layer,
-- with the held and pressed masks set by each test.
local gp = { PAD_UP = 1, PAD_DOWN = 2, PAD_LEFT = 4, PAD_RIGHT = 8, PAD_A = 16, PAD_B = 32,
    PAD_X = 64, PAD_Y = 128, PAD_L = 256, PAD_R = 512, PAD_START = 1024, PAD_SELECT = 2048,
    held = 0, pressed = 0, labels = {}, alt = {} }
function gp.getButtons() return gp.held end
function gp.getButtonsPressed() return gp.pressed end
function gp.getLabel(btn, slot) return (slot == 1 and gp.alt or gp.labels)[btn] end

local saved = picocalc
picocalc = { gamepad = gp }
package.loaded["src.controls"] = nil
local controls = require("src.controls")
picocalc = saved

local function read(held, auto)
    gp.held = held
    return controls.read({}, auto)
end

return {
    dpad_steers = function()
        T.eq(read(gp.PAD_LEFT).steer, -1)
        T.eq(read(gp.PAD_RIGHT).steer, 1)
        T.eq(read(gp.PAD_LEFT | gp.PAD_RIGHT).steer, 0, "both cancel")
        T.eq(read(0).steer, 0)
    end,
    a_accelerates_b_brakes = function()
        local c = read(gp.PAD_A)
        T.eq(c.thrust, true); T.eq(c.brake, false)
        c = read(gp.PAD_B)
        T.eq(c.thrust, false); T.eq(c.brake, true)
        T.eq(read(0).thrust, false, "no thrust without A")
    end,
    brake_overrides_accelerate = function()
        local c = read(gp.PAD_A | gp.PAD_B)
        T.eq(c.thrust, false); T.eq(c.brake, true)
    end,
    auto_thrust_needs_no_button = function()
        T.eq(read(0, true).thrust, true)
        T.eq(read(gp.PAD_B, true).thrust, false, "braking still cuts it")
    end,
    shoulders_are_the_airbrakes = function()
        local c = read(gp.PAD_L)
        T.eq(c.abL, true); T.eq(c.abR, false)
        c = read(gp.PAD_R | gp.PAD_RIGHT | gp.PAD_A)
        T.eq(c.abL, false); T.eq(c.abR, true); T.eq(c.steer, 1); T.eq(c.thrust, true)
    end,
    a_or_start_races_again = function()
        local function press(btn)
            controls.arm_again()
            gp.held, gp.pressed = 0, 0
            for _ = 1, controls.ARM_POLLS do controls.again_pressed() end -- both up: armed
            gp.held, gp.pressed = btn, btn
            local again = controls.again_pressed()
            gp.held, gp.pressed = 0, 0
            return again
        end
        T.eq(press(gp.PAD_A), true)
        T.eq(press(gp.PAD_START), true)
        T.eq(press(gp.PAD_B), false)
    end,
    again_waits_for_a_fresh_press = function()
        controls.arm_again()
        -- A still held from racing: the key's repeat re-presses it
        gp.held, gp.pressed = gp.PAD_A, gp.PAD_A
        T.eq(controls.again_pressed(), false, "not while A is still held from the race")
        -- a repeat-as-press key (an arrow, a letter) after input.clearState():
        -- up for a poll, then the next repeat arrives as a fresh press
        gp.held, gp.pressed = 0, 0
        T.eq(controls.again_pressed(), false)
        gp.held, gp.pressed = gp.PAD_A, gp.PAD_A
        T.eq(controls.again_pressed(), false, "a repeat after one quiet poll is not a fresh press")
        gp.held, gp.pressed = 0, 0
        for _ = 1, controls.ARM_POLLS do
            T.eq(controls.again_pressed(), false, "released: arming")
        end
        gp.held, gp.pressed = gp.PAD_A, gp.PAD_A
        T.eq(controls.again_pressed(), true, "a fresh press")
        gp.held, gp.pressed = 0, 0
    end,
    a_button_with_no_key_is_unbound = function()
        gp.labels, gp.alt = {}, {}
        T.eq(controls.bound(gp.PAD_A), false)
        gp.alt[gp.PAD_A] = "Z"
        T.eq(controls.bound(gp.PAD_A), true, "the alternate slot counts")
        gp.labels[gp.PAD_A], gp.alt[gp.PAD_A] = "F4", nil
        T.eq(controls.bound(gp.PAD_A), true)
    end,
    labels_name_the_bound_key = function()
        gp.labels[gp.PAD_A] = "F4"
        T.eq(controls.label(gp.PAD_A), "F4")
        T.eq(controls.label(gp.PAD_B), "?", "unbound")
    end,
}
