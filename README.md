# Nova Rail

An anti-gravity racer for [PicoDeck](https://picodeck.net): flat-shaded low-poly
ships on a banked, hilly track, drawn with `picocalc.gfx3d`. This is the
greybox build (phase P3): one track, one ship, flat colours, and a locked
30 fps on the PicoCalc.

Needs PicoDeck firmware 0.5.0 or newer (gfx3d with `drawList`, `require`,
`sys.getTimeUs`). It runs the CPU at 300 MHz (`system_clock_khz` in
`app.json`): a race of six ships needs the headroom.

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
    make hw-lap DEVICE=/dev/serial/by-id/usb-Raspberry_Pi_PicoDeck_Device_<serial>-if00

`PICODECK_ROOT` (default `~/Projects/PicoDeck/picodeck`) locates PicoDeck's Lua
sources.
`PICODECK_SIM_BINARY` picks another simulator build.

`make hw-lap` is the hardware gate (`tools/hw_lap.py`): two autopilot laps with
bench audio; it passes when no frame misses its 33.3 ms deadline, the frame
interval's p95 is at most 34 ms and the audio ISR stays under 2.4 ms. Stop any
other reader of the serial port first.

## Test modes

`/data/net.picodeck.novarail/dev.json` (a JSON object; anything else is ignored):

- `"autolap": true`: the autopilot drives; the app exits after `"laps"` laps
  (default 1) and writes `perf.json` (frame work and interval min/avg/p95/max,
  missed deadlines, lap times, gfx3d stats).
- `"bench_audio": true`: plays `bench/music.wav` and `bench/sfx1-6.wav` from the
  app directory (the gate tool stages them).
- `"telemetry": true`: writes `telemetry.json` (the ship's state) every 15 frames.
