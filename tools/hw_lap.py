#!/usr/bin/env python3
"""The P3 hardware gate: autopilot laps at a locked 30 fps on a PicoCalc.

    python3 tools/hw_lap.py --device /dev/serial/by-id/usb-Raspberry_Pi_PicoDeck_Device_<serial>-if00

1. Reboots the device (a fresh heap), pushes Nova Rail plus generated bench
   audio (music and six looping voices; two pushes, each under ~250 KB,
   because push_app's unzip timeout assumes ~64 KB/s and the SD card writes
   ~12 KB/s).
2. Writes dev.json (autolap, `--laps`, bench_audio) and launches the app.
3. Resets `audiostat` once the race is under way and reads it back 40 s
   later, while the race still runs. No screenshot is taken during this
   run: a screenshot transfer stalls Core 0 for seconds.
4. Waits for the app to exit and reads perf.json.
5. Launches one more short autolap run for a screenshot (colour check),
   then deletes dev.json so the next launch from the launcher is a race.

Gate: no logged frame misses its 33 333 us deadline, the frame interval's
p95 is at most 34 000 us, and the audio refill ISR's worst case stays
under 2 400 us of its ~2 900 us period. Prints a verdict, writes
reports/hw_lap-<time>.json and .png, and exits 1 if the gate fails.

Nothing else may hold the serial port (stop the MCP server's log capture
first). Needs ffmpeg for the bench music.
"""
import argparse
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import wave
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP, APP_ID = "novarail", "net.picodeck.novarail"
APP_FILES = ("app.json", "main.lua", "src", "data")
SFX_HZ = (523, 659, 784, 1047, 1319, 1568)

GATE_MISSED = 0
GATE_INTERVAL_P95_US = 34000
GATE_ISR_MAX_US = 2400
WORK_P95_TARGET_US = 25000  # headroom P4 needs; reported, not gated


def stage(dest: Path):
    dest.mkdir(parents=True, exist_ok=True)
    for name in APP_FILES:
        src = REPO / name
        if src.is_dir():
            shutil.copytree(src, dest / name, dirs_exist_ok=True,
                            ignore=shutil.ignore_patterns("__pycache__"))
        else:
            shutil.copy(src, dest / name)


