#!/usr/bin/env bash
# Стенд укуса waiting.py: каждое утверждение о строке и хранилище ломается нарочно.
#
#   bash ~/.claude/scripts/waiting-bite.sh
#   WAITING=/путь/к/сломанной/копии bash ~/.claude/scripts/waiting-bite.sh
#
# Зачем в репозитории, а не в скрэтчпаде: сторож, чей стенд умирает вместе с
# сессией, второй раз дефекта не ловит.
#
# 🔴 ПРАВИЛО УКУСА. Утверждение «rc=0 и больше ничего» — не укус: заглушка,
# которая ничего не делает и выходит нулём, проходит его зелёным. Каждый укус
# обязан сверять ЛИБО ненулевой код, ЛИБО содержимое вывода, ЛИБО файл на диске.
# Приём поставки 1b-1 нашёл пять укусов, проходивших впустую, — искали именно так.
#
# Оснастка: `wt` гоняет waiting.py и кладёт вывод в $out, код в $rc; `has`/`nohas`
# смотрят $out; `is` печатает вердикт. Идиома вызова:
#   wt "$D" new "заголовок"
#   { [ "$rc" = 0 ] && has "заведена:"; }; is "ярлык укуса" $?
set -u
W="${WAITING:-$HOME/.claude/scripts/waiting.py}"
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
export WAITING_HOME="$ROOT/home"     # ящик, кэш и корни — НЕ в живой ~/.claude
mkdir -p "$WAITING_HOME" "$ROOT/repos"
# ~/.claude в жизни — репозиторий git, и стенд обязан воспроизводить это, иначе
# особый случай «ящик дома» проверяется не на том, на чём он живёт.
git -C "$WAITING_HOME" init -q -b main .
git -C "$WAITING_HOME" config user.email t@t
git -C "$WAITING_HOME" config user.name t
echo x > "$WAITING_HOME/a.txt"
git -C "$WAITING_HOME" add -A; git -C "$WAITING_HOME" commit -qm init
printf '%s\n' "$ROOT/repos" > "$WAITING_HOME/waiting-roots.txt"
pass=0; fail=0; out=""; rc=0
TODAY="$(date +%Y-%m-%d)"
PLUS30="$(date -v+30d +%Y-%m-%d)"    # BSD date: стенд macOS-только, как и 1b-1
PLUS7="$(date -v+7d +%Y-%m-%d)"

mk() {  # mk <имя> → печатает путь к свежему репозиторию под корнем скана
  d="$ROOT/repos/$1"; mkdir -p "$d"
  git -C "$d" init -q -b main .
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo x > "$d/a.txt"
  git -C "$d" add -A; git -C "$d" commit -qm init
  printf '%s' "$d"
}
wt() {  # wt <каталог> <аргументы waiting.py…> → $out, $rc
  d="$1"; shift
  out="$(cd "$d" && python3 "$W" "$@" 2>&1)"; rc=$?
}
has()   { printf '%s' "$out" | grep -q -- "$1"; }
nohas() { ! printf '%s' "$out" | grep -q -- "$1"; }
inf()   { grep -q -- "$2" "$1" 2>/dev/null; }   # inf <файл> <подстрока>
is() {  # is <ярлык> <0 если утверждение верно>
  if [ "${2:-1}" = 0 ]; then echo "  ✅ $1"; pass=$((pass+1))
  else
    echo "  ❌ $1 — rc=$rc"
    printf '%s\n' "$out" | sed 's/^/       /'
    fail=$((fail+1))
  fi
}
one() { ls "$1" 2>/dev/null | head -1; }        # one <каталог> → первое имя

echo "=== заведение строки ==="

