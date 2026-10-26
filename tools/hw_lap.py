#!/usr/bin/env python3
"""The hardware gate: a race at a locked 30 fps on a PicoCalc.

    python3 tools/hw_lap.py --device /dev/serial/by-id/usb-Raspberry_Pi_PicoDeck_Device_<serial>-if00

1. Reboots the device (a fresh heap) and pushes Nova Rail with the game's
   own audio plus six bench voices (run `make assets` first): the engine
   sample and bench/sfx1-6.wav (looping voices standing in for the effects
   P4b and P5 add), then, in a second push with the same app.json, a
   MUSIC_S excerpt of the race music (whole QOA frames: decoding costs the
   same per second whatever the length, and the race loops it).
2. Writes dev.json (autolap, `--laps`, `--rivals`, bench_sfx), resets
   `audiostat` and launches the app.
3. Sends NOTHING while the race runs: the device answers every dev command
   inside the app, which stalls it a few ms (enough to miss a deadline), so
   the tool sleeps through the expected race, then waits for the exit and
   reads `audiostat` (its window spans the whole race) and perf.json. No
   screenshot either: a transfer stalls Core 0 for seconds.
4. Launches one more short autolap run for a screenshot (colour check),
   then deletes dev.json so the next launch from the launcher is a race.

Gate: no logged frame misses its 33 333 us deadline or is shown late, the
frame interval's p95 is at most 34 000 us, the frame work's p95 is at most
24 000 us (headroom for P4b and P5), gfx3d drops no triangle, and the audio
refill ISR's worst case stays under 2 400 us of its ~2 900 us period. Prints
a verdict, writes reports/hw_lap-<time>.json and .png, and exits 1 if the
gate fails.

Other modes:
    --install            push the game with all its music, as a player gets
                         it (no dev.json), for playing
    --soak-stage MINUTES push and arm an autolap race of about MINUTES for a
                         battery run: unplug the USB cable, launch Nova Rail,
                         plug back in once it is back at the launcher, then
    --soak-read          print the battery level at the race's start and end
--clock KHZ sets system_clock_khz in the pushed app.json (default: the
repo's).

Nothing else may hold the serial port (stop the MCP server's log capture
first).
"""
import argparse
import json
import math
import os
import re
import shutil
import struct
import sys
import tempfile
import time
import wave
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP, APP_ID = "novarail", "net.picodeck.novarail"
APP_FILES = ("app.json", "main.lua", "src", "data")
MUSIC = Path("assets/music/track02.qoa")
ENGINE = Path("assets/sfx/engine.wav")
MUSIC_S = 20
SFX_HZ = (523, 659, 784, 1047, 1319, 1568)
LAP_S = 40  # a lap takes about 37 s

GATE_MISSED = 0
GATE_INTERVAL_P95_US = 34000
GATE_ISR_MAX_US = 2400
GATE_WORK_P95_US = 24000  # headroom P4b and P5 need at 300 MHz
# Output frames (44.1 kHz) the music stream may go without data before the
# tool warns: 0.1 s is audible. Reported, not gated (PicoDeck issue #34).
UNDERRUN_WARN_FRAMES = 4410


def stage(dest: Path, clock_khz=None):
    """The app's device files in dest; clock_khz replaces app.json's
    system_clock_khz."""
    dest.mkdir(parents=True, exist_ok=True)
    for name in APP_FILES:
        src = REPO / name
        if src.is_dir():
            shutil.copytree(src, dest / name, dirs_exist_ok=True,
                            ignore=shutil.ignore_patterns("__pycache__"))
        else:
            shutil.copy(src, dest / name)
    if clock_khz is not None:
        manifest = json.loads((dest / "app.json").read_text())
        manifest["system_clock_khz"] = clock_khz
        (dest / "app.json").write_text(json.dumps(manifest, indent=2) + "\n")


def sfx_wav(path: Path, hz: int, seconds: float = 0.5, rate: int = 22050):
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = int(seconds * rate)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(
            struct.pack("<h", int(8000 * math.sin(2 * math.pi * hz * i / rate)))
            for i in range(frames)))


def qoa_excerpt(data: bytes, seconds: float) -> bytes:
    """The first `seconds` of a QOA file (at least one frame) as a QOA file:
    whole frames from the front (each carries its own decoder state) and a
    file header whose sample count matches them."""
    if len(data) < 16 or data[:4] != b"qoaf":
        raise ValueError("not a QOA file")
    rate = int.from_bytes(data[9:12], "big")
    want = max(1, int(seconds * rate))
    out, pos, samples = bytearray(data[:8]), 8, 0
    while samples < want and pos + 8 <= len(data):
        fsamples, fsize = struct.unpack(">HH", data[pos + 4:pos + 8])
        if fsize < 8 or pos + fsize > len(data):
            break
        out += data[pos:pos + fsize]
        pos, samples = pos + fsize, samples + fsamples
    if samples == 0:
        raise ValueError("no whole QOA frame")
    out[4:8] = struct.pack(">I", samples)
    return bytes(out)