def music_mp3(path: Path, seconds: int = 12):
    """A loopable chord well above the speaker's weak low end."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("hw_lap: ffmpeg is needed for the bench music (or pass --no-audio)")
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([ffmpeg, "-v", "error", "-y",
                    "-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}",
                    "-f", "lavfi", "-i", f"sine=frequency=660:duration={seconds}",
                    "-filter_complex", "amix=inputs=2", "-ac", "2", "-ar", "44100",
                    "-c:a", "libmp3lame", "-b:a", "64k", str(path)], check=True)


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


def audiostat(t, arg=""):
    """One `audiostat` reply as a dict of ints."""
    lines = t.command(("audiostat " + arg).strip(), timeout=3.0)
    for line in lines:
        if "[DEV] Audio:" in line:
            return {k: int(v) for k, v in
                    re.findall(r"(\w+)=(-?\d+)", line.split("Audio:", 1)[1])}
    raise RuntimeError(f"no Audio reply to 'audiostat {arg}': {lines}")


def verdict(perf: dict, audio) -> list:
    """Gate failures, as readable lines (empty = pass)."""
    fails = []
    if "logged" not in perf:
        return ["perf.json has no frame log (the race ended before the warm-up)"]
    if perf["missed"] > GATE_MISSED:
        fails.append(f"{perf['missed']} frames missed the 33 333 us deadline")
    if perf["interval_us"]["p95"] > GATE_INTERVAL_P95_US:
        fails.append(f"frame interval p95 {perf['interval_us']['p95']} us > {GATE_INTERVAL_P95_US}")
    if audio is not None and audio.get("isr_max_us", 0) >= GATE_ISR_MAX_US:
        fails.append(f"audio ISR max {audio['isr_max_us']} us >= {GATE_ISR_MAX_US}")
    return fails


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--device", required=True, help="/dev/serial/by-id/... of the PicoCalc")
    ap.add_argument("--laps", type=int, default=2)
    ap.add_argument("--no-audio", action="store_true", help="skip the bench audio")
    ap.add_argument("--picodeck", default=os.environ.get(
        "PICODECK_ROOT", str(Path.home() / "Projects" / "PicoDeck" / "picodeck")))
    args = ap.parse_args()
    audio_on = not args.no_audio
    sys.path.insert(0, str(Path(args.picodeck) / "tests" / "e2e"))
    from hw_target import HwTarget

    t = HwTarget(args.device).connect()
    audio = None
    try:
        t.reboot()
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp) / APP
            stage(app)
            if audio_on:
                music_mp3(app / "bench" / "music.mp3")
            t.push_app(app, APP)
        if audio_on:
            # Same app.json (no extra reboot); unzip merges into /apps/novarail.
            with tempfile.TemporaryDirectory() as tmp:
                app = Path(tmp) / APP
                app.mkdir()
                shutil.copy(REPO / "app.json", app / "app.json")
                for i, hz in enumerate(SFX_HZ, 1):
                    sfx_wav(app / "bench" / f"sfx{i}.wav", hz)
                t.push_app(app, APP)
        dev = {"autolap": True, "laps": args.laps, "bench_audio": audio_on}
        t.write_file(f"/data/{APP_ID}/dev.json", json.dumps(dev).encode())
        t.delete_file(f"/data/{APP_ID}/perf.json")

        t.launch_app(APP)
        time.sleep(12)
        audiostat(t, "reset")
        time.sleep(40)
        stats = audiostat(t)
        audio = stats if audio_on else None
        t.wait_for_exit(timeout=60 * args.laps + 120)
        perf = json.loads(t.read_file(f"/data/{APP_ID}/perf.json"))

        # A second, short run for the screenshot.
        t.write_file(f"/data/{APP_ID}/dev.json",
                     json.dumps({"autolap": True, "laps": 1}).encode())
        t.launch_app(APP)
        time.sleep(10)
        shot = t.screenshot()
        t.exit_app()
        t.wait_for_exit(timeout=30)
        # A normal launch from the launcher must race, not autolap.
        t.delete_file(f"/data/{APP_ID}/dev.json")
    finally:
        t.close()

    fails = verdict(perf, audio)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    reports = REPO / "reports"
    reports.mkdir(exist_ok=True)
    report = {"perf": perf, "audiostat": stats, "gate_failures": fails,
              "laps": args.laps, "bench_audio": audio_on}
    (reports / f"hw_lap-{stamp}.json").write_text(json.dumps(report, indent=2))
    (reports / f"hw_lap-{stamp}.png").write_bytes(shot)

    w, i = perf.get("work_us", {}), perf.get("interval_us", {})
    print(f"laps {perf.get('laps')} lap_ms {perf.get('lap_ms')} frames logged {perf.get('logged')}")
    print(f"work_us     min {w.get('min')} avg {w.get('avg')} p95 {w.get('p95')} max {w.get('max')}"
          f"  (P4 headroom target p95 <= {WORK_P95_TARGET_US})")
    print(f"interval_us min {i.get('min')} avg {i.get('avg')} p95 {i.get('p95')} max {i.get('max')}"
          f"  missed {perf.get('missed')}")
    print(f"gfx3d {perf.get('gfx3d')}")
    print(f"audiostat {stats}")
    if audio_on and stats.get("mp3_underruns", 0) > 0:
        print(f"WARN: {stats['mp3_underruns']} MP3 underruns during the race")
    if w.get("p95", 0) > WORK_P95_TARGET_US:
        print(f"WARN: work p95 {w.get('p95')} us leaves less than P4's headroom")
    print(f"report: reports/hw_lap-{stamp}.json")
    if fails:
        print("GATE FAIL: " + "; ".join(fails))
        sys.exit(1)
    print("GATE PASS")


if __name__ == "__main__":
    main()
