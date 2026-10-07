-- Gamepad to ship controls. PicoDeck's gamepad layer (firmware 0.5.0)
-- aliases keys to buttons that players rebind in Settings -> Controls: the
-- D-pad steers, A accelerates, B brakes, L and R are the airbrakes. The
-- keyboard reports at most three keys at once, so steering, accelerate and
-- one airbrake fit; braking means letting go of accelerate.
local M = {}

local gp = picocalc.gamepad

-- Fills out = { steer, thrust, brake, abL, abR }. auto_thrust thrusts
-- whenever the ship is not braking, with no button held.
function M.read(out, auto_thrust)
    local held = gp.getButtons()
    local steer = 0
    if held & gp.PAD_LEFT ~= 0 then steer = steer - 1 end
    if held & gp.PAD_RIGHT ~= 0 then steer = steer + 1 end
    out.steer = steer
    out.brake = held & gp.PAD_B ~= 0
    out.thrust = not out.brake and (auto_thrust or held & gp.PAD_A ~= 0)
    out.abL = held & gp.PAD_L ~= 0
    out.abR = held & gp.PAD_R ~= 0
    return out
end

-- Race again, on the results page: A or Start pressed, but only once both
-- have been seen up after arm_again(). The player may still hold A
-- (accelerate) when the page comes up, and the PicoCalc keyboard reports a
-- held key's repeats as fresh presses.
local armed = false

function M.arm_again()
    armed = false
end

function M.again_pressed()
    local again = gp.PAD_A | gp.PAD_START
    if not armed then
        armed = gp.getButtons() & again == 0
        return false
    end
    return gp.getButtonsPressed() & again ~= 0
end

-- True if btn has a key in either slot (a player can unbind it in
-- Settings -> Controls).
function M.bound(btn)
    return gp.getLabel(btn, 0) ~= nil or gp.getLabel(btn, 1) ~= nil
end

-- The name of the key bound to btn, for hints ("F4"); "?" when unbound.
function M.label(btn)
    return gp.getLabel(btn) or "?"
end

return M
