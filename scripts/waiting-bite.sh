#!/usr/bin/env bash
# Стенд укуса waiting.py: каждое утверждение о строке и хранилище ломается нарочно.
#
#   bash ~/.claude/scripts/waiting-bite.sh
#   WAITING=/путь/к/сломанной/копии bash ~/.claude/scripts/waiting-bite.sh
#
# Зачем в репозитории, а не в скрэтчпаде: сторож, чей стенд умирает вместе с
# сессией, второй раз дефекта не ловит.
#
# 🔴 ПРАВИЛО УКУСА. Отрицательное утверждение НИКОГДА не стоит в укусе одно.
# «Каталога X не появилось», «в выводе нет Y», «поле не дописано» — всё это
# истинно и тогда, когда инструмент не сделал НИЧЕГО и НИГДЕ, а значит зелено на
# заглушке. Каждое отрицательное спаяно в ТОМ ЖЕ укусе с положительным, которое
# даёт только работающий инструмент. То же про файл-фикстуру: «файл не изменился»
# зелено на заглушке, потому что фикстуру писал стенд, а не инструмент.
#
# Правило куплено дважды. Приём 1b-1 нашёл пять укусов, проходивших впустую, —
# по слабой формулировке «сверяй rc либо содержимое либо файл». Она недостаточна:
# первый же прогон этого стенда дал ✅ 5 на отсутствующем waiting.py, и все пять
# ей формально удовлетворяли. Сверка одна и та же: заглушка обязана дать ✅ 0.
#
# 🔴 ЗАМЕРЫ ПРИЁМКИ (11.09.2026, 90 укусов). Стенд, который не умеет краснеть,
# охраняет ничего — поэтому его краснота замерена на нарочно сломанных КОПИЯХ:
#   cp scripts/waiting.py /tmp/w.py && правка копии && WAITING=/tmp/w.py bash ...
#
#   живой waiting.py .......................... ✅ 90  ❌ 0
#   заглушка (print + exit 0) ................. ✅ 0   ❌ 90
#   claim_name дописывает pid к имени ......... ✅ 88  ❌ 2   (имя формы YYYYMMDD-NN)
#   repo_box берёт --show-toplevel мимо
#     worktree_main ........................... ✅ 88  ❌ 2   (глава «ворктри и дом»)
#   boxes() не добавляет HOME/BOX строкой ..... ✅ 54  ❌ 36  (см. ниже)
#   classify при отсутствии кэша — «молчит» ... ✅ 78  ❌ 12  (см. ниже)
#
# Два последних числа ШИРЕ, чем поломка размечена, и это не слабость укусов:
#   · домашний ящик несущий — фикстуры глав «кэш», «done» и «stamp» лежат в
#     $WAITING_HOME/waiting ($HB), и без него скан не видит их вовсе;
#   · «нет кэша → молчит» уводит В ОДНУ ГРУППУ все строки без кэша, а их в
#     стенде десяток сверх двух названных.
# Расхождение с этими числами после правки укусов разбирать, а не переписывать
# молча: либо укус ослаб, либо поломка задевает не то, что размечено.
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
# Путь, а не голое имя (решение Р13). Регулярка, а не литерал: стенд живёт в
# mktemp-каталоге, и python отдаёт его через /private/var, а bash — через /var.
{ inf "$D/.claude/waiting/$f" 'entry: "/.*/rk_bot · main"'; }
is "entry называет ПУТЬ к репозиторию и ветку, а не файл хендоффа" $?
{ inf "$D/.claude/waiting/$f" "state: waiting"; }; is "новая строка в состоянии waiting" $?
{ [ -f "$D/.claude/waiting/$f" ] && ! inf "$D/.claude/waiting/$f" "^probe:"; }
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
# Сверка с литеральной восьмёркой, а не с $n: ноль равен нулю, и на пустом
# ящике укус проходил бы, ничего не проверив.
{ [ "$(ls "$D/.claude/waiting" 2>/dev/null | grep -Ec '^[0-9]{8}-[0-9]{2}\.md$')" = 8 ]; }
is "все восемь имён формы YYYYMMDD-NN — pid дописывать нельзя (инвариант 9)" $?

