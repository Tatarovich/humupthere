#!/usr/bin/env python3
"""Синтез звука уведомления «hum-hum» — низкий гул, как от самолёта над головой.

Два коротких импульса: низкая основа с обертоном, мягкие фронты, лёгкое приглушение.
Результат — Resources/hum.aiff (формат, который понимают уведомления macOS).
"""
import math
import struct
import subprocess
import sys
import wave

RATE = 44100
PULSE = 0.34          # длительность одного импульса, с
GAP = 0.15            # пауза между импульсами, с
BASE = 112.0          # основной тон, Гц
HARMONIC = 224.0      # обертон, Гц
LEAD = 0.012          # тишина в начале файла


def envelope(t: float, duration: float) -> float:
    attack = 0.07
    release = 0.20
    if t < attack:
        return t / attack
    if t > duration - release:
        return max(0.0, (duration - t) / release)
    return 1.0


def pulse(duration: float) -> list[float]:
    count = int(duration * RATE)
    samples = []
    for index in range(count):
        t = index / RATE
        value = (
            math.sin(2 * math.pi * BASE * t)
            + 0.34 * math.sin(2 * math.pi * HARMONIC * t)
        )
        samples.append(value * envelope(t, duration) * 0.55)
    return samples


def main() -> int:
    samples = [0.0] * int(LEAD * RATE)
    for index in range(2):
        samples.extend(pulse(PULSE))
        if index == 0:
            samples.extend([0.0] * int(GAP * RATE))

    # Мягкое приглушение: скользящее среднее убирает звонкость, оставляя «гул».
    window = 12
    smoothed = []
    for index in range(len(samples)):
        start = max(0, index - window)
        chunk = samples[start:index + 1]
        smoothed.append(sum(chunk) / len(chunk) * 1.35)

    peak = max(abs(value) for value in smoothed) or 1.0
    scaled = [value / peak * 0.72 for value in smoothed]

    raw = b"".join(struct.pack("<h", int(value * 32767)) for value in scaled)
    wav_path = "/tmp/hum_source.wav"
    with wave.open(wav_path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(raw)

    output = sys.argv[1] if len(sys.argv) > 1 else "Resources/hum.aiff"
    subprocess.run(
        ["afconvert", "-f", "AIFF", "-d", f"BEI16@{RATE}", wav_path, output],
        check=True,
    )
    print(f"Готово: {output} ({len(scaled) / RATE:.2f} с)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
