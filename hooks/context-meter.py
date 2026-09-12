#!/usr/bin/env python3
"""Каждый ход показывает размер контекста сессии и два события смены задачи.

Агент не умеет самодетектить, что его контекст дорос до полумиллиона токенов:
у него нет показания. Та же болезнь, что у параллельности в `_parallel.md`, и
то же лечение — факт печатается хуком `UserPromptSubmit`, а не живёт правилом,
которое надо помнить.

Контекст = input + cache_write + cache_read последнего хода главного цикла:
именно эта сумма перечитывается на КАЖДОМ следующем ходу и составляет
основную часть счёта (замер: `~/.claude/scripts/context-spend.py`).

`ctx:` — состояние, а не событие: оно ни с чем не сравнивается. Поэтому рядом
печатаются два СОБЫТИЯ, оба машинные и даром:

1. **смена ветки** с прошлого хода — недостающий механизм правила «новая
   проблема = новая ветка И новая сессия» (`derflow/_parallel.md`);
2. **возврат после паузы в дорогой контекст** — опасен не разрыв сам по себе,
   а разрыв в большой контекст: именно тогда на старую дорогую сессию цепляют
   новую задачу.

Прошлый ход лежит в `~/.claude/state/<session_id>.json`: ветка берётся из
файла, пауза — из его mtime. Файл на сессию, поэтому сестринские сессии не
топчут друг друга.
"""
import json, os, subprocess, sys, time

TAIL_BYTES = 4_000_000       # хвост транскрипта; полный файл бывает сотнями МБ
WARN, LOUD = 150_000, 300_000
PAUSE_SEC = 2 * 3600         # ниже — перерыв, а не возврат к отложенной задаче
STALE_SEC = 30 * 86_400      # мёртвые файлы состояния
STATE_DIR = os.path.expanduser("~/.claude/state")


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


def current_branch(cwd):
    """Своим вызовом, а не разбором чужого вывода: в транскрипте на месте ветки
    лежит ТЕКСТ команды соседнего хука, и парсер его однажды уже съел."""
    try:
        p = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"],
                           cwd=cwd or None, capture_output=True, timeout=2)
    except (OSError, subprocess.SubprocessError):
        return None
    if p.returncode:                  # не репозиторий / нет коммитов
        return None
    return p.stdout.decode("utf-8", "replace").strip() or None


def read_state(path):
    """Прошлый ход: (ветка, когда). Время — mtime файла, отдельного поля нет."""
    try:
        ts = os.path.getmtime(path)
    except OSError:
        return None, None
    try:
        with open(path) as f:
            return (json.load(f) or {}).get("branch"), ts
    except (OSError, ValueError):
        return None, ts


def write_state(path, branch, first_turn):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        tmp = f"{path}.tmp"
        with open(tmp, "w") as f:
            json.dump({"branch": branch}, f)
        os.replace(tmp, path)         # атомарно: сестринские сессии не увидят полфайла
    except OSError:
        return
    if first_turn:                    # жатва раз за сессию, а не каждый ход
        reap(path)


def reap(keep):
    cutoff = time.time() - STALE_SEC
    try:
        names = os.listdir(STATE_DIR)
    except OSError:
        return
    for name in names:
        p = os.path.join(STATE_DIR, name)
        try:
            if p != keep and os.path.getmtime(p) < cutoff:
                os.remove(p)
        except OSError:
            pass                      # чужая сессия могла удалить его первой


def ago(sec):
    if sec < 3600:
        return f"{sec / 60:.0f}м"
    if sec < 86_400:
        return f"{sec / 3600:.0f}ч"
    return f"{sec / 86_400:.0f}д"


def loud_msg():
    """Один текст на оба входа: порог, названный дважды по-разному, — два правила."""
    return ("‼ расщепи сессию САМ: доведи хендофф до «здесь и сейчас» и позови "
            "~/.claude/scripts/hand.sh <каталог> (derflow/_capture.md)")


def main_tool():
    """Вход для `PostToolUse`. Печатает порог РОВНО ОДИН РАЗ за сессию.

    🔴 Зачем отдельный вход. `UserPromptSubmit` меряет на РЕПЛИКЕ, а дорожает
    сессия на ХОДАХ. Замер 12.09.2026, `V·хвосты слияния` (82cae91b): одна
    человеческая реплика, 404 хода, контекст 55k → 488k, cache-read 113,5M —
    и метр отработал ровно один раз, на 55k. То есть он слеп именно в том
    случае, который дороже всего: в длинном автономном прогоне. Последняя треть
    ходов там стоила 48% счёта.

    Печатается один раз, а не на каждом вызове: сказать 178 раз — это не
    громче, это фон, который перестают читать. Защёлка — отдельный файл, а не
    поле в состоянии: `write_state` перезаписывает его целиком на каждой
    реплике, и поле бы стёрлось.
    """
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0
    session = payload.get("session_id")
    if not session:
        return 0
    latch = os.path.join(STATE_DIR, f"{session}.loud")
    # Дешёвая сторона вперёд: после первого раза хук не читает транскрипт вовсе.
    if os.path.exists(latch):
        return 0
    n = last_context(payload.get("transcript_path") or "")
    if not n or n < LOUD:
        return 0
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        os.close(os.open(latch, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644))
    except FileExistsError:
        return 0                      # гонка: печатает тот, кто поставил защёлку
    except OSError:
        pass                          # защёлку не поставили — лучше дважды, чем ни разу
    print(f"ctx: {n / 1000:.0f}k {loud_msg()}")
    return 0


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0
    n = last_context(payload.get("transcript_path") or "")
    branch = current_branch(payload.get("cwd"))
    session = payload.get("session_id")

    out = []
    if n:
        msg = f"ctx: {n / 1000:.0f}k"
        if n >= LOUD:
            msg += " " + loud_msg()
        elif n >= WARN:
            msg += " ⚠ дальше каждый ход платит за этот контекст"
        out.append(msg)

    if session:
        path = os.path.join(STATE_DIR, f"{session}.json")
        prev_branch, prev_ts = read_state(path)
        if prev_branch and branch and prev_branch != branch:
            out.append(f"⚠ ветка: {prev_branch} → {branch} — другая проблема? "
                       "Тогда своя сессия (derflow/_parallel.md)")
        if prev_ts and n and n >= WARN and time.time() - prev_ts >= PAUSE_SEC:
            out.append(f"↩ возврат через {ago(time.time() - prev_ts)} в контекст "
                       f"{n / 1000:.0f}k — новую задачу лучше в свою сессию")
        write_state(path, branch, first_turn=prev_ts is None)

    if out:
        print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main_tool() if "--tool" in sys.argv else main())