echo "=== ворктри и дом ==="

# Укус 2 спеки: строка живёт в ОСНОВНОМ чекауте, никогда в ворктри.
D="$(mk wt_main)"
git -C "$D" worktree add -q "$ROOT/wt_side" -b side
wt "$ROOT/wt_side" new "заведено из ворктри"
{ [ "$rc" = 0 ] && [ -n "$(one "$D/.claude/waiting")" ]; }
is "new из ворктри положил строку в основной чекаут" $?
{ [ -n "$(one "$D/.claude/waiting")" ] && [ ! -d "$ROOT/wt_side/.claude/waiting" ]; }
is "в самом ворктри ящика не появилось" $?

# Укус 3 спеки: ~/.claude — не корень скана, а именованное второе хранилище.
wt "$WAITING_HOME" new "беспроектная, заведена изнутри дома"
{ [ "$rc" = 0 ] && [ -n "$(one "$WAITING_HOME/waiting")" ]; }
is "new изнутри ~/.claude положил строку в ~/.claude/waiting/" $?
{ [ -n "$(one "$WAITING_HOME/waiting")" ] && [ ! -d "$WAITING_HOME/.claude" ]; }
is "и НЕ завёл ~/.claude/.claude/waiting/ — там строку не найдёт никто" $?
{ has "home/"; }; is "id беспроектной строки начинается с home/ (Р4)" $?

D="$(mk with_repo)"
wt "$D" new "беспроектная из репозитория" --global
{ [ "$rc" = 0 ] && [ "$(ls "$WAITING_HOME/waiting" | wc -l | tr -d ' ')" = 2 ]; }
is "--global из репозитория кладёт строку в дом, а не в репозиторий" $?
{ [ "$(ls "$WAITING_HOME/waiting" 2>/dev/null | wc -l | tr -d ' ')" = 2 ] \
    && [ ! -d "$D/.claude/waiting" ]; }
is "--global не завёл ящик в репозитории" $?
g="$(ls "$WAITING_HOME/waiting" | tail -1)"
{ inf "$WAITING_HOME/waiting/$g" "entry: none"; }
is "у беспроектной строки entry: none — владеющей линии нет" $?

mkdir -p "$ROOT/plain"
wt "$ROOT/plain" new "заведена вне git"
{ [ "$rc" = 0 ] && has "home/"; }
is "new вне репозитория кладёт строку в дом, а не падает" $?

line() {  # line <каталог-ящика> <имя без .md> — содержимое файла со stdin
  mkdir -p "$1"; cat > "$1/$2.md"
}
grp() {  # grp <имя строки> → печатает ГРУППУ, в которой она напечатана
  # Ключевая оснастка главы. «id нет в выводе» для ПРАВИЛЬНОЙ строки невозможно:
  # list обязан печатать все группы целиком, и корректная строка неизбежно стоит
  # в «ни разу не опрошена». Проверять надо не присутствие, а ГРУППУ.
  printf '%s\n' "$out" | awk -v n="$1" '/^— /{g=$0} $0 ~ n {print g; exit}'
}
full() {  # full <каталог-ящика> <имя> — заведомо ПРАВИЛЬНАЯ строка-образец
  line "$1" "$2" <<EOF
---
title: "образец: все поля добыты боем"
state: waiting
review_by: $PLUS30
stamped_at: $TODAY
host: mprz
cwd: ~/dev/rk_bot
probe: |
  journalctl -u bot-rk --since "2026-09-06 17:48"
ripe_match: "приёмник (?!—)"
ripe_when: "в строке подачи стоит АДРЕС приёмника, а не прочерк"
sample: "06.09 19:40 у платежа 1442 стоит прочерк — греп находит строки"
entry: "rk_bot · main"
---

Тело.
EOF
}

echo "=== скан: где ищем и где не ищем ==="