def missing_assets(audio: str) -> list:
    """The `make assets` outputs a push with this audio needs but the repo
    lacks."""
    need = [] if audio == "none" else [ENGINE, MUSIC]
    return [str(p) for p in need if not (REPO / p).exists()]


def push_game(t, clock_khz, audio: str):
    """Push Nova Rail. audio: "none"; "bench" (the engine sample, the six
    bench voices and a MUSIC_S music excerpt); or "full" (the engine sample
    and every music track whole, as a player gets them). The music goes one
    file per push, each with the first push's app.json (no second reboot)."""
    with tempfile.TemporaryDirectory() as tmp:
        app = Path(tmp) / "app" / APP
        stage(app, clock_khz)
        if audio != "none":
            (app / ENGINE).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / ENGINE, app / ENGINE)
        if audio == "bench":
            for i, hz in enumerate(SFX_HZ, 1):
                sfx_wav(app / "bench" / f"sfx{i}.wav", hz)
        t.push_app(app, APP)
        tracks = []
        if audio == "bench":
            tracks = [(MUSIC, qoa_excerpt((REPO / MUSIC).read_bytes(), MUSIC_S))]
        elif audio == "full":
            tracks = [(p.relative_to(REPO), p.read_bytes())
                      for p in sorted((REPO / MUSIC.parent).glob("*.qoa"))]
        for k, (rel, data) in enumerate(tracks):
            part = Path(tmp) / f"music{k}" / APP
            (part / rel).parent.mkdir(parents=True)
            shutil.copy(app / "app.json", part / "app.json")
            (part / rel).write_bytes(data)
            t.push_app(part, APP)


def audiostat(t, arg=""):
    """One `audiostat` reply as a dict of ints."""
    lines = t.command(("audiostat " + arg).strip(), timeout=3.0)
    for line in lines:
        if "[DEV] Audio:" in line:
            return {k: int(v) for k, v in
                    re.findall(r"(\w+)=(-?\d+)", line.split("Audio:", 1)[1])}
    raise RuntimeError(f"no Audio reply to 'audiostat {arg}': {lines}")


def measured_run(t, race_s: float, sleep=time.sleep, warn=print) -> dict:
    """Launch and wait out the race with no dev command in between; returns
    the `audiostat` whose window spans the whole race. If the app is still
    running after race_s, the polls that follow land in the race and stall
    it (warned: raise race_s)."""
    audiostat(t, "reset")
    t.launch_app(APP)
    sleep(race_s)
    if t.status().get("app") not in (None, "launcher"):
        warn(f"WARN: still racing after {race_s} s: exit polls now land in the race "
             "and stall it (raise --race-s)")
    t.wait_for_exit(timeout=180)
    return audiostat(t)


def verdict(perf: dict, audio) -> list:
    """Gate failures, as readable lines (empty = pass)."""
    fails = []
    if "logged" not in perf:
        return ["perf.json has no frame log (the race ended before the warm-up)"]
    if perf["missed"] > GATE_MISSED:
        fails.append(f"{perf['missed']} frames missed the 33 333 us deadline")
    if perf.get("late", 0) > GATE_MISSED:
        fails.append(f"{perf['late']} frames were shown late (interval > 34 000 us)")
    if perf["interval_us"]["p95"] > GATE_INTERVAL_P95_US:
        fails.append(f"frame interval p95 {perf['interval_us']['p95']} us > {GATE_INTERVAL_P95_US}")
    if audio is not None and audio.get("isr_max_us", 0) >= GATE_ISR_MAX_US:
        fails.append(f"audio ISR max {audio['isr_max_us']} us >= {GATE_ISR_MAX_US}")
    if perf["work_us"]["p95"] > GATE_WORK_P95_US:
        fails.append(f"frame work p95 {perf['work_us']['p95']} us > {GATE_WORK_P95_US}")
    overflow = perf.get("gfx3d", {}).get("overflow")
    if overflow is None:
        fails.append("perf.json has no gfx3d overflow count")
    elif overflow > 0:
        fails.append(f"gfx3d dropped {overflow} triangles (more than 4096 in a frame)")
    return fails


def race_failures(perf: dict, laps: int) -> list:
    """Gate failures for a run meant to finish `laps` laps, from the
    player's (idx 1) row in perf["results"]."""
    fails = []
    if perf.get("laps", 0) < laps:
        fails.append(f"the player completed {perf.get('laps', 0)} of {laps} laps")
    row = next((r for r in perf.get("results", []) if r.get("idx") == 1), None)
    if row is None:
        fails.append("no results row for the player (idx 1)")
    elif row.get("dnf"):
        fails.append("the player did not finish (dnf)")
    return fails


