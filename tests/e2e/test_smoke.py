"""Nova Rail smoke tests in the simulator: the race runs, steering steers,
the autopilot lap writes perf.json, and bad inputs degrade gracefully.
Frame times here are meaningless (the simulator is not the device); the
hardware gate is tools/hw_lap.py."""
import io
import json
import time

from PIL import Image

from conftest import APP


def wait_json(path, cond, timeout=20.0):
    """Poll a JSON file until cond(doc) holds; returns the doc."""
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = json.loads(path.read_text())
            if cond(last):
                return last
        except (FileNotFoundError, ValueError):
            pass
        time.sleep(0.1)
    raise TimeoutError(f"{path.name}: condition not met (last: {last})")


def lua_errors(sim):
    return [l["text"] for l in sim.get_log_lines() if l.get("src") == "err"]


def colours(png, box):
    img = Image.open(io.BytesIO(png)).convert("RGB").crop(box)
    return len(img.getcolors(maxcolors=320 * 320))


def test_race_runs_and_steers(novarail):
    sim, data = novarail(dev={"telemetry": True})
    sim.launch_app(APP)
    tel = data / "telemetry.json"
    before = wait_json(tel, lambda d: d["frame"] >= 60 and d["v"] > 10)
    sim.call("inject_button", {"button": "right", "action": "press"})
    time.sleep(0.8)
    sim.call("inject_button", {"button": "right", "action": "release"})
    after = wait_json(tel, lambda d: d["frame"] > before["frame"] + 30)
    assert after["u"] > before["u"] + 1.0, (before, after)
    png = sim.screenshot()
    assert colours(png, (0, 0, 320, 240)) >= 6, "the 3D viewport looks empty"
    assert colours(png, (0, 240, 320, 320)) >= 3, "the HUD looks empty"
    sim.keypress("esc")
    res = sim.wait_for_exit(timeout=15)
    assert res["result"] == "returned", res
    assert not lua_errors(sim)


def test_autolap_writes_perf_json(novarail):
    sim, data = novarail(dev={"autolap": True, "laps": 1})
    sim.launch_app(APP)
    res = sim.wait_for_exit(timeout=150)
    assert res["result"] == "returned", res
    assert not lua_errors(sim)
    perf = json.loads((data / "perf.json").read_text())
    assert perf["laps"] == 1
    assert len(perf["lap_ms"]) == 1 and 25000 < perf["lap_ms"][0] < 50000, perf["lap_ms"]
    assert perf["logged"] > 600 and isinstance(perf["missed"], int)
    for key in ("work_us", "interval_us"):
        assert set(perf[key]) == {"min", "avg", "p95", "max"}, perf[key]
    assert perf["gfx3d"]["drawn_avg"] > 50, perf["gfx3d"]
    assert perf["bench_audio"] is False


def test_bad_dev_json_is_ignored(novarail):
    sim, data = novarail(dev_text="{ not json")
    sim.launch_app(APP)
    time.sleep(3)
    assert sim.call("get_running_app").get("running"), "the race should be running"
    assert not (data / "perf.json").exists()
    sim.keypress("esc")
    res = sim.wait_for_exit(timeout=15)
    assert res["result"] == "returned", res
    assert not lua_errors(sim)


def test_zero_laps_means_one(novarail):
    sim, data = novarail(dev={"autolap": True, "laps": 0})
    sim.launch_app(APP)
    res = sim.wait_for_exit(timeout=150)
    assert res["result"] == "returned", res
    assert json.loads((data / "perf.json").read_text())["laps"] == 1


def test_old_firmware_gets_a_message(novarail):
    # Firmware before gfx3d: the app must explain, not raise.
    sim, _ = novarail(prelude="picocalc.gfx3d = nil")
    sim.launch_app(APP)
    time.sleep(2)
    png = sim.screenshot()
    assert colours(png, (0, 120, 320, 200)) >= 2, "no message on screen"
    sim.keypress("enter")
    res = sim.wait_for_exit(timeout=10)
    assert res["result"] == "returned", res
    assert not lua_errors(sim)
