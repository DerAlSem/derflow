#!/usr/bin/env python3
"""Показывает размер контекста текущей сессии каждый ход.

Агент не умеет самодетектить, что его контекст дорос до полумиллиона токенов:
у него нет показания. Та же болезнь, что у параллельности в `_parallel.md`, и
то же лечение — факт печатается хуком `UserPromptSubmit`, а не живёт правилом,
которое надо помнить.

Контекст = input + cache_write + cache_read последнего хода главного цикла:
именно эта сумма перечитывается на КАЖДОМ следующем ходу и составляет
основную часть счёта (замер: `~/.claude/scripts/context-spend.py`).
"""
import json, os, sys

TAIL_BYTES = 4_000_000       # хвост транскрипта; полный файл бывает сотнями МБ
WARN, LOUD = 150_000, 300_000


def last_context(path):
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            if size > TAIL_BYTES:
                f.seek(size - TAIL_BYTES)
                f.readline()          # выбросить обрезанную строку
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return None
    for line in reversed(lines):
        if '"usage"' not in line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("isSidechain"):      # сабагент держит свой контекст, не наш
            continue
        u = (d.get("message") or {}).get("usage") or {}
        if not u:
            continue
        return (u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
                + u.get("cache_read_input_tokens", 0))
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0
    path = payload.get("transcript_path")
    if not path:
        return 0
    n = last_context(path)
    if not n:
        return 0
    msg = f"ctx: {n/1000:.0f}k"
    if n >= LOUD:
        msg += " ‼ расщепи сессию — передай задачу файлом (derflow/_capture.md)"
    elif n >= WARN:
        msg += " ⚠ дальше каждый ход платит за этот контекст"
    print(msg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
