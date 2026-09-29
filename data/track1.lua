-- Track 1: a closed loop of spline control points {x, y, z, width, bank}.
-- Metres; x right, y up, z towards the viewer (the start line is the first
-- point, driving towards -z). bank is in radians: > 0 lowers the right edge,
-- for a right-hand bend. The lap runs clockwise seen from above.
-- Pads: `at` is the fraction of the lap where the pad starts, `u` its lateral
-- centre (metres, + = right) and `half` its half width. `recharge` is the
-- energy-recharge strip, from and to as fractions of the lap.
return {
    name = "Proving Ground",
    points = {
        { 0, 0, 0, 24, 0 },
        { 0, 0, -180, 24, 0 },
        { 15, 0, -330, 22, 0.05 },
        { 80, 0, -430, 22, 0.15 },
        { 190, 0, -460, 22, 0.15 },
        { 290, 0, -400, 22, 0.12 },
        { 350, 3, -290, 22, 0.02 },
        { 370, 13, -170, 22, 0 },
        { 380, 24, -60, 22, 0 },
        { 385, 13, 50, 22, 0 },
        { 380, 1, 160, 22, 0 },
        { 340, 0, 260, 22, -0.08 },
        { 270, 0, 300, 20, 0 },
        { 210, 0, 360, 20, 0.08 },
        { 130, 0, 420, 22, 0.15 },
        { 20, 0, 420, 22, 0.12 },
        { -60, 0, 340, 22, 0.1 },
        { -80, 0, 210, 24, 0.04 },
        { -40, 0, 90, 24, 0 },
    },
    recharge = { from = 0.95, to = 0.02 }, -- the start straight
    pads = {
        { at = 0.07, u = 0, half = 4 },
        { at = 0.55, u = -5, half = 3 },
        { at = 0.80, u = 5, half = 3 },
    },
}
