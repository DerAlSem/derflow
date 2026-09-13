# Пересборка derflow (правило / нужда / архив) — план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** пять движков derflow сжаты до слоёв правил под машинными бюджетами,
рассказы уехали в `archive/`, три новых сторожа стоят, `CHANGELOG.md` не существует.

**Architecture:** сторожа ставятся первыми (миграция идёт под их присмотром),
затем движки мигрируют по одному от дорогого к дешёвому. Каждая миграция — пара
«таблица классификации → архивные файлы → слой правил», проверяемая скриптом
`canon-budget.py` (бюджет + разрешимость ссылок). Точки загрузки канона не меняются.

**Tech Stack:** bash-хуки Claude Code (SessionStart/PreToolUse/Stop), python3
без зависимостей, git.

**Spec:** `specs/2026-09-13-derflow-rebuild-design.md` — план аргументирует от неё,
исполнителю читать обе.

## Global Constraints

- Репозиторий — `~/.claude`, работается ПАРАЛЛЕЛЬНО. Ворктри тут не изоляция:
  правки только read-modify-write по точному якорю, никогда перезапись файла
  целиком. Коммит после каждого таска, пуш сразу, `git status` до и после.
- Бюджеты движков (строк): `_lane-c` 120 · `_gates` 100 · `_capture` 120 ·
  `_ship` 80 · `_parallel` 80. Бюджет индекса памяти: 16 КБ (потолок харнесса ~24 КБ).
- Правило: 2–5 строк, триггер + предписание, ссылка `→ archive/<слаг>.md`.
  Рассказ, версия v4.x, числа замера — только в архиве.
- Архив: `skills/derflow/archive/`, по файлу на урок, НЕ грузится ничем.
- Дефолт классификации — архив. Экзамены: правило (сжатие без потери силы),
  нужда (машинный сигнал момента существует).
- Из охвата исключены: `waiting.py` (механику реестра не трогать — сторож
  бюджетов живёт отдельным скриптом), `hand.sh`, `_conformance-sweep.md`,
  `SKILL.md` (кроме одной строки про CHANGELOG в Task 9).
- Таблица классификации каждого движка показывается владельцу на ревью таска
  ДО переписывания движка. Черновики таблиц в этом плане — предложение
  исполнителя, не решение.
- `ack`/`taken`/`done` реестра отложки — только по прямой просьбе владельца.

---

### Task 1: `canon-budget.py` — сторож бюджетов и ссылок

**Files:**
- Create: `scripts/canon-budget.py`
- Modify: `settings.json` (блок `hooks.SessionStart[0].hooks` — добавить команду по якорю)

**Interfaces:**
- Produces: `python3 ~/.claude/scripts/canon-budget.py` → exit 0 и молчание,
  если всё в бюджетах и ссылки целы; exit 1 и строки `🔴 …` по одной на нарушение.
  Task 4–8 используют его как тест-цикл; человек зовёт его же руками
  (это и есть «дубль doctor» из спеки — waiting.py не трогаем).

- [ ] **Step 1: написать скрипт**

```python
#!/usr/bin/env python3
"""Сторож канона derflow: бюджеты движков, индекс памяти, разрешимость ссылок.

Молчит, когда всё в порядке. Каждое нарушение — одна строка 🔴. Зовётся хуком
SessionStart (рядом с дельтой реестра) и человеком напрямую — вторая роль и
есть «дубль doctor» из спеки: waiting.py по охвату не трогаем.
Спека: specs/2026-09-13-derflow-rebuild-design.md §4.
"""
import os, re, sys

D = os.path.expanduser("~/.claude/skills/derflow")
MEM = os.path.expanduser(
    "~/.claude/projects/-Users-deralsem--claude/memory/MEMORY.md")
BUDGET = {"_lane-c.md": 120, "_gates.md": 100, "_capture.md": 120,
          "_ship.md": 80, "_parallel.md": 80}
MEM_BUDGET = 16 * 1024
LINK = re.compile(r'archive/([\w\-.]+\.md)')

bad = []
for f, lim in BUDGET.items():
    p = os.path.join(D, f)
    if not os.path.exists(p):
        bad.append(f"канон: нет файла {f}"); continue
    n = sum(1 for _ in open(p, encoding="utf-8", errors="replace"))
    if n > lim:
        bad.append(f"канон: {f} — {n} строк при бюджете {lim}; "
                   f"рост оплачивается сжатием или уходит в архив")
    for m in LINK.finditer(open(p, encoding="utf-8", errors="replace").read()):
        if not os.path.exists(os.path.join(D, "archive", m.group(1))):
            bad.append(f"канон: {f} ссылается на archive/{m.group(1)} — файла нет")
if os.path.exists(MEM) and os.path.getsize(MEM) > MEM_BUDGET:
    bad.append(f"память: индекс {os.path.getsize(MEM)} байт при бюджете "
               f"{MEM_BUDGET} (потолок харнесса ~24 КБ обрежет МОЛЧА) — "
               f"сжимай или вытесняй")
for line in bad:
    print("🔴 " + line)
sys.exit(1 if bad else 0)
```