S="$(mk scan_a)"; SB="$S/.claude/waiting"
full "$SB" 20260101-01
wt "$S" list
# Кода 0 тут не ждём: в ящике дома уже лежат шаблоны из главы «заведение», и они
# честно недооформлены — list вернёт 1. Укус сверяет СОСТАВ вывода, а не код.
{ has "20260101-01"; }; is "оформленная строка проекта находится сканом" $?
{ has "ни разу не опрошена"; }
is "и лежит в «ни разу не опрошена», а НЕ в «молчит» (инвариант 3)" $?

# Укус 4 спеки: ~/.claude/waiting/ добавляется к результату глоба отдельной
# строкой — сам глоб <root>/*/.claude/waiting его не находит вовсе.
full "$WAITING_HOME/waiting" 20260101-02
wt "$S" list
{ has "home/20260101-02"; }
is "строка в ~/.claude/waiting/ находится сканом наравне с проектной" $?

# Ворктри под самым корнем скана: глоб его увидит, скан обязан отсеять.
git -C "$S" worktree add -q "$ROOT/repos/scan_a_wt" -b sidewt
full "$ROOT/repos/scan_a_wt/.claude/waiting" 20260101-09
wt "$S" list
{ has "20260101-01" && nohas "20260101-09"; }
is "ящик, заведённый в ворктри, сканом не подхватывается (инвариант 6)" $?

O="$ROOT/outside/far"; mkdir -p "$O"; full "$O/.claude/waiting" 20260101-08
wt "$S" list
{ has "20260101-01" && nohas "20260101-08"; }
is "репозиторий вне корней сканом не виден — корни это конфиг" $?

mkdir -p "$ROOT/home2"; printf '# только комментарий\n' > "$ROOT/home2/waiting-roots.txt"
out="$(cd "$ROOT" && WAITING_HOME="$ROOT/home2" python3 "$W" list 2>&1)"; rc=$?
{ [ "$rc" = 2 ] && has "не называет ни одного корня"; }
is "файл корней без единого корня — ошибка конфигурации, код 2, а не «корней нет»" $?

mkdir -p "$ROOT/home3"
out="$(cd "$ROOT" && WAITING_HOME="$ROOT/home3" python3 "$W" list 2>&1)"; rc=$?
{ [ "$rc" != 2 ] && { has "реестр пуст" || has "— "; }; }
is "отсутствие файла корней — не ошибка: работает умолчание ~/dev" $?

echo "=== форма отказывает при list ==="

F="$(mk form)"; FB="$F/.claude/waiting"

# Укус 5 спеки — три утверждения в одном месте, и они разные.
full "$FB" 20260202-01
line "$FB" 20260202-02 <<EOF
---
title: "образца нет вовсе"
state: waiting
review_by: $PLUS30
stamped_at: $TODAY
host: mprz
cwd: ~/dev/rk_bot
probe: |
  journalctl -u bot-rk
ripe_match: "приёмник"
ripe_when: "адрес вместо прочерка"
entry: "rk_bot · main"
---
Тело.
EOF
wt "$F" list
{ [ "$rc" = 1 ]; }; is "строка без sample → list возвращает 1" $?
{ grp 20260202-02 | grep -q "недооформленные"; }
is "…и печатает её в группе «недооформленные»" $?
{ has "sample"; }; is "…называя, какого поля не хватает" $?
{ has "20260202-01"; }
is "…и ОСТАЛЬНЫЕ группы напечатаны полностью, а не заглушены отказом" $?

# Укус 7 спеки: естественная реализация проглотила бы это try/except.
line "$FB" 20260202-03 <<'EOF'
---
title: "тут двоеточие: и кавычек нет
state: waiting
---
Тело.
EOF
wt "$F" list
{ grp 20260202-03 | grep -q "недооформленные"; }
is "непарсящийся франтматтер напечатан, а не пропущен молча" $?

line "$FB" 20260202-04 <<EOF
---
title: "ключ повторяется"
state: waiting
state: done
review_by: $PLUS30
---
Тело.
EOF
wt "$F" list
{ grp 20260202-04 | grep -q "недооформленные"; }
is "повтор ключа во франтматтере — тоже отказ, а не последний выигрывает" $?

