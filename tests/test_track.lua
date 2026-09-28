local T = require("tests.t")
local F = require("tests.fixtures")
local track = require("src.track")

local tr = F.circle(1000, 16)

return {
    advance_within_segment = function()
        local seg, t, laps = track.advance(tr, 3, 0.25, tr.len * 0.5)
        T.eq(seg, 3); T.near(t, 0.75, 1e-5); T.eq(laps, 0)
    end,
    advance_across_segments = function()
        local seg, t = track.advance(tr, 3, 0.5, tr.len * 2.25)
        T.eq(seg, 5); T.near(t, 0.75, 1e-4)
    end,
    advance_across_start_line_counts_a_lap = function()
        local seg, t, laps = track.advance(tr, tr.n, 0.9, tr.len * 0.2)
        T.eq(seg, 1); T.near(t, 0.1, 1e-4); T.eq(laps, 1)
    end,
    advance_backwards_across_start_line = function()
        local seg, t, laps = track.advance(tr, 1, 0.1, -tr.len * 0.2)
        T.eq(seg, tr.n); T.near(t, 0.9, 1e-4); T.eq(laps, -1)
    end,
    advance_zero_stays = function()
        local seg, t, laps = track.advance(tr, 7, 0.3, 0)
        T.eq(seg, 7); T.near(t, 0.3, 1e-6); T.eq(laps, 0)
    end,
    advance_rejects_nan_and_huge = function()
        T.raises(function() track.advance(tr, 1, 0, 0 / 0) end, "bad distance")
        T.raises(function() track.advance(tr, 1, 0, math.huge) end, "bad distance")
        T.raises(function() track.advance(tr, 1, 0, -tr.total * 2) end, "bad distance")
    end,
    frame_is_orthonormal = function()
        for seg = 1, tr.n, 7 do
            local _, _, _, tx, ty, tz, ux, uy, uz, rx, ry, rz = track.frame(tr, seg, 0.37)
            T.near(tx * tx + ty * ty + tz * tz, 1, 1e-4, "|T|")
            T.near(ux * ux + uy * uy + uz * uz, 1, 1e-4, "|U|")
            T.near(rx * rx + ry * ry + rz * rz, 1, 1e-3, "|R|")
            T.near(tx * ux + ty * uy + tz * uz, 0, 1e-3, "T.U")
        end
    end,
    point_offsets_along_right_and_up = function()
        local px, py, pz, _, _, _, ux, uy, uz, rx, ry, rz = track.frame(tr, 5, 0.5)
        local x, y, z = track.point(tr, 5, 0.5, 3, 2)
        T.near(x, px + rx * 3 + ux * 2, 1e-3); T.near(y, py + ry * 3 + uy * 2, 1e-3)
        T.near(z, pz + rz * 3 + uz * 2, 1e-3)
    end,
    lerp_wraps_at_the_last_segment = function()
        T.near(track.lerp(tr.px, tr, tr.n, 1), tr.px[1], 1e-3)
    end,
}
