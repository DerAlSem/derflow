# Мемо по дереву (1b-1) — план реализации

> **Для агентов-исполнителей:** ОБЯЗАТЕЛЬНЫЙ ПОДНАВЫК — `superpowers:subagent-driven-development`
> (рекомендуется) либо `superpowers:executing-plans`. Шаги размечены чекбоксами `- [ ]`.

**Цель:** сделать вердикт гейта функцией дерева, а не сессии: `~/.claude/scripts/memo.py`
отвечает «этот `tree_sha` уже проходил чистый гейт» и не гонит его второй раз.

**Архитектура:** чистая функция `(tree_sha, gate_version_external) → pass`. Ключ выводится
из git, вердикт лежит в `~/.claude/gate-verdicts/<repo-id>/`, где `repo-id` общий у всех
ворктри репозитория. Команды гейта берутся из `deploy.json` в корне репозитория — он
закоммичен, поэтому их текст покрыт самим `tree_sha` и в ключ не входит. Кэшируется только
`pass`.

**Стек:** Python 3.14 (stdlib, без зависимостей), git 2.50, bash-стенд укусов в идиоме
`hand-bite.sh`.

**Спека:** `~/.claude/specs/2026-09-08-deploy-as-tree-function.md` — читать вместе с планом,
план спорит со спекой в двух местах и говорит об этом вслух (Р8, Р5).

## Глобальные ограничения

- **Инвариант 1.** Вердикт принадлежит дереву, а не сессии и не рабочему каталогу.
- **Инвариант 2.** Зависящее от среды не кэшируется никогда.
- **Инвариант 4.** «Нечего катить» — ответ, а не ошибка. Код 0.
- **Инвариант 5.** Отказ кодом, а не предупреждением. Печать — не сторож.
- **Инвариант 7.** Кэшируется только `pass`. Провал — событие, а не знание о дереве.
- **Никаких русских имён у файлов.** Содержимое — по-русски, имена — латиницей.
- **Прогон не заворачивается в конвейер.** `| tail` глотает код возврата pytest.
- **Правка файлов `~/.claude`** — read-modify-write по якорю с проверкой единственности,
  никогда перезапись целиком: репозиторий работают 4–6 сессий разом.
- **Коммитить мелко, пушить сразу.** `git status` до и после.
- `~/.claude/scripts/` в белом списке `.gitignore` — новые скрипты версионируются.
  `~/.claude/plans/` впущен 08.09.2026 этой же работой.

---

## Решения, принимаемые этим планом

Спека оставила их открытыми либо не заметила. Каждое названо здесь, чтобы исполнитель не
принимал их заново по ходу и не принимал молча.

**Р1. `deploy.json` лежит в корне репозитория и КОММИТИТСЯ.**
Тогда текст `gate_pure` — часть дерева, и правка команд гейта меняет `tree_sha` сама,
без единой строки кода. Спека это и подразумевала («Файлы в дереве уже покрыты `tree_sha`;
перечислять их — вести список руками»), но места конфига не назвала.

**Р2. `gate_pure` в ключ вердикта НЕ входит.** Следствие Р1. В ключ входит только
`gate_version_external` — то, чего дерево не видит.

**Р3. Если `deploy.json` не отслеживается git — кэш выключен.**
Дыра, которую Р1 оставляет: правленый отслеживаемый конфиг делает дерево грязным и кэш
и так отключается, а вот **неотслеживаемый** конфиг под `--untracked-files=no` невидим, и
подмена команд гейта прошла бы незамеченной. Проверка — одна `git ls-files --error-unmatch`.

**Р4. Команды разбираются `shlex.split` и гоняются без шелла** (`subprocess.run(argv)`,
`shell=False`). Это не гигиена, а исполнение требования спеки структурно: без шелла
конвейер невозможен в принципе, поэтому `feedback_pipe_swallows_pytest_rc` не может
повториться. Побочно снимается исполнение произвольной строки из конфига ветки.
Цена названа: перенаправления и пайпы в `gate_pure` запрещены — команда, которой они
нужны, оформляется скриптом в дереве.

**Р5. Отпечаток установленного окружения в ключ НЕ входит — принято сознательно.**
Это ответ на открытый вопрос спеки, и вот «почему». Локфайлы (`uv.lock`,
`package-lock.json`) лежат в дереве, значит уже покрыты `tree_sha`. Не покрыт только
разрыв «венв отстал от локфайла» — и он ломается в безопасную сторону: устаревший венв
даёт красный гейт, а красное не кэшируется (инвариант 7). Опасен единственный сценарий:
вердикт снят, когда в венве лежал лишний пакет, потом пакет снесли, дерево не менялось.
Он редок, а лекарство дороже болезни: `pip freeze` в ключе обесценивал бы кэш при
установке любого постороннего инструмента. Механизм при этом ЕСТЬ — `gate_version_external`
принимает список путей и хэширует их содержимое, так что репозиторий, которому отпечаток
нужен, включает его конфигом без правки кода. Отпечаток венва пишется в вердикт **как
диагностика, а не как часть ключа**: `memo list` покажет, при каком интерпретаторе снят
вердикт, и человек увидит расхождение сам.

**Р6. Вердикт с чужого хоста не используется, факт печатается.** Инвариант 2 запрещает
делить вердикт между средами; `~/.claude` — каталог, который однажды кто-нибудь
засинхронит. Проверка — одно сравнение `socket.gethostname()`.

**Р7. Грязное дерево: гоним, но не кэшируем.** Не отказ. `deploy.sh` на грязном дереве
отказывает, и `deploy.py --preflight` поймает это раньше memo; но memo гоняется и просто
так, руками, десять раз на дню, и отказ там был бы вредительством. Печатается строка
«кэш выключен, потому что».

**Р8. Маркер `pg` уходит из `gate_pure` — это правка к спеке, а не к коду.**
Спека в главе «Разделимость гейта» установила чистоту `pytest -m "not integration"` по
маркеру `integration` и монкипатчу в `tests/conftest.py`. Замер этого плана нашёл в
`gmb_v2/pyproject.toml` **второй** маркер, которого спека не видела:

> `pg: local PostgreSQL — ... Из гейта НЕ исключается: без сервера фикстура пропускает
> тесты сама, а с сервером они бесплатное покрытие`

Девять тестов. «Фикстура пропускает сама» означает, что `-m "not integration"` даёт
**зелёное и там, где сервера нет, и там, где он есть** — то есть команда зависит от среды.
Сессия без Postgres снимает вердикт, в котором девять тестов не гонялись; сессия с
Postgres берёт этот вердикт и не гонит их тоже. Ложная зелень, ровно та, ради запрета
которой написан инвариант 2. Поэтому `gate_pure` для gmb_v2 —
`pytest -m "not integration and not pg"`, а `pg` переезжает в `gate_env` (поставка 1b-3,
никогда не кэшируется). «Бесплатное покрытие» при этом не теряется: оно перестаёт быть
бесплатным ровно в тот момент, когда начинает врать.

**Р9. `repo-id` = `<имя главного чекаута>-<8 hex от пути к общему .git>`.**
Читаемая половина — чтобы `memo list --all` можно было смотреть глазами; хэш — чтобы два
клона одного репозитория не слиплись. Путь берётся
`git rev-parse --path-format=absolute --git-common-dir`: **проверено 08.09.2026**, что без
`--path-format` git отдаёт `.git` из корня и `../.git` из подкаталога, а из ворктри —
абсолютный путь; на голом сравнении строк главный сценарий («два ворктри одного репозитория»)
развалился бы молча.

**Р10. Коды возврата memo.** `0` — гейт зелёный (кэш или свежий прогон). `1` — гейт
красный. `2` — конфигурация или положение: не репозиторий, нет коммитов, нет `deploy.json`,
он не JSON, `gate_pure` пуст, файл из `gate_version_external` не читается. Совпадает с
таблицей 1b-3 в кодах 1 и 2, поэтому `deploy.py` пробрасывает их как есть.

**Р11. `MEMO_HOME` — переменная окружения, подменяющая `~/.claude`.** Нужна стенду укусов:
без неё укусы гадят в живой `gate-verdicts` и не воспроизводятся. Единственная строка кода,
существующая ради тестируемости, — названа отдельно, чтобы не выглядела случайной.

---

## Структура файлов

| файл | ответственность |
|---|---|
| `~/.claude/scripts/memo.py` (создать) | вся поставка: контекст git, конфиг, ключ, вердикт, три команды CLI |
| `~/.claude/scripts/memo-bite.sh` (создать) | стенд укусов в идиоме `hand-bite.sh`: временные репозитории, `chk`, красная и зелёная половины |
| `~/dev/gmb_v2/deploy.json` (создать, задача 8) | конфиг первого боевого репозитория |
| `~/.claude/specs/2026-09-08-deploy-as-tree-function.md` (правка, задача 8) | закрыть открытый вопрос про отпечаток, внести Р8 |

`memo.py` не делится на модули: 330 строк, один потребитель, ни одной части, которую
позовут отдельно. `scripts/` в этом репозитории — плоский каталог одиночных инструментов
(`check.py`, `hand.sh`, `context-spend.py`), пакетов в нём нет.

**Тестов в идиоме pytest здесь нет и не заводить.** В `~/.claude` тестовая конвенция —
bash-стенд укусов (`hand-bite.sh`), гоняющий инструмент как чёрный ящик на временных
репозиториях. Так и делаем: каждая задача сначала дописывает укусы, гоняет их красными,
потом пишет код.

---

### Задача 1: положение в git — репозиторий, дерево, грязь

**Файлы:**
- Создать: `~/.claude/scripts/memo.py`
- Создать: `~/.claude/scripts/memo-bite.sh`

