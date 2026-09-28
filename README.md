# Nova Rail

An anti-gravity racer for [PicoDeck](https://picodeck.net): flat-shaded low-poly
ships on a banked, hilly track, drawn with `picocalc.gfx3d`. This is the
greybox build (phase P3): one track, one ship, flat colours, and a locked
30 fps on the PicoCalc.

Needs PicoDeck firmware 0.5.0 or newer (gfx3d, `require`, `sys.getTimeUs`).

## Controls

| Key | Action |
|---|---|
| Left / Right | Steer |
| Z / X | Left / right airbrake |
| Down | Brake |
| Esc | Quit |

Thrust is automatic: the keyboard reports at most three keys at once.

## Layout

- `main.lua`: checks the firmware, then runs `src/game.lua`.
- `src/`: pure modules with no `picocalc` (host-tested) and the device
  modules `render`, `hud`, `controls` and `game`.
- `data/`: track definitions.
- `tests/`: host tests (`tests/run.lua`).
- `tools/build_lua32.sh`: host Lua with the device's 32-bit numbers.

## Tests

    make test        # host tests under lua and lua32
    make e2e         # simulator smoke tests (build PicoDeck's simulator first)

`PICODECK_ROOT` (default `~/Projects/PicoDeck/picodeck`) locates PicoDeck's Lua
sources.
`PICODECK_SIM_BINARY` picks another simulator build.

## Test modes

`/data/net.picodeck.novarail/dev.json` (a JSON object; anything else is ignored):

- `"autolap": true`: the autopilot drives; the app exits after `"laps"` laps
  (default 1) and writes `perf.json` (frame work and interval min/avg/p95/max,
  missed deadlines, lap times, gfx3d stats).
- `"bench_audio": true`: plays `bench/music.mp3` and `bench/sfx1-6.wav` from the
  app directory (the gate tool stages them).
- `"telemetry": true`: writes `telemetry.json` (the ship's state) every 15 frames.