echo "=== сторож пробы: конъюнкции нет, но данные не код ==="

C="$(mk conj)"; CB="$C/.claude/waiting"
mkprobe() {  # mkprobe <имя> <<'EOF' — тело блочного скаляра probe
  name="$1"; body="$(cat)"
  { printf -- '---\ntitle: "проба %s"\nstate: waiting\nreview_by: %s\nstamped_at: %s\n' \
      "$name" "$PLUS30" "$TODAY"
    printf 'host: mprz\ncwd: ~/dev/x\nprobe: |\n'
    printf '%s\n' "$body" | sed 's/^/  /'
    printf 'ripe_match: "ok"\nripe_when: "наступило"\nsample: "видел оба исхода"\n'
    printf -- 'entry: "conj · main"\n---\nТело.\n'
  } > "$CB/$name.md"
}
mkdir -p "$CB"
mkprobe 20260303-01 <<'EOF'
cd /srv && journalctl -u bot
EOF
mkprobe 20260303-02 <<'EOF'
psql -f a.sql; psql -f b.sql
EOF
mkprobe 20260303-03 <<'EOF'
./scripts/prod_sql.sh <<'SQL'
select id, state
  from orders
 where state = 'new';
SQL
EOF
mkprobe 20260303-04 <<'EOF'
.venv/bin/python -c 'import x; print(x.n)'
EOF
mkprobe 20260303-05 <<'EOF'
journalctl -u bot
grep -c ошибка /var/log/app.log
EOF
mkprobe 20260303-06 <<'EOF'
journalctl -u bot 2>&1 | tail -50
EOF
wt "$C" list
{ grp 20260303-01 | grep -q "недооформленные"; }
is "конъюнкция через && поймана" $?
{ grp 20260303-02 | grep -q "недооформленные"; }
is "конъюнкция через ; поймана" $?
{ grp 20260303-03 | grep -q "ни разу не опрошена"; }
is "многострочный SQL в heredoc с ; внутри — НЕ конъюнкция: тело heredoc это данные" $?
{ grp 20260303-04 | grep -q "ни разу не опрошена"; }
is "; внутри кавычек — не конъюнкция, а часть аргумента" $?
{ grp 20260303-05 | grep -q "недооформленные"; }
is "две команды в столбик — конъюнкция: перевод строки разделяет так же, как ;" $?
{ grp 20260303-06 | grep -q "ни разу не опрошена"; }
is "конвейер и 2>&1 конъюнкцией не считаются" $?

echo "=== кавычки, none и pending ==="

Q="$(mk quotes)"; QB="$Q/.claude/waiting"
line "$QB" 20260404-01 <<EOF
---
title: заголовок без кавычек
state: waiting
review_by: $PLUS30
stamped_at: $TODAY
host: mprz
cwd: ~/dev/x
probe: |
  journalctl -u bot
ripe_match: "ok"
ripe_when: "наступило"
sample: "видел оба исхода"
entry: "quotes · main"
---
Тело.
EOF
line "$QB" 20260404-02 <<EOF
---
title: "sample: pending — законный третий вид"
state: waiting
review_by: $PLUS30
stamped_at: $TODAY
host: mprz
cwd: ~/dev/x
probe: |
  grep -c ключ /etc/app.conf
ripe_match: "^[1-9]"
ripe_when: "ключ в конфиге появился"
sample: pending
entry: "quotes · main"
---
Файла с ключом никогда не существовало — образца нет и быть не может.
EOF
line "$QB" 20260404-03 <<EOF
---
title: "машинной пробы нет, срок +7"
state: waiting
review_by: $PLUS7
stamped_at: $TODAY
host: none
cwd: none
probe: none
ripe_match: none
ripe_when: "поддержка ответила по тикету 4417"
sample: none
entry: none
---
Ответ человека машинно не проверяется.
EOF
line "$QB" 20260404-04 <<EOF
---
title: "probe: none при штампе +30"
state: waiting
review_by: $PLUS30
stamped_at: $TODAY
host: none
cwd: none
probe: none
ripe_match: none
ripe_when: "решение владельца по derflow"
sample: none
entry: none
---
Штамп и проба разошлись.
EOF
line "$QB" 20260404-05 <<EOF
---
title: "проба есть, а штамп короткий — это НЕ расхождение"
state: waiting
review_by: $PLUS7
stamped_at: $TODAY
host: mprz
cwd: ~/dev/x
probe: |
  journalctl -u bot