**Стыки:**
- Потребляет: ничего.
- Отдаёт: `context(cwd=None) -> Ctx` с полями `toplevel: pathlib.Path`,
  `common: pathlib.Path`, `repo_id: str`, `tree_sha: str` (40 hex),
  `dirty: list[str]` (строки `git status --porcelain`); `die(code: int, msg: str)`;
  `git(*args, cwd=None) -> tuple[int, str, str]`; константы `HOME`, `VERDICTS`.
  Команда CLI `memo.py list`, которая на пустом кэше печатает шапку контекста.

- [ ] **Шаг 1: написать стенд с первыми четырьмя укусами**

Создать `~/.claude/scripts/memo-bite.sh`:

```bash
#!/usr/bin/env bash
# Стенд укуса memo.py: каждое утверждение вердикта ломается нарочно.
#
#   bash ~/.claude/scripts/memo-bite.sh
#   MEMO=/путь/к/сломанной/копии bash ~/.claude/scripts/memo-bite.sh
#
# Зачем в репозитории, а не в скрэтчпаде: сторож, чей стенд умирает вместе с
# сессией, второй раз дефекта не ловит. Стенд обязан УМЕТЬ КРАСНЕТЬ — задача 7
# ломает memo.py нарочно и сверяет, что стенд это видит.
set -u
M="${MEMO:-$HOME/.claude/scripts/memo.py}"
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
export MEMO_HOME="$ROOT/home"        # вердикты НЕ в живой ~/.claude
mkdir -p "$MEMO_HOME"
pass=0; fail=0

mk() {  # mk <имя> → печатает путь к свежему репозиторию с гейтом-счётчиком
  d="$ROOT/$1"; mkdir -p "$d"
  git -C "$d" init -q -b main .
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  # Путь к счётчику ЗАПЕКАЕТСЯ абсолютным, а не берётся от __file__: в ворктри
  # gate.py — это чекаут того же файла, и по __file__ он писал бы счётчик в
  # ворктри. Укус «вердикт переезжает между ворктри» тогда считал бы прогоны в
  # двух разных файлах и проходил зелёным, ничего не проверив.
  cat > "$d/gate.py" <<GATE
import pathlib, sys
log = pathlib.Path("$d/runs.log")
log.open("a").write("run\n")
rcf = pathlib.Path("$d/rc.txt")
sys.exit(int(rcf.read_text().strip()) if rcf.exists() else 0)
GATE
  printf '{"gate_pure": ["python3 gate.py"], "gate_version_external": []}\n' > "$d/deploy.json"
  echo x > "$d/a.txt"
  git -C "$d" add -A; git -C "$d" commit -qm init
  printf '%s' "$d"
}
runs() { [ -f "$1/runs.log" ] && wc -l < "$1/runs.log" | tr -d ' ' || echo 0; }
chk() {  # chk <ожидаемый rc> <ярлык> [<подстрока>|!<подстроки быть не должно>]
  want="$1"; label="$2"; needle="${3:-}"
  out="$(cd "$D" && python3 "$M" ${ARG:-check} 2>&1)"; rc=$?
  ok=1
  [ "$rc" = "$want" ] || ok=0
  case "$needle" in
    '!'*) printf '%s' "$out" | grep -q -- "${needle#!}" && ok=0 ;;
    ?*)   printf '%s' "$out" | grep -q -- "$needle" || ok=0 ;;
  esac
  if [ "$ok" = 1 ]; then echo "  ✅ $label (rc=$rc)"; pass=$((pass+1))
  else
    case "$needle" in
      # Скобки ОБЯЗАТЕЛЬНЫ: bash 3.2 (единственный на macOS) присоединяет первый
      # байт многобайтового «»» к имени переменной, и под `set -u` это не пустая
      # строка, а обрыв всего стенда на первом же красном укусе. Замер 08.09.2026:
      # `bash -c 'set -u; n=abc; echo "[«$n»]"'` → «n<байт>: unbound variable».
      # Та же форма живёт в hand-bite.sh, где `set -u` нет и симптом другой —
      # диагностика молча выходит пустой (его комментарий от 07.09 винит в этом
      # последовательность «« + !», и это неверный диагноз той же болезни).
      '!'*) say="и НЕ должно быть «${needle#!}»" ;;
      ?*)   say="и «${needle}»" ;;
      *)    say="" ;;
    esac
    echo "  ❌ $label — ждали rc=$want ${say}, получили rc=$rc"
    echo "$out" | sed 's/^/       /'; fail=$((fail+1)); fi
  ARG=""
}
cnt() {  # cnt <ожидаемое число прогонов> <ярлык> [<ожидаемый rc последнего chk>]
  # Третий параметр — сверка с кодом возврата ПРЕДЫДУЩЕГО вызова chk (глобальный
  # $rc). Нужен там, где «ноль прогонов» тривиально истинно и на сломанном
  # инструменте: заглушка не запускает гейт никогда, безотносительно причины.
  # Замер 08.09.2026: без сверки такой укус был зелёным на заглушке.
  # ⚠️ Зовётся ТОЛЬКО сразу после chk — иначе $rc протухший.
  got="$(runs "$D")"; ok=1
  [ "$got" = "$1" ] || ok=0
  [ -z "${3:-}" ] || [ "$rc" = "$3" ] || ok=0
  if [ "$ok" = 1 ]; then echo "  ✅ $2 (прогонов: $got)"; pass=$((pass+1))
  else
    echo "  ❌ $2 — ждали прогонов $1${3:+ и rc=$3}, получили прогонов $got, rc=${rc:-?}"
    fail=$((fail+1))
  fi
}

echo "=== положение в git ==="

D="$(mk ctx1)"
ARG="list"; chk 0 "list на пустом кэше печатает дерево HEAD" "дерево HEAD:"
ARG="list"; chk 0 "list на пустом кэше говорит, что вердиктов нет" "вердиктов нет"

# Главный сценарий подпроекта: две сессии = два ворктри одного репозитория.
D="$(mk ctx2)"
git -C "$D" worktree add -q "$ROOT/ctx2-wt" -b wb
id_main="$(cd "$D" && python3 "$M" list | grep '^репозиторий:')"
id_wt="$(cd "$ROOT/ctx2-wt" && python3 "$M" list | grep '^репозиторий:')"
if [ "$id_main" = "$id_wt" ] && [ -n "$id_main" ]; then
  echo "  ✅ repo-id ОДИНАКОВ в главном чекауте и в ворктри"; pass=$((pass+1))
else echo "  ❌ repo-id разошёлся: [$id_main] против [$id_wt]"; fail=$((fail+1)); fi
t_main="$(cd "$D" && python3 "$M" list | grep '^дерево HEAD:')"
t_wt="$(cd "$ROOT/ctx2-wt" && python3 "$M" list | grep '^дерево HEAD:')"
if [ "$t_main" = "$t_wt" ] && [ -n "$t_main" ]; then
  echo "  ✅ tree_sha ОДИНАКОВ в двух ворктри на одном коммите"; pass=$((pass+1))
else echo "  ❌ tree_sha разошёлся: [$t_main] против [$t_wt]"; fail=$((fail+1)); fi

# Из подкаталога — тот же repo-id. Ловит наивное сравнение строк `--git-common-dir`:
# git отдаёт оттуда «../.git», и без --path-format=absolute id был бы другим.
mkdir -p "$D/sub"
id_sub="$(cd "$D/sub" && python3 "$M" list | grep '^репозиторий:')"
# `-n` тут не украшение, а тот же сторож, что на двух укусах выше: на вконец
# сломанном memo обе переменные пусты, пустое равно пустому, и укус проходит
# зелёным, ничего не проверив. Замер 08.09.2026 на заглушке: без `-n` из девяти
# красных этот один был зелёным.
if [ "$id_sub" = "$id_main" ] && [ -n "$id_sub" ]; then
  echo "  ✅ repo-id из ПОДКАТАЛОГА тот же"; pass=$((pass+1))
else echo "  ❌ repo-id из подкаталога разошёлся: [$id_sub]"; fail=$((fail+1)); fi

# ARG="list" здесь обязателен: команды `check` в задаче 1 ещё нет, и по умолчанию
# argparse отказал бы кодом 2 по СВОЕЙ причине — укус прошёл бы зелёным впустую.
D="$ROOT/not-a-repo"; mkdir -p "$D"
ARG="list"; chk 2 "вне репозитория git — код 2, а не падение" "не репозиторий"

D="$ROOT/empty-repo"; mkdir -p "$D"; git -C "$D" init -q -b main .
ARG="list"; chk 2 "репозиторий без коммитов — код 2, дерева нет" "нет коммитов"

D="$(mk ctx3)"
echo draft > "$D/untracked.txt"
ARG="list"; chk 0 "untracked-файл дерево НЕ грязнит" "грязное:     нет"

D="$(mk ctx4)"
echo changed > "$D/a.txt"
ARG="list"; chk 0 "правка отслеживаемого файла дерево грязнит" "грязное:     да"

echo
echo "итог: ✅ $pass   ❌ $fail"
[ "$fail" = 0 ]
```

- [ ] **Шаг 2: прогнать стенд, убедиться, что он красный**

```
bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: все укусы ❌, потому что `memo.py` ещё не существует
(`python3: can't open file ... memo.py`). Красный стенд до кода — обязателен:
зелёный с первого раза означает, что укус ничего не проверяет.

- [ ] **Шаг 3: написать `memo.py` до команды `list` включительно**

Создать `~/.claude/scripts/memo.py`:

```python
#!/usr/bin/env python3
"""memo — вердикт гейта принадлежит ДЕРЕВУ, а не сессии.

    memo.py check [--config PATH]      # зелёный? кэш или прогон
    memo.py list [--all]               # что лежит в кэше
    memo.py forget --current|--all|<tree_sha>

Задача: две сессии на одном стволе гоняют один и тот же гейт по разу каждая, на
неизменившемся коде. Общего состояния у них нет, потому что вердикт привязан к
НАМЕРЕНИЮ сессии, а не к состоянию дерева. Здесь он привязан к дереву.

Ключ — (tree_sha, gate_version_external). Текста команд гейта в ключе НЕТ
намеренно: `deploy.json` лежит в дереве и закоммичен, значит правка команд
меняет tree_sha сама. Если конфиг не отслеживается — кэш выключается, потому что
эта опора исчезает (см. `cacheable()`).

Кэшируется ТОЛЬКО pass. Провал — событие, а не знание о дереве: разовый
`Permission denied` иначе заблокировал бы sha до правки байта.

Коды: 0 зелёный · 1 красный · 2 конфигурация либо положение.
"""

import argparse
import hashlib
import json
import os
import pathlib
import shlex
import socket
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone

# MEMO_HOME существует ради стенда укусов: без подмены дома укусы писали бы в
# живой ~/.claude/gate-verdicts и не воспроизводились бы дважды подряд.
HOME = pathlib.Path(os.environ.get("MEMO_HOME") or (pathlib.Path.home() / ".claude"))
VERDICTS = HOME / "gate-verdicts"
CONFIG_NAME = "deploy.json"


def die(code, msg):
    print(f"memo: {msg}", file=sys.stderr)
    sys.exit(code)


def git(*args, cwd=None):
    p = subprocess.run(("git",) + args, cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


@dataclass
class Ctx:
    toplevel: pathlib.Path
    common: pathlib.Path
    repo_id: str
    tree_sha: str
    dirty: list = field(default_factory=list)


def context(cwd=None):
    """Положение: какой репозиторий, какое дерево, грязно ли."""
    cwd = pathlib.Path(cwd) if cwd else pathlib.Path.cwd()
    rc, top, err = git("rev-parse", "--show-toplevel", cwd=cwd)
    if rc != 0:
        die(2, f"не репозиторий git: {cwd}")
    # --path-format=absolute обязателен: без него git отдаёт «.git» из корня,
    # «../.git» из подкаталога и абсолютный путь из ворктри. На сравнении этих
    # строк главный сценарий (два ворктри одного репозитория) развалился бы молча.
    rc, common, err = git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=cwd)
    if rc != 0:
        die(2, f"git не отдал --git-common-dir: {err}")
    common = pathlib.Path(common).resolve()
    rc, tree, err = git("rev-parse", "HEAD^{tree}", cwd=cwd)
    if rc != 0:
        die(2, "в репозитории нет коммитов — дерева нет, вердикту не к чему привязаться")
    rc, porc, _ = git("status", "--porcelain", "--untracked-files=no", cwd=cwd)
    # --untracked-files=no — то же определение грязи, что у deploy.sh:127.
    # Компромисс назван вслух: untracked-файл с кодом вердиктом не покрыт, и
    # deploy.sh его тоже не увезёт. Без флага кэш не сработал бы ни разу: в
    # рабочем ворктри почти всегда лежит черновик.
    main_dir = common.parent if common.name == ".git" else common
    slug = "".join(c if (c.isalnum() or c in "._-") else "-" for c in main_dir.name)[:32]
    repo_id = f"{slug}-{hashlib.sha256(str(common).encode()).hexdigest()[:8]}"
    return Ctx(toplevel=pathlib.Path(top), common=common, repo_id=repo_id,
               tree_sha=tree, dirty=[ln for ln in porc.splitlines() if ln.strip()])


def cmd_list(a):
    ctx = context()
    print(f"репозиторий: {ctx.repo_id}   ({ctx.common})")
    print(f"дерево HEAD: {ctx.tree_sha}")
    print(f"грязное:     {'да, файлов ' + str(len(ctx.dirty)) if ctx.dirty else 'нет'}")
    print("вердиктов нет")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="memo", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list", help="что лежит в кэше").set_defaults(fn=cmd_list)
    a = ap.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Шаг 4: прогнать стенд, убедиться, что положение в git зелёное**

```
chmod +x ~/.claude/scripts/memo.py
bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: `итог: ✅ 9   ❌ 0`, а на заглушке (см. ниже) `✅ 0   ❌ 9`.

```
printf 'import sys\nprint("заглушка")\nsys.exit(0)\n' > /tmp/memo-stub.py
MEMO=/tmp/memo-stub.py bash ~/.claude/scripts/memo-bite.sh
```

Ровно ноль зелёных на заглушке — признак того, что ни один укус не проходит впустую.

Если `repo-id ОДИНАКОВ` красный — значит `--path-format=absolute` потерян либо
`.resolve()` не вызван. Если красный `untracked-файл дерево НЕ грязнит` — потерян
`--untracked-files=no`.

- [ ] **Шаг 5: коммит**

```
cd ~/.claude
git add scripts/memo.py scripts/memo-bite.sh .gitignore plans/
git commit -m "мемо(1b-1): положение в git — repo-id общий у ворктри, стенд укусов"
git push
```

---

### Задача 2: конфигурация и ключ `gate_version`

**Файлы:**
- Изменить: `~/.claude/scripts/memo.py` (добавить `load_config`, `gate_version`, `config_tracked`; расширить `cmd_list`)
- Изменить: `~/.claude/scripts/memo-bite.sh` (добавить главу «конфигурация и ключ»)

**Стыки:**
- Потребляет: `Ctx`, `die`, `git` из задачи 1.
- Отдаёт: `load_config(ctx, explicit=None) -> (path: pathlib.Path, gate: list[str], ext: list[str])`;
  `gate_version(ctx, ext) -> (gv: str, parts: dict[str, str])` где `gv` — 12 hex;
  `config_tracked(ctx, path) -> bool`. `memo.py list` печатает строку `ключ gv:`.

**Форма `deploy.json`, которую читает 1b-1** (остальные поля 1b-3 игнорируются молча —
это один файл на три поставки, и ранняя поставка не имеет права спотыкаться о поздние):

```json
{
  "gate_pure": ["pytest -m \"not integration and not pg\" -q -n 12", "bunx vue-tsc -b"],
  "gate_version_external": []
}
```

`gate_version_external` — список путей к файлам **за пределами дерева**; абсолютные либо
с `~`; относительные считаются от корня репозитория (это допущено для симметрии, но
относительный путь почти всегда означает файл в дереве, а такой в ключе не нужен —
он и так покрыт `tree_sha`).

- [ ] **Шаг 1: дописать укусы в `memo-bite.sh`**

Вставить перед строкой `echo` и `echo "итог: ...` следующую главу:

```bash
echo
echo "=== конфигурация и ключ ==="

# ⚠️ Здесь ТОЛЬКО те укусы, которым хватает `list`. Ошибки конфига проверяются
# через `check`, а его ещё нет: argparse отказал бы кодом 2 по своей причине, и
# укус проходил бы зелёным, ничего не проверив. Они заведены в задаче 3.

# Ключ обязан двигаться от ВНЕШНЕГО входа и не двигаться без него.
D="$(mk cfg5)"
ext="$ROOT/external.txt"; echo v1 > "$ext"
printf '{"gate_pure": ["python3 gate.py"], "gate_version_external": ["%s"]}\n' "$ext" \
  > "$D/deploy.json"
git -C "$D" add -A; git -C "$D" commit -qm ext
gv1="$(cd "$D" && python3 "$M" list | grep '^ключ gv:')"
gv1b="$(cd "$D" && python3 "$M" list | grep '^ключ gv:')"
echo v2 > "$ext"
gv2="$(cd "$D" && python3 "$M" list | grep '^ключ gv:')"
if [ "$gv1" = "$gv1b" ] && [ -n "$gv1" ]; then
  echo "  ✅ ключ УСТОЙЧИВ при неизменном внешнем входе"; pass=$((pass+1))
else echo "  ❌ ключ прыгает сам по себе: [$gv1] против [$gv1b]"; fail=$((fail+1)); fi
if [ "$gv1" != "$gv2" ]; then
  echo "  ✅ правка ВНЕШНЕГО входа двигает ключ"; pass=$((pass+1))
else echo "  ❌ внешний вход в ключ не попал: [$gv1] = [$gv2]"; fail=$((fail+1)); fi

D="$(mk cfg7)"
ARG="list"; chk 0 "list БЕЗ вердиктов всё равно печатает ключ" "ключ gv:"

# list обязан пережить отсутствие конфига: смотреть кэш надо и там, где конфига
# нет, иначе инструмент «посмотреть и сбросить» отказывает ровно там, где нужен.
D="$(mk cfg8)"; rm "$D/deploy.json"; git -C "$D" rm -q --cached deploy.json
git -C "$D" commit -qm "без конфига"
ARG="list"; chk 0 "list без конфига — не падает, а говорит об этом" "конфига нет"
```

- [ ] **Шаг 2: прогнать стенд, убедиться, что новая глава красная**

```
bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: 9 ✅ из задачи 1 и ❌ на всех новых — `list` ещё не печатает `ключ gv:`.

- [ ] **Шаг 3: добавить чтение конфига и ключ в `memo.py`**

Вставить после `def context(...)` и до `def cmd_list(...)`:

```python
def load_config(ctx, explicit=None):
    """Что гнать и что входит в ключ. Ошибки конфига — код 2, не трейсбек."""
    path = pathlib.Path(explicit).expanduser() if explicit else ctx.toplevel / CONFIG_NAME
    if not path.is_file():
        die(2, f"нет {path} — memo не знает, что гнать")
    try:
        cfg = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        die(2, f"{path}: не JSON — {e}")
    except OSError as e:
        die(2, f"{path}: не читается — {e}")
    if not isinstance(cfg, dict):
        die(2, f"{path}: не JSON-объект")
    gate = cfg.get("gate_pure")
    if not isinstance(gate, list) or not gate or not all(isinstance(c, str) for c in gate):
        die(2, f"{path}: gate_pure должен быть непустым списком строк")
    ext = cfg.get("gate_version_external", [])
    if not isinstance(ext, list) or not all(isinstance(p, str) for p in ext):
        die(2, f"{path}: gate_version_external должен быть списком путей")
    # Прочие поля (targets, gate_env, gate_post, allow_skips) принадлежат 1b-3 и
    # здесь не читаются. Один файл на три поставки: ранняя не спотыкается о поздние.
    return path, gate, ext


