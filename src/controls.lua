-- Keyboard to ship controls. The keyboard reports at most three keys at
-- once, so thrust is automatic by default: steering plus one airbrake plus
-- one more key always fits.
local M = {}

local input = picocalc.input

-- Airbrake keys (isKeyDown names). Provisional until the hardware playtest.
M.AIRBRAKE_L, M.AIRBRAKE_R = "z", "x"

-- Fills out = { steer, thrust, brake, abL, abR }.
function M.read(out, auto_thrust)
    local held = input.getButtons()
    local steer = 0
    if held & input.BTN_LEFT ~= 0 then steer = steer - 1 end
    if held & input.BTN_RIGHT ~= 0 then steer = steer + 1 end
    out.steer = steer
    out.brake = held & input.BTN_DOWN ~= 0
    out.thrust = not out.brake and (auto_thrust or held & input.BTN_UP ~= 0)
    out.abL = input.isKeyDown(M.AIRBRAKE_L)
    out.abR = input.isKeyDown(M.AIRBRAKE_R)
    return out
end

return M