- [ ] **Step 2: прогнать — сейчас он ОБЯЗАН краснеть на все пять движков**

Run: `python3 ~/.claude/scripts/canon-budget.py; echo "exit=$?"`
Expected: пять строк `🔴 канон: …строк при бюджете…`, `exit=1`.
Это не поломка — это факт: канон над бюджетом. Миграция (Tasks 5–9) гасит
строки по одной. Если строк не пять или exit=0 — скрипт написан неверно.

- [ ] **Step 3: зарегистрировать в SessionStart по якорю**

В `settings.json` в массив hooks у `SessionStart` (там сейчас одна команда
`waiting.py wake`) добавить ВТОРЫМ элементом, правкой по якорю:

```json
{
 "type": "command",
 "command": "python3 $HOME/.claude/scripts/canon-budget.py",
 "timeout": 5
}
```

- [ ] **Step 4: проверить регистрацию**

Run:
```bash
python3 - <<'P'
import json, os
h = json.load(open(os.path.expanduser("~/.claude/settings.json")))["hooks"]["SessionStart"][0]["hooks"]
print(len(h), h[1]["command"])
P
```
Expected: `2 python3 $HOME/.claude/scripts/canon-budget.py`

- [ ] **Step 5: коммит**

```bash
cd ~/.claude && git add scripts/canon-budget.py settings.json
git commit -m "canon-budget: сторож бюджетов движков, индекса памяти и ссылок в архив" && git push
```

---

### Task 2: гейт второго круга критики

**Files:**
- Modify: `hooks/openspec-critique-gate.sh` (ветка для Task/Agent)
- Modify: `settings.json` (matcher `"Skill|Bash"` → `"Skill|Bash|Task|Agent"`)

**Interfaces:**
- Consumes: `.critique`-отметки, которые пишет `openspec-critique-record.sh`
  (формат: первая строка — хеш specs/, дальше режим и заметка).
- Produces: попытка запустить критиков (`Agent` с subagent_type
  `system-architect` или `gap-finder`) по заявке с ДЕЙСТВУЮЩЕЙ отметкой
  блокируется с текстом «круг был». Правка спеки после отметки распечатывает
  круг сама (хеш перестаёт сходиться) — это уже так работает, логика хеша общая.

- [ ] **Step 1: добавить ветку в case по якорю `Bash)`**

В `hooks/openspec-critique-gate.sh` в `case "$tool"` добавить ПЕРЕД веткой
`Bash)`:

```bash
  Task|Agent)
    sub=$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty')
    case "$sub" in
      system-architect|gap-finder) ;;
      *) exit 0 ;;
    esac
    # круг ОТКРЫВАЮТ — блокируем, если отметка по этой заявке ещё действует
    args=$(printf '%s' "$payload" | jq -r '.tool_input.prompt // empty')
    second_circle=1
    ;;
```

и в конце скрипта, где сейчас сравнивается хеш для apply/archive, добавить
симметричную развилку (точный якорь исполнитель находит по чтению хвоста
скрипта; формула хеша НЕ дублируется — используется уже вычисленный `cur`):

