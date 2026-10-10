"""Nova Rail smoke tests in the simulator: the race runs (countdown, rivals,
results), steering steers, music and the engine note play, the autolap race
writes perf.json, and bad inputs degrade gracefully.
Frame times here are meaningless (the simulator is not the device); the
hardware gate is tools/hw_lap.py."""
import io
import json
import time

import pytest
from PIL import Image

from conftest import APP, qoa_bytes, wav_bytes


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


def hold(sim, key, down):
    """Hold or release a key: F4 is the gamepad's A (accelerate) and F5 its
    B (brake) by default."""
    sim.call("inject_button", {"button": key, "action": "press" if down else "release"})


def test_race_runs_and_steers(novarail):
    sim, data = novarail(dev={"telemetry": True})
    sim.launch_app(APP)
    tel = data / "telemetry.json"
    hold(sim, "f4", True)
    before = wait_json(tel, lambda d: d["frame"] >= 60 and d["v"] > 10)
    hold(sim, "right", True)
    time.sleep(0.8)
    hold(sim, "right", False)
    after = wait_json(tel, lambda d: d["frame"] > before["frame"] + 30)
    hold(sim, "f4", False)
    assert after["u"] > before["u"] + 1.0, (before, after)
    png = sim.screenshot()
    assert colours(png, (0, 0, 320, 240)) >= 6, "the 3D viewport looks empty"
    assert colours(png, (0, 240, 320, 320)) >= 3, "the HUD looks empty"
    sim.keypress("esc")
    res = sim.wait_for_exit(timeout=15)
    assert res["result"] == "returned", res
    assert not lua_errors(sim)


def test_no_thrust_without_a_and_b_brakes(novarail):
    sim, data = novarail(dev={"telemetry": True})
    sim.launch_app(APP)
    tel = data / "telemetry.json"
    idle = wait_json(tel, lambda d: d["frame"] >= 150)  # well past the countdown
    assert idle["v"] < 1, idle                          # thrust is not automatic
    hold(sim, "f4", True)
    fast = wait_json(tel, lambda d: d["v"] > 30)
    hold(sim, "f5", True)                               # B brakes, even with A held
    slow = wait_json(tel, lambda d: d["frame"] > fast["frame"] + 30)
    hold(sim, "f5", False)
    hold(sim, "f4", False)
    assert slow["v"] < fast["v"] - 10, (fast, slow)
    sim.keypress("esc")
    assert sim.wait_for_exit(timeout=15)["result"] == "returned"
    assert not lua_errors(sim)


def audio_assets(music_s=2.0):
    """Short stand-ins for the game's audio (the real files come from make
    assets): stereo 44.1 kHz QOA music, a WAV engine sample."""
    return {"assets/music/track01.qoa": qoa_bytes(music_s, 220),
            "assets/music/track02.qoa": qoa_bytes(music_s, 330),
            "assets/sfx/engine.wav": wav_bytes(0.5, 110)}


def test_race_plays_music_and_engine(novarail):
    # The track is 2 s long: still playing 5 s into the race means it loops.
    sim, data = novarail(dev={"telemetry": True}, assets=audio_assets())
    sim.launch_app(APP)
    tel = wait_json(data / "telemetry.json", lambda d: d["frame"] >= 150)
    assert tel["music"] is True and tel["engine"] is True, tel
    state = sim.call("get_audio_state")
    assert state["stream_active"] and state["sound_players_active"] >= 1, state
    sim.keypress("esc")
    assert sim.wait_for_exit(timeout=15)["result"] == "returned"
    state = sim.call("get_audio_state")
    assert not state["stream_active"] and state["sound_players_active"] == 0, state
    assert not lua_errors(sim)


