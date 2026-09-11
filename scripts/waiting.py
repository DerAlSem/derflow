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

Команд ровно четыре. `ack` и `doctor` принадлежат поставке 2-2 (решение Р1
плана), и их отсутствие здесь — не недоделка: `ack` пишет класс исхода, а в 2-1
исход у каждой строки ровно один — кэша не заполняет никто, — так что от `stamp`
он был бы неотличим; `doctor` сверяет запись хука в настройках и свежесть кэша,
а оба артефакта заводит 2-2, и на исправном реестре 2-1 он обязан был бы кричать
«реестр сломан».

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


KEY = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):(.*)$")


@dataclass
class Field:
    value: str
    style: str      # quoted | bare | block


def unescape(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s) and s[i + 1] in '\\"':
            out.append(s[i + 1]); i += 2
        else:
            out.append(s[i]); i += 1
    return "".join(out)


def strip_comment(s):
    """Комментарий снимается ТОЛЬКО у голого скаляра.

    В кавычках и в блоке решётка — часть значения: `ripe_match: "#\\d+"` —
    законная регулярка, а не строка с комментарием.
    """
    if s.startswith("#"):
        return ""
    cut = s.find(" #")
    return (s[:cut] if cut >= 0 else s).strip()


def parse_front(text):
    """Разбор франтматтера СВОИМ парсером и с сохранением стиля.

    Своим — потому что PyYAML в системе нет (замер 10.09.2026), а тащить
    зависимость ради пятнадцати полей дороже шестидесяти строк.

    Стиль нужен сторожу: спека требует кавычек у пяти полей, а разобранное
    значение о кавычках уже не помнит.

    Возвращает (fields, error). error — причина либо None. Непарсящийся файл
    НИКОГДА не проглатывается: строка с ошибкой печатается наравне с целыми,
    иначе она исчезает беззвучно — то есть врёт в сторону тишины.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, "нет франтматтера: файл не начинается с ---"
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return {}, "франтматтер не закрыт вторым ---"
    fields, i = {}, 1
    while i < end:
        raw = lines[i]
        if not raw.strip() or raw.lstrip().startswith("#"):
            i += 1
            continue
        m = KEY.match(raw)
        if not m:
            return fields, f"строка {i + 1}: не «ключ: значение» — {raw.strip()!r}"
        key, rest = m.group(1), m.group(2).strip()
        if key in fields:
            return fields, f"строка {i + 1}: ключ {key!r} повторяется — какое из двух значений верно, не решает никто"
        if rest == "|":
            body, i = [], i + 1
            while i < end and (not lines[i].strip() or lines[i][:1] in " \t"):
                body.append(lines[i])
                i += 1
            pad = min((len(b) - len(b.lstrip()) for b in body if b.strip()), default=0)
            fields[key] = Field("\n".join(b[pad:] for b in body).strip("\n"), "block")
            continue
        if rest.startswith('"'):
            if len(rest) < 2 or not rest.endswith('"'):
                return fields, f"строка {i + 1}: кавычка у {key!r} не закрыта"
            fields[key] = Field(unescape(rest[1:-1]), "quoted")
        else:
            fields[key] = Field(strip_comment(rest), "bare")
        i += 1
    return fields, None


def day(v):
    """Дата или None. Принимает и поле, и строку — зовут и так, и так."""
    if v is None:
        return None
    s = v.value if isinstance(v, Field) else v
    try:
        return datetime.strptime(s, "%Y-%m-%d").date()
    except ValueError:
        return None


HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def strip_data(text):
    """Выкидывает ДАННЫЕ, оставляет код.

    Наивный `";" in probe` отвергает четыре живые строки нынешней отложки: у
    них многострочный SQL, и точка с запятой там — конец оператора, а не
    разделитель команд. Тело heredoc и содержимое кавычек — данные; сторож
    смотрит на то, что осталось.

    Разбор шелла здесь свой и неполный, и это сказано вслух: сторож ловит
    написанную конъюнкцию, а не выдуманную. `bash -n` тут не помог бы — он
    отвечает на вопрос о синтаксисе, а не о числе команд.
    """
    kept_lines, here, quote = [], None, None
    for raw in text.splitlines():
        if here is not None:
            if raw.strip() == here:
                here = None
            continue
        kept, i = [], 0
        while i < len(raw):
            ch = raw[i]
            if quote:
                if ch == quote:
                    quote = None
                i += 1
                continue
            if ch in "'\"":
                quote = ch
                i += 1
                continue
            # Ограничитель ищется ДО снятия кавычек: в `<<'SQL'` они часть
            # маркера, и снятые первыми они оставили бы голое `<<`.
            m = HEREDOC.match(raw, i)
            if m:
                here = m.group(2)
                i = m.end()
                continue
            kept.append(ch)
            i += 1
        kept_lines.append("".join(kept))
    return kept_lines


def conjunction(text):
    """Причина отказа либо None. Инвариант 1: одна строка — одна проба.

    Ноль конъюнкции двусмыслен: «событий нет» и «ветка кода ни разу не
    исполнялась» из него неразличимы (замер 08.09.2026, строка 15).
    """
    lines = [ln for ln in strip_data(text) if ln.strip()]
    joined = "\n".join(lines)
    for token in ("&&", "||", ";"):
        if token in joined:
            return (f"проба несёт конъюнкцию «{token}» — одна строка, одна проба: "
                    f"ноль конъюнкции не отличить от «не исполнялось ни разу»")
    if len(lines) > 1:
        return ("проба несёт конъюнкцию: две команды в столбик — перевод строки "
                "разделяет их так же, как «;»")
    return None


ALWAYS = ("title", "state", "review_by", "stamped_at", "entry")
WITH_PROBE = ("host", "cwd", "probe", "ripe_match", "ripe_when", "sample")
QUOTED = ("title", "probe", "ripe_match", "ripe_when", "sample")


def faults(fields):
    """Чего не хватает форме. Пустой список — строка оформлена.

    Отказ формой, а не предупреждением (инвариант 4): строку без образца никто
    не отвергает — её просто заводят, и она становится обещанием вместо
    проверки.
    """
    out = []
    for k in ALWAYS:
        if k not in fields:
            out.append(f"нет поля {k}")
    for k in ALWAYS + WITH_PROBE:
        f = fields.get(k)
        if f is not None and not f.value.strip():
            out.append(f"поле {k} пустое — пустое поле это не «нет данных», "
                       f"а «данные были и потерялись при разборе»")
    st = fields.get("state")
    if st is not None and st.value not in ("waiting", "done"):
        out.append(f"state: {st.value!r} — состояний два, waiting и done; третьего нет")
    for k in ("review_by", "stamped_at"):
        f = fields.get(k)
        if f is not None and day(f) is None:
            out.append(f"{k}: {f.value!r} — не дата вида ГГГГ-ММ-ДД")
    probe = fields.get("probe")
    if probe is None:
        out.append("нет поля probe — либо команда, либо явное none")
    elif probe.value == "none":
        # Событие бывает непроверяемым машинно (ответ поддержки, решение
        # человека). Тогда строка созревает ТОЛЬКО по сроку — и остальные поля
        # пробы обязаны быть явным none, а не забытыми.
        for k in ("host", "cwd", "ripe_match", "sample"):
            f = fields.get(k)
            if f is None or f.value != "none":
                out.append(f"probe: none, а {k} не none — спрашивать нечем, "
                           f"и полупустая проба это скрывает")
        if "ripe_when" not in fields:
            out.append("нет поля ripe_when: без пробы прозой сказано только оно")
        rb, sa = day(fields.get("review_by")), day(fields.get("stamped_at"))
        if rb and sa and (rb - sa).days > DAYS_NO_PROBE:
            out.append(
                f"probe: none при штампе +{(rb - sa).days} — срок вдвое длиннее, "
                f"чем положено единственному датчику; чинится `waiting.py stamp`")
    else:
        for k in WITH_PROBE:
            if k not in fields:
                out.append(f"нет поля {k}")
        why = conjunction(probe.value)
        if why:
            out.append(why)
        for k in ("host", "cwd"):
            f = fields.get(k)
            if f is not None and f.value in ("", "none"):
                out.append(f"{k}: none при живой пробе — фоновая проба стартует "
                           f"из неизвестного каталога и честно не найдёт путей")
    for k in QUOTED:
        f = fields.get(k)
        if f is None or f.style in ("quoted", "block"):
            continue
        if k != "title" and f.value in ("none", "pending"):
            continue
        out.append(f"{k} без кавычек: двоеточие с пробелом внутри плоского "
                   f"скаляра YAML либо ломает разбор, либо меняет смысл")
    return out


def roots():
    """Корни скана. Конфиг, а не индекс.

    Отсутствующий файл с работающим умолчанием честнее заведённого файла,
    который надо вести. Файл с нулём корней — ошибка: это не «корней нет», это
    «сказали, что есть, и не назвали».
    """
    if not ROOTS.is_file():
        return [pathlib.Path.home() / "dev"]
    out = []
    for ln in ROOTS.read_text(encoding="utf-8").splitlines():
        ln = ln.split("#", 1)[0].strip()
        if ln:
            out.append(pathlib.Path(ln).expanduser())
    if not out:
        die(2, f"{ROOTS} есть, но не называет ни одного корня")
    return out


def boxes():
    """Каталоги-ящики. Список репозиториев НЕ ведётся — выводится глобом:
    ведённый индекс расходится с реальностью молча, скан не может.

    `~/.claude/waiting/` добавляется ОТДЕЛЬНОЙ строкой: глоб
    <root>/*/.claude/waiting по корню ~/.claude дал бы
    ~/.claude/*/.claude/waiting и не нашёл бы его вовсе.
    """
    seen, out = set(), []
    for root in roots():
        for d in sorted(root.glob(f"*/.claude/{BOX}")):
            if not d.is_dir():
                continue
            repo = d.parent.parent
            if worktree_main(repo) != repo.resolve():
                continue      # ворктри: его строки живут в основном чекауте
            r = d.resolve()
            if r not in seen:
                seen.add(r)
                out.append(r)
    h = HOME / BOX
    if h.is_dir() and h.resolve() not in seen:
        out.append(h.resolve())
    return out


@dataclass
class Row:
    box: Box
    path: pathlib.Path
    name: str
    fields: dict
    error: str
    faults: list

    @property
    def id(self):
        return f"{self.box.repo_id}/{self.name}"


def scan():
    rows = []
    for d in boxes():
        box = box_of_dir(d)
        for p in sorted(d.glob("*.md")):
            if p.name == "MIGRATION.md":
                continue      # карта старых номеров поставки 2-3 — не строка
            try:
                text = p.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError) as e:
                rows.append(Row(box, p, p.stem, {}, f"не читается — {e}", []))
                continue
            f, err = parse_front(text)
            rows.append(Row(box, p, p.stem, f, err, [] if err else faults(f)))
    return rows


def state_of(row):
    f = row.fields.get("state")
    return f.value if f else ""


def sort_key(row):
    return (day(row.fields.get("review_by")) or date.max, row.id)


GROUPS = ("созрело", "молчит", "недостижима", "ни разу не опрошена",
          "недооформленные", "данные протухли")


def cache_of(row):
    """Кэш исходов: ФАЙЛ НА СТРОКУ, писатель один.

    Общий JSON на шесть сессий воспроизвёл бы в самом реестре дефект №3, ради
    которого реестр и пишется: git конфликта не даст, правка целиком затрёт
    чужую главу молча. После разреза по файлам замок перестал быть условием
    корректности и стал экономией на ssh.

    Форма файла — КОНТРАКТ ДЛЯ ПОСТАВКИ 2-2, здесь только читается:
        {"outcome": "fired" | "silent" | "unreachable",
         "since": "ISO-8601 — начало ТЕКУЩЕЙ серии этого исхода",
         "last_run_at_ts": float,     # когда фон спрашивал в последний раз
         "last_rc": int}              # чем кончился САМ ПРОГОН, не проба
    `since` нужен водяному знаку 2-2 (квитанция ключуется исходом, а не датой)
    и в 2-1 не читается — но заводится здесь, чтобы 2-2 не выдумала второй.
    """
    p = CACHE / row.box.repo_id / f"{row.name}.json"
    try:
        c = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        # Битый или отсутствующий кэш — не отказ реестра: строка честно
        # становится «ни разу не опрошена». Соврать в сторону тишины тут
        # невозможно — «не спрашивали» и есть правда о нечитаемом файле.
        return None
    return c if isinstance(c, dict) else None


def vanished(rows):
    """Пропажа из скана — событие, и печатается она ОДИН раз.

    Репозиторий уехал за корни, переименован или удалён — его строки перестают
    находиться, list печатает меньше, и никто не считает сколько. Кэш помнит
    виденные id и потому врать не может; ведённый список репозиториев — может.

    Зовётся со ВСЕМИ строками скана, включая снятые: иначе `done` выглядела бы
    пропажей и гасила бы собственный кэш при каждом list.
    """
    if not CACHE.is_dir():
        return
    live = {(r.box.repo_id, r.name) for r in rows}
    for d in sorted(CACHE.glob("*")):
        if not d.is_dir():
            continue
        for p in sorted(d.glob("*.json")):
            if (d.name, p.stem) in live:
                continue
            print(f"строка {d.name}/{p.stem} пропала из скана — кэш о ней забыт")
            try:
                p.unlink()
            except OSError:
                pass


def resolve(arg, rows):
    """Голый NN принимается, ТОЛЬКО если разрешается однозначно.

    Два `20260908-01` в один день — норма, а не редкость: NN атомарен внутри
    каталога, а каталогов столько, сколько репозиториев. Угадать хуже, чем не
    двигаться: так же отказывает hand.sh кодом 6 на нескольких хендоффах ветки.
    """
    hits = [r for r in rows if (r.id == arg if "/" in arg else r.name == arg)]
    if not hits:
        die(2, f"нет строки {arg}. Что есть — `waiting.py list --all`")
    if len(hits) > 1:
        cands = "\n".join(f"  {r.id}  {r.path}" for r in sorted(hits, key=lambda r: r.id))
        die(2, f"id {arg} неоднозначен — строк с таким именем {len(hits)}:\n{cands}\n"
               f"Назвать полный: <repo-id>/{arg}")
    return hits[0]


def set_fields(path, pairs):
    """Правка франтматтера ПО КЛЮЧУ: своё меняем, чужое не трогаем.

    Перезаписью целиком нельзя — у файла один писатель, человек (инвариант 7), и
    его комментарии, порядок полей и тело обязаны пережить машинную правку. Та
    же дисциплина, что для файлов ~/.claude вообще: read-modify-write по якорю.

    Блочные скаляры не правятся никогда — ни `probe`, ни что-либо ещё
    многострочное: подмена одной строки оставила бы осиротевший отступ.
    """
    lines = path.read_text(encoding="utf-8").splitlines()
    end = None
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                end = i
                break
    if end is None:
        die(1, f"{path}: франтматтер не закрыт — машина в такой файл не пишет")
    left = dict(pairs)
    for i in range(1, end):
        m = KEY.match(lines[i])
        if m and m.group(1) in left:
            lines[i] = f"{m.group(1)}: {left.pop(m.group(1))}"
    for k, v in left.items():
        lines.insert(end, f"{k}: {v}")
        end += 1
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def cmd_done(a):
    row = resolve(a.id, scan())
    if row.error:
        # Тот же сторож, что у stamp. Закрывающий --- на месте, а кавычка внутри
        # не закрыта — set_fields найдёт ограду и запишет в файл, которого разбор
        # не понял. Машина не правит непонятое: у файла один писатель, человек,
        # и починить франтматтер обязан он.
        die(1, f"{row.id}: франтматтер не разбирается ({row.error}) — "
               f"машина в такой файл не пишет; почини форму и повтори")
    if not a.because.strip():
        die(1, "надгробие без причины смерти не отвечает на вопрос, ради которого "
               "его хранят: «сработала» и «линия закрыта» — разные исходы")
    set_fields(row.path, [
        ("state", "done"),
        ("closed_at", datetime.now().date().isoformat()),
        ("closed_because", yaml_quote(a.because)),
    ])
    print(f"снята: {row.id} — {a.because}")
    return 0


def cmd_stamp(a):
    """Пере-вывести review_by по НЫНЕШНЕМУ полю probe.

    Существует ради строк, у которых проба выяснилась после заведения: `new`
    штампует +30, а строка становится `probe: none` позже. `ack` для этого не
    годится — он пишет acked_outcome, то есть утверждает, что строку посмотрели
    по существу. Здесь не посмотрели, здесь переклеили срок.
    """
    row = resolve(a.id, scan())
    if row.error:
        die(1, f"{row.id}: франтматтер не разбирается ({row.error}) — "
               f"срок машина в такой файл не пишет")
    probe = row.fields.get("probe")
    days = DAYS_NO_PROBE if (probe is not None and probe.value == "none") else DAYS_WITH_PROBE
    today = datetime.now().date()
    when = today + timedelta(days=days)
    set_fields(row.path, [("review_by", when.isoformat()), ("stamped_at", today.isoformat())])
    why = ("машинной пробы нет, срок — единственный датчик" if days == DAYS_NO_PROBE
           else "проба есть, срок — подстраховка")
    print(f"{row.id}: пересмотр {when} (+{days} — {why})")
    return 0


def classify(row, today, now):
    """Группа строки. Созрелость ВЫЧИСЛЯЕТСЯ (инвариант 2), не хранится.

    Порядок развилок — не вкусовой:
    форма → срок → есть ли кэш → свеж ли он → что он говорит.
    Срок раньше кэша, потому что review_by и есть страховка на случай, когда
    проба врёт в сторону тишины; кэш раньше исхода, потому что «не спрашивали»
    и «спросили, пусто» — разные ответы (инвариант 3).
    """
    if row.error or row.faults:
        return "недооформленные"
    rb = day(row.fields.get("review_by"))
    if rb is not None and rb <= today:
        return "созрело"
    c = cache_of(row)
    if c is None:
        return "ни разу не опрошена"
    ts = c.get("last_run_at_ts")
    if c.get("last_rc") not in (0, None) or not isinstance(ts, (int, float)) \
            or now - ts > 3 * CACHE_TTL_S:
        # Молчащий реестр неотличим от пустого, а пустой — нормальное
        # состояние, поэтому тревогу не поднимет никто. Отсюда отдельная группа.
        return "данные протухли"
    outcome = c.get("outcome")
    if outcome == "fired":
        return "созрело"
    return {"silent": "молчит", "unreachable": "недостижима"}.get(
        outcome, "ни разу не опрошена")


def line_of(row, group):
    title = row.fields.get("title")
    head = f"  {row.id}  {title.value if title else '(без title)'}"
    marks = []
    rb = row.fields.get("review_by")
    if rb is not None:
        marks.append(f"пересмотр {rb.value}")
    probe = row.fields.get("probe")
    if probe is not None and probe.value == "none":
        marks.append("машинной пробы нет, созреет только сроком")
    sample = row.fields.get("sample")
    if sample is not None and sample.value == "pending":
        marks.append("образца нет, отрицательный ответ ничего не доказывает")
    entry = row.fields.get("entry")
    if entry is not None and entry.value != "none":
        marks.append(entry.value)
    if state_of(row) == "done":
        why = row.fields.get("closed_because")
        marks.insert(0, "снята: " + (why.value if why else "причина не названа"))
    out = [head + (("   [" + " · ".join(marks) + "]") if marks else "")]
    if group == "недооформленные":
        for why in ([row.error] if row.error else row.faults):
            out.append(f"      ⚠ {why}")
        out.append(f"      файл: {row.path}")
    return "\n".join(out)


def cmd_list(a):
    today = datetime.now().date()
    now = time.time()
    rows = scan()
    buckets = {g: [] for g in GROUPS}
    for r in rows:
        if state_of(r) == "done" and not a.all:
            continue
        buckets[classify(r, today, now)].append(r)
    printed = 0
    for g in GROUPS:
        rs = sorted(buckets[g], key=sort_key)
        if not rs:
            continue
        print(f"— {g} ({len(rs)}) —")
        for r in rs:
            print(line_of(r, g))
        printed += len(rs)
    if printed == 0:
        print("реестр пуст")
    vanished(rows)      # со ВСЕМИ строками, включая снятые
    # Код 1 возвращается ПОСЛЕ полной печати. Упасть на первой недооформленной
    # значило бы заглушить вывод реестра для всех шести сессий; пропустить её —
    # спрятать до review_by, то есть устроить ту самую тишину.
    return 1 if buckets["недооформленные"] else 0


def display_path(p):
    """Путь репозитория для entry (Р13) — путь ВСЕГДА, `~` только как сокращение.

    Голое имя репозиторий не локализует: корней скана может быть несколько, и
    одноимённые каталоги под разными корнями — тот самый класс, ради которого
    идентификатор сделан глобальным. Спека приводит единственный конкретный
    образец entry — с путём: `~/dev/rk_bot · main`. Формат один и не зависит от
    места: промежуточный вариант «под домом путь, вне дома имя» отвергнут — два
    формата в одном поле хуже любого одного, а путь вне дома в боевом случае не
    встречается никогда (корень по умолчанию, Р7, — единственный `~/dev`).
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

    p_list = sub.add_parser("list", help="что ждёт события снаружи")
    p_list.add_argument("--all", action="store_true", help="показать и снятые строки")
    p_list.set_defaults(fn=cmd_list)

    p_done = sub.add_parser("done", help="снять строку")
    p_done.add_argument("id", help="<repo-id>/YYYYMMDD-NN либо голый YYYYMMDD-NN")
    p_done.add_argument("because", help="почему снята — обязательно")
    p_done.set_defaults(fn=cmd_done)

    p_stamp = sub.add_parser("stamp", help="пере-вывести срок по нынешней probe")
    p_stamp.add_argument("id", help="<repo-id>/YYYYMMDD-NN либо голый YYYYMMDD-NN")
    p_stamp.set_defaults(fn=cmd_stamp)

    a = ap.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