def gate_version(ctx, ext):
    """Ключ по тому, чего дерево НЕ видит. Текста команд здесь нет — он в дереве."""
    parts = {}
    for raw in sorted(ext):
        p = pathlib.Path(raw).expanduser()
        if not p.is_absolute():
            p = ctx.toplevel / p
        try:
            parts[raw] = hashlib.sha256(p.read_bytes()).hexdigest()
        except OSError as e:
            die(2, f"gate_version_external: {raw} не читается — {e}")
    blob = json.dumps(parts, sort_keys=True, ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()[:12], parts


def config_tracked(ctx, path):
    """Отслеживается ли конфиг git. Не отслеживается — команды гейта деревом не покрыты."""
    try:
        rel = path.resolve().relative_to(ctx.toplevel.resolve())
    except ValueError:
        return False
    rc, _, _ = git("ls-files", "--error-unmatch", "--", str(rel), cwd=ctx.toplevel)
    return rc == 0
```

Заменить `cmd_list` целиком на:

```python
def cmd_list(a):
    ctx = context()
    print(f"репозиторий: {ctx.repo_id}   ({ctx.common})")
    print(f"дерево HEAD: {ctx.tree_sha}")
    print(f"грязное:     {'да, файлов ' + str(len(ctx.dirty)) if ctx.dirty else 'нет'}")
    # list читает конфиг МЯГКО: смотреть кэш надо и в репозитории без конфига,
    # иначе инструмент «посмотреть и сбросить» отказывает ровно там, где нужен.
    try:
        cfgpath, gate, ext = load_config(ctx, a.config)
        gv, _ = gate_version(ctx, ext)
        print(f"ключ gv:     {gv}   ({len(ext)} внешних входов, {len(gate)} команд)")
    except SystemExit:
        print("ключ gv:     — (конфига нет либо он невалиден)")
    print("вердиктов нет")
    return 0
```

⚠️ `except SystemExit` здесь намеренно: `die` — единственный способ выйти из `load_config`,
и `list` обязан пережить его, не проглотив при этом настоящие ошибки — они уже напечатаны
`die` в stderr.

В `main` добавить `--config` обеим командам:

```python
def main(argv=None):
    ap = argparse.ArgumentParser(prog="memo", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_list = sub.add_parser("list", help="что лежит в кэше")
    p_list.add_argument("--config", help=f"путь к {CONFIG_NAME}")
    p_list.set_defaults(fn=cmd_list)
    a = ap.parse_args(argv)
    return a.fn(a)
```

- [ ] **Шаг 4: прогнать стенд**

```
bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: `итог: ✅ 13   ❌ 0`.

**И сразу вторая проверка — на заглушке.** Зелёный стенд говорит, что укусы
проходят; он НЕ говорит, что они что-нибудь сторожат. Прогон на вконец сломанном
инструменте отвечает на второй вопрос и стоит десять секунд:

```
printf 'import sys\nprint("заглушка")\nsys.exit(0)\n' > /tmp/memo-stub.py
MEMO=/tmp/memo-stub.py bash ~/.claude/scripts/memo-bite.sh
```

Ожидается `итог: ✅ 0   ❌ 13` — **ровно ноль зелёных**. Любой зелёный означает укус,
проходящий впустую: он сравнивает пустое с пустым, либо берёт иголкой строку, которую
инструмент печатает всегда. Найти, назвать и починить — это дефект укуса, а не заглушки.
Замер 08.09.2026: в задаче 1 так нашёлся ровно один такой укус из девяти.

Если красный «правка ВНЕШНЕГО входа двигает ключ» — файл из `gate_version_external`
хэшируется не по содержимому либо путь разрешается относительно не того каталога.

- [ ] **Шаг 5: коммит**

```
cd ~/.claude
git add scripts/memo.py scripts/memo-bite.sh
git commit -m "мемо(1b-1): конфиг и ключ — команды в дереве, в ключе только внешнее"
git push
```

---

### Задача 3: `check` без кэша — прогон гейта и честный код возврата

**Файлы:**
- Изменить: `~/.claude/scripts/memo.py` (добавить `run_gate`, `cmd_check`)
- Изменить: `~/.claude/scripts/memo-bite.sh` (глава «прогон»)

**Стыки:**
- Потребляет: `context`, `load_config`, `gate_version` из задач 1–2.
- Отдаёт: `run_gate(ctx, gate) -> (ok: bool, took: float, failed_cmd: str | None)`;
  команда CLI `memo.py check [--config PATH]`, коды 0/1/2. Кэша здесь ещё НЕТ —
  каждый вызов гонит. Задача 4 вставляет кэш вокруг этого же прогона.

- [ ] **Шаг 1: дописать укусы**

Вставить перед итоговой строкой стенда:

```bash
echo
echo "=== прогон ==="

# Перенесено из задачи 2: этим укусам нужна команда `check`, и только теперь она
# есть. Проверяется не код 2 сам по себе (его дал бы и argparse), а ТЕКСТ причины.
D="$(mk cfg1)"; rm "$D/deploy.json"; git -C "$D" rm -q --cached deploy.json
git -C "$D" commit -qm "без конфига"
chk 2 "нет deploy.json — код 2 с названной причиной" "не знает, что гнать"
# Третьим параметром — сверка rc: «ноль прогонов» само по себе истинно и на
# заглушке, которая гейт не запускает никогда. Найдено прогоном на заглушке.
cnt 0 "гейт при отсутствии конфига не гонялся" 2

D="$(mk cfg2)"; printf 'не json вовсе\n' > "$D/deploy.json"
git -C "$D" add -A; git -C "$D" commit -qm broken
chk 2 "deploy.json не JSON — код 2, а не падение трейсбеком" "не JSON"

D="$(mk cfg3)"; printf '{"gate_pure": []}\n' > "$D/deploy.json"
git -C "$D" add -A; git -C "$D" commit -qm empty
chk 2 "пустой gate_pure — код 2" "непустым списком"

D="$(mk cfg4)"; printf '{"gate_pure": "python3 gate.py"}\n' > "$D/deploy.json"
git -C "$D" add -A; git -C "$D" commit -qm str
chk 2 "gate_pure строкой, а не списком — код 2" "непустым списком"

D="$(mk cfg6)"
printf '{"gate_pure": ["python3 gate.py"], "gate_version_external": ["%s/нет-такого"]}\n' \
  "$ROOT" > "$D/deploy.json"
git -C "$D" add -A; git -C "$D" commit -qm noext
chk 2 "нечитаемый внешний вход — код 2, а не тихий ключ из ничего" "не читается"

D="$(mk run1)"
chk 0 "зелёный гейт — код 0" "гейт зелёный"
cnt 1 "зелёный гейт гонялся ровно раз"

D="$(mk run2)"; echo 1 > "$D/rc.txt"
chk 1 "красный гейт — код 1, а НЕ 0" "гейт красный"

# Тот самый feedback_pipe_swallows_pytest_rc, только структурно: без шелла
# конвейер невозможен, поэтому код возврата некому глотать.
D="$(mk run3)"; echo 7 > "$D/rc.txt"
chk 1 "код возврата гейта не проглочен: rc=7 → memo rc=1" "кодом 7"

D="$(mk run4)"
printf '{"gate_pure": ["python3 gate.py", "python3 нет-такого.py"]}\n' > "$D/deploy.json"
git -C "$D" add -A; git -C "$D" commit -qm two
chk 1 "вторая команда падает — общий результат красный" "гейт красный"
cnt 1 "первая команда всё же гонялась"

D="$(mk run5)"
printf '{"gate_pure": ["не-существует-такой-команды"]}\n' > "$D/deploy.json"
git -C "$D" add -A; git -C "$D" commit -qm nocmd
chk 1 "команды нет в PATH — код 1, а не трейсбек" "не запустилась"
```

- [ ] **Шаг 2: прогнать стенд, убедиться, что глава «прогон» красная**

```
bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: 13 ✅ и ❌ на всех укусах главы «прогон» (`argparse: invalid choice: 'check'`).

- [ ] **Шаг 3: добавить прогон и `check`**

Вставить после `config_tracked`:

```python
def run_gate(ctx, gate):
    """Гоняем команды по очереди в корне репозитория. Первый ненулевой — конец.

    БЕЗ ШЕЛЛА и БЕЗ КОНВЕЙЕРА, и это не гигиена, а требование спеки, исполненное
    структурно: `| tail` глотает код возврата pytest (feedback_pipe_swallows_pytest_rc).
    Без shell=True конвейер невозможен в принципе. Цена: перенаправления в
    gate_pure запрещены — команде, которой они нужны, место в скрипте в дереве.

    stdout/stderr наследуются, а не перехватываются: гейт идёт минуты, и человек
    обязан видеть его вывод по мере появления.
    """
    started = time.monotonic()
    for cmd in gate:
        argv = shlex.split(cmd)
        if not argv:
            die(2, f"пустая команда в gate_pure: {cmd!r}")
        print(f"→ {cmd}", flush=True)
        try:
            rc = subprocess.run(argv, cwd=ctx.toplevel).returncode
        except (FileNotFoundError, PermissionError, OSError) as e:
            print(f"гейт красный: «{cmd}» не запустилась — {e}")
            return False, round(time.monotonic() - started, 1), cmd
        if rc != 0:
            print(f"гейт красный: «{cmd}» вышла кодом {rc}. Вердикт НЕ записан.")
            return False, round(time.monotonic() - started, 1), cmd
    return True, round(time.monotonic() - started, 1), None


def cmd_check(a):
    ctx = context()
    cfgpath, gate, ext = load_config(ctx, a.config)
    gv, extparts = gate_version(ctx, ext)
    ok, took, _ = run_gate(ctx, gate)
    if not ok:
        return 1
    print(f"гейт зелёный за {took} с.")
    return 0
```

В `main` добавить команду:

```python
    p_check = sub.add_parser("check", help="гейт зелёный? кэш или прогон")
    p_check.add_argument("--config", help=f"путь к {CONFIG_NAME}")
    p_check.set_defaults(fn=cmd_check)
```

- [ ] **Шаг 4: прогнать стенд целиком**

```
bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: `итог: ✅ 26   ❌ 0`.

**И сразу вторая проверка — на заглушке.** Зелёный стенд говорит, что укусы
проходят; он НЕ говорит, что они что-нибудь сторожат. Прогон на вконец сломанном
инструменте отвечает на второй вопрос и стоит десять секунд:

```
printf 'import sys\nprint("заглушка")\nsys.exit(0)\n' > /tmp/memo-stub.py
MEMO=/tmp/memo-stub.py bash ~/.claude/scripts/memo-bite.sh
```

Ожидается `итог: ✅ 0   ❌ 26` — **ровно ноль зелёных**. Любой зелёный означает укус,
проходящий впустую: он сравнивает пустое с пустым, либо берёт иголкой строку, которую
инструмент печатает всегда. Найти, назвать и починить — это дефект укуса, а не заглушки.
Замер 08.09.2026: в задаче 1 так нашёлся ровно один такой укус из девяти.

- [ ] **Шаг 5: коммит**

```
cd ~/.claude
git add scripts/memo.py scripts/memo-bite.sh
git commit -m "мемо(1b-1): прогон гейта без шелла — код возврата некому глотать"
git push
```

---

### Задача 4: кэш — запись и чтение вердикта

Центральная задача поставки. Всё до неё — подготовка, всё после — страховки.

**Файлы:**
- Изменить: `~/.claude/scripts/memo.py` (`verdict_path`, `read_verdict`, `write_verdict`, `session_id`, `env_fingerprint`; переписать `cmd_check`)
- Изменить: `~/.claude/scripts/memo-bite.sh` (глава «кэш»)

**Стыки:**
- Потребляет: всё из задач 1–3.
- Отдаёт: `verdict_path(ctx, gv) -> pathlib.Path`;
  `read_verdict(path) -> dict | None`; `write_verdict(path, payload) -> None`;
  `session_id() -> str`; `env_fingerprint() -> dict`.
  Файл вердикта: `~/.claude/gate-verdicts/<repo_id>/<tree_sha>.<gv>.json`.

**Формат вердикта** — поля фиксируются здесь, `memo list` и задача 5 на них опираются:

```json
{
  "tree_sha": "6ca2b082c4982a05d9978c0e48bfbae57de44389",
  "gate_version": "4f3a1c9d0b72",
  "repo_id": "gmb_v2-1f3a9c2b",
  "result": "pass",
  "recorded_at": "2026-09-08T18:41:07+03:00",
  "host": "mbp-deralsem",
  "session": "e4c1a0f2-...",
  "worktree": "/Users/deralsem/dev/gmb_v2-roster",
  "duration_s": 41.2,
  "commands": ["pytest -m \"not integration and not pg\" -q -n 12"],
  "external": {},
  "env": {"python": "/Users/.../.venv/bin/python3", "python_version": "3.14.7"}
}
```

`env` — **диагностика, а не часть ключа** (решение Р5). `memo list` её показывает, чтобы
человек увидел «вердикт снят под другим интерпретатором» сам; машина по ней решений не
принимает. Поле `result` всегда `"pass"`: `fail` не пишется никогда (инвариант 7), а
значит поле существует только чтобы чужой или битый файл не был принят за вердикт.

- [ ] **Шаг 1: дописать укусы**

```bash
echo
echo "=== кэш ==="

# Укус 1 спеки: пишет один процесс, читает ДРУГОЙ — с другим pid и другой сессией.
D="$(mk c1)"
(cd "$D" && CLAUDE_CODE_SESSION_ID=aaa python3 "$M" check >/dev/null 2>&1)
out="$(cd "$D" && CLAUDE_CODE_SESSION_ID=bbb python3 "$M" check 2>&1)"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q "сессия aaa"; then
  echo "  ✅ вердикт процесса A виден процессу B и назван его сессией"; pass=$((pass+1))
else echo "  ❌ кросс-процессный вердикт не сработал (rc=$rc)"; echo "$out" | sed 's/^/       /'; fail=$((fail+1)); fi
cnt 1 "второй процесс чистую часть НЕ гонял"

# Укус 2 спеки: главный сценарий подпроекта — вердикт переезжает между ворктри.
D="$(mk c2)"
git -C "$D" worktree add -q "$ROOT/c2-wt" -b c2b
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
(cd "$ROOT/c2-wt" && python3 "$M" check >/dev/null 2>&1)
cnt 1 "вердикт из ворктри A действует в ворктри B того же репозитория"

# Укус 3 спеки: правка байта в дереве обесценивает вердикт.
D="$(mk c3)"
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
echo y >> "$D/a.txt"; git -C "$D" add -A; git -C "$D" commit -qm byte
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
cnt 2 "закоммиченная правка байта — вердикт не действует, гейт гнался снова"

# Укус 4 спеки: внешний вход при НЕИЗМЕННОМ дереве обесценивает вердикт.
D="$(mk c4)"
ext="$ROOT/ext4.txt"; echo v1 > "$ext"
printf '{"gate_pure": ["python3 gate.py"], "gate_version_external": ["%s"]}\n' "$ext" \
  > "$D/deploy.json"
git -C "$D" add -A; git -C "$D" commit -qm ext4
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
echo v2 > "$ext"
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
cnt 2 "правка ВНЕШНЕГО входа при том же дереве — гейт гнался снова"

# Укус 5 спеки: untracked-файл кэш не ломает.
D="$(mk c5)"
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
echo draft > "$D/черновик.txt"
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
cnt 1 "untracked-файл кэш НЕ ломает"

# Укус 6 спеки: красное не кэшируется никогда.
D="$(mk c6)"; echo 1 > "$D/rc.txt"
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
cnt 2 "красный гейт не записан — второй раз гнался заново"
echo 0 > "$D/rc.txt"
chk 0 "после починки тот же sha даёт зелёное" "гейт зелёный"
```

- [ ] **Шаг 2: прогнать стенд, убедиться, что глава «кэш» красная**

```
bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: 26 ✅ и ❌ на всех укусах кэша — кэша нет, гейт гоняется каждый раз,
`cnt` видит 2 там, где ждёт 1.

⚠️ Красным обязан быть и укус 6 наоборот: он ждёт **2** прогона и сейчас их и получает,
то есть проходит зелёным по случайности. Это нормально — он сторожит будущую ошибку
«записали fail», а не сегодняшнее отсутствие кэша.

- [ ] **Шаг 3: добавить хранилище вердиктов**

Вставить после `run_gate`:

```python
def session_id():
    return os.environ.get("CLAUDE_CODE_SESSION_ID") or f"pid:{os.getpid()}"


def env_fingerprint():
    """ДИАГНОСТИКА, а не ключ (решение Р5 плана).

    Вердикт по дереву переживает `pip install`. Отпечаток венва в ключе обесценивал
    бы кэш при установке любого постороннего инструмента, а ловил бы только редкий
    сценарий «пакет снесли, дерево не менялось». Устаревший венв ломается в
    безопасную сторону: гейт краснеет, красное не кэшируется. Поэтому отпечаток
    ЗАПИСЫВАЕТСЯ и показывается человеком в `memo list`, но решений по нему не
    принимается.
    """
    return {"python": sys.executable,
            "python_version": ".".join(str(x) for x in sys.version_info[:3])}


def verdict_path(ctx, gv):
    return VERDICTS / ctx.repo_id / f"{ctx.tree_sha}.{gv}.json"


def read_verdict(path):
    """Вердикт либо None. Битый файл — это отсутствие вердикта, а не авария."""
    try:
        d = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(d, dict) or d.get("result") != "pass":
        return None
    return d


def write_verdict(path, payload):
    """tmp + os.replace: файл вердикта либо целый, либо его нет.

    Имена файлов уникальны и писатель у каждого один, поэтому параллельность
    ~/.claude (4–6 сессий разом) им не вредит.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.parent / f"{path.name}.tmp-{os.getpid()}"
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)
```

Заменить `cmd_check` целиком:

```python
def cmd_check(a):
    ctx = context()
    cfgpath, gate, ext = load_config(ctx, a.config)
    gv, extparts = gate_version(ctx, ext)
    vp = verdict_path(ctx, gv)

    v = read_verdict(vp)
    if v:
        print(f"гейт пройден: дерево {ctx.tree_sha[:12]} · gv {gv} · "
              f"{v.get('recorded_at', '?')} · сессия {v.get('session', '?')}")
        return 0

    ok, took, _ = run_gate(ctx, gate)
    if not ok:
        return 1

    write_verdict(vp, {
        "tree_sha": ctx.tree_sha,
        "gate_version": gv,
        "repo_id": ctx.repo_id,
        "result": "pass",
        "recorded_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "host": socket.gethostname(),
        "session": session_id(),
        "worktree": str(ctx.toplevel),
        "duration_s": took,
        "commands": list(gate),
        "external": extparts,
        "env": env_fingerprint(),
    })
    print(f"гейт зелёный за {took} с. Вердикт записан: {vp}")
    return 0
```

- [ ] **Шаг 4: прогнать стенд**

```
bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: `итог: ✅ 34   ❌ 0`.

**И сразу вторая проверка — на заглушке.** Зелёный стенд говорит, что укусы
проходят; он НЕ говорит, что они что-нибудь сторожат. Прогон на вконец сломанном
инструменте отвечает на второй вопрос и стоит десять секунд:

```
printf 'import sys\nprint("заглушка")\nsys.exit(0)\n' > /tmp/memo-stub.py
MEMO=/tmp/memo-stub.py bash ~/.claude/scripts/memo-bite.sh
```

Ожидается `итог: ✅ 0   ❌ 34` — **ровно ноль зелёных**. Любой зелёный означает укус,
проходящий впустую: он сравнивает пустое с пустым, либо берёт иголкой строку, которую
инструмент печатает всегда. Найти, назвать и починить — это дефект укуса, а не заглушки.
Замер 08.09.2026: в задаче 1 так нашёлся ровно один такой укус из девяти.

Если красный «вердикт из ворктри A действует в ворктри B» — смотреть `repo_id`:
он обязан быть одинаков, задача 1 это уже проверяла, значит ломается путь вердикта.

- [ ] **Шаг 5: коммит**

```
cd ~/.claude
git add scripts/memo.py scripts/memo-bite.sh
git commit -m "мемо(1b-1): вердикт по дереву — кэш только pass, общий у ворктри"
git push
```

---

### Задача 5: три страховки — грязь, чужой хост, неотслеживаемый конфиг

Задача 4 сделала кэш работающим. Эта делает его **не врущим**. Каждая страховка закрывает
свой способ получить ложную зелень.

**Файлы:**
- Изменить: `~/.claude/scripts/memo.py` (`cacheable`, правка `read_verdict` и `cmd_check`)
- Изменить: `~/.claude/scripts/memo-bite.sh` (глава «страховки»)

**Стыки:**
- Потребляет: всё из задач 1–4.
- Отдаёт: `cacheable(ctx, cfgpath) -> (bool, str | None)` — можно ли доверять кэшу и
  почему нет. `read_verdict(path)` получает вторую половину: отказ от вердикта чужого хоста.

- [ ] **Шаг 1: дописать укусы**

```bash
echo
echo "=== страховки ==="

# Грязное дерево: tree_sha описывает HEAD, а гоняется рабочая копия. Это РАЗНЫЕ
# деревья, и вердикт по первому ничего не говорит о втором.
D="$(mk s1)"
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
echo changed > "$D/a.txt"
chk 0 "грязное дерево — гоним, а не отказываем" "кэш выключен"
cnt 2 "грязное дерево кэш НЕ использует"
git -C "$D" checkout -q -- a.txt
chk 0 "дерево снова чистое — берётся ПЕРВЫЙ вердикт" "гейт пройден"
cnt 2 "на грязном дереве вердикт не записывался: третьего прогона не было"

# Инвариант 2: вердикт локален. ~/.claude однажды кто-нибудь засинхронит.
D="$(mk s2)"
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
# Область поиска — каталог ЭТОГО репозитория. Все временные репозитории стенда
# имеют ОДИНАКОВЫЙ tree_sha (содержимое файлов совпадает), и `find | head -1` по
# всему MEMO_HOME правил бы чужой вердикт.
rid="$(cd "$D" && python3 "$M" list | sed -n 's/^репозиторий: \([^ ]*\).*/\1/p')"
vf="$(ls "$MEMO_HOME/gate-verdicts/$rid"/*.json | head -1)"
python3 - "$vf" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["host"] = "чужая-машина"
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
chk 0 "вердикт с ЧУЖОГО хоста не берётся, факт напечатан" "на другом хосте"
cnt 2 "чужой хост — гейт гнался заново"

# Неотслеживаемый deploy.json: под --untracked-files=no он невидим, значит
# подмена команд гейта прошла бы мимо и грязи, и tree_sha.
D="$(mk s3)"
git -C "$D" rm -q --cached deploy.json; git -C "$D" commit -qm "конфиг вне git"
chk 0 "неотслеживаемый deploy.json — гоним, кэш выключен" "не отслеживается"
cnt 1 "прогон при выключенном кэше состоялся"
chk 0 "и во второй раз тоже гоним" "кэш выключен"
cnt 2 "неотслеживаемый конфиг кэш НЕ использует"
```

- [ ] **Шаг 2: прогнать стенд, убедиться, что глава «страховки» красная**

```
bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: 34 ✅ и ❌ на страховках. В частности `чужой хост` даст `гейт пройден`
вместо прогона — то есть ровно ложную зелень, ради которой укус написан.

- [ ] **Шаг 3: добавить `cacheable` и подключить её**

Вставить после `config_tracked`:

```python
def cacheable(ctx, cfgpath):
    """Можно ли доверять кэшу на этом дереве — и если нет, то почему словами.

    Обе причины ведут к одному: то, что гоняется, не совпадает с тем, что описывает
    ключ. Грязное дерево — HEAD^{tree} описывает НЕ рабочую копию. Неотслеживаемый
    конфиг — команды гейта не покрыты tree_sha (решение Р3 плана), и подмена
    команд прошла бы мимо и грязи, и ключа.
    """
    if ctx.dirty:
        return False, f"дерево грязное, правлено отслеживаемых файлов: {len(ctx.dirty)}"
    if not config_tracked(ctx, cfgpath):
        return False, f"{cfgpath.name} не отслеживается git — команды гейта деревом не покрыты"
    return True, None
```

В `read_verdict` добавить проверку хоста перед `return d`:

```python
    if d.get("host") != socket.gethostname():
        print(f"вердикт снят на другом хосте ({d.get('host')}) — не беру: "
              f"инвариант 2, зависящее от среды не делится между машинами")
        return None
    return d
```

Заменить тело `cmd_check` между `vp = verdict_path(...)` и `ok, took, _ = run_gate(...)` на:

```python
    can_cache, why = cacheable(ctx, cfgpath)
    if can_cache:
        v = read_verdict(vp)
        if v:
            print(f"гейт пройден: дерево {ctx.tree_sha[:12]} · gv {gv} · "
                  f"{v.get('recorded_at', '?')} · сессия {v.get('session', '?')}")
            return 0
    else:
        print(f"кэш выключен: {why}")
```

и обернуть запись вердикта:

```python
    if not can_cache:
        print(f"гейт зелёный за {took} с. Вердикт НЕ записан: {why}")
        return 0

    write_verdict(vp, { ... как в задаче 4, без изменений ... })
    print(f"гейт зелёный за {took} с. Вердикт записан: {vp}")
    return 0
```

- [ ] **Шаг 4: прогнать стенд**

```
bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: `итог: ✅ 44   ❌ 0`.

**И сразу вторая проверка — на заглушке.** Зелёный стенд говорит, что укусы
проходят; он НЕ говорит, что они что-нибудь сторожат. Прогон на вконец сломанном
инструменте отвечает на второй вопрос и стоит десять секунд:

```
printf 'import sys\nprint("заглушка")\nsys.exit(0)\n' > /tmp/memo-stub.py
MEMO=/tmp/memo-stub.py bash ~/.claude/scripts/memo-bite.sh
```

Ожидается `итог: ✅ 0   ❌ 44` — **ровно ноль зелёных**. Любой зелёный означает укус,
проходящий впустую: он сравнивает пустое с пустым, либо берёт иголкой строку, которую
инструмент печатает всегда. Найти, назвать и починить — это дефект укуса, а не заглушки.
Замер 08.09.2026: в задаче 1 так нашёлся ровно один такой укус из девяти.

- [ ] **Шаг 5: коммит**

```
cd ~/.claude
git add scripts/memo.py scripts/memo-bite.sh
git commit -m "мемо(1b-1): три страховки от ложной зелени — грязь, чужой хост, конфиг вне git"
git push
```

---

### Задача 6: `list` с вердиктами и `forget`

Кэш без способа посмотреть и сбросить — оракул, с которым нельзя спорить. И укусы
задач 4–5 без `forget` ставились бы только на свежих временных репозиториях.

**Файлы:**
- Изменить: `~/.claude/scripts/memo.py` (переписать `cmd_list`, добавить `cmd_forget`)
- Изменить: `~/.claude/scripts/memo-bite.sh` (глава «посмотреть и сбросить»)

**Стыки:**
- Потребляет: всё из задач 1–5.
- Отдаёт: `memo.py list [--all] [--config PATH]`, `memo.py forget (--current | --all | <tree_sha>)`.
  Оба всегда выходят кодом 0, если репозиторий определился: это инструменты человека,
  а не сторожа, и «нечего забывать» — ответ, а не ошибка (инвариант 4).

- [ ] **Шаг 1: дописать укусы**

```bash
echo
echo "=== посмотреть и сбросить ==="

# Иголка — СЕССИЯ, а не sha дерева: sha печатается строкой «дерево HEAD:» всегда,
# и укус на нём проходил бы зелёным при полностью отсутствующей таблице.
D="$(mk f1)"
(cd "$D" && CLAUDE_CODE_SESSION_ID=опознавательная python3 "$M" check >/dev/null 2>&1)
ARG="list"; chk 0 "list показывает строку записанного вердикта" "опознавательная"
ARG="list"; chk 0 "list помечает вердикт ТЕКУЩЕГО дерева стрелкой" "→"

D="$(mk f2)"
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
(cd "$D" && python3 "$M" forget --current >/dev/null 2>&1)
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
cnt 2 "forget --current заставляет гнать заново"

D="$(mk f3)"
ARG="forget --current"; chk 0 "forget на пустом кэше — ответ, а не ошибка" "нечего забывать"

D="$(mk f4)"
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
echo y >> "$D/a.txt"; git -C "$D" add -A; git -C "$D" commit -qm two
(cd "$D" && python3 "$M" check >/dev/null 2>&1)
(cd "$D" && python3 "$M" forget --all >/dev/null 2>&1)
left="$(cd "$D" && python3 "$M" list | grep -c '^[→ ][0-9a-f]' || true)"
if [ "$left" = 0 ]; then echo "  ✅ forget --all вычищает оба вердикта"; pass=$((pass+1))
else echo "  ❌ forget --all оставил $left"; fail=$((fail+1)); fi
```

- [ ] **Шаг 2: прогнать стенд, убедиться, что новая глава красная**

```
bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: 44 ✅, ❌ на всех укусах главы (`list` печатает «вердиктов нет» жёстко,
`forget` не существует).

- [ ] **Шаг 3: переписать `cmd_list` и добавить `cmd_forget`**

```python
def _load_rows(dirs):
    rows = []
    for d in dirs:
        if not d.is_dir():
            continue
        for f in sorted(d.glob("*.json")):
            try:
                v = json.loads(f.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if isinstance(v, dict):
                rows.append(v)
    return rows


def cmd_list(a):
    ctx = context()
    print(f"репозиторий: {ctx.repo_id}   ({ctx.common})")
    print(f"дерево HEAD: {ctx.tree_sha}")
    print(f"грязное:     {'да, файлов ' + str(len(ctx.dirty)) if ctx.dirty else 'нет'}")
    try:
        cfgpath, gate, ext = load_config(ctx, a.config)
        gv, _ = gate_version(ctx, ext)
        print(f"ключ gv:     {gv}   ({len(ext)} внешних входов, {len(gate)} команд)")
        can, why = cacheable(ctx, cfgpath)
        if not can:
            print(f"кэш:         выключен — {why}")
    except SystemExit:
        print("ключ gv:     — (конфига нет либо он невалиден)")

    dirs = sorted(VERDICTS.glob("*")) if a.all else [VERDICTS / ctx.repo_id]
    rows = _load_rows(dirs)
    if not rows:
        print("вердиктов нет")
        return 0
    print()
    print(f"  {'дерево':13} {'gv':13} {'снят':20} {'хост':14} {'python':10} сессия")
    for v in sorted(rows, key=lambda r: r.get("recorded_at", ""), reverse=True):
        mark = "→" if v.get("tree_sha") == ctx.tree_sha else " "
        env = v.get("env", {}) or {}
        print(f"{mark} {v.get('tree_sha', '')[:12]:13} {v.get('gate_version', ''):13} "
              f"{v.get('recorded_at', '')[:19]:20} {str(v.get('host', ''))[:13]:14} "
              f"{str(env.get('python_version', ''))[:9]:10} {v.get('session', '')}")
    return 0


def cmd_forget(a):
    ctx = context()
    d = VERDICTS / ctx.repo_id
    if a.all:
        targets = sorted(d.glob("*.json"))
    elif a.current:
        targets = sorted(d.glob(f"{ctx.tree_sha}.*.json"))
    else:
        targets = sorted(d.glob(f"{a.tree_sha}*.json"))
    if not targets:
        print("нечего забывать")
        return 0
    for t in targets:
        t.unlink()
        print(f"забыт: {t.name}")
    return 0
```

В `main`:

```python
    p_list.add_argument("--all", action="store_true", help="по всем репозиториям")

    p_forget = sub.add_parser("forget", help="сбросить вердикт")
    g = p_forget.add_mutually_exclusive_group(required=True)
    g.add_argument("--current", action="store_true", help="вердикты текущего дерева")
    g.add_argument("--all", action="store_true", help="все вердикты этого репозитория")
    g.add_argument("tree_sha", nargs="?", help="префикс sha дерева")
    p_forget.set_defaults(fn=cmd_forget)
```

⚠️ `nargs="?"` внутри `required=True`-группы: argparse считает позиционный аргумент
«поданным» только когда он не `None`, поэтому голый `memo forget` отказывает, как и надо.
Проверить это отдельно — поведение неочевидное:

```
cd ~/.claude && python3 scripts/memo.py forget ; echo "rc=$?"
```
Ожидается: `error: one of the arguments --current --all tree_sha is required`, `rc=2`.

- [ ] **Шаг 4: прогнать стенд**

```
bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: `итог: ✅ 49   ❌ 0`.

**И сразу вторая проверка — на заглушке.** Зелёный стенд говорит, что укусы
проходят; он НЕ говорит, что они что-нибудь сторожат. Прогон на вконец сломанном
инструменте отвечает на второй вопрос и стоит десять секунд:

```
printf 'import sys\nprint("заглушка")\nsys.exit(0)\n' > /tmp/memo-stub.py
MEMO=/tmp/memo-stub.py bash ~/.claude/scripts/memo-bite.sh
```

Ожидается `итог: ✅ 0   ❌ 49` — **ровно ноль зелёных**. Любой зелёный означает укус,
проходящий впустую: он сравнивает пустое с пустым, либо берёт иголкой строку, которую
инструмент печатает всегда. Найти, назвать и починить — это дефект укуса, а не заглушки.
Замер 08.09.2026: в задаче 1 так нашёлся ровно один такой укус из девяти.

- [ ] **Шаг 5: коммит**

```
cd ~/.claude
git add scripts/memo.py scripts/memo-bite.sh
git commit -m "мемо(1b-1): list и forget — с кэшем должно быть можно спорить"
git push
```

---

### Задача 7: доказать, что стенд умеет краснеть

Зелёный стенд, ни разу не покрасневший, ничего не доказывает. В этом репозитории гейт
свежести оказывался **молча инертен дважды** (`-uall` 05.09.2026, `core.quotePath`
06.09.2026), и оба раза скрипт печатал успех. Здесь то же самое проверяется нарочно.

**Файлы:**
- Изменить: `~/.claude/scripts/memo-bite.sh` (дописать шапку — результаты этой задачи)
- Временно: `/private/tmp/.../scratchpad/memo-broken-N.py` — ломаные копии, в репозиторий не кладутся

**Стыки:**
- Потребляет: `memo.py` и `memo-bite.sh` в законченном виде.
- Отдаёт: строку в шапке стенда с числом красных на каждой ломаной копии. Это и есть
  свидетельство, что укусы что-то сторожат.

- [ ] **Шаг 1: сломать проверку хоста и убедиться, что стенд это видит**

```
cd ~/.claude
cp scripts/memo.py /tmp/memo-broken-1.py
```

В копии удалить в `read_verdict` две строки проверки хоста (`if d.get("host") != ...`
и её `print`), оставив `return d`. Затем:

```
MEMO=/tmp/memo-broken-1.py bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: **ровно 2 ❌** — «вердикт с ЧУЖОГО хоста не берётся» и «чужой хост — гейт
гнался заново». Если 0 ❌ — укус ничего не сторожит, чинить укус, а не копию.

- [ ] **Шаг 2: сломать проверку грязи**

```
cp ~/.claude/scripts/memo.py /tmp/memo-broken-2.py
```

В копии в `cacheable` заменить `if ctx.dirty:` на `if False:`. Затем:

```
MEMO=/tmp/memo-broken-2.py bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: **≥3 ❌** в главе «страховки» (укусы грязного дерева) и **0 ❌** в главах
«кэш» и «прогон» — иначе укусы главы «страховки» подтекают в соседние.

- [ ] **Шаг 3: сломать инвариант 7 — записать красное**

```
cp ~/.claude/scripts/memo.py /tmp/memo-broken-3.py
```

В копии в `cmd_check` заменить

```python
    ok, took, _ = run_gate(ctx, gate)
    if not ok:
        return 1
```
на
```python
    ok, took, _ = run_gate(ctx, gate)
    # СЛОМАНО НАРОЧНО: вердикт пишется и на красном гейте (нарушение инварианта 7)
```

и в самом конце `cmd_check` заменить `return 0` на `return 0 if ok else 1`.
Поле `"result"` оставить `"pass"` — **именно так, а не `"fail"`**: `read_verdict`
отвергает всё, кроме `pass`, и «честно записанный fail» был бы отвергнут при
чтении, то есть поломка не проявилась бы и укус зря прошёл бы зелёным. Ломается
ровно инвариант 7 — красное попадает в кэш как зелёное. Код возврата при этом
остаётся честным: ломается запись, а не отчёт. Затем:

```
MEMO=/tmp/memo-broken-3.py bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: **≥2 ❌**, среди них обязательно «красный гейт не записан — второй раз гнался
заново». Это тот самый укус, который в задаче 4 проходил зелёным по случайности; здесь
выясняется, сторожит ли он что-нибудь.

- [ ] **Шаг 4: сломать `--path-format=absolute`**

```
cp ~/.claude/scripts/memo.py /tmp/memo-broken-4.py
```

В копии убрать `"--path-format=absolute", ` из вызова `git(...)` и заменить
`pathlib.Path(common).resolve()` на `pathlib.Path(common)`. Затем:

```
MEMO=/tmp/memo-broken-4.py bash ~/.claude/scripts/memo-bite.sh
```

Ожидается: **≥2 ❌** — «repo-id из ПОДКАТАЛОГА тот же» и «вердикт из ворктри A действует
в ворктри B». Это доказательство, что главный сценарий подпроекта действительно
проверяется, а не просто описан в спеке.

- [ ] **Шаг 5: записать результат в шапку стенда и убрать копии**

Дописать в комментарий-шапку `memo-bite.sh` после строки про краснеть:

```bash
# Проверка самого стенда 08.09.2026 — на нарочно сломанных копиях:
#   без проверки хоста         → 2 ❌ (страховки)
#   без проверки грязи         → 3 ❌ (страховки), соседние главы зелёные
#   с записью красного вердикта→ 2 ❌ (кэш)
#   без --path-format=absolute → 2 ❌ (положение в git, кэш между ворктри)
# Числа сверять после любой правки укусов: расхождение значит, что укус ослаб.
```

(числа подставить фактические, а не эти, если они разойдутся — и тогда объяснить
расхождение строкой рядом, а не молча заменить)

```
rm -f /tmp/memo-broken-*.py
cd ~/.claude
git add scripts/memo-bite.sh
git commit -m "мемо(1b-1): стенд доказал, что краснеет — четыре нарочных поломки"
git push
```

---

### Задача 8: первый боевой репозиторий и закрытие открытого вопроса спеки

**Файлы:**
- Создать: `~/dev/gmb_v2/deploy.json`
- Изменить: `~/.claude/specs/2026-09-08-deploy-as-tree-function.md` (глава «Открытые вопросы» и глава «Разделимость гейта»)
- Изменить: `~/.claude/handoff/redesign-1b-and-registry.md` (очередь работ)

**Стыки:**
- Потребляет: законченный `memo.py`.
- Отдаёт: работающий кэш на gmb_v2 и спеку без открытого вопроса про отпечаток.

⚠️ **`~/dev/gmb_v2` — чужой репозиторий с параллельными сессиями.** Перед правкой прочитать
его корневой `CLAUDE.md`: что нельзя делать автономно и есть ли `openspec/`. `deploy.json`
— новый файл, конфликта не даст, но коммитить его в gmb_v2 **отдельным коммитом и
не смешивая** с чем бы то ни было.

- [ ] **Шаг 1: завести `deploy.json` в gmb_v2**

```
cd ~/dev/gmb_v2
git status --short
```

Убедиться, что дерево чистое и на нужной ветке. Создать `deploy.json`:

```json
{
  "gate_pure": [
    "pytest -m \"not integration and not pg\" -q -n 12",
    "bunx vue-tsc -b"
  ],
  "gate_version_external": [],
  "gate_env": [],
  "gate_post": [],
  "targets": {},
  "allow_skips": []
}
```

⚠️ **`not pg` — это решение Р8 плана, а не опечатка.** Маркер `pg` (9 тестов,
`pyproject.toml`) исключается из кэшируемой части, потому что «без сервера фикстура
пропускает тесты сама, а с сервером они гоняются» — то есть команда даёт зелёное в двух
разных смыслах, и вердикт, снятый без Postgres, врал бы сессии с Postgres. Поля
`gate_env`, `gate_post`, `targets`, `allow_skips` пустые — они принадлежат 1b-3; здесь
они заведены пустыми, чтобы в файле сразу была видна его окончательная форма.

- [ ] **Шаг 2: боевой прогон — измерить, что кэш даёт**

```
cd ~/dev/gmb_v2
time python3 ~/.claude/scripts/memo.py check
time python3 ~/.claude/scripts/memo.py check
python3 ~/.claude/scripts/memo.py list
```

Ожидается: первый прогон — полный гейт с выводом pytest, строка
`гейт зелёный за <N> с. Вердикт записан:`; второй — мгновенный
`гейт пройден: дерево <12 hex> · gv <12 hex> · <дата> · сессия <id>`; `list` — одна
строка со стрелкой. **Записать оба времени** — они идут в отчёт владельцу и в спеку:
экономия этой поставки и есть разница между ними.

- [ ] **Шаг 3: проверить главный сценарий на живом репозитории**

Если у gmb_v2 есть второй ворктри — прогнать `memo check` в нём на том же коммите и
убедиться, что гейт не гонялся. Если ворктри нет, завести временный:

```
cd ~/dev/gmb_v2
git worktree add /tmp/gmb-memo-probe HEAD --detach
cd /tmp/gmb-memo-probe
python3 ~/.claude/scripts/memo.py check
cd ~/dev/gmb_v2
git worktree remove /tmp/gmb-memo-probe
```

Ожидается: `гейт пройден` мгновенно. Это подтверждение главного сценария на настоящем
репозитории, а не на фикстуре.

- [ ] **Шаг 4: коммит в gmb_v2**

```
cd ~/dev/gmb_v2
git add deploy.json
git commit -m "деплой: deploy.json — чистая часть гейта для memo (1b-1)"
```

Пуш — по правилам gmb_v2 (`_ship.md`: в ствол только через `scripts/land.sh`).
**Самостоятельно в `main` не пушить.**

- [ ] **Шаг 5: закрыть открытый вопрос в спеке**

Правка `~/.claude/specs/2026-09-08-deploy-as-tree-function.md` — read-modify-write по
якорю, файл работают несколько сессий.

Якорь 1 — в главе «Открытые вопросы» первый пункт начинается строкой
`- **Отпечаток установленного окружения в ключе.**`. Заменить весь пункт на:

```markdown
- ~~**Отпечаток установленного окружения в ключе.**~~ — **решён при реализации
  1b-1 (08.09.2026): в ключ НЕ входит, принято сознательно.** Локфайлы лежат в
  дереве и покрыты `tree_sha`; непокрыт только разрыв «венв отстал от локфайла»,
  и он ломается в безопасную сторону — устаревший венв даёт красный гейт, а
  красное не кэшируется. Опасен единственный сценарий: вердикт снят при лишнем
  пакете в венве, пакет снесли, дерево не менялось. Он редок, а `pip freeze` в
  ключе обесценивал бы кэш при установке любого постороннего инструмента.
  Механизм при этом есть: `gate_version_external` хэширует содержимое любых
  перечисленных путей, так что репозиторий, которому отпечаток нужен, включает
  его конфигом. Интерпретатор пишется в вердикт как **диагностика** и виден в
  `memo list`.
```

Якорь 2 — в главе «Разделимость гейта» абзац, начинающийся
`**Чисто по дереву:** `pytest -m "not integration"``. Дописать сразу после него:

```markdown
⚠️ **Поправка 08.09.2026, найдена при реализации 1b-1.** В `pyproject.toml` есть
ВТОРОЙ маркер, которого эта глава не видела: `pg` — 9 тестов, локальный Postgres,
«из гейта НЕ исключается: без сервера фикстура пропускает тесты сама». Значит
`-m "not integration"` даёт зелёное и с сервером, и без него — команда зависит от
среды, и вердикт, снятый без Postgres, соврал бы сессии с Postgres. Кэшируемая
часть поэтому — `pytest -m "not integration and not pg"`, а `pg` переезжает в
`gate_env` (1b-3, не кэшируется никогда). «Бесплатное покрытие» перестаёт быть
бесплатным ровно тогда, когда начинает врать.
```

- [ ] **Шаг 6: обновить очередь в хендоффе и закоммитить `~/.claude`**

В `~/.claude/handoff/redesign-1b-and-registry.md`, глава «Очередь работ», заменить
строку `1. **`writing-plans` на 1b-1** — это ты, см. «Твоё первое действие».` на:

```markdown
1. ~~`writing-plans` на 1b-1~~ — СДЕЛАНО, план
   `plans/2026-09-08-memo-tree-verdict.md`, реализация приземлена 08.09.2026.
   Следующая поставка — **1b-2 (аренда)**, отдельным планом.
```

🔴 `~/.claude/handoff/` **не в git** — правка хендоффа `git status` не покажет, и это
не значит, что она закоммичена. Проверять `git check-ignore -v handoff/`, а не `git status`.

```
cd ~/.claude
git status --short
git add specs/ plans/
git commit -m "спека(1b): открытый вопрос про отпечаток закрыт, маркер pg вычтен из чистой части"
git push
```

---

## Что эта поставка НЕ делает — и почему это не пропуск

- **`lease acquire gate:<tree_sha>`** — поставка 1b-2. До неё две сессии, обе промахнувшиеся
  мимо кэша, гонят гейт одновременно на общих двенадцати ядрах. Спека называет это прямо:
  «потеря экономии, не потеря корректности».
- **`deploy.py`, `state`, `ship`, коды 3–6** — поставка 1b-3.
- **Вызов `memo check` из `land.sh`** — стык, ради которого спека снимает половину кода 5
  («вердикт по `tree_sha` пишет `land.sh` под тем же замком, выкатка только читает»).
  Одна строка в чужом репозитории, но она меняет правило приземления и требует решения
  владельца gmb_v2. Не тащить сюда.
- **pre-push хук «мимо `land.sh` не мержить»** — спека называет его отдельной поставкой.
- **Сборка мусора в `gate-verdicts/`** — YAGNI. Файл вердикта ~600 байт; тысяча деревьев
  даст 600 КБ. Когда появится жалоба — появится и `forget --older-than`.

## Самопроверка плана

**Покрытие спеки.** Все шесть укусов главы «Укусы · memo-bite.sh» разложены по задачам:
1 и 2 → задача 4; 3, 4, 5, 6 → задача 4; страховки сверх спеки → задача 5.
Требования главы «1b-1 · Мемо по дереву» — `tree_sha` (задача 1),
`gate_version_external` (задача 2), определение грязи (задачи 1 и 5), «`fail` не
записывается никогда» (задача 4), `list` и `forget` (задача 6), «прогон не заворачивается
в конвейер» (задача 3, исполнено структурно). Хранилище `gate-verdicts/<repo-id>/` и вывод
`repo-id` из `--git-common-dir` — задачи 1 и 4. Открытый вопрос про отпечаток — решение Р5
и задача 8.

**Не покрыто намеренно:** `lease acquire gate:<tree_sha>` и укусы 7–13 спеки — они
принадлежат 1b-2 и 1b-3, и стенды у них свои (`lease-bite.sh`, `deploy-bite.sh`).

**Расхождение со спекой, названное вслух:** решение Р8 (маркер `pg`) правит главу
«Разделимость гейта». Спека утверждала чистоту по одному маркеру, замер нашёл второй.
Правка спеки — шаг 5 задачи 8, а не молчаливое отклонение.

**Согласованность имён.** `context/Ctx`, `load_config`, `gate_version`, `config_tracked`,
`cacheable`, `run_gate`, `verdict_path`, `read_verdict`, `write_verdict`, `session_id`,
`env_fingerprint`, `_load_rows`, `cmd_check`, `cmd_list`, `cmd_forget`, `die`, `git` —
каждое имя вводится ровно в одной задаче и дальше только вызывается. Поля вердикта
(`tree_sha`, `gate_version`, `repo_id`, `result`, `recorded_at`, `host`, `session`,
`worktree`, `duration_s`, `commands`, `external`, `env`) заданы в задаче 4 и читаются
задачами 5 и 6 под теми же именами.
