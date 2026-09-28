"""tools/hw_lap.py without a device: staging, bench audio and the verdict."""
import shutil
import sys
import wave
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import hw_lap  # noqa: E402

PERF_OK = {"logged": 1100, "missed": 0,
           "interval_us": {"min": 33000, "avg": 33333, "p95": 33500, "max": 34100},
           "work_us": {"min": 9000, "avg": 14000, "p95": 18000, "max": 24000}}


def test_verdict_passes_a_locked_run():
    assert hw_lap.verdict(PERF_OK, {"isr_max_us": 1800}) == []


def test_verdict_fails_each_gate():
    perf = dict(PERF_OK, missed=3, interval_us=dict(PERF_OK["interval_us"], p95=40000))
    fails = hw_lap.verdict(perf, {"isr_max_us": 2400})
    assert len(fails) == 3, fails


def test_verdict_without_a_frame_log():
    assert hw_lap.verdict({"laps": 1}, None)


def test_verdict_skips_audio_when_off():
    assert hw_lap.verdict(PERF_OK, None) == []


def test_stage_copies_only_device_files(tmp_path):
    hw_lap.stage(tmp_path / "app")
    names = sorted(p.name for p in (tmp_path / "app").iterdir())
    assert names == ["app.json", "data", "main.lua", "src"]


def test_sfx_wav(tmp_path):
    p = tmp_path / "s.wav"
    hw_lap.sfx_wav(p, 523)
    with wave.open(str(p)) as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 22050)
        assert w.getnframes() == 11025


@pytest.mark.skipif(not shutil.which("ffmpeg"), reason="needs ffmpeg")
def test_bench_pushes_stay_small(tmp_path):
    music = tmp_path / "m.wav"
    hw_lap.music_wav(music)
    assert music.stat().st_size < 250_000
    for i, hz in enumerate(hw_lap.SFX_HZ, 1):
        hw_lap.sfx_wav(tmp_path / f"sfx{i}.wav", hz)
    voices = sum((tmp_path / f"sfx{i}.wav").stat().st_size for i in range(1, 7))
    assert voices < 250_000


def test_music_wav_is_small_mono_16bit(tmp_path):
    if not shutil.which("ffmpeg"):
        pytest.skip("needs ffmpeg")
    p = tmp_path / "music.wav"
    hw_lap.music_wav(p)
    with wave.open(str(p)) as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 22050)
    assert p.stat().st_size < 250_000


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

    stats = hw_lap.measured_run(Fake(), race_s=5, sleep=lambda s: calls.append(("sleep", s)))
    kinds = [c[0] for c in calls]
    launch, exit_ = kinds.index("launch"), kinds.index("exit")
    assert "cmd" not in kinds[launch:exit_], calls
    assert calls[0] == ("cmd", "audiostat reset") and calls[-1] == ("cmd", "audiostat")
    assert stats["isr_max_us"] == 1
