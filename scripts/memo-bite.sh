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
cnt() {  # cnt <ожидаемое число прогонов> <ярлык>
  got="$(runs "$D")"
  if [ "$got" = "$1" ]; then echo "  ✅ $2 (прогонов: $got)"; pass=$((pass+1))
  else echo "  ❌ $2 — ждали прогонов $1, получили $got"; fail=$((fail+1)); fi
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

echo
echo "итог: ✅ $pass   ❌ $fail"
[ "$fail" = 0 ]
