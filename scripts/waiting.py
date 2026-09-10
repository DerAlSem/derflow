#!/usr/bin/env python3
"""waiting — реестр не-сейчас-работы: строка и хранилище (поставка 2-1).

    waiting.py new "<заголовок>" [--global]
    waiting.py list [--all]
    waiting.py done <id> "<почему>"
    waiting.py stamp <id>

Строка — файл `<repo>/.claude/waiting/YYYYMMDD-NN.md` ОСНОВНОГО чекаута,
беспроектная — `~/.claude/waiting/`. У файла один писатель, и это человек:
всё машинно-производное живёт в кэше `~/.claude/waiting-cache/`.

Форма отказывает при `list`, а не при заведении: заполнить всё сразу нельзя по
построению — проба часто ещё не известна. `list` печатает недооформленные
ОТДЕЛЬНОЙ группой, печатает остальные группы целиком и возвращает 1 ПОСЛЕ
полной печати. Упасть на первой недооформленной значило бы заглушить реестр для
всех шести сессий; пропустить её — спрятать до `review_by`, то есть устроить ту
самую тишину, против которой написан весь реестр.

Коды: 0 сделано либо печатать нечего · 1 форма строки · 2 конфигурация либо
положение. Коды 3 (замок занят) и 4 (проба не смогла спросить) принадлежат
поставке 2-2 и здесь не возвращаются никогда.

Спека: ~/.claude/specs/2026-09-08-waiting-registry.md
План:  ~/.claude/plans/2026-09-10-waiting-registry-2-1.md
"""

import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta

# json, re, time и date задаче 1 не нужны — их зовут задачи 2 и 3. Импорт стоит
# здесь сразу, чтобы шапка файла не переписывалась четыре раза подряд.

# WAITING_HOME существует ради стенда укусов: без подмены дома укусы писали бы в
# живой ~/.claude/waiting и не воспроизводились бы дважды подряд. Подменяет
# разом три вещи — беспроектный ящик, кэш и файл корней.
HOME = pathlib.Path(os.environ.get("WAITING_HOME") or (pathlib.Path.home() / ".claude"))
BOX = "waiting"                  # имя каталога-ящика внутри репозитория
CACHE = HOME / "waiting-cache"
ROOTS = HOME / "waiting-roots.txt"
HOME_REPO_ID = "home"            # Р4: у ящика дома id фиксирован
DAYS_WITH_PROBE = 30             # инвариант 5: подстраховка там, где спрашивает машина
DAYS_NO_PROBE = 7                # инвариант 5: единственный датчик там, где не спрашивает никто
CACHE_TTL_S = 3600               # Р11: временное число, выбирается после миграции


def die(code, msg):
    print(f"waiting: {msg}", file=sys.stderr)
    sys.exit(code)


def git(*args, cwd=None):
    # Отсутствие самого git — не «git ответил ошибкой», а «спросить некого»:
    # subprocess бросает FileNotFoundError ДО всякого кода возврата.
    try:
        p = subprocess.run(("git",) + args, cwd=cwd, capture_output=True, text=True)
    except (FileNotFoundError, PermissionError) as e:
        die(2, f"git не запускается — {e}")
    return p.returncode, p.stdout.strip(), p.stderr.strip()


@dataclass
class Box:
    """Ящик строк: каталог, его глобальный id и репозиторий-владелец."""
    dir: pathlib.Path
    repo_id: str
    repo: pathlib.Path        # None у ящика дома
    branch: str               # None у ящика дома


def repo_id_of(main):
    """Имя основного чекаута + 8 знаков sha его пути.

    Алгоритм скопирован из memo.py:context, а не вынесен в общий модуль:
    `lib/` в ~/.claude под запретом .gitignore (глоб без ведущего слэша ловит
    любой lib/ на любой глубине — 10.09.2026 так потерялся файл при коммите), а
    общий модуль ради десяти строк дороже, чем повтор с этой ссылкой. Отличие
    одно и намеренное: хэшуется путь основного чекаута, а не каталога .git —
    здесь id принадлежит ЯЩИКУ (Р4), и у ящика дома каталога .git может не быть
    вовсе.
    """
    slug = "".join(c if (c.isalnum() or c in "._-") else "-" for c in main.name)
    slug = slug.lstrip(".")[:32] or "repo"
    return f"{slug}-{hashlib.sha256(str(main).encode()).hexdigest()[:8]}"


def worktree_main(repo):
    """Основной чекаут репозитория. Ворктри → его хозяин (инвариант 6).

    --path-format=absolute обязателен: без него git отдаёт «.git» из корня,
    «../.git» из подкаталога и абсолютный путь из ворктри. На сравнении этих
    строк главный сценарий развалился бы молча (тот же промах чинил memo.py).
    """
    rc, common, _ = git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=repo)
    if rc != 0:
        return pathlib.Path(repo).resolve()   # не git вовсе — каталог сам себе основной
    c = pathlib.Path(common).resolve()
    return (c.parent if c.name == ".git" else c).resolve()


def home_box():
    return Box(dir=HOME / BOX, repo_id=HOME_REPO_ID, repo=None, branch=None)


