-- Gamepad to ship controls. PicoDeck's gamepad layer (firmware 0.5.0)
-- aliases keys to buttons that players rebind in Settings -> Controls: the
-- D-pad steers, A accelerates, B brakes, L and R are the airbrakes. The
-- keyboard reports at most three keys at once, so steering, accelerate and
-- one airbrake fit; braking means letting go of accelerate.
local M = {}

local gp = picocalc.gamepad
local PAD_LEFT, PAD_RIGHT, PAD_A, PAD_B = gp.PAD_LEFT, gp.PAD_RIGHT, gp.PAD_A, gp.PAD_B
local PAD_L, PAD_R = gp.PAD_L, gp.PAD_R

-- Fills out = { steer, thrust, brake, abL, abR }. auto_thrust thrusts
-- whenever the ship is not braking, with no button held.
function M.read(out, auto_thrust)
    local held = gp.getButtons()
    local steer = 0
    if held & PAD_LEFT ~= 0 then steer = steer - 1 end
    if held & PAD_RIGHT ~= 0 then steer = steer + 1 end
    out.steer = steer
    local brake = held & PAD_B ~= 0
    out.brake = brake
    out.thrust = not brake and (auto_thrust or held & PAD_A ~= 0)
    out.abL = held & PAD_L ~= 0
    out.abR = held & PAD_R ~= 0
    return out
end

-- Race again, on the results page: A or Start pressed, but only once both
-- have read up for ARM_POLLS polls in a row after arm_again(). The player
-- may still hold A (accelerate) when the page comes up, and the PicoCalc
-- keyboard repeats arrows, letters and the like as fresh presses every
-- 100 ms, so one quiet poll after input.clearState() proves nothing; the
-- results page polls every 20 ms, so 8 polls outlast a repeat.
M.ARM_POLLS = 8

local armed, quiet = false, 0

function M.arm_again()
    armed, quiet = false, 0
end

function M.again_pressed()
    local again = gp.PAD_A | gp.PAD_START
    if not armed then
        quiet = gp.getButtons() & again == 0 and quiet + 1 or 0
        armed = quiet >= M.ARM_POLLS
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
