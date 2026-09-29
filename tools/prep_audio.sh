#!/usr/bin/env bash
# Converts the audio sources in assets/src into what the game plays:
#   assets/music/<name>.qoa  each assets/src/track*.mp3 as 44.1 kHz stereo QOA,
#                            loudness-normalised. The game streams it with a
#                            fileplayer: QOA is a fifth of the size of 16-bit
#                            PCM and the cheapest music on PicoDeck (measured
#                            in this race: +4.6% frame time at 300 MHz, WAV
#                            +11%, MP3 spikes to 45 ms).
#   assets/sfx/engine.wav    assets/src/engine.flac as a 16-bit 22.05 kHz mono
#                            sample (under the 64 KB sample limit).
# Needs ffmpeg (loudness, format) and qoaconv (https://github.com/phoboslab/qoa:
# ffmpeg decodes QOA but has no encoder).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
src="$here/assets/src"
command -v ffmpeg >/dev/null || { echo "prep_audio: ffmpeg is needed" >&2; exit 1; }
command -v qoaconv >/dev/null || { echo "prep_audio: qoaconv is needed (https://github.com/phoboslab/qoa)" >&2; exit 1; }
mkdir -p "$here/build" "$here/assets/music" "$here/assets/sfx"
wav="$here/build/music.wav"
for f in "$src"/track*.mp3; do
    name=$(basename "$f" .mp3)
    ffmpeg -v error -y -i "$f" -af loudnorm=I=-16:TP=-1.5:LRA=11 \
        -ac 2 -ar 44100 -c:a pcm_s16le "$wav"
    qoaconv "$wav" "$here/assets/music/$name.qoa"
done
rm -f "$wav"
ffmpeg -v error -y -i "$src/engine.flac" -ac 1 -ar 22050 -c:a pcm_s16le "$here/assets/sfx/engine.wav"
size=$(stat -c %s "$here/assets/sfx/engine.wav")
if [ "$size" -gt 65536 ]; then
    echo "prep_audio: engine.wav is $size bytes; samples keep only the first 64 KB" >&2
    exit 1
fi
echo "prep_audio: $(ls "$here/assets/music"/*.qoa | wc -l) music tracks, engine.wav ($size bytes)"
