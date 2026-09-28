"""Nova Rail in the PicoDeck simulator.

Uses PicoDeck's E2E harness (tests/e2e/picodeck_simulator.py) from
$PICODECK_ROOT (default ~/Projects/PicoDeck/picodeck); the simulator binary
is $PICODECK_SIM_BINARY or that checkout's build_sim/picodeck_simulator.
"""
import json
import os
import shutil
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
PICODECK = Path(os.environ.get("PICODECK_ROOT",
                               Path.home() / "Projects" / "PicoDeck" / "picodeck"))
sys.path.insert(0, str(PICODECK / "tests" / "e2e"))

from picodeck_simulator import PicodeckSimulator  # noqa: E402

APP, APP_ID = "novarail", "net.picodeck.novarail"
APP_FILES = ("app.json", "main.lua", "src", "data")


def stage_app(dest: Path, prelude: str = ""):
    """Copy the app's device files to dest; `prelude` goes before main.lua."""
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


@pytest.fixture
def novarail(tmp_path):
    """start(dev=None, dev_text=None, prelude="") -> (sim, data_dir).

    Boots a simulator whose SD card holds only Nova Rail. dev (a dict) or
    dev_text (raw text) becomes /data/<APP_ID>/dev.json."""
    sims = []

    def start(dev=None, dev_text=None, prelude=""):
        sd = tmp_path / f"sd{len(sims)}"
        stage_app(sd / "apps" / APP, prelude)
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