```bash
if [ "${second_circle:-0}" -eq 1 ]; then
  mark="$changes_dir/$id/.critique"
  if [ -f "$mark" ] && [ "$(head -1 "$mark")" = "$cur" ]; then
    echo "🔴 Круг критики по «$id» уже пройден по ТЕКУЩЕЙ редакции спеки" \
         "($(sed -n 2p "$mark")). Слой закрыт по счёту: один круг." \
         "Дальше — механика: check.py, дифф имён сценариев, N→SHALL." \
         "Каталог отговорок: skills/derflow/archive/critic-ceiling.md" >&2
    exit 2
  fi
  exit 0
fi
```

- [ ] **Step 2: расширить matcher в settings.json по якорю**

`"matcher": "Skill|Bash"` → `"matcher": "Skill|Bash|Task|Agent"`.

- [ ] **Step 3: проверить оба плеча руками**

Run (из каталога с openspec, где у заявки стоит свежая отметка):
`printf '{"tool_name":"Agent","tool_input":{"subagent_type":"gap-finder","prompt":"критика <change-id>"}}' | hooks/openspec-critique-gate.sh; echo "exit=$?"`
Expected: `exit=2` и текст «Круг критики … уже пройден».
Run то же с `subagent_type":"Explore"`: Expected `exit=0`, молчание.
Run в каталоге БЕЗ openspec: Expected `exit=0` (гейт молчит, где не применим).

- [ ] **Step 4: коммит**

```bash
cd ~/.claude && git add hooks/openspec-critique-gate.sh settings.json
git commit -m "гейт второго круга: машинный отказ вместо таблицы отговорок" && git push
```

---

### Task 3: reap-гейт полосы C

**Files:**
- Create: `hooks/openspec-reap-gate.sh`
- Modify: `settings.json` (новый блок `Stop`)

**Interfaces:**
- Produces: на Stop-событии сессии в репозитории с `openspec/` печатается по
  строке на каждую активную заявку с незакрытыми задачами: `заявка <id>: 9/28
  задач`. Не блокирует, только называет факт. В репо без openspec молчит.

- [ ] **Step 1: написать хук**

```bash
#!/usr/bin/env bash
# Reap-гейт полосы C: конец сессии называет незажатые заявки счётом задач.
# Спека: specs/2026-09-13-derflow-rebuild-design.md §3. Не блокирует.
set -uo pipefail
payload=$(cat)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
d=${cwd:-$PWD}
while [ "$d" != "/" ]; do
  [ -d "$d/openspec/changes" ] && break
  d=$(dirname "$d")
done
[ -d "$d/openspec/changes" ] || exit 0
command -v openspec >/dev/null || exit 0
cd "$d" || exit 0
openspec list --json 2>/dev/null | jq -r '
  .[]? | select(.completedTasks != null and .totalTasks != null
                and .completedTasks < .totalTasks)
  | "🔴 заявка \(.id // .name): \(.completedTasks)/\(.totalTasks) задач — жнётся, а не бросается"' \
  2>/dev/null || true
exit 0
```

- [ ] **Step 2: проверить на живом репо**

Run: `printf '{"cwd":"%s"}' ~/dev/gmb_v2 | hooks/openspec-reap-gate.sh`
Expected: строки `🔴 заявка …: N/M задач` по незакрытым заявкам gmb_v2 (их
сейчас ≥1) — либо тишина, если все закрыты. В `~/.claude`: тишина, exit 0.

- [ ] **Step 3: зарегистрировать Stop-хук**

В `settings.json` рядом с существующими событиями добавить по якорю:

```json
"Stop": [
 {
  "hooks": [
   {
    "type": "command",
    "command": "$HOME/.claude/hooks/openspec-reap-gate.sh",
    "timeout": 10
   }
  ]
 }
]
```

- [ ] **Step 4: коммит**

```bash
cd ~/.claude && git add hooks/openspec-reap-gate.sh settings.json
git commit -m "reap-гейт: счёт незакрытых задач заявок на Stop" && git push
```

---

### Task 4: каркас архива + переезд CHANGELOG

**Files:**
- Create: `skills/derflow/archive/README.md`
- Move: `skills/derflow/CHANGELOG.md` → `skills/derflow/archive/CHANGELOG.md`
- Modify: `skills/derflow/SKILL.md:221` (одна строка про CHANGELOG)

