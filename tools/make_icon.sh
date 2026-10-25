#!/usr/bin/env bash
# Сборка иконки приложения из исходного рисунка в корне проекта.
set -euo pipefail

cd "$(dirname "$0")/.."

PY="${PY:-}"
if [[ -z "$PY" ]]; then
    for candidate in \
        "python3" \
        "/opt/homebrew/bin/python3" \
        "/usr/local/bin/python3" \
        "/usr/bin/python3"; do
        if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import PIL, numpy' >/dev/null 2>&1; then
            PY="$candidate"
            break
        fi
    done
fi

if [[ -z "$PY" ]]; then
    echo "Не найден python с Pillow и numpy." >&2
    echo "Установите их: python3 -m pip install pillow numpy" >&2
    exit 1
fi

exec "$PY" tools/make_icon.py "$@"
