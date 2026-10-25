#!/usr/bin/env python3
"""Готовит звук оповещения из исходной записи.

Что делает: декодирует источник, берёт нужный отрезок, сводит в моно, гасит
плавно в конце и нормирует на заданный пик. Для уведомлений macOS нужен
линейный PCM в AIFF/WAV/CAF, поэтому на выходе всегда AIFF.

Пример:
    python3 tools/make_alert_sound.py \
        --input signal-before-the-announcement-at-the-airport-version-2.mp3 \
        --output Resources/airport.aiff \
        --start 0.10 --duration 1.40 --peak 0.10
"""
import argparse
import struct
import subprocess
import sys
import tempfile
import wave


def decode_to_wav(source: str, target: str) -> None:
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", "LEI16@44100", source, target],
        check=True,
        capture_output=True,
    )


def read_mono(path: str) -> tuple[list[float], int]:
    with wave.open(path, "rb") as handle:
        rate = handle.getframerate()
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        frames = handle.getnframes()
        raw = handle.readframes(frames)

    if width != 2:
        raise SystemExit(f"ожидался 16-битный звук, получено {width * 8} бит")

    samples = struct.unpack(f"<{len(raw) // 2}h", raw)
    if channels > 1:
        # Сводим в моно: усредняем каналы.
        mono = [
            sum(samples[index + offset] for offset in range(channels)) / channels
            for index in range(0, len(samples) - channels + 1, channels)
        ]
    else:
        mono = [float(value) for value in samples]
    return mono, rate


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--start", type=float, default=0.0, help="с какого момента брать, с")
    parser.add_argument("--duration", type=float, default=None, help="сколько брать, с")
    parser.add_argument("--peak", type=float, default=0.10, help="целевой пик, доля от максимума")
    parser.add_argument("--fade-in", type=float, default=0.01, help="плавное появление, с")
    parser.add_argument("--fade-out", type=float, default=0.28, help="плавное затухание, с")
    arguments = parser.parse_args()

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=True) as temporary:
        decode_to_wav(arguments.input, temporary.name)
        mono, rate = read_mono(temporary.name)

    begin = int(arguments.start * rate)
    end = len(mono) if arguments.duration is None else begin + int(arguments.duration * rate)
    segment = mono[begin:end]
    if not segment:
        raise SystemExit("выбранный отрезок пуст — проверьте --start и --duration")

    fade_in = max(1, int(arguments.fade_in * rate))
    fade_out = max(1, int(arguments.fade_out * rate))
    for index in range(min(fade_in, len(segment))):
        segment[index] *= index / fade_in
    for index in range(min(fade_out, len(segment))):
        position = len(segment) - 1 - index
        segment[position] *= index / fade_out

    peak = max(abs(value) for value in segment)
    if peak == 0:
        raise SystemExit("в отрезке тишина")
    gain = arguments.peak * 32767 / peak
    scaled = [int(max(-32768, min(32767, value * gain))) for value in segment]

    raw = b"".join(struct.pack("<h", value) for value in scaled)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=True) as temporary:
        with wave.open(temporary.name, "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(rate)
            handle.writeframes(raw)
        subprocess.run(
            ["afconvert", "-f", "AIFF", "-d", f"BEI16@{rate}", temporary.name, arguments.output],
            check=True,
            capture_output=True,
        )

    original = peak / 32767
    print(f"Готово: {arguments.output}")
    print(f"  длительность {len(scaled) / rate:.2f} с, моно {rate} Гц")
    print(f"  пик был {original:.3f} → стал {arguments.peak:.3f}"
          f" (тише в {original / arguments.peak:.1f} раз)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