**Interfaces:**
- Produces: каталог `skills/derflow/archive/` с README-контрактом; Task 5–8
  кладут туда файлы уроков.

- [ ] **Step 1: README архива**

```markdown
# Архив derflow — рассказы, не правила

По файлу на урок: история промаха, версия v4.x, числа замера. В рантайм НЕ
грузится никогда и ничем — ни скиллом, ни хуком, ни извлечением. Читатель —
человек и сессия-разборщик по прямой просьбе. Правила движков ссылаются сюда
(`→ archive/<слаг>.md`); разрешимость ссылок сторожит `scripts/canon-budget.py`.
Спека пересборки: `specs/2026-09-13-derflow-rebuild-design.md`.
```

- [ ] **Step 2: переезд CHANGELOG и правка ссылки**

```bash
cd ~/.claude && git mv skills/derflow/CHANGELOG.md skills/derflow/archive/CHANGELOG.md
```

В `SKILL.md` строку `**История версий — \`CHANGELOG.md\` рядом.**…` править по
якорю на: `**История версий — \`archive/CHANGELOG.md\`.** Грузить не надо: это
рассказы, не правила.`

- [ ] **Step 3: проверить**

Run: `python3 scripts/canon-budget.py; grep -c 'CHANGELOG' skills/derflow/SKILL.md`
Expected: те же пять красных строк бюджета (не больше — ссылок-сирот нет), `1`.

- [ ] **Step 4: коммит**

```bash
cd ~/.claude && git add -A skills/derflow/ && git commit -m "архив derflow: каркас, CHANGELOG уехал целиком" && git push
```

---

### Task 5: миграция `_lane-c.md` (753 → ≤120)

**Files:**
- Modify: `skills/derflow/_lane-c.md`
- Create: `skills/derflow/archive/*.md` по таблице

**Interfaces:**
- Consumes: канон classification из спеки §1/§3; `canon-budget.py` из Task 1.
- Produces: слой правил ≤120 строк; каждая строка-правило со ссылкой в архив
  или на машинную проверку. Внутренний порядок глав сохранён.

- [ ] **Step 1: черновик таблицы классификации — показать владельцу на ревью ДО правок**

| глава (строки сегодня) | класс | носитель |
|---|---|---|
| Цикл (20–70) | правило | ~15 строк: цикл полосы как есть, он уже сжат |
| Reap-гейт заявки (71–217) | правило+нужда+архив | 4 строки + Stop-хук (Task 3) + `archive/reap-gate.md` |
| Lane C-drain (218–272) | правило+архив | ~8 строк порядка триажа + `archive/c-drain.md` |
| Спека читается первой (273–297) | правило | 3 строки |
| Внешние API и контракты (298–308) | правило | 3 строки (сам гейт — в `_gates`) |
| Входы в openspec (309–319) | правило | 4 строки |
| Критик-слой (320–550) | правило+нужда+архив | ~14 строк: условие деньги/права/ПД (решение владельца 13.09), один узкий круг парой, механика до/после, отметка сразу; гейт второго круга (Task 2); `archive/critic-ceiling.md` (потолок, цена 460k, кривые, отговорки), `archive/critic-narrow-circle.md` (узкая мишень, 0/8 против 8/8) |
| Ошибки этой полосы (732–753) | правило | сжать до 6 строк |

- [ ] **Step 2: написать архивные файлы** — содержимое = сегодняшние главы как
есть, с шапкой `# <название> (архив derflow, глава _lane-c до 13.09.2026)`.
Резать текст глав нельзя — они переезжают целиком.

- [ ] **Step 3: переписать `_lane-c.md` слоем правил** по таблице, сохранив
порядок глав. Каждое правило: триггер + предписание + `→ archive/<слаг>.md`.

- [ ] **Step 4: проверить**

Run: `python3 scripts/canon-budget.py`
Expected: строки про `_lane-c` НЕТ (≤120 и ссылки целы); остальные четыре 🔴 на месте.
Run: `git diff --stat skills/derflow/_lane-c.md` — убедиться, что это правка
одного файла, а не переезд.

