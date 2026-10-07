-- Track 1: a closed loop of spline control points {x, y, z, width, bank}.
-- Metres; x right, y up, z towards the viewer (the start line is the first
-- point, driving towards -z). bank is in radians: > 0 lowers the right edge,
-- for a right-hand bend. The lap runs clockwise seen from above.
-- Pads: `at` is the fraction of the lap where the pad starts, `u` its lateral
-- centre (metres, + = right) and `half` its half width. `recharge` is the
-- energy-recharge strip, from and to as fractions of the lap.
--
-- With the grip limit (physics A_GRIP) the lap has one hard stop, the
-- hairpin at the end of the start straight (its pad throws you in at up to
-- 85 m/s), and one braking complex, the chicane at the foot of the hill and
-- the right after it; the sweepers between need at most a lift. Ships hop
-- over the crest at full speed and land well before the chicane.
return {
    name = "Proving Ground",
    points = {
        { 0, 0, 0, 24, 0 },
        { 0, 0, -200, 24, 0 },
        { 0, 0, -320, 22, 0 },
        { 12, 0, -372, 20, 0.12 },   -- hairpin entry
        { 46, 0, -392, 20, 0.18 },   -- hairpin apex
        { 80, 0, -372, 20, 0.12 },
        { 92, 0, -320, 22, 0.02 },   -- hairpin exit, heading south
        { 100, 0, -268, 22, -0.03 },
        { 135, 0, -215, 22, -0.06 }, -- an easy left onto the diagonal
        { 190, 0, -175, 22, 0 },
        { 250, 1, -140, 22, 0.02 },
        { 315, 3, -105, 22, 0.1 },   -- fast right
        { 352, 10, -50, 22, 0.06 },
        { 368, 22, 15, 22, 0.02 },   -- the climb
        { 374, 34, 80, 22, 0 },
        { 376, 36, 130, 22, 0 },     -- crest
        { 375, 24, 195, 22, 0 },
        { 373, 6, 260, 22, 0 },
        { 380, 0, 300, 20, -0.08 },
        { 396, 0, 327, 20, -0.1 },   -- chicane: left flick
        { 394, 0, 365, 20, 0.1 },    -- ...right flick
        { 378, 0, 397, 20, 0.06 },
        { 360, 0, 430, 22, 0.04 },
        { 322, -1, 467, 22, 0.1 },   -- right onto the back straight
        { 260, -4, 480, 22, 0.02 },
        { 170, -10, 485, 22, 0 },    -- the dip
        { 80, -4, 478, 22, 0 },
        { 5, 0, 445, 24, 0.08 },     -- final right
        { -38, 0, 360, 24, 0.1 },
        { -42, 0, 240, 24, 0.04 },
        { -25, 0, 120, 24, 0 },
        { -6, 0, 50, 24, 0 },
    },
    recharge = { from = 0.95, to = 0.02 },
    pads = {
        { at = 0.06, u = 0, half = 4 },
        { at = 0.22, u = 4, half = 3 },
        { at = 0.70, u = -4, half = 3 },
    },
}
