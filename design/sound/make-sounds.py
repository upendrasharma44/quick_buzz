#!/usr/bin/env python3
"""Generates QuickBuzz's sound effects as 16-bit mono WAV files (Python standard library only).

Usage: python3 design/sound/make-sounds.py
Writes App/Resources/Sounds/*.wav. Edit the parameters here and re-run; never hand-edit the WAVs.
"""
import math
import struct
import wave
from pathlib import Path

RATE = 44_100
OUT = Path(__file__).resolve().parents[2] / "App" / "Resources" / "Sounds"


def buzzer(duration=0.42, base=146.8, detune=1.012, harmonics=31, volume=0.55):
    """Game-show buzzer: two slightly detuned band-limited square waves with a fast attack.

    Odd harmonics only (square wave), stopping below Nyquist so nothing aliases.
    """
    n = int(RATE * duration)
    attack, release = int(RATE * 0.006), int(RATE * 0.07)
    samples = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for f in (base, base * detune):
            for k in range(1, harmonics + 1, 2):
                if f * k >= RATE / 2:
                    break
                s += math.sin(2 * math.pi * f * k * t) / k
        envelope = min(1.0, i / attack) * min(1.0, (n - i) / release)
        samples.append(s * envelope)
    peak = max(abs(x) for x in samples)
    return [x / peak * volume for x in samples]


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in samples))
    print(f"wrote {path.relative_to(OUT.parents[2])} ({len(samples) / RATE:.2f} s)")


if __name__ == "__main__":
    write("buzz.wav", buzzer())