def audio_failures(perf: dict) -> list:
    """Gate failures for a run meant to play the game's audio and the bench
    voices, from what perf.json says was playing when the race ended."""
    a = perf.get("audio") or {}
    fails = []
    if not a.get("music"):
        fails.append("the music was not playing when the race ended")
    if not a.get("engine"):
        fails.append("the engine note was not playing when the race ended")
    if a.get("voices", 0) < len(SFX_HZ):
        fails.append(f"{a.get('voices', 0)} of {len(SFX_HZ)} bench voices played")
    return fails


def soak_summary(perf: dict, clock_khz) -> tuple:
    """A battery run's result: (one line, report dict). The battery level
    reads -1 only before the first reading."""
    bat = perf.get("battery") or {}
    start, finish = bat.get("start", -1), bat.get("finish", -1)
    interval = (perf.get("interval_us") or {}).get("avg") or 33333
    minutes = perf.get("frames", 0) * interval / 60e6
    report = {"clock_khz": clock_khz, "minutes": round(minutes, 1), "battery": bat,
              "laps": perf.get("laps")}
    if bat.get("usb_start") or bat.get("usb_finish"):
        return ("on USB power at the race's start or end: unplug the cable before "
                "launching, and plug it back in only after the race", report)
    if start < 0 or finish < 0 or minutes <= 0:
        return (f"no battery reading (start {start}, finish {finish}): was the cable "
                "unplugged for the whole race?", report)
    # isUSBPowered() reads a wireless-chip pin on this board and is not
    # reliable (PicoDeck docs); a level that never fell over a long run is
    # the tell instead.
    if minutes >= 10 and finish >= start:
        return (f"the battery level did not fall over {minutes:.0f} min: probably on "
                "USB power", report)
    per_hour = (start - finish) / minutes * 60
    report["percent_per_hour"] = round(per_hour, 1)
    return (f"{clock_khz} kHz: battery {start}% -> {finish}% over {minutes:.1f} min "
            f"({per_hour:.0f}%/h)", report)


def write_report(reports: Path, name: str, report: dict):
    reports.mkdir(exist_ok=True)
    (reports / f"{name}.json").write_text(json.dumps(report, indent=2))


def connect(args):
    sys.path.insert(0, str(Path(args.picodeck) / "tests" / "e2e"))
    from hw_target import HwTarget
    return HwTarget(args.device).connect()


def disarm(t):
    """A normal launch from the launcher must race, not autolap."""
    try:
        t.delete_file(f"/data/{APP_ID}/dev.json")
    except Exception as e:
        print(f"WARN: could not delete dev.json ({e}); the next launch will autolap")


def gate(args, audio: str):
    race_s = args.race_s if args.race_s is not None else LAP_S * args.laps + 25
    stamp = time.strftime("%Y%m%d-%H%M%S")
    reports = REPO / "reports"
    t = connect(args)
    perf, stats, shot = None, None, None
    try:
        t.reboot()
        push_game(t, args.clock, audio)
        dev = {"autolap": True, "laps": args.laps, "rivals": args.rivals,
               "bench_sfx": audio != "none", "mute": audio == "none"}
        t.write_file(f"/data/{APP_ID}/dev.json", json.dumps(dev).encode())
        t.delete_file(f"/data/{APP_ID}/perf.json")

        stats = measured_run(t, race_s=race_s)
        perf = json.loads(t.read_file(f"/data/{APP_ID}/perf.json"))
        # The measurement is saved before anything else can fail.
        write_report(reports, f"hw_lap-{stamp}", {"perf": perf, "audiostat": stats,
                                                  "laps": args.laps, "rivals": args.rivals,
                                                  "audio": audio, "clock_khz": args.clock})

        # A second, short run for the screenshot.
        t.write_file(f"/data/{APP_ID}/dev.json", json.dumps(
            {"autolap": True, "laps": 1, "rivals": args.rivals, "mute": audio == "none"}).encode())
        t.launch_app(APP)
        time.sleep(12)
        shot = t.screenshot()
        t.exit_app()
        t.wait_for_exit(timeout=30)
    finally:
        disarm(t)
        t.close()

    fails = verdict(perf, stats if audio != "none" else None)
    if audio != "none":
        fails += audio_failures(perf)
    fails += race_failures(perf, args.laps)
    write_report(reports, f"hw_lap-{stamp}", {"perf": perf, "audiostat": stats,
                                              "gate_failures": fails, "laps": args.laps,
                                              "rivals": args.rivals, "audio": audio,
                                              "clock_khz": args.clock})
    if shot:
        (reports / f"hw_lap-{stamp}.png").write_bytes(shot)

    w, i = perf.get("work_us", {}), perf.get("interval_us", {})
    print(f"laps {perf.get('laps')} lap_ms {perf.get('lap_ms')} frames logged {perf.get('logged')}"
          f" rivals {perf.get('rivals')} audio {audio}")
    print(f"work_us     min {w.get('min')} avg {w.get('avg')} p95 {w.get('p95')} max {w.get('max')}"
          f"  (gate p95 <= {GATE_WORK_P95_US})")
    print(f"interval_us min {i.get('min')} avg {i.get('avg')} p95 {i.get('p95')} max {i.get('max')}"
          f"  missed {perf.get('missed')} late {perf.get('late')}")
    print(f"sections {perf.get('sections')}")
    print(f"gfx3d {perf.get('gfx3d')}")
    print(f"audiostat {stats}")
    if audio != "none" and stats.get("stream_underruns", 0) > UNDERRUN_WARN_FRAMES:
        print(f"WARN: the music stream underran for {stats['stream_underruns']} output "
              "frames (PicoDeck issue #34)")
    print(f"report: reports/hw_lap-{stamp}.json")
    if fails:
        print("GATE FAIL: " + "; ".join(fails))
        sys.exit(1)
    print("GATE PASS")