- [ ] **Step 5: коммит**

```bash
cd ~/.claude && git add skills/derflow/ && git commit -m "_lane-c: слой правил + архив (таблица одобрена владельцем)" && git push
```

---

### Task 6: миграция `_gates.md` (628 → ≤100)

**Files:** Modify `skills/derflow/_gates.md`; Create `archive/*.md` по таблице.

**Interfaces:** как Task 5.

- [ ] **Step 1: черновик таблицы — владельцу на ревью**

| глава | класс | носитель |
|---|---|---|
| verify-гейт (7–65) | правило | ~10 строк |
| Внешне-контрактный гейт (66–77) | правило | 4 строки: контракт до парсера и до вердикта |
| UI = дизайн (78–94) | правило | 3 строки |
| «Набор зелёный» ≠ продукт (95–170) | правило+архив | 3 строки + `archive/green-suite.md` |
| Сторож проверяется укусом (171–326) | правило+нужда+архив | 3 строки + ссылка на пять `scripts/*-bite.sh` + `archive/bite-not-green.md` |
| Пустой вывод поиска (327–357) | правило | 3 строки: код возврата до вывода |
| Радиус фикса задаёт вызов (358–399) | правило+архив | 3 строки + `archive/fix-radius.md` |
| Инвариант на границу (400–478) | правило+архив | 3 строки + `archive/invariant-boundary.md` |
| Различающая сила на редкости (479–507) | правило+архив | 3 строки + `archive/rarity-power.md` |
| Замер не на тот вопрос (508–568) | правило+архив | 3 строки + `archive/wrong-question-measure.md` |
| Громкая половина прячет тихую (569–608) | правило+архив | 3 строки + `archive/loud-half.md` |
| Ошибки главы (609–628) | правило | 5 строк |

- [ ] **Step 2–5:** как в Task 5 (архив → слой правил → `canon-budget.py`
без строки `_gates` → коммит `"_gates: слой правил + архив"`).

---

### Task 7: миграция `_capture.md` (1265 → ≤120) + новый протокол захвата

**Files:** Modify `skills/derflow/_capture.md`; Create `archive/*.md`.

**Interfaces:** как Task 5. Дополнительно Produces: протокол захвата по спеке §4.

- [ ] **Step 1: черновик таблицы — владельцу на ревью**

| глава | класс | носитель |
|---|---|---|
| Граница проект/контекст (6–25) | правило | 4 строки |
| Контекст квадратичен (26–95) | правило+архив | 3 строки + ссылка `context-meter` + `archive/context-quadratic.md` |
| Граница хранилищ (96–219) | правило+архив | ~10 строк таблицы «где что» + `archive/storage-boundary.md` |
| Сессия живёт на снимке (220–259) | правило+архив | 3 строки + `archive/snapshot-canon.md` |
| Дрейф наблюдаем (260–318) | архив | `archive/canon-drift-live.md` — урок впитан хуком |
| Детектор промахивается без решения (319–373) | архив | `archive/drift-detector-miss.md` |
| Расщепление сессии (374–926) | правило+архив | ~15 строк протокола (порядок, hand.sh, здесь-и-сейчас) + `archive/session-split.md` (553 строки целиком) |
| Закрытие с долгами ≠ сплит (927–1021) | правило+архив | 3 строки + `archive/close-with-debts.md` |
| Опрос сестринских (1022–1074) | правило+архив | 3 строки + `archive/sibling-silence.md` |
| Метр на реплике (1075–1102) | архив | `archive/meter-replica.md` — впитан кодом |
| Где происходит захват (1103–1135) | правило | ЗАМЕНЯЕТСЯ новым протоколом |
| Гигиена памяти (1136–1212) | правило | ~8 строк + ссылка `check.py`, бюджет 16 КБ |
| Ошибки главы (1213–1265) | правило | 5 строк |

- [ ] **Step 2: новый протокол захвата** — в слой правил, дословно по спеке §4:

