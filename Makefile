LUA ?= lua
PICODECK_ROOT ?= $(HOME)/Projects/PicoDeck/picodeck
export PICODECK_ROOT

.PHONY: test test-host test-lua32 test-tools e2e hw-lap assets clean

# Host tests under the system Lua and under lua32 (the device's numbers).
test: test-host test-lua32 test-tools

test-host:
	$(LUA) tests/run.lua

build/lua32: tools/build_lua32.sh
	tools/build_lua32.sh

test-lua32: build/lua32
	build/lua32 tests/run.lua

# The tools' device-free parts (the audio pipeline's tests need ffmpeg and
# qoaconv, and skip without them).
test-tools:
	python3 -m pytest tests/test_hw_lap.py tests/test_prep_audio.py -q

# Simulator smoke tests (needs PicoDeck's simulator built: make simulator).
e2e:
	SDL_VIDEODRIVER=dummy python3 -m pytest tests/e2e -v -n 4

# The hardware gate: make hw-lap DEVICE=/dev/serial/by-id/usb-Raspberry_Pi_PicoDeck_Device_<serial>-if00
hw-lap:
	python3 tools/hw_lap.py --device $(DEVICE)

# The music (QOA) and the engine sample (WAV) the game plays, from
# assets/src (needs ffmpeg and qoaconv).
assets:
	tools/prep_audio.sh

clean:
	rm -rf build