ripe_match: "#\\d+ готов"
ripe_when: "наряд закрыт"
sample: "видел оба исхода"
entry: "quotes · main"
---
Короткий срок безвреден: он даёт лишний взгляд, а не пропуск.
EOF
line "$QB" 20260404-06 <<EOF
---
title: "состояния третьего не бывает"
state: отложено
review_by: $PLUS7
stamped_at: $TODAY
host: none
cwd: none
probe: none
ripe_match: none
ripe_when: "что-нибудь"
sample: none
entry: none
---
Тело.
EOF
line "$QB" 20260404-07 <<EOF
---
title: "комментарий у голого скаляра — форма из самой спеки"
state: waiting            # waiting | done — третьего нет
review_by: $PLUS30        # машиной: +30, потому что проба есть
stamped_at: $TODAY
host: mprz                # local | mprz | …
cwd: ~/dev/x
probe: |
  journalctl -u bot
ripe_match: "ok"
ripe_when: "наступило"
sample: "# 06.09 у платежа 1442 прочерк — греп показал оба исхода"
entry: "quotes · main"
---
Тело.
EOF
wt "$Q" list
{ grp 20260404-01 | grep -q "недооформленные"; }
is "title без кавычек — недооформленная строка" $?
{ grp 20260404-02 | grep -q "ни разу не опрошена"; }
is "sample: pending — законный третий вид, не порок" $?
{ has "образца нет, отрицательный ответ ничего не доказывает"; }
is "…и list печатает про неё именно это, а не молчит" $?
{ grp 20260404-03 | grep -q "ни разу не опрошена"; }
is "probe: none при штампе +7 — законная строка" $?
{ has "машинной пробы нет, созреет только сроком"; }
is "…и list называет это явно, иначе она тихо не сработает никогда" $?
{ grp 20260404-04 | grep -q "недооформленные"; }
is "probe: none при штампе +30 — расхождение, которое обязано быть видным" $?
{ has "stamp"; }; is "…и list называет команду, которой это чинится" $?
{ grp 20260404-05 | grep -q "ни разу не опрошена"; }
is "проба при штампе +7 расхождением НЕ считается — короткий срок безвреден" $?
{ grp 20260404-06 | grep -q "недооформленные"; }
is "state: третьего значения — недооформленная строка" $?
{ grp 20260404-07 | grep -q "ни разу не опрошена"; }
is "комментарий у ГОЛОГО скаляра снимается — иначе review_by перестаёт быть датой" $?
{ has "20260404-01" && nohas "поле sample пустое"; }
is "…а в кавычках решётка часть значения: sample с неё начинается и уцелел" $?

cache() {  # cache <repo-id> <имя строки> <json одной строкой>
  mkdir -p "$WAITING_HOME/waiting-cache/$1"
  printf '%s\n' "$3" > "$WAITING_HOME/waiting-cache/$1/$2.json"
}
NOW="$(date +%s)"
OLD="$((NOW - 4 * 3600))"          # старше 3×TTL при TTL=3600
HB="$WAITING_HOME/waiting"

echo "=== исход берётся из кэша, созрелость вычисляется ==="

