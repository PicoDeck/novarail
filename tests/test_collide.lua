local T = require("tests.t")
local F = require("tests.fixtures")
local collide = require("src.collide")
local physics = require("src.physics")
local P = physics.P

local tr = F.circle(1000, 16)

local function ship(seg, t, u, v)
    local s = physics.new_ship(seg, t, u)
    s.v = v or 30
    return s
end

local function gap(a, b)
    local d = ((b.seg - 1 + b.t) - (a.seg - 1 + a.t)) * tr.len
    if d > tr.total / 2 then d = d - tr.total elseif d < -tr.total / 2 then d = d + tr.total end
    return d
end

return {
    side_by_side_pushes_apart = function()
        local a, b = ship(5, 0.5, 0), ship(5, 0.5, 1)
        collide.resolve(tr, { a, b })
        T.near(b.u - a.u, collide.WID, 1e-3, "separated")
        T.near((a.u + b.u) / 2, 0.5, 1e-3, "about their midpoint")
        T.ok(a.bump and b.bump)
        T.eq(a.energy, P.ENERGY, "no closing speed, no damage")
    end,
    side_swipe_costs_energy_and_bounces_off = function()
        local a, b = ship(5, 0.5, 0, 50), ship(5, 0.5, 1, 50)
        a.psi, b.psi = 0.2, -0.1           -- steering into each other
        collide.resolve(tr, { a, b })
        T.ok(a.energy < P.ENERGY and b.energy < P.ENERGY, "damage")
        T.ok(a.psi < 0 and b.psi > 0, "headings bounce apart: " .. a.psi .. " " .. b.psi)
    end,
    sustained_side_contact_does_not_grind_energy_away = function()
        local a, b = ship(5, 0.5, 0, 50), ship(5, 0.5, 1, 50)
        a.psi, b.psi = 0.2, -0.2
        local phys = require("src.physics")
        for _ = 1, 90 do  -- three seconds side by side
            phys.step(tr, a, { steer = 1 }, 1 / 30)
            phys.step(tr, b, { steer = -1 }, 1 / 30)
            collide.resolve(tr, { a, b })
        end
        -- at most one capped hit per cooldown: 3 s of deliberate grinding
        -- costs about half the store, not all of it
        T.ok(a.energy >= P.ENERGY - 90 / collide.COOLDOWN * collide.MAX_HIT, "energy left " .. a.energy)
        T.ok(a.energy > 0 and not a.dnf)
    end,
    rear_end_sets_back_and_shares_speed = function()
        local back, front = ship(5, 0.5, 0, 50), ship(5, 0.5 + 2 / tr.len, 0.2, 40)
        collide.resolve(tr, { back, front })
        T.near(gap(back, front), collide.LEN, 1e-3, "no overlap along the track")
        T.ok(back.v < 50 and front.v > 40, "speed passed forward: " .. back.v .. " " .. front.v)
        T.ok(back.energy < P.ENERGY and front.energy < P.ENERGY, "both took damage")
    end,
    gentle_contact_costs_no_energy = function()
        local back, front = ship(5, 0.5, 0, 42), ship(5, 0.5 + 2 / tr.len, 0, 40)
        collide.resolve(tr, { back, front })
        T.ok(back.bump, "they touched")
        T.eq(back.energy, P.ENERGY); T.eq(front.energy, P.ENERGY)
    end,
    slower_ship_behind_takes_nothing = function()
        local back, front = ship(5, 0.5, 0, 30), ship(5, 0.5 + 2 / tr.len, 0, 40)
        collide.resolve(tr, { back, front })
        T.eq(back.v, 30); T.eq(front.v, 40)
        T.eq(back.energy, P.ENERGY)
    end,
    apart_means_no_contact = function()
        local a, b, c = ship(5, 0.5, 0), ship(7, 0.5, 0), ship(5, 0.5, 6)
        collide.resolve(tr, { a, b, c })
        T.eq(a.u, 0); T.eq(c.u, 6); T.eq(a.bump, false)
    end,
    contact_across_the_start_line = function()
        local a, b = ship(tr.n, 0.9, 0), ship(1, 0.1, 0.5)
        b.lap = a.lap + 1
        collide.resolve(tr, { a, b })
        T.ok(a.bump and b.bump, "1.6 m apart across the line")
    end,
    set_back_across_the_line_takes_a_lap_off = function()
        local back, front = ship(1, 0.05, 0, 50), ship(1, 0.3, 0, 40)
        back.lap, front.lap = 1, 1
        collide.resolve(tr, { back, front })
        T.eq(back.seg, tr.n, "moved back over the line"); T.eq(back.lap, 0)
    end,
    pushed_ships_stay_inside_the_walls = function()
        local lim = tr.w[5] / 2 - P.SHIP_HALF_W
        local a, b = ship(5, 0.5, lim - 0.5), ship(5, 0.5, lim)
        collide.resolve(tr, { a, b })
        T.ok(b.u <= lim + 1e-6 and a.u >= -lim, "clamped: " .. b.u)
    end,
    six_ships_allocate_nothing = function()
        local ships = {}
        for i = 1, 6 do ships[i] = ship(5, i * 0.05, (i % 2) * 1.5) end
        collide.resolve(tr, ships)
        local before = collectgarbage("count")
        for _ = 1, 200 do collide.resolve(tr, ships) end
        T.ok(collectgarbage("count") - before < 1, "no garbage")
    end,
}