def repo_box(cwd=None):
    """Ящик для текущего положения.

    Три развилки, и каждая куплена: не репозиторий → дом; основной чекаут ЕСТЬ
    ~/.claude → дом (иначе `new` завёл бы ~/.claude/.claude/waiting/ и сделал
    существующие строки невидимыми — а изнутри ~/.claude зовут ежедневно);
    ворктри → его основной чекаут, молча и без отказа (Р9).
    """
    cwd = pathlib.Path(cwd) if cwd else pathlib.Path.cwd()
    rc, _top, _ = git("rev-parse", "--show-toplevel", cwd=cwd)
    if rc != 0:
        return home_box()
    main = worktree_main(cwd)
    if main == HOME.resolve():
        return home_box()
    rc, branch, _ = git("rev-parse", "--abbrev-ref", "HEAD", cwd=cwd)
    return Box(dir=main / ".claude" / BOX, repo_id=repo_id_of(main),
               repo=main, branch=(branch if rc == 0 else None))


def box_of_dir(d):
    """Ящик по каталогу: id принадлежит КАТАЛОГУ, а не пути, которым пришли."""
    d = pathlib.Path(d).resolve()
    if d == (HOME / BOX).resolve():
        return home_box()
    main = d.parent.parent
    return Box(dir=d, repo_id=repo_id_of(main), repo=main, branch=None)


def yaml_quote(s):
    """Плоский скаляр в кавычках. Двоеточие с пробелом внутри голого скаляра
    YAML либо ломает разбор, либо меняет смысл, поэтому кавычки не украшение."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def display_path(p):
    """Путь репозитория для entry, сокращённый через ~ под домашним каталогом.

    Голое имя репозиторий не локализует: корней скана может быть несколько, и
    одноимённые каталоги под разными корнями — тот самый класс, ради которого
    идентификатор сделан глобальным. Спека приводит единственный конкретный
    образец entry — с путём: `~/dev/rk_bot · main`.
    """
    p = pathlib.Path(p)
    try:
        return "~/" + str(p.relative_to(pathlib.Path.home()))
    except ValueError:
        return str(p)


def claim_name(d, today):
    """Атомарный захват имени. O_EXCL — единственное, что различает два `new` в
    одну секунду: проверка exists() перед записью проигрывает гонку молча.

    Имя обязано остаться формы YYYYMMDD-NN (инвариант 9): дописать pid значит
    пройти укус и сломать ссылочный идентификатор, на который смотрят хендоффы,
    память и сестринские сессии.
    """
    stem = today.strftime("%Y%m%d")
    for n in range(1, 100):
        path = d / f"{stem}-{n:02d}.md"
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        except FileExistsError:
            continue
        os.close(fd)
        return path.stem
    die(2, f"в {d} за {stem} уже 99 строк — сотую заводить нечем: "
           f"форма имени YYYYMMDD-NN двузначна и не расширяется")


TEMPLATE = """---
title: {title}
state: waiting
review_by: {review_by}
stamped_at: {stamped_at}
entry: {entry}
---

<!-- Дозаполнить. Пока полей нет, строка висит в группе «недооформленные».
Подсказка нарочно с отступом: без него греп по началу строки не отличит её от
настоящего поля, и укус «new не придумывает probe» проходил бы впустую.

  host: local            local | имя хоста | none при probe: none
  cwd: ~/dev/…           каталог, из которого проба запускается; none при probe: none
  probe: |               ОДНА команда, без && и ; ; либо строкой `probe: none`
    …
  ripe_match: "…"        регулярка по stdout пробы; none при probe: none
  ripe_when: "…"         ТО САМОЕ решение прозой, а не его окрестность
  sample: "…"            наблюдение, где проба показала ОБА исхода; либо pending

Если машинной пробы нет — поставить `probe: none` и позвать
`waiting.py stamp {name}`: срок станет +7 дней, потому что без пробы он
остаётся единственным датчиком. -->

Тело: что наблюдалось, чем куплено, что делать по созревании.
"""


def cmd_new(a):
    box = home_box() if a.global_box else repo_box()
    box.dir.mkdir(parents=True, exist_ok=True)
    today = datetime.now().date()
    name = claim_name(box.dir, today)
    entry = yaml_quote(f"{display_path(box.repo)} · {box.branch or '?'}") if box.repo else "none"
    path = box.dir / f"{name}.md"
    path.write_text(TEMPLATE.format(
        title=yaml_quote(a.title),
        review_by=(today + timedelta(days=DAYS_WITH_PROBE)).isoformat(),
        stamped_at=today.isoformat(),
        entry=entry,
        name=name,
    ), encoding="utf-8")
    print(f"заведена: {box.repo_id}/{name}")
    print(f"файл:     {path}")
    print("дозаполнить: host · cwd · probe · ripe_match · ripe_when · sample.")
    print("Пока их нет, list держит строку в «недооформленных» и возвращает 1.")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="waiting", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_new = sub.add_parser("new", help="завести строку")
    p_new.add_argument("title", help="заголовок строки, по-русски")
    # dest обязателен: `global` — ключевое слово Python, a.global не разбирается.
    p_new.add_argument("--global", dest="global_box", action="store_true",
                       help="строка без проекта — в ~/.claude/waiting/")
    p_new.set_defaults(fn=cmd_new)

    a = ap.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
