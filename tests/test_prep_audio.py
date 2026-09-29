"""tools/prep_audio.sh on short generated sources: the files the game plays,
in the formats it expects."""
import json
import shutil
import struct
import subprocess
import wave
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
pytestmark = pytest.mark.skipif(not (shutil.which("ffmpeg") and shutil.which("qoaconv")),
                                reason="needs ffmpeg and qoaconv")


def tree(tmp_path, engine_s=1.0):
    """A copy of the script beside generated sources: a 3 s stereo MP3 and
    an engine FLAC of engine_s seconds."""
    root = tmp_path / "nr"
    (root / "tools").mkdir(parents=True)
    shutil.copy(REPO / "tools" / "prep_audio.sh", root / "tools")
    src = root / "assets" / "src"
    src.mkdir(parents=True)
    for name, seconds, channels in (("track01.mp3", 3, 2), ("engine.flac", engine_s, 1)):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                        "-i", f"sine=frequency=440:duration={seconds}",
                        "-ac", str(channels), str(src / name)], check=True)
    return root


def run(root):
    return subprocess.run([str(root / "tools" / "prep_audio.sh")],
                          capture_output=True, text=True)


def test_makes_stereo_qoa_music_and_a_mono_engine_sample(tmp_path):
    root = tree(tmp_path)
    r = run(root)
    assert r.returncode == 0, r.stderr
    q = (root / "assets" / "music" / "track01.qoa").read_bytes()
    assert q[:4] == b"qoaf"
    samples = struct.unpack(">I", q[4:8])[0]
    assert (q[8], int.from_bytes(q[9:12], "big")) == (2, 44100), "stereo, 44.1 kHz"
    assert 2.9 * 44100 < samples < 3.2 * 44100, samples
    with wave.open(str(root / "assets" / "sfx" / "engine.wav")) as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 22050)
    assert not (root / "build" / "music.wav").exists(), "the intermediate WAV is gone"


def test_refuses_an_engine_sample_over_64_kb(tmp_path):
    r = run(tree(tmp_path, engine_s=2.0))  # 2 s of 16-bit 22.05 kHz mono: 88 KB
    assert r.returncode == 1
    assert "64 KB" in r.stderr


def embedded_prompt(path):
    """The text prompt in a file's embedded ComfyUI workflow metadata."""
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format_tags=prompt",
                          "-of", "json", str(path)], capture_output=True, text=True,
                         check=True).stdout
    graph = json.loads(json.loads(out)["format"]["tags"]["prompt"])
    texts = [n["inputs"][k] for n in graph.values() for k in ("prompt", "text")
             if isinstance(n.get("inputs", {}).get(k), str)]
    assert len(texts) == 1, texts
    return texts[0]


def test_prompts_md_quotes_each_source_files_own_prompt():
    # The files carry the prompt that made them; the doc must quote it.
    doc = (REPO / "tools" / "prompts.md").read_text()
    for name in ("track01.mp3", "track02.mp3", "engine.flac"):
        assert embedded_prompt(REPO / "assets" / "src" / name) in doc, name