def install(args, audio: str):
    t = connect(args)
    try:
        t.reboot()
        push_game(t, args.clock, audio)
    finally:
        disarm(t)
        t.close()
    print(f"Installed Nova Rail ({audio} audio): launch it from the launcher.")


def soak_stage(args, audio: str):
    laps = max(1, round(args.soak_stage * 60 / LAP_S))
    t = connect(args)
    try:
        t.reboot()
        push_game(t, args.clock, audio)
        t.write_file(f"/data/{APP_ID}/dev.json", json.dumps(
            {"autolap": True, "laps": laps, "rivals": args.rivals,
             "mute": audio == "none"}).encode())
        t.delete_file(f"/data/{APP_ID}/perf.json")
    finally:
        t.close()
    clock = args.clock or json.loads((REPO / "app.json").read_text()).get("system_clock_khz")
    print(f"Armed: a {laps}-lap race (about {laps * LAP_S / 60:.0f} min) at {clock} kHz.")
    print("Unplug the USB cable, wait 10 s (the level is read every 5 s), launch Nova")
    print("Rail from the launcher, and plug the cable back in once it is back at the")
    print("launcher. Then run --soak-read.")


def soak_read(args):
    t = connect(args)
    try:
        perf = json.loads(t.read_file(f"/data/{APP_ID}/perf.json"))
        clock = json.loads(t.read_file(f"/apps/{APP}/app.json")).get("system_clock_khz")
    finally:
        disarm(t)
        t.close()
    line, report = soak_summary(perf, clock)
    name = f"soak-{time.strftime('%Y%m%d-%H%M%S')}"
    write_report(REPO / "reports", name, report)
    print(line)
    print(f"report: reports/{name}.json")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--device", required=True, help="/dev/serial/by-id/... of the PicoCalc")
    ap.add_argument("--laps", type=int, default=2)
    ap.add_argument("--rivals", type=int, default=5)
    ap.add_argument("--race-s", type=float, default=None,
                    help=f"seconds to wait before polling for the exit (default {LAP_S} per lap + 25)")
    ap.add_argument("--no-audio", action="store_true", help="a silent race (dev.json mute)")
    ap.add_argument("--clock", type=int, default=None, help="system_clock_khz for the pushed app.json")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--install", action="store_true",
                      help="push the game with all its music, as a player gets it")
    mode.add_argument("--soak-stage", type=float, metavar="MINUTES",
                      help="push and arm a battery run of about MINUTES")
    mode.add_argument("--soak-read", action="store_true", help="read the battery run's result")
    ap.add_argument("--picodeck", default=os.environ.get(
        "PICODECK_ROOT", str(Path.home() / "Projects" / "PicoDeck" / "picodeck")))
    args = ap.parse_args()
    if args.install and args.no_audio:
        ap.error("--install cannot be combined with --no-audio: an install without "
                 "mute would play leftover audio")
    if args.soak_stage is not None and args.soak_stage <= 0:
        ap.error("--soak-stage needs a positive number of minutes")
    if args.soak_read:
        return soak_read(args)
    audio = "none" if args.no_audio else ("full" if args.install else "bench")
    missing = missing_assets(audio)
    if missing:
        raise SystemExit(f"hw_lap: no {', '.join(missing)}: run make assets (or pass --no-audio)")
    if args.install:
        return install(args, audio)
    if args.soak_stage is not None:
        return soak_stage(args, audio)
    return gate(args, audio)


if __name__ == "__main__":
    main()
