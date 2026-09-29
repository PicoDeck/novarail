"""tools/hw_lap.py without a device: staging, the pushes, the music excerpt,
the verdict and the battery summary."""
import json
import math
import shutil
import struct
import subprocess
import sys
import wave
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import hw_lap  # noqa: E402

PERF_OK = {"logged": 1100, "missed": 0, "late": 0,
           "interval_us": {"min": 33000, "avg": 33333, "p95": 33500, "max": 34100},
           "work_us": {"min": 9000, "avg": 14000, "p95": 18000, "max": 24000}}


def fake_qoa(frames, rate=44100, channels=2):
    """A QOA file of `frames` full frames with zero payloads (the excerpt
    reads only the headers)."""
    out = bytearray(b"qoaf" + struct.pack(">I", frames * 5120))
    fsize = 8 + 16 * channels + 8 * 256 * channels
    for _ in range(frames):
        out += bytes([channels]) + rate.to_bytes(3, "big") + struct.pack(">HH", 5120, fsize)
        out += bytes(fsize - 8)
    return bytes(out)


def qoa_samples(data):
    return struct.unpack(">I", data[4:8])[0]


class Push:
    def __init__(self, root: Path):
        self.files = sorted(str(p.relative_to(root)) for p in root.rglob("*") if p.is_file())
        self.manifest = (root / "app.json").read_text()
        self.qoa = {f: (root / f).read_bytes() for f in self.files if f.endswith(".qoa")}


class FakeTarget:
    def __init__(self):
        self.pushes = []

    def push_app(self, local_dir, name):
        assert name == hw_lap.APP
        self.pushes.append(Push(Path(local_dir)))


@pytest.fixture
def repo(tmp_path, monkeypatch):
    """A copy of the app's device files with stand-in `make assets` outputs:
    a 23 s track01, a short track02 and an engine sample."""
    root = tmp_path / "repo"
    hw_lap.stage(root)
    (root / "assets" / "music").mkdir(parents=True)
    (root / "assets" / "sfx").mkdir(parents=True)
    (root / "assets" / "music" / "track01.qoa").write_bytes(fake_qoa(200))
    (root / "assets" / "music" / "track02.qoa").write_bytes(fake_qoa(3))
    (root / "assets" / "sfx" / "engine.wav").write_bytes(b"RIFF engine")
    monkeypatch.setattr(hw_lap, "REPO", root)
    return root


def test_verdict_passes_a_locked_run():
    assert hw_lap.verdict(PERF_OK, {"isr_max_us": 1800}) == []


def test_verdict_fails_each_gate():
    perf = dict(PERF_OK, missed=3, interval_us=dict(PERF_OK["interval_us"], p95=40000))
    fails = hw_lap.verdict(perf, {"isr_max_us": 2400})
    assert len(fails) == 3, fails


def test_verdict_fails_late_frames():
    perf = dict(PERF_OK, late=2)
    assert any("late" in f for f in hw_lap.verdict(perf, None))


def test_verdict_without_a_frame_log():
    assert hw_lap.verdict({"laps": 1}, None)


def test_verdict_skips_audio_when_off():
    assert hw_lap.verdict(PERF_OK, None) == []


def test_stage_copies_only_device_files(tmp_path):
    hw_lap.stage(tmp_path / "app")
    names = sorted(p.name for p in (tmp_path / "app").iterdir())
    assert names == ["app.json", "data", "main.lua", "src"]


def test_stage_can_set_the_clock(tmp_path):
    hw_lap.stage(tmp_path / "app", clock_khz=200000)
    manifest = json.loads((tmp_path / "app" / "app.json").read_text())
    assert manifest["system_clock_khz"] == 200000 and manifest["id"] == hw_lap.APP_ID


def test_sfx_wav(tmp_path):
    p = tmp_path / "s.wav"
    hw_lap.sfx_wav(p, 523)
    with wave.open(str(p)) as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 22050)
        assert w.getnframes() == 11025


def test_qoa_excerpt_keeps_whole_frames():
    src = fake_qoa(20)
    out = hw_lap.qoa_excerpt(src, 1.0)          # 44 100 samples: 9 frames of 5120
    assert qoa_samples(out) == 9 * 5120
    assert out[8:] == src[8:8 + 9 * 4136], "the frames, untouched"
    assert hw_lap.qoa_excerpt(src, 0) == src[:4] + struct.pack(">I", 5120) + src[8:8 + 4136]
    assert hw_lap.qoa_excerpt(src, 999) == src, "longer than the file: all of it"


def test_qoa_excerpt_refuses_what_is_not_qoa():
    for junk in (b"", b"RIFF" + bytes(40), b"qoaf" + bytes(4) + b"\x02\x00\xac\x44" + bytes(4)):
        with pytest.raises(ValueError):
            hw_lap.qoa_excerpt(junk, 1.0)


@pytest.mark.skipif(not (shutil.which("qoaconv") and shutil.which("ffmpeg")),
                    reason="needs qoaconv and ffmpeg")