```markdown
## Захват урока (в конце полосы)
1. Рассказ — СНАЧАЛА в `archive/<слаг>.md`: дата, промах, числа. Всегда.
2. Экзамен на правило: сжался до 2–5 строк, меняющих решение под давлением, —
   строки в слой правил движка со ссылкой на архив. Бюджет сторожит
   `scripts/canon-budget.py`: движок полон — сожми/слей существующие или
   оставь урок архивом. Это штатный исход, не поражение.
3. Экзамен на нужду: есть машинный сигнал момента — пиши проверку по образцу
   `hooks/canon-drift.py`, регистрируй в settings.json.
4. Версий v4.x больше нет: хронология — имя файла и дата в архиве.
```

- [ ] **Step 3–5:** как в Task 5 (проверка: `canon-budget.py` без строки
`_capture`; коммит `"_capture: слой правил + архив + новый протокол захвата"`).

---

### Task 8: миграция `_ship.md` (228 → ≤80) и `_parallel.md` (221 → ≤80)

**Files:** Modify оба движка; Create `archive/*.md`.

**Interfaces:** как Task 5. Два движка в одном таске: они самые короткие, но
коммиты РАЗДЕЛЬНЫЕ — откат гранулярный.

- [ ] **Step 1: черновики таблиц — владельцу на ревью**

`_ship.md`: Lane F (23–72) → правило ~8 строк; Ops-полоса (73–92) → правило
~6 строк; изоляция ≠ деплой-таргет (93–137) → правило 3 строки +
`archive/deploy-target-surface.md`; ветка интеграции (138–210) → правило
4 строки + `archive/integration-branch.md`; ошибки (211–228) → 4 строки.

`_parallel.md`: параллельность по умолчанию (21–43) → правило 4 строки; чужой
код = интеграция (44–65) → правило 3 строки; ворктри жнутся (66–89) → правило
4 строки; новый запрос = новая ветка и сессия (90–121) → правило 4 строки +
`archive/new-request-new-branch.md`; изоляция достаёт не везде (122–209) →
правило 5 строк + `archive/isolation-surfaces.md`; ошибки (210–221) → 4 строки.

- [ ] **Step 2–4:** для КАЖДОГО движка отдельно: архив → слой правил →
`python3 scripts/canon-budget.py` (его строка гаснет) → коммит
(`"_ship: слой правил + архив"`, затем `"_parallel: слой правил + архив"`), пуш.

---

### Task 9: сквозная сверка и приёмка

**Files:**
- Modify: `skills/derflow/SKILL.md:171-186` (таблица «Движки» — состав описаний,
  если содержимое движков в ней разъехалось с новыми слоями правил)
- Проверка: `hooks/canon-drift.py`, `CLAUDE.md` — упоминания движков живы

**Interfaces:** Consumes всё выше.

- [ ] **Step 1: полная механика**

```bash
python3 ~/.claude/scripts/canon-budget.py; echo "exit=$?"
grep -rn 'CHANGELOG' ~/.claude/skills/derflow/SKILL.md ~/.claude/CLAUDE.md ~/.claude/hooks/*.py | grep -v archive
ls ~/.claude/skills/derflow/archive/ | wc -l
```

Expected: `exit=0`, молчание сторожа; грep пуст (все упоминания ведут в архив);
в архиве ≥ 20 файлов + CHANGELOG + README.

- [ ] **Step 2: суммарный вес полосы C**

Run: `wc -l ~/.claude/skills/derflow/{SKILL.md,_lane-c.md,_gates.md,_capture.md}`
Expected: сумма ≤ 570 строк (≈ 8–10 тыс. токенов — критерий спеки).

- [ ] **Step 3: строка отложки на недельную проверку** (из каталога `~/.claude`)

```bash
python3 ~/.claude/scripts/waiting.py new "derflow пересобран: полоса C ≤10k токенов канона — проверить прогоном cacheread-mix.py через неделю жизни"
```

(`entry` строки: репо `~/.claude`, ветка `main`, спека
`specs/2026-09-13-derflow-rebuild-design.md`. Гасить строку — только владелец.)

- [ ] **Step 4: финальный коммит**

```bash
cd ~/.claude && git add -A skills/derflow/ && git commit -m "derflow: пересборка завершена — пять слоёв правил, архив, сторожа зелёные" && git push
```
