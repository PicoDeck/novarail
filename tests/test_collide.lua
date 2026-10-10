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
        T.ok(a.psi < 0.2 and b.psi > -0.1, "headings twitch apart: " .. a.psi .. " " .. b.psi)
        T.ok(a.vs < 0 and b.vs > 0, "and the ships slide apart")
    end,
    side_bump_shoves_both_ships_apart = function()
        local a, b = ship(5, 0.5, 0, 50), ship(5, 0.5, 2, 50)
        a.psi = 0.1 -- a drifts into b
        local closing = 50 * math.sin(0.1)
        collide.resolve(tr, { a, b })
        local j = (1 + collide.E) * 0.5 * closing
        T.near(a.vs, -j, 1e-6, "a slides left")
        T.near(b.vs, j, 1e-6, "b slides right")
        T.near(a.psi, 0.1 - collide.K_YAW * j, 1e-6, "a twitches away")
        T.near(b.psi, collide.K_YAW * j, 1e-6, "b twitches away")
        local c, d = ship(5, 0.5, 0, 60), ship(5, 0.5, 2, 60)
        c.vs = 40 -- a huge shove still twitches only so far
        collide.resolve(tr, { c, d })
        T.near(d.psi, collide.MAX_TWITCH, 1e-6, "capped")
    end,
    gentle_bump_still_shoves_but_costs_nothing = function()
        local a, b = ship(5, 0.5, 0, 30), ship(5, 0.5, 2, 30)
        a.vs = 2 -- under MIN_CLOSING
        collide.resolve(tr, { a, b })
        T.ok(a.vs < 2 and b.vs > 0, "shoved: " .. a.vs .. " " .. b.vs)
        T.eq(a.energy, P.ENERGY); T.eq(b.energy, P.ENERGY)
        T.eq(a.psi, 0); T.eq(b.psi, 0, "jostling does not twitch")
    end,
    shoved_ships_slide_apart_then_grip = function()
        local phys = require("src.physics")
        local a, b = ship(5, 0.5, -1, 40), ship(5, 0.5, 1, 40)
        a.vs = 8 -- a slams sideways into b
        collide.resolve(tr, { a, b })
        for _ = 1, 30 do -- one second
            phys.step(tr, a, { steer = 0 }, 1 / 30)
            phys.step(tr, b, { steer = 0 }, 1 / 30)
            collide.resolve(tr, { a, b })
        end
        T.ok(b.u - a.u > collide.WID + 1, "apart: " .. (b.u - a.u))
        T.eq(a.vs, 0); T.eq(b.vs, 0, "grip took the slides")
    end,
    off_centre_rear_end_twitches_both = function()
        -- 3 m apart along the track and 0.8 m across: nose to tail, off centre
        local back, front = ship(5, 0.5, 0, 50), ship(5, 0.5 + 3 / tr.len, 0.8, 40)
        collide.resolve(tr, { back, front })
        T.ok(front.psi > 0, "the one ahead turns away, to its side: " .. front.psi)
        T.ok(back.psi < 0, "the one behind turns the other way: " .. back.psi)
        local b2, f2 = ship(5, 0.5, 0, 50), ship(5, 0.5 + 2 / tr.len, 0, 40)
        collide.resolve(tr, { b2, f2 })
        T.eq(f2.psi, 0, "dead centre: no twitch"); T.eq(b2.psi, 0)
    end,
    pinned_to_the_wall_by_a_rival = function()
        local phys = require("src.physics")
        local lim = tr.w[5] * 0.5 - P.SHIP_HALF_W
        -- b rides the right wall; a holds station alongside it (thrust when
        -- behind, brake when ahead, the player's two substeps), steering in
        local a, b = ship(5, 0.5, lim - collide.WID, 50), ship(5, 0.5, lim, 50)
        local touching, slide, turn = 0, 0, 0
        for _ = 1, 60 do -- two seconds
            local ahead = ((a.seg - b.seg) + (a.t - b.t)) * tr.len
            local c = { steer = 1, thrust = ahead < 0, brake = ahead > 0.5 }
            for _ = 1, 2 do phys.step(tr, a, c, 1 / 60) end
            phys.step(tr, b, { steer = 0, thrust = true }, 1 / 30)
            collide.resolve(tr, { a, b })
            if b.bump then touching = touching + 1 end
            slide, turn = math.max(slide, math.abs(a.vs)), math.max(turn, math.abs(a.psi))
        end
        T.ok(touching >= 10, "it kept coming back for two seconds: " .. touching .. " contacts")
        T.ok(b.u <= lim + 1e-9, "still inside the wall")
        T.ok(b.energy >= P.ENERGY / 2, "the pinned ship keeps half its energy: " .. b.energy)
        T.ok(b.energy >= a.energy, "pinning never costs the victim more: " .. b.energy .. " vs " .. a.energy)
        -- it bounces off the pinned ship as off a wall: no slide or heading
        -- building up while it leans on it
        T.ok(slide < 15, "the aggressor's slide stays sane: up to " .. slide)
        T.ok(turn < phys.P.PSI_MAX - 0.1, "and its heading: up to " .. turn)
    end,
    ramming_a_pinned_ship_hurts_the_rammer = function()
        local lim = tr.w[5] * 0.5 - P.SHIP_HALF_W
        local a, b = ship(5, 0.5, lim - collide.WID + 0.5, 50), ship(5, 0.5, lim, 50)
        a.vs = 12 -- slams sideways into b, which is against the wall
        collide.resolve(tr, { a, b })
        T.eq(b.energy, P.ENERGY, "the pinned ship takes nothing")
        T.ok(a.energy < P.ENERGY, "the rammer pays: " .. a.energy)
        T.eq(b.u, lim, "the pinned ship does not move")
        T.ok(a.v * math.sin(a.psi) + a.vs < 0, "the rammer bounces off")
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