def test_qoa_excerpt_decodes(tmp_path):
    rate = 44100
    with wave.open(str(tmp_path / "s.wav"), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<hh", v, v) for v in (
            int(8000 * math.sin(2 * math.pi * 440 * i / rate)) for i in range(4 * rate))))
    subprocess.run(["qoaconv", str(tmp_path / "s.wav"), str(tmp_path / "s.qoa")],
                   check=True, capture_output=True)
    ex = hw_lap.qoa_excerpt((tmp_path / "s.qoa").read_bytes(), 1.5)
    (tmp_path / "ex.qoa").write_bytes(ex)
    pcm = subprocess.run(["ffmpeg", "-v", "error", "-i", str(tmp_path / "ex.qoa"),
                          "-f", "s16le", "-"], check=True, capture_output=True).stdout
    assert len(pcm) == qoa_samples(ex) * 2 * 2
    assert 1.5 * rate <= qoa_samples(ex) < 1.5 * rate + 5120


def test_bench_push_is_engine_and_voices_then_a_music_excerpt(repo):
    t = FakeTarget()
    hw_lap.push_game(t, None, "bench")
    assert len(t.pushes) == 2
    first, second = t.pushes
    assert "assets/sfx/engine.wav" in first.files
    assert [f for f in first.files if f.startswith("bench/")] == \
        [f"bench/sfx{i}.wav" for i in range(1, 7)]
    assert not any(f.endswith(".qoa") for f in first.files)
    assert second.files == ["app.json", "assets/music/track01.qoa"]
    samples = qoa_samples(second.qoa["assets/music/track01.qoa"])
    assert hw_lap.MUSIC_S * 44100 <= samples < hw_lap.MUSIC_S * 44100 + 5120
    assert second.manifest == first.manifest, "one app.json: no second reboot"


def test_full_push_sends_every_track_whole(repo):
    t = FakeTarget()
    hw_lap.push_game(t, None, "full")
    assert [p.files for p in t.pushes[1:]] == [["app.json", "assets/music/track01.qoa"],
                                             ["app.json", "assets/music/track02.qoa"]]
    assert t.pushes[1].qoa["assets/music/track01.qoa"] == \
        (repo / "assets" / "music" / "track01.qoa").read_bytes()
    assert "assets/sfx/engine.wav" in t.pushes[0].files
    assert not any(f.startswith("bench/") for f in t.pushes[0].files)


def test_silent_push_has_no_audio(repo):
    t = FakeTarget()
    hw_lap.push_game(t, None, "none")
    assert len(t.pushes) == 1
    assert not any(f.startswith(("assets/", "bench/")) for f in t.pushes[0].files)


def test_clock_goes_into_every_pushed_manifest(repo):
    t = FakeTarget()
    hw_lap.push_game(t, 200000, "bench")
    for p in t.pushes:
        assert json.loads(p.manifest)["system_clock_khz"] == 200000


def test_missing_assets_are_named(repo):
    (repo / "assets" / "sfx" / "engine.wav").unlink()
    assert hw_lap.missing_assets("bench") == ["assets/sfx/engine.wav"]
    assert hw_lap.missing_assets("none") == []


def test_soak_summary_gives_the_drain_per_hour():
    perf = {"frames": 30 * 60 * 12, "laps": 18, "battery": {"start": 90, "finish": 84}}
    line, report = hw_lap.soak_summary(perf, 300000)
    assert report["percent_per_hour"] == 30.0 and report["minutes"] == 12.0
    assert "90% -> 84%" in line


def test_soak_summary_without_a_battery_reading():
    line, report = hw_lap.soak_summary({"frames": 900, "battery": {"start": -1, "finish": -1}},
                                       300000)
    assert "no battery reading" in line and "percent_per_hour" not in report


def test_gate_sends_nothing_mid_race():
    # The race window is measured with no dev commands in it: audiostat is
    # reset before the launch and read after the exit.
    calls = []

    class Fake:
        def command(self, cmd, timeout=None):
            calls.append(("cmd", cmd))
            return ["[DEV] Audio: isr_max_us=1 mp3_underruns=0"]

        def launch_app(self, name):
            calls.append(("launch", name))

        def wait_for_exit(self, timeout):
            calls.append(("exit", None))

        def status(self):
            calls.append(("status", None))
            return {"app": "launcher"}

    stats = hw_lap.measured_run(Fake(), race_s=5, sleep=lambda s: calls.append(("sleep", s)))
    kinds = [c[0] for c in calls]
    launch, exit_ = kinds.index("launch"), kinds.index("exit")
    assert "cmd" not in kinds[launch:exit_], calls
    assert calls[0] == ("cmd", "audiostat reset") and calls[-1] == ("cmd", "audiostat")
    assert stats["isr_max_us"] == 1


def test_measured_run_warns_when_the_race_outlasts_the_wait():
    warnings = []

    class Fake:
        def command(self, cmd, timeout=None):
            return ["[DEV] Audio: isr_max_us=1"]

        def launch_app(self, name):
            pass

        def wait_for_exit(self, timeout):
            pass

        def status(self):
            return {"app": "Nova Rail"}

    hw_lap.measured_run(Fake(), race_s=1, sleep=lambda s: None, warn=warnings.append)
    assert warnings and "still racing" in warnings[0]
