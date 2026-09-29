"""Nova Rail in the PicoDeck simulator.

Uses PicoDeck's E2E harness (tests/e2e/picodeck_simulator.py) from
$PICODECK_ROOT (default ~/Projects/PicoDeck/picodeck); the simulator binary
is $PICODECK_SIM_BINARY or that checkout's build_sim/picodeck_simulator.
"""
import json
import math
import os
import shutil
import struct
import sys
import wave
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
PICODECK = Path(os.environ.get("PICODECK_ROOT",
                               Path.home() / "Projects" / "PicoDeck" / "picodeck"))
sys.path.insert(0, str(PICODECK / "tests" / "e2e"))

from picodeck_simulator import PicodeckSimulator  # noqa: E402
from helpers import write_qoa  # noqa: E402  (PicoDeck's spec-valid QOA writer)

APP, APP_ID = "novarail", "net.picodeck.novarail"
APP_FILES = ("app.json", "main.lua", "src", "data")


def wav_bytes(seconds: float, freq: float = 220.0, rate: int = 22050) -> bytes:
    """A 16-bit mono sine WAV: a stand-in for the game's audio assets."""
    import io
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        n = int(seconds * rate)
        w.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * freq * i / rate)))
                               for i in range(n)))
    return buf.getvalue()


def qoa_bytes(seconds: float, hz: int, rate: int = 44100, channels: int = 2) -> bytes:
    """A QOA sine: a stand-in for the game's music (the real tracks come
    from make assets)."""
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "t.qoa"
        write_qoa(path, seconds=seconds, rate=rate, channels=channels, hz=hz)
        return path.read_bytes()


def stage_app(dest: Path, prelude: str = "", assets=None):
    """Copy the app's device files to dest; `prelude` goes before main.lua;
    `assets` maps paths under the app (e.g. "assets/sfx/engine.wav") to bytes."""
    dest.mkdir(parents=True, exist_ok=True)
    for name in APP_FILES:
        src = REPO / name
        if src.is_dir():
            shutil.copytree(src, dest / name, dirs_exist_ok=True)
        else:
            shutil.copy(src, dest / name)
    if prelude:
        main = dest / "main.lua"
        main.write_text(prelude + "\n" + main.read_text())
    for rel, data in (assets or {}).items():
        (dest / rel).parent.mkdir(parents=True, exist_ok=True)
        (dest / rel).write_bytes(data)


@pytest.fixture
def novarail(tmp_path):
    """start(dev=None, dev_text=None, prelude="", assets=None) -> (sim, data_dir).

    Boots a simulator whose SD card holds only Nova Rail (without its audio
    unless `assets` stages some; see stage_app). dev (a dict) or dev_text
    (raw text) becomes /data/<APP_ID>/dev.json."""
    sims = []

    def start(dev=None, dev_text=None, prelude="", assets=None):
        sd = tmp_path / f"sd{len(sims)}"
        stage_app(sd / "apps" / APP, prelude, assets)
        data = sd / "data" / APP_ID
        data.mkdir(parents=True, exist_ok=True)
        if dev is not None:
            (data / "dev.json").write_text(json.dumps(dev))
        elif dev_text is not None:
            (data / "dev.json").write_text(dev_text)
        binary = os.environ.get("PICODECK_SIM_BINARY")
        sim = PicodeckSimulator(binary_path=binary, sd_card_path=str(sd), test_mode=True)
        sim.start()
        sims.append(sim)
        return sim, data

    yield start
    for sim in sims:
        sim.stop()