full "$HB" 20260505-01; cache home 20260505-01 "{\"outcome\":\"fired\",\"since\":\"2026-09-10T10:00:00\",\"last_run_at_ts\":$NOW,\"last_rc\":0}"
full "$HB" 20260505-02; cache home 20260505-02 "{\"outcome\":\"silent\",\"since\":\"2026-09-10T10:00:00\",\"last_run_at_ts\":$NOW,\"last_rc\":0}"
full "$HB" 20260505-03; cache home 20260505-03 "{\"outcome\":\"unreachable\",\"since\":\"2026-09-10T10:00:00\",\"last_run_at_ts\":$NOW,\"last_rc\":0}"
full "$HB" 20260505-04; cache home 20260505-04 "{\"outcome\":\"silent\",\"since\":\"2026-09-10T10:00:00\",\"last_run_at_ts\":$OLD,\"last_rc\":0}"
full "$HB" 20260505-05; cache home 20260505-05 "{\"outcome\":\"silent\",\"since\":\"2026-09-10T10:00:00\",\"last_run_at_ts\":$NOW,\"last_rc\":4}"
full "$HB" 20260505-06; cache home 20260505-06 "не json вовсе"
full "$HB" 20260505-07
wt "$WAITING_HOME" list
{ grp 20260505-01 | grep -q "созрело"; }
is "кэш fired → «созрело», хотя срок пересмотра не прошёл" $?
{ grp 20260505-02 | grep -q "молчит"; }
is "кэш silent → «молчит»: проба спросила и ответ был пуст" $?
{ grp 20260505-03 | grep -q "недостижима"; }
is "кэш unreachable → «недостижима», а не «молчит» (инвариант 3)" $?
{ grp 20260505-04 | grep -q "данные протухли"; }
is "кэш старше 3×TTL → «данные протухли», а не вчерашняя правда под видом сегодняшней" $?
{ grp 20260505-05 | grep -q "данные протухли"; }
is "последний прогон упал (last_rc≠0) → «данные протухли»" $?
{ grp 20260505-06 | grep -q "ни разу не опрошена"; }
is "битый кэш → строка не пропадает и list не падает" $?
{ grp 20260505-07 | grep -q "ни разу не опрошена"; }
is "кэша нет вовсе → «ни разу не опрошена», а не «молчит»" $?

# Прошедший срок пересмотра созревает строку сам, без всякой пробы: он и есть
# страховка на случай, когда проба врёт в сторону тишины.
line "$HB" 20260505-08 <<EOF
---
title: "срок пересмотра прошёл вчера"
state: waiting
review_by: $(date -v-1d +%Y-%m-%d)
stamped_at: $(date -v-31d +%Y-%m-%d)
host: mprz
cwd: ~/dev/x
probe: |
  journalctl -u bot
ripe_match: "ok"
ripe_when: "наступило"
sample: "видел оба исхода"
entry: "none"
---
Тело.
EOF
cache home 20260505-08 "{\"outcome\":\"silent\",\"since\":\"2026-09-10T10:00:00\",\"last_run_at_ts\":$NOW,\"last_rc\":0}"
wt "$WAITING_HOME" list
{ grp 20260505-08 | grep -q "созрело"; }
is "прошедший review_by созревает строку, даже когда проба молчит" $?

echo "=== чужой кэш, снятые строки, пропажа из скана ==="

full "$HB" 20260505-09
cache notmine-deadbeef 20260505-09 "{\"outcome\":\"fired\",\"since\":\"x\",\"last_run_at_ts\":$NOW,\"last_rc\":0}"
wt "$WAITING_HOME" list
{ grp 20260505-09 | grep -q "ни разу не опрошена"; }
is "кэш под ЧУЖИМ repo-id к строке не приклеивается — id глобален" $?
{ has "notmine-deadbeef/20260505-09 пропала из скана"; }
is "…а сам он объявлен пропавшим: скан породил этот исход, скан о нём и говорит" $?
{ [ ! -f "$WAITING_HOME/waiting-cache/notmine-deadbeef/20260505-09.json" ]; }
is "…и забыт: печатается ОДИН раз, ведённого списка нет" $?
wt "$WAITING_HOME" list
{ has "20260505-01" && nohas "пропала из скана"; }
is "второй прогон о той же пропаже молчит" $?

