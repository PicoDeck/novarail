# Nova Rail

An anti-gravity racer for [PicoDeck](https://picodeck.net): flat-shaded low-poly
ships on a banked, hilly track, drawn with `picocalc.gfx3d`. This is the
greybox build (phase P3): one track, one ship, flat colours, and a locked
30 fps on the PicoCalc.

Needs PicoDeck firmware 0.5.0 or newer (gfx3d, `require`, `sys.getTimeUs`).

## Layout

- `main.lua`: checks the firmware, then runs `src/game.lua`.
- `src/`: pure modules with no `picocalc` (host-tested) and the device
  modules `render`, `hud`, `controls` and `game`.
- `data/`: track definitions.
- `tests/`: host tests (`tests/run.lua`).
- `tools/build_lua32.sh`: host Lua with the device's 32-bit numbers.

## Tests

    make test        # host tests under lua and lua32

`PICODECK_ROOT` (default `~/Projects/PicoDeck/picodeck`) locates PicoDeck's Lua
sources.
