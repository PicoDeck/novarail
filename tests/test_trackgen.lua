local T = require("tests.t")
local F = require("tests.fixtures")
local trackgen = require("src.trackgen")

local tr = F.track1()

local function def_with(fn)
    local d = F.circle_def(300, 8)
    fn(d)
    return d
end

return {
    track1_size = function()
        T.ok(tr.total > 1800 and tr.total < 2600, "lap length " .. tr.total)
        T.near(tr.len, 8, 0.1, "segment length")
        T.eq(tr.n * tr.len - tr.total < 0.01, true, "n * len = total")
    end,
    track1_closes = function()
        local dx, dy, dz = tr.px[1] - tr.px[tr.n], tr.py[1] - tr.py[tr.n], tr.pz[1] - tr.pz[tr.n]
        T.near(math.sqrt(dx * dx + dy * dy + dz * dz), tr.len, 0.3, "last ring to first")
    end,
    starts_at_first_point_heading_minus_z = function()
        T.near(tr.px[1], 0, 1e-3); T.near(tr.pz[1], 0, 1e-3)
        T.ok(tr.tz[1] < -0.98, "forward at the start line")
    end,
    frames_are_orthonormal = function()
        for i = 1, tr.n do
            local t = { tr.tx[i], tr.ty[i], tr.tz[i] }
            local u = { tr.ux[i], tr.uy[i], tr.uz[i] }
            local r = { tr.rx[i], tr.ry[i], tr.rz[i] }
            local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
            T.near(dot(t, t), 1, 1e-4); T.near(dot(u, u), 1, 1e-4); T.near(dot(r, r), 1, 1e-4)
            T.near(dot(t, u), 0, 1e-4); T.near(dot(t, r), 0, 1e-4); T.near(dot(u, r), 0, 1e-4)
        end
    end,
    track1_is_drivable = function()
        local maxk, maxgrade = 0, 0
        for i = 1, tr.n do
            maxk = math.max(maxk, math.abs(tr.kr[i]))
            maxgrade = math.max(maxgrade, math.abs(tr.ty[i]))
        end
        T.ok(1 / maxk >= 55, "tightest bend radius " .. 1 / maxk)
        T.ok(maxgrade <= 0.2, "steepest grade " .. maxgrade)
    end,
    track1_has_a_crest = function()
        local crest = false
        for i = 1, tr.n do
            if tr.py[i] > 15 and tr.ku[i] < -0.002 then crest = true end
        end
        T.ok(crest, "a crest (ku < -0.002 above 15 m)")
    end,
    bank_lowers_the_right_edge = function()
        local seen = 0
        for i = 1, tr.n do
            if tr.bank[i] > 0.1 then
                local hw = tr.w[i] * 0.5
                T.ok(tr.py[i] + tr.ry[i] * hw < tr.py[i] - tr.ry[i] * hw, "ring " .. i)
                seen = seen + 1
            end
        end
        T.ok(seen > 0, "track1 has banked rings")
    end,
    curvature_sign = function()
        local c = F.circle(300, 12)
        T.near(c.kr[5], 1 / 300, 2e-4, "a clockwise circle bends right")
        T.near(c.ku[5], 0, 1e-5, "flat")
    end,
    pads_placed = function()
        local ids = {}
        for seg = 1, tr.n do
            local id = tr.padid[seg]
            if id then
                ids[id] = (ids[id] or 0) + 1
                T.ok(tr.padlo[seg] < tr.padhi[seg])
                T.ok(tr.padhi[seg] <= tr.w[seg] * 0.5 - 1 and tr.padlo[seg] >= -tr.w[seg] * 0.5 + 1)
            end
        end
        for id = 1, 3 do T.eq(ids[id], trackgen.PAD_SEGS, "pad " .. id .. " segments") end
    end,
    deterministic = function()
        local again = F.track1()
        for i = 1, tr.n do
            T.eq(again.px[i], tr.px[i]); T.eq(again.uy[i], tr.uy[i]); T.eq(again.kr[i], tr.kr[i])
        end
    end,
    rejects_too_few_points = function()
        T.raises(function()
            trackgen.generate({ points = { { 0, 0, 0, 20, 0 }, { 0, 0, -50, 20, 0 }, { 50, 0, -50, 20, 0 } } }, 8)
        end, "at least 4 control points")
    end,
    rejects_duplicate_points = function()
        T.raises(function()
            trackgen.generate(def_with(function(d) d.points[3] = { table.unpack(d.points[2]) } end), 8)
        end, "under 1 m apart")
    end,
    rejects_non_numbers = function()
        T.raises(function()
            trackgen.generate(def_with(function(d) d.points[2][2] = 0 / 0 end), 8)
        end, "is not a number")
        T.raises(function()
            trackgen.generate(def_with(function(d) d.points[2][4] = nil end), 8)
        end, "is not a number")
    end,
    rejects_narrow_road = function()
        T.raises(function()
            trackgen.generate(def_with(function(d) d.points[2][4] = 3 end), 8)
        end, "narrower than 4 m")
    end,
    rejects_a_pad_off_the_road = function()
        T.raises(function()
            trackgen.generate(def_with(function(d) d.pads = { { at = 0.5, u = 9, half = 2 } } end), 8)
        end, "does not fit the road")
    end,
    rejects_overlapping_pads = function()
        T.raises(function()
            trackgen.generate(def_with(function(d)
                d.pads = { { at = 0.5, u = 0, half = 2 }, { at = 0.5, u = 0, half = 2 } }
            end), 8)
        end, "overlap")
    end,
    rejects_a_pad_outside_the_lap = function()
        T.raises(function()
            trackgen.generate(def_with(function(d) d.pads = { { at = 1, u = 0, half = 2 } } end), 8)
        end, "must be in [0, 1)")
    end,
    rejects_a_cliff = function()
        T.raises(function()
            trackgen.generate(def_with(function(d) d.points[4][2] = 400 end), 8)
        end, "too steep")
    end,
}