line "$HB" 20260505-10 <<EOF
---
title: "снята, сработала"
state: done
closed_at: $TODAY
closed_because: "платёж прошёл, адрес приёмника встал на место"
review_by: $PLUS30
stamped_at: $TODAY
host: mprz
cwd: ~/dev/x
probe: |
  journalctl -u bot
ripe_match: "ok"
ripe_when: "наступило"
sample: "видел оба исхода"
entry: "none"
---
Тело.
EOF
cache home 20260505-10 "{\"outcome\":\"fired\",\"since\":\"x\",\"last_run_at_ts\":$NOW,\"last_rc\":0}"
wt "$WAITING_HOME" list
{ has "20260505-01" && nohas "20260505-10"; }
is "снятая строка в обычный list не печатается" $?
{ has "20260505-01" && nohas "20260505-10 пропала"; }
is "…и пропавшей НЕ считается: скан её видел, просто не печатал" $?
wt "$WAITING_HOME" list --all
{ has "20260505-10"; }; is "list --all показывает и снятые" $?
{ has "снята"; }; is "…с пометкой, что строка снята, а не молча в общем списке" $?

echo "=== снятие, переклейка срока и разрешение id ==="

# Укус 6 спеки. Одноимённые строки в двух хранилищах — норма, а не редкость:
# NN атомарен только ВНУТРИ каталога, а каталогов столько, сколько репозиториев.
R="$(mk twin)"; RB="$R/.claude/waiting"
full "$RB" 20260606-01
full "$HB" 20260606-01
wt "$R" done 20260606-01 "потому что"
{ [ "$rc" = 2 ]; }; is "голый id, разрешающийся в две строки → отказ кодом 2" $?
{ has "home/20260606-01"; }; is "…со списком кандидатов, а не с догадкой" $?
{ has "20260606-01" && printf '%s' "$out" | grep -q "twin-"; }
is "…и в списке названы ОБА полных id" $?
# ОБЕ половины, и здесь это не педантизм: следующая же команда законно снимает
# ту, что в $HB, и окно для обнаружения закрывается необратимо.
{ [ "$rc" = 2 ] && inf "$RB/20260606-01.md" "state: waiting" \
    && inf "$HB/20260606-01.md" "state: waiting"; }
is "…и ни одна из двух не снята: угадать хуже, чем не двигаться" $?

wt "$R" done home/20260606-01 "линия закрыта, ждать больше нечего"
{ [ "$rc" = 0 ] && has "снята:"; }; is "полный id снимает строку" $?
{ inf "$HB/20260606-01.md" "state: done"; }; is "…ровно ту, что названа" $?
{ inf "$HB/20260606-01.md" "state: done" && inf "$RB/20260606-01.md" "state: waiting"; }
is "…и не трогает одноимённую соседку" $?
{ inf "$HB/20260606-01.md" "closed_at: $TODAY"; }; is "done ставит машинный closed_at" $?
{ inf "$HB/20260606-01.md" 'closed_because: "линия закрыта'; }
is "done требует причину смерти и записывает её В КАВЫЧКАХ" $?

wt "$R" done home/20260606-01 ""
{ [ "$rc" = 1 ]; }
is "пустая причина — отказ: надгробие без причины не отвечает на вопрос, ради которого его хранят" $?

wt "$R" done home/20261111-99 "нет такой"
{ [ "$rc" = 2 ]; }; is "снятие несуществующей строки — код 2, а не тихий успех" $?

# Правка машиной не смеет затирать человеческое: у файла один писатель, и это он.
line "$HB" 20260707-01 <<EOF
---
title: "у этой строки есть комментарий и тело"
# этот комментарий человек написал руками
state: waiting
review_by: $PLUS30
stamped_at: $TODAY
host: none
cwd: none
probe: none
ripe_match: none
ripe_when: "владелец решит судьбу derflow"
sample: none
entry: none
---

Замер 08.09: сработали все 14 полос. НЕ ТЕРЯТЬ ЭТУ СТРОКУ ТЕЛА.
EOF
wt "$WAITING_HOME" done home/20260707-01 "решено"
{ inf "$HB/20260707-01.md" "state: done" \
    && inf "$HB/20260707-01.md" "этот комментарий человек написал руками"; }
