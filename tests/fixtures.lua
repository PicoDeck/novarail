-- Shared test tracks.
local trackgen = require("src.trackgen")

local F = {}

-- A flat circle of radius r (m), `count` control points, width 20.
function F.circle_def(r, count)
    local pts = {}
    for k = 0, count - 1 do
        local a = 2 * math.pi * k / count
        -- clockwise seen from above: start at the origin heading -z, bending right
        pts[#pts + 1] = { r - r * math.cos(a), 0, -r * math.sin(a), 20, 0 }
    end
    return { name = "circle", points = pts, pads = {} }
end

function F.circle(r, count)
    return trackgen.generate(F.circle_def(r or 1000, count or 16), 8)
end

function F.track1()
    return trackgen.generate(require("data.track1"), 8)
end

return F
