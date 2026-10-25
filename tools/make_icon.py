#!/usr/bin/env python3
"""Собирает иконку приложения из исходного рисунка.

Тонкость про форму. В macOS 26 система сама обрамляет иконки: добавляет поля и
скругляет углы. Поэтому рисунок нужно отдавать во весь квадрат 1024x1024 — если
заранее нарисовать поля и скругления самому, система обрамит их повторно, и иконка
будет выглядеть вложенной в серую рамку (проверено).

Флаг --rounded оставлен для тех случаев, когда поля и скругления нужны от самого
файла: на macOS 15 и раньше система этого не делает.

Пример:
    python3 tools/make_icon.py --input icon_hum.png --output Resources/HumUpThere.icns
"""
import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

CANVAS = 1024          # полотно иконки
ART = 824              # сторона рисунка по сетке macOS
MARGIN = (CANVAS - ART) // 2
EXPONENT = 5.0         # форма суперэллипса: у иконок macOS примерно такая
SUPERSAMPLE = 4        # сглаживание краёв


def squircle_mask(size: int, exponent: float, supersample: int) -> Image.Image:
    """Маска скруглённого квадрата нужной формы, со сглаженными краями."""
    big = size * supersample
    axis = (np.arange(big) - (big - 1) / 2) / (big / 2)
    grid_x, grid_y = np.meshgrid(axis, axis)
    distance = np.abs(grid_x) ** exponent + np.abs(grid_y) ** exponent
    binary = np.where(distance <= 1.0, 255, 0).astype(np.uint8)
    mask = Image.fromarray(binary, mode="L")
    return mask.resize((size, size), Image.LANCZOS)


def build_canvas(source: Image.Image) -> Image.Image:
    """Кладёт рисунок на прозрачное полотно в сетке macOS."""
    art = source.convert("RGBA").resize((ART, ART), Image.LANCZOS)
    art.putalpha(squircle_mask(ART, EXPONENT, SUPERSAMPLE))

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(art, (MARGIN, MARGIN), art)
    return canvas


def build_icns(canvas: Image.Image, output: Path) -> None:
    with tempfile.TemporaryDirectory() as directory:
        iconset = Path(directory) / "HumUpThere.iconset"
        iconset.mkdir()

        for size in (16, 32, 128, 256, 512):
            for scale, suffix in ((1, ""), (2, "@2x")):
                pixels = size * scale
                target = iconset / f"icon_{size}x{size}{suffix}.png"
                canvas.resize((pixels, pixels), Image.LANCZOS).save(target)

        output.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(output)],
            check=True,
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="icon_hum.png", help="исходный рисунок")
    parser.add_argument("--output", default="Resources/HumUpThere.icns")
    parser.add_argument("--preview", default="docs/icon.png", help="превью для проверки глазами")
    parser.add_argument("--rounded", action="store_true",
                        help="дорисовать поля и скругления самому (для macOS 15 и раньше)")
    arguments = parser.parse_args()

    source_path = Path(arguments.input)
    if not source_path.exists():
        print(f"нет исходного файла: {source_path}", file=sys.stderr)
        return 1

    source = Image.open(source_path)
    print(f"источник: {source_path} ({source.width}x{source.height}, {source.mode})")

    if arguments.rounded:
        canvas = build_canvas(source)
        print("форма: поля и скругления нарисованы в файле")
    else:
        canvas = source.convert("RGBA").resize((CANVAS, CANVAS), Image.LANCZOS)
        print("форма: рисунок во весь квадрат, обрамление сделает система")

    build_icns(canvas, Path(arguments.output))
    print(f"иконка собрана: {arguments.output}")

    preview = Path(arguments.preview)
    if arguments.preview:
        preview.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(preview)
        print(f"превью: {preview}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