D="$(mk rk_bot)"
wt "$D" new "ОФД в rk_bot — ждёт первого боевого платежа"
{ [ "$rc" = 0 ] && has "заведена:"; }; is "new говорит, что строка заведена" $?
{ has "rk_bot-"; }; is "new печатает ПОЛНЫЙ id — имя репозитория в нём есть" $?
{ [ -d "$D/.claude/waiting" ]; }; is "new завёл ящик <repo>/.claude/waiting/" $?
f="$(one "$D/.claude/waiting")"
{ printf '%s' "$f" | grep -Eq '^[0-9]{8}-[0-9]{2}\.md$'; }
is "имя файла — ровно YYYYMMDD-NN.md, без pid и без суффиксов" $?
{ inf "$D/.claude/waiting/$f" 'title: "ОФД в rk_bot'; }
is "заголовок лёг в title и лёг В КАВЫЧКАХ" $?
{ inf "$D/.claude/waiting/$f" "review_by: $PLUS30"; }
is "new штампует review_by на +30 дней — дату не придумывает человек" $?
{ inf "$D/.claude/waiting/$f" "stamped_at: $TODAY"; }
is "new пишет stamped_at — без него расхождение штампа с probe: none не поймать" $?
{ inf "$D/.claude/waiting/$f" 'entry: "rk_bot · main"'; }
is "entry называет репозиторий и ветку, а не файл хендоффа" $?
{ inf "$D/.claude/waiting/$f" "state: waiting"; }; is "новая строка в состоянии waiting" $?
{ ! inf "$D/.claude/waiting/$f" "^probe:"; }
is "new НЕ придумывает probe: заполнить всё сразу нельзя по построению" $?

# Укус 1 спеки. Восемь разом, а не два: у наивной реализации `exists() → write`
# окно гонки узкое, и на двух процессах она проходит зелёной по везению.
D="$(mk race)"
i=0; while [ $i -lt 8 ]; do
  ( cd "$D" && python3 "$W" new "гонка $i" >/dev/null 2>&1 ) &
  i=$((i+1))
done
wait
n="$(ls "$D/.claude/waiting" 2>/dev/null | wc -l | tr -d ' ')"
out="в ящике: $(ls "$D/.claude/waiting" 2>/dev/null | tr '\n' ' ')"; rc=0
{ [ "$n" = 8 ]; }; is "восемь new в одну секунду → восемь разных NN" $?
{ [ "$(ls "$D/.claude/waiting" | grep -Ec '^[0-9]{8}-[0-9]{2}\.md$')" = "$n" ]; }
is "все восемь имён формы YYYYMMDD-NN — pid дописывать нельзя (инвариант 9)" $?

echo "=== ворктри и дом ==="

# Укус 2 спеки: строка живёт в ОСНОВНОМ чекауте, никогда в ворктри.
D="$(mk wt_main)"
git -C "$D" worktree add -q "$ROOT/wt_side" -b side
wt "$ROOT/wt_side" new "заведено из ворктри"
{ [ "$rc" = 0 ] && [ -n "$(one "$D/.claude/waiting")" ]; }
is "new из ворктри положил строку в основной чекаут" $?
{ [ ! -d "$ROOT/wt_side/.claude/waiting" ]; }
is "в самом ворктри ящика не появилось" $?

# Укус 3 спеки: ~/.claude — не корень скана, а именованное второе хранилище.
wt "$WAITING_HOME" new "беспроектная, заведена изнутри дома"
{ [ "$rc" = 0 ] && [ -n "$(one "$WAITING_HOME/waiting")" ]; }
is "new изнутри ~/.claude положил строку в ~/.claude/waiting/" $?
{ [ ! -d "$WAITING_HOME/.claude" ]; }
is "и НЕ завёл ~/.claude/.claude/waiting/ — там строку не найдёт никто" $?
{ has "home/"; }; is "id беспроектной строки начинается с home/ (Р4)" $?

D="$(mk with_repo)"
wt "$D" new "беспроектная из репозитория" --global
{ [ "$rc" = 0 ] && [ "$(ls "$WAITING_HOME/waiting" | wc -l | tr -d ' ')" = 2 ]; }
is "--global из репозитория кладёт строку в дом, а не в репозиторий" $?
{ [ ! -d "$D/.claude/waiting" ]; }; is "--global не завёл ящик в репозитории" $?
g="$(ls "$WAITING_HOME/waiting" | tail -1)"
{ inf "$WAITING_HOME/waiting/$g" "entry: none"; }
is "у беспроектной строки entry: none — владеющей линии нет" $?

mkdir -p "$ROOT/plain"
wt "$ROOT/plain" new "заведена вне git"
{ [ "$rc" = 0 ] && has "home/"; }
is "new вне репозитория кладёт строку в дом, а не падает" $?

echo
echo "итог: ✅ $pass   ❌ $fail"
[ "$fail" = 0 ]
