# Nova Rail

An anti-gravity racer for [PicoDeck](https://picodeck.net): flat-shaded low-poly
ships on a banked, hilly track, drawn with `picocalc.gfx3d`. This is the
greybox build: one track, the player against five AI rivals, flat colours,
and a locked 30 fps on the PicoCalc.

Needs PicoDeck firmware 0.5.0 or newer (gfx3d with `drawList`, `require`,
`sys.getTimeUs`, the gamepad, QOA music). It runs the CPU at 300 MHz
(`system_clock_khz` in `app.json`): a race of six ships needs the headroom.

## Controls

Nova Rail reads PicoDeck's gamepad, so players can rebind every button for
it in Settings -> Controls (and a controller drives the same buttons).

| Gamepad | Default key | Action |
|---|---|---|
| Left / Right | Left / Right | Steer |
| A | F4 | Accelerate (hold) |
| B | F5 | Brake |
| L / R | F2 / F3 | Left / right airbrake |
| A or Start | F4 / F1 | Race again (results page) |
| | Esc | Quit |

The keyboard reports at most three keys at once: steering, accelerate and
one airbrake fit; braking means letting go of accelerate.

## Layout

- `main.lua`: checks the firmware, then runs `src/game.lua`.
- `src/`: pure modules with no `picocalc` (host-tested) and the device
  modules `render`, `hud`, `results`, `audio`, `controls` and `game`.
- `data/`: track definitions.
- `tests/`: host tests (`tests/run.lua`).
- `tools/build_lua32.sh`: host Lua with the device's 32-bit numbers.
- `assets/src/`: the audio sources; `make assets` (`tools/prep_audio.sh`,
  needs ffmpeg and [qoaconv](https://github.com/phoboslab/qoa)) turns them into
  `assets/music/track*.qoa` (44.1 kHz stereo QOA, streamed by a fileplayer)
  and `assets/sfx/engine.wav`. Without them the game runs silent.

## Tests

    make test        # host tests under lua and lua32
    make e2e         # simulator smoke tests (build PicoDeck's simulator first)
    make hw-lap DEVICE=/dev/serial/by-id/usb-Raspberry_Pi_PicoDeck_Device_<serial>-if00

`PICODECK_ROOT` (default `~/Projects/PicoDeck/picodeck`) locates PicoDeck's Lua
sources.
`PICODECK_SIM_BINARY` picks another simulator build.

`make hw-lap` is the hardware gate (`tools/hw_lap.py`; run `make assets`
first): a two-lap race against five AI rivals, the player's ship driven by the
AI, with the game's music and engine note plus six looping bench voices standing
in for the effects still to come. It passes when no frame misses its 33.3 ms
deadline or is shown late, the frame interval's p95 is at most 34 ms, the
frame work's p95 is at most 24 ms (headroom for what P4b and P5 add), gfx3d
drops no triangle and the audio ISR stays under 2.4 ms. It sends nothing to
the device during the race. Stop any other reader of the serial port first.
The same tool installs the game with all its music for playing (`--install`;
about 12 minutes over serial, so copying the files over USB storage mode is
quicker) and measures battery drain (`--soak-stage`, then `--soak-read`; see
its help). The on-device USB-power flag is not reliable, so `--soak-read` also
refuses a run whose battery level did not fall.

## Test modes

`/data/net.picodeck.novarail/dev.json` (a JSON object; anything else is ignored):

- `"autolap": true`: the AI drives the player's ship too; the app exits when the
  race reaches its results and writes `perf.json` (frame work and interval
  min/avg/p95/max, missed and late frames, per-section timings, the player's
  lap times, the finishing order, gfx3d stats (with the triangles it dropped
  over the race), the battery level and USB power
  at the start and the end, and what audio was playing when the race ended).
- `"stay": true` (with autolap): show the results page and wait for a key
  instead of exiting.
- `"laps": n`: race length (default 3, or 1 with autolap).
- `"rivals": n`: AI rivals, 0 to 5 (default 5).
- `"bench_sfx": true`: plays `bench/sfx1-6.wav` from the app directory as six
  looping voices over the game's own audio (the gate tool stages them).
- `"mute": true`: no music and no engine note.
- `"telemetry": true`: writes `telemetry.json` (the player's ship, the race
  phase, the music track and whether the music and the engine note play) every
  15 frames.