@pytest.mark.parametrize("junk", [b"", b"RIFF\x00\x00", b"not a wav file at all" * 20])
def test_bad_audio_files_mean_silence(novarail, junk):
    assets = {k: junk for k in audio_assets()}
    sim, data = novarail(dev={"telemetry": True}, assets=assets)
    sim.launch_app(APP)
    tel = wait_json(data / "telemetry.json", lambda d: d["frame"] >= 60)
    assert tel["music"] is False and tel["engine"] is False, tel
    sim.keypress("esc")
    assert sim.wait_for_exit(timeout=15)["result"] == "returned"
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
    assert perf["gfx3d"]["overflow"] == 0, perf["gfx3d"]
    assert perf["bench_sfx"] is False
    bat = perf["battery"]
    assert set(bat) == {"start", "finish", "usb_start", "usb_finish"}, bat
    assert isinstance(bat["start"], int) and isinstance(bat["finish"], int), bat
    assert isinstance(bat["usb_start"], bool) and isinstance(bat["usb_finish"], bool), bat
    assert perf["audio"] == {"music": False, "engine": False, "voices": 0}, perf["audio"]
    assert isinstance(perf["late"], int)
    assert set(perf["sections"]) == {"input", "sim", "camera", "draw", "hud"}
    assert perf["rivals"] == 5
    assert [r["pos"] for r in perf["results"]] == [1, 2, 3, 4, 5, 6]
    assert sorted(r["idx"] for r in perf["results"]) == [1, 2, 3, 4, 5, 6]


def test_countdown_holds_the_grid(novarail):
    sim, data = novarail(dev={"telemetry": True})
    sim.launch_app(APP)
    hold(sim, "f4", True)                   # accelerate held through the countdown
    early = wait_json(data / "telemetry.json", lambda d: d["frame"] >= 30)
    assert early["phase"] == "countdown" and early["v"] == 0, early
    later = wait_json(data / "telemetry.json", lambda d: d["frame"] >= 150)
    hold(sim, "f4", False)
    assert later["phase"] == "racing" and later["v"] > 20, later
    sim.keypress("esc")
    assert sim.wait_for_exit(timeout=15)["result"] == "returned"


def test_results_page_then_race_again_or_quit(novarail):
    # The AI drives the player through a one-lap solo race (~45 s); `stay` keeps the
    # results page up for keys.
    sim, data = novarail(dev={"telemetry": True, "autolap": True, "stay": True, "rivals": 0,
                              "laps": 1}, assets=audio_assets())
    sim.launch_app(APP)
    tel = data / "telemetry.json"
    assert wait_json(tel, lambda d: d["frame"] >= 15)["track"] == 1
    hold(sim, "f4", True)               # A held to the end (the AI drives regardless)
    # Alone on track, the player's finish ends the race at once: the results
    # page (a few flat colours, not the 3D view) replaces the race.
    deadline = time.monotonic() + 90
    while colours(sim.screenshot(), (0, 0, 320, 240)) > 8:
        assert time.monotonic() < deadline, "no results page"
        time.sleep(0.5)
    first = json.loads(tel.read_text())["frame"]
    time.sleep(2)                       # A still held: its key repeat must not race again
    assert colours(sim.screenshot(), (0, 0, 320, 240)) <= 8, "raced again on a held A"
    hold(sim, "f4", False)
    time.sleep(0.3)
    sim.keypress("f4")                  # a fresh A races again: a new countdown, the next track
    again = wait_json(tel, lambda d: d["frame"] < first and d["phase"] == "countdown", timeout=20)
    assert again["track"] == 2 and again["music"] is True, again
    sim.keypress("esc")
    assert sim.wait_for_exit(timeout=15)["result"] == "returned"
    assert not lua_errors(sim)


@pytest.mark.parametrize("text", ["{ not json", "[1, 2]", '"x"'])
def test_bad_dev_json_is_ignored(novarail, text):
    sim, data = novarail(dev_text=text)
    sim.launch_app(APP)
    time.sleep(3)
    assert sim.call("get_running_app").get("running"), "the race should be running"
    assert not (data / "perf.json").exists()
    sim.keypress("esc")
    res = sim.wait_for_exit(timeout=15)
    assert res["result"] == "returned", res
    assert not lua_errors(sim)


@pytest.mark.parametrize("laps", [0, -3, "x"])
def test_bad_laps_mean_one(novarail, laps):
    sim, data = novarail(dev={"autolap": True, "laps": laps, "rivals": 0})
    sim.launch_app(APP)
    res = sim.wait_for_exit(timeout=150)
    assert res["result"] == "returned", res
    assert json.loads((data / "perf.json").read_text())["laps"] == 1


@pytest.mark.parametrize("prelude", ["picocalc.gfx3d = nil", "picocalc.gfx3d.drawList = nil",
                                     "require = nil", "picocalc.sys.getTimeUs = nil",
                                     "picocalc.gamepad = nil"])