is "done не съел комментарий человека во франтматтере" $?
{ inf "$HB/20260707-01.md" "closed_at: $TODAY" \
    && inf "$HB/20260707-01.md" "НЕ ТЕРЯТЬ ЭТУ СТРОКУ ТЕЛА"; }
is "…и не съел тело: правка идёт по ключу, а не перезаписью файла" $?
{ inf "$HB/20260707-01.md" "closed_because" \
    && inf "$HB/20260707-01.md" 'ripe_when: "владелец решит судьбу derflow"'; }
is "…и не тронул чужие поля" $?

# Расхождение «probe: none при штампе +30» чинится stamp, а не ack.
line "$HB" 20260707-02 <<EOF
---
title: "проба выяснилась после заведения — её нет"
state: waiting
review_by: $PLUS30
stamped_at: $TODAY
host: none
cwd: none
probe: none
ripe_match: none
ripe_when: "поддержка ответит по тикету"
sample: none
entry: none
---
Тело.
EOF
wt "$WAITING_HOME" list
{ grp 20260707-02 | grep -q "недооформленные"; }
is "до stamp строка висит в недооформленных" $?
wt "$WAITING_HOME" stamp home/20260707-02
{ [ "$rc" = 0 ] && inf "$HB/20260707-02.md" "review_by: $PLUS7"; }
is "stamp при probe: none переклеивает срок на +7 — он единственный датчик" $?
{ inf "$HB/20260707-02.md" "review_by: $PLUS7" \
    && ! inf "$HB/20260707-02.md" "acked_outcome"; }
is "stamp НЕ пишет acked_outcome: это не «посмотрел», а «переклеил срок»" $?
wt "$WAITING_HOME" list
{ grp 20260707-02 | grep -q "ни разу не опрошена"; }
is "после stamp строка ушла из недооформленных в честную группу" $?

# Срок и штамп нарочно ЧУЖИЕ: если фикстура уже несёт +30 и сегодняшний штамп,
# stamp'у нечего двигать, и оба укуса зелены даже на заглушке. Короткий срок при
# живой пробе законен (расхождением он не считается) — потому и взят.
line "$HB" 20260707-03 <<EOF
---
title: "срок короткий, а проба живая — stamp обязан выправить"
state: waiting
review_by: $PLUS7
stamped_at: $(date -v-31d +%Y-%m-%d)
host: mprz
cwd: ~/dev/x
probe: |
  journalctl -u bot
ripe_match: "ok"
ripe_when: "наступило"
sample: "видел оба исхода"
entry: none
---
Тело.
EOF
wt "$WAITING_HOME" stamp home/20260707-03
{ [ "$rc" = 0 ] && inf "$HB/20260707-03.md" "review_by: $PLUS30"; }
is "stamp при живой пробе даёт +30 — подстраховка, а не датчик" $?
{ inf "$HB/20260707-03.md" "stamped_at: $TODAY"; }
is "stamp двигает stamped_at, иначе расхождение не пересчитать никогда" $?

line "$HB" 20260707-04 <<'EOF'
---
title: "кавычка не закрыта
state: waiting
---
Тело.
EOF
wt "$WAITING_HOME" stamp home/20260707-04
{ [ "$rc" = 1 ]; }
is "stamp по непарсящейся строке отказывает: срок машина в такой файл не пишет" $?
{ [ "$rc" = 1 ] && inf "$HB/20260707-04.md" 'title: "кавычка не закрыта'; }
is "…и файла не тронул: непонятый франтматтер правке не подлежит" $?

wt "$WAITING_HOME" done home/20260707-04 "снимаю вслепую"
{ [ "$rc" = 1 ] && ! inf "$HB/20260707-04.md" "state: done"; }
is "done по непарсящейся строке отказывает ТОЖЕ — сторож у обеих команд один" $?

echo
echo "итог: ✅ $pass   ❌ $fail"
[ "$fail" = 0 ]
