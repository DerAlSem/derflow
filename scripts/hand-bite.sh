#!/usr/bin/env bash
# Стенд укуса hand.sh: каждый гейт ломается нарочно и обязан покраснеть.
#
#   bash ~/.claude/scripts/hand-bite.sh            # текущий скрипт
#   HAND=/путь/к/старому bash ~/.claude/scripts/hand-bite.sh
#
# Зачем он лежит в репозитории, а не в скрэтчпаде: гейт свежести оказывался
# МОЛЧА ИНЕРТЕН дважды (`-uall` 05.09.2026, `core.quotePath` 06.09.2026), и оба
# раза дефект был невидим — скрипт печатал успех. Стенд, живущий в сессии,
# умирает вместе с ней и второй раз не ловит. Прогонять после любой правки
# подбора или гейтов.
#
# Проверка самого стенда: на скрипте ДО правки 06.09.2026 он даёт 9 красных из
# 11. Зелёный стенд, ни разу не покрасневший, ничего не доказывает.
H="${HAND:-$HOME/.claude/scripts/hand.sh}"
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
pass=0; fail=0

mk() {  # mk <имя> <ветка>  → печатает путь к свежему репо
  d="$ROOT/$1"; mkdir -p "$d"; cd "$d"
  git init -q -b "$2" . ; git config user.email t@t; git config user.name t
  echo x > .keep; git add -A; git commit -qm init
  printf '%s' "$d"
}
chk() {  # chk <ожидаемый rc> <ярлык> [<подстрока в выводе>]
  want="$1"; label="$2"; needle="${3:-}"
  out="$(bash "$H" -n "$D" ${ARG:-} 2>&1)"; rc=$?
  ok=1
  [ "$rc" = "$want" ] || ok=0
  [ -n "$needle" ] && { printf '%s' "$out" | grep -q -- "$needle" || ok=0; }
  if [ "$ok" = 1 ]; then echo "  ✅ $label (rc=$rc)"; pass=$((pass+1))
  else echo "  ❌ $label — ждали rc=$want${needle:+ и «$needle»}, получили rc=$rc"; echo "$out" | sed 's/^/       /'; fail=$((fail+1)); fi
  ARG=""
}

echo "=== RED: то, ради чего гейты и стоят ==="

D="$(mk red5 feature/x)"
printf '# чужой хендофф другой линии\n\nсостояние\n' > "$D/HANDOFF.md"
git -C "$D" add -A; git -C "$D" commit -qm h
chk 5 "корневой хендофф без «ветка:» — ОТКАЗ, а не подмена" "НЕ ОБЪЯВЛЯЕТ ВЕТКУ"

D="$(mk red6 feature/y)"
mkdir -p "$D/.claude/handoff"
printf 'ветка: feature/y\nимя: T·первый\n' > "$D/.claude/handoff/один.md"
printf 'ветка: feature/y\nимя: T·второй\n' > "$D/.claude/handoff/два.md"
git -C "$D" add -A; git -C "$D" commit -qm h
chk 6 "два хендоффа на одну ветку — ОТКАЗ со списком" "НЕСКОЛЬКО"

D="$(mk red3 feature/z)"
mkdir -p "$D/.claude/handoff"
printf 'ветка: feature/ЧУЖАЯ\nимя: T·чужой\n' > "$D/.claude/handoff/чужой.md"
printf '# корень\n' > "$D/HANDOFF.md"
git -C "$D" add -A; git -C "$D" commit -qm h
chk 5 "чужая ветка в .claude/handoff не подбирается, корень отказывает" ""

D="$(mk red3b feature/w)"
printf 'ветка: feature/ДРУГАЯ\nимя: T·чужой\n' > "$D/HANDOFF.md"
git -C "$D" add -A; git -C "$D" commit -qm h
chk 3 "явно объявленная ЧУЖАЯ ветка — прежний отказ цел" "ОТ ДРУГОЙ ЗАДАЧИ"

D="$(mk red2 feature/f)"
mkdir -p "$D/.claude/handoff"
printf 'ветка: feature/f\nимя: T·свежесть\n' > "$D/.claude/handoff/тема.md"
git -C "$D" add -A; git -C "$D" commit -qm h
sleep 1; echo "новая правка" > "$D/после.txt"
chk 2 "несвежий хендофф (ASCII-имя правки) — отказ" "СТАРШЕ"

D="$(mk red2cyr feature/c)"
mkdir -p "$D/.claude/handoff"
printf 'ветка: feature/c\nимя: T·кириллица\n' > "$D/.claude/handoff/тема.md"
git -C "$D" add -A; git -C "$D" commit -qm h
sleep 1; echo "правка" > "$D/новый-файл.txt"
chk 2 "несвежесть по КИРИЛЛИЧЕСКОМУ имени — гейт больше не слеп" "СТАРШЕ"

D="$(mk red4 feature/n)"
mkdir -p "$D/.claude/handoff"
printf 'ветка: feature/n\nимя: без-буквы\n' > "$D/.claude/handoff/тема.md"
git -C "$D" add -A; git -C "$D" commit -qm h
chk 4 "имя не в каноничной форме — прежний отказ цел" "НЕ В КАНОННОЙ ФОРМЕ"

echo
echo "=== GREEN: то, что обязано проезжать ==="

D="$(mk gr1 feature/inbox-push-and-move-trace)"
mkdir -p "$D/.claude/handoff"
printf 'ветка: feature/inbox-push-and-move-trace\nимя: G·колокольчик\n' \
  > "$D/.claude/handoff/inbox-push-and-move-trace.md"
git -C "$D" add -A; git -C "$D" commit -qm h
chk 0 "ЧЕЛОВЕЧЕСКОЕ имя файла находится по шапке" "хендофф: .claude/handoff/inbox-push-and-move-trace.md"

D="$(mk gr2 feature/face-control-toggle)"
mkdir -p "$D/openspec/changes/face-control-toggle"
printf 'ветка: feature/face-control-toggle (ворктри .claude/worktrees/fct)\nимя: G·галка\n' \
  > "$D/openspec/changes/face-control-toggle/HANDOFF.md"
git -C "$D" add -A; git -C "$D" commit -qm h
chk 0 "ХВОСТ в строке «ветка:» больше не ломает совпадение" "openspec/changes/face-control-toggle/HANDOFF.md"

D="$(mk gr3 feature/q)"
printf 'без шапки вовсе\n' > "$D/мой.md"
git -C "$D" add -A; git -C "$D" commit -qm h
ARG="мой.md"
chk 0 "явный файл без «ветка:» — предупреждение, не отказ 5" "принадлежность не проверяется"

D="$(mk gr4 main)"
mkdir -p "$D/handoff"
printf 'ветка: main\nимя: C·единственный\n' > "$D/handoff/тема.md"
git -C "$D" add -A; git -C "$D" commit -qm h
chk 0 "один хендофф на стволе — проезжает" "handoff/тема.md"

echo
echo "итог: ✅ $pass   ❌ $fail"
[ "$fail" = 0 ]