def test_old_firmware_gets_a_message(novarail, prelude):
    # Firmware missing what the game needs: the app must explain, not raise.
    sim, _ = novarail(prelude=prelude)
    sim.launch_app(APP)
    # The launch applies the app's 300 MHz clock first (a few seconds in the
    # simulator); the message page is white text on black. A blank black
    # frame on the way (launcher gone, text not yet drawn) is not the page.
    deadline = time.monotonic() + 10
    while True:
        png = sim.screenshot()
        if (colours(png, (0, 0, 320, 320)) <= 3
                and colours(png, (0, 120, 320, 200)) >= 2):
            break
        assert time.monotonic() < deadline, "no message page"
        time.sleep(0.25)
    sim.keypress("enter")
    res = sim.wait_for_exit(timeout=10)
    assert res["result"] == "returned", res
    assert not lua_errors(sim)


def test_esc_in_the_countdown_quits_cleanly(novarail):
    sim, data = novarail(dev={"telemetry": True}, assets=audio_assets())
    sim.launch_app(APP)
    tel = wait_json(data / "telemetry.json", lambda d: d["frame"] >= 30)
    assert tel["phase"] == "countdown", tel
    sim.keypress("esc")
    assert sim.wait_for_exit(timeout=15)["result"] == "returned"
    state = sim.call("get_audio_state")
    assert not state["stream_active"] and state["sound_players_active"] == 0, state
    assert not lua_errors(sim)


def test_no_audio_files_means_silence(novarail):
    # A checkout without `make assets`: the race runs, silent.
    sim, data = novarail(dev={"telemetry": True})
    sim.launch_app(APP)
    tel = wait_json(data / "telemetry.json", lambda d: d["frame"] >= 60)
    assert tel["music"] is False and tel["engine"] is False, tel
    sim.keypress("esc")
    assert sim.wait_for_exit(timeout=15)["result"] == "returned"
    assert not lua_errors(sim)


@pytest.mark.parametrize("rivals,want", [(-1, 0), (9, 5), ("x", 5)])
def test_bad_rivals_are_clamped(novarail, rivals, want):
    sim, data = novarail(dev={"autolap": True, "laps": 1, "rivals": rivals})
    sim.launch_app(APP)
    res = sim.wait_for_exit(timeout=150)
    assert res["result"] == "returned", res
    assert not lua_errors(sim)
    perf = json.loads((data / "perf.json").read_text())
    assert perf["rivals"] == want and len(perf["results"]) == want + 1, perf


def test_mute_means_no_game_audio(novarail):
    sim, data = novarail(dev={"telemetry": True, "mute": True}, assets=audio_assets())
    sim.launch_app(APP)
    tel = wait_json(data / "telemetry.json", lambda d: d["frame"] >= 60)
    assert tel["music"] is False and tel["engine"] is False, tel
    sim.keypress("esc")
    assert sim.wait_for_exit(timeout=15)["result"] == "returned"
    assert not lua_errors(sim)


def test_bench_sfx_play_over_the_music(novarail):
    assets = dict(audio_assets())
    for i in range(1, 7):
        assets[f"bench/sfx{i}.wav"] = wav_bytes(0.5, 400 + 100 * i)
    sim, data = novarail(dev={"telemetry": True, "bench_sfx": True}, assets=assets)
    sim.launch_app(APP)
    tel = wait_json(data / "telemetry.json", lambda d: d["frame"] >= 150)
    assert tel["music"] is True and tel["engine"] is True, tel
    state = sim.call("get_audio_state")
    assert state["stream_active"] and state["sound_players_active"] >= 7, state
    sim.keypress("esc")
    assert sim.wait_for_exit(timeout=15)["result"] == "returned"
    state = sim.call("get_audio_state")
    assert state["sound_players_active"] == 0, state
    assert not lua_errors(sim)


def test_autolap_records_what_audio_played(novarail):
    assets = dict(audio_assets())
    for i in range(1, 7):
        assets[f"bench/sfx{i}.wav"] = wav_bytes(0.5, 400 + 100 * i)
    sim, data = novarail(dev={"autolap": True, "laps": 1, "rivals": 0, "bench_sfx": True},
                         assets=assets)
    sim.launch_app(APP)
    res = sim.wait_for_exit(timeout=150)
    assert res["result"] == "returned", res
    assert not lua_errors(sim)
    perf = json.loads((data / "perf.json").read_text())
    assert perf["audio"] == {"music": True, "engine": True, "voices": 6}, perf["audio"]
