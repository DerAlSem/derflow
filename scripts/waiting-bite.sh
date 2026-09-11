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
# 🔴 И ТРЕТЬЕ: искомая подстрока не смеет встречаться НИ В ФИКСТУРЕ, НИ В ПУТЯХ
# стенда. Иначе положительную половину обеспечивает стенд, а не инструмент —
# укус при этом положителен, группу сверяет, код спаян с текстом и окно открыто,
# то есть все прежние правила соблюдены, и он всё равно пуст. Шестой вид, найден
# финальным ревью 11.09.2026 и замерен: греп голого `home/` ловил ИМЯ КАТАЛОГА
# стенда ($ROOT/home), а греп `снята` — заголовок собственной фикстуры. Обе
# поломки (id дома не `home`; пометка «снята» не вставляется вовсе) давали
# ✅ 90 ❌ 0. Лечится якорем на печатаемое: `заведена: home/`, `[снята: причина`.
#
# Правило куплено дважды. Приём 1b-1 нашёл пять укусов, проходивших впустую, —
# по слабой формулировке «сверяй rc либо содержимое либо файл». Она недостаточна:
# первый же прогон этого стенда дал ✅ 5 на отсутствующем waiting.py, и все пять
# ей формально удовлетворяли. Сверка одна и та же: заглушка обязана дать ✅ 0.
#
# 🔴 ЗАМЕРЫ ПРИЁМКИ (11.09.2026, 104 укуса, после круга починки финального ревью).
# Стенд, который не умеет краснеть, охраняет ничего — поэтому его краснота
# замерена на нарочно сломанных КОПИЯХ:
#   cp scripts/waiting.py /tmp/w.py && правка копии && WAITING=/tmp/w.py bash ...
#
#   живой waiting.py .......................... ✅ 104 ❌ 0
#   заглушка (print + exit 0) ................. ✅ 0   ❌ 104
#   claim_name дописывает pid к имени ......... ✅ 102 ❌ 2
#   repo_box берёт --show-toplevel мимо
#     worktree_main ........................... ✅ 102 ❌ 2
#   boxes() не добавляет HOME/BOX строкой ..... ✅ 58  ❌ 46
#   classify при отсутствии кэша — «молчит» ... ✅ 92  ❌ 12
#   id беспроектной строки не `home` (Р4) ..... ✅ 101 ❌ 3
#   пометка «снята» не вставляется в вывод .... ✅ 102 ❌ 2
#
# Два средних числа ШИРЕ, чем поломка размечена, и это не слабость укусов:
#   · домашний ящик несущий — фикстуры глав «кэш», «done», «stamp» и всего
#     круга починки лежат в $WAITING_HOME/waiting ($HB), и без него скан не
#     видит их вовсе;
#   · «нет кэша → молчит» уводит В ОДНУ ГРУППУ все строки без кэша.
# Две последние поломки — те самые, на которых стенд был зелен ЦЕЛИКОМ до
# 11.09: см. третий абзац правила укуса.
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
# Р18: транспорт подменяется — стенд обязан работать без сети и без чужих хостов.
# Хост приезжает аргументом, поэтому распознаём его перебором: `refuse` роняет
# транспорт кодом 255, `slow` висит дольше потолка пробы, остальные исполняют
# скрипт местно — то есть дают настоящие fired и silent.
export WAITING_SSH="$ROOT/fake-ssh"
export WAITING_PROBE_TIMEOUT_S=1
cat > "$WAITING_SSH" <<'FAKESSH'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    refuse) exit 255 ;;
    slow)   sleep 3 ;;
  esac
done
exec bash -o pipefail -s
FAKESSH
chmod +x "$WAITING_SSH"
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
{ has "заведена: home/"; }; is "id беспроектной строки начинается с home/ (Р4)" $?

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
{ [ "$rc" = 0 ] && has "заведена: home/"; }
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
state: waiting            # waiting | taken | done
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
is "state: четвёртого значения не бывает — недооформленная строка" $?
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
HC="$WAITING_HOME/waiting-cache"

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
{ has "\[снята: платёж прошёл"; }; is "…с пометкой, что строка снята, а не молча в общем списке" $?

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

echo "=== машина не смеет портить файл человека (круг починки финального ревью) ==="

# Critical: проза переносится строками, и незаэкранированный перевод строки клал
# в ИСПРАВНЫЙ файл незакрытую кавычку. Спаяно тремя половинами: файл разбирается,
# причина цела ЦЕЛИКОМ, и заголовок не подменён на «(без title)».
full "$HB" 20260808-01
wt "$WAITING_HOME" done home/20260808-01 "сработала 11.09
подробности: платёж 1442"
{ [ "$rc" = 0 ] && has "снята: home/20260808-01"; }
is "done с многострочной причиной не падает" $?
wt "$WAITING_HOME" list --all
{ nohas "кавычка у 'closed_because' не закрыта"; } \
  && { has "образец: все поля добыты боем"; }
is "…и файл ПОСЛЕ него разбирается, заголовок на месте — а не «(без title)»" $?
{ has "\[снята: сработала 11.09 подробности: платёж 1442"; }
is "…и причина уцелела ЦЕЛИКОМ, схлопнутая в строку, а не обрублена" $?
wt "$WAITING_HOME" stamp home/20260808-01
{ [ "$rc" = 0 ] && has "пересмотр $PLUS30"; }
is "…и строка чинится своим же инструментом: stamp по ней не отказывает" $?

# Тот же вход со стороны new: код 0 и непарсящийся файл — исход хуже отказа.
wt "$WAITING_HOME" new "$(printf 'многострочный\nзаголовок: беда')"
g="$(printf '%s' "$out" | sed -n 's/^заведена: home\///p')"
wt "$WAITING_HOME" list --all
# Якорь на СВОЮ строку: фикстура 20260707-04 нарочно несёт незакрытую кавычку
# у title, и голый nohas по тексту ошибки краснел бы от соседки.
{ [ -n "$g" ] && has "многострочный заголовок: беда"; }
is "new с переводом строки в заголовке пишет РАЗБИРАЕМЫЙ франтматтер" $?

# Important: хвостовой комментарий человека. Спека приводит его в своём образце
# строки; до починки stamp и done стирали его молча.
line "$HB" 20260808-02 <<EOF
---
title: "строка с комментариями человека"
state: waiting            # waiting | taken | done
review_by: 2026-01-01     # машиной: +30, потому что проба есть (без неё +7)
stamped_at: $TODAY
host: mprz
cwd: ~/dev/rk_bot
probe: |
  journalctl -u bot-rk
ripe_match: "приёмник"
ripe_when: "адрес встал"
sample: "06.09 видел оба исхода"
entry: "rk_bot · main"
---

Тело.
EOF
wt "$WAITING_HOME" stamp home/20260808-02
# Спаяно: дату $PLUS30 в этот файл может положить ТОЛЬКО работающий stamp
# (фикстура несёт 2026-01-01), а комментарий — только сохранивший его stamp.
{ [ "$rc" = 0 ] && inf "$HB/20260808-02.md" "review_by: $PLUS30" \
    && inf "$HB/20260808-02.md" "# машиной: +30"; }
is "stamp не съел хвостовой комментарий человека у review_by" $?
{ inf "$HB/20260808-02.md" "review_by: $PLUS30     # машиной"; }
is "…и не съел ВЫРАВНИВАНИЕ: файл человека не меняется пробелами" $?
wt "$WAITING_HOME" done home/20260808-02 "причина"
{ [ "$rc" = 0 ] && inf "$HB/20260808-02.md" "state: done            # waiting | taken | done"; }
is "done не съел хвостовой комментарий у state" $?

# Important: сторож конъюнкции молчал на неразобранном. Апостроф в комментарии
# открывал кавычку, и ВТОРАЯ команда исчезала вместе с настоящей конъюнкцией.
line "$FB" 20260808-03 <<'EOF'
---
title: "апостроф в комментарии съедал вторую команду"
state: waiting
review_by: 2026-12-01
stamped_at: 2026-09-11
host: mprz
cwd: ~/dev/rk_bot
probe: |
  journalctl -u bot   # don't grep
  grep -c ошибка /var/log/app.log
ripe_match: "ok"
ripe_when: "наступило"
sample: "видел оба исхода"
entry: "rk_bot · main"
---

Тело.
EOF
wt "$F" list
{ [ "$rc" = 1 ] && has "пробу не разобрали"; }
is "неразобранная проба — ОТКАЗ, а не молчание: промах в безопасную сторону" $?
{ grp 20260808-03 | grep -q "недооформленные"; }
is "…и строка с ней висит в недооформленных, а не выдаётся за оформленную" $?

# Important: неизвестный исход в кэше. «Не спрашивали» про строку, которую
# спрашивали и получили ответ, — ровно конфляция инварианта 3.
full "$HB" 20260808-04
cache home 20260808-04 "{\"outcome\":\"timeout\",\"since\":\"2026-09-10T10:00:00\",\"last_run_at_ts\":$NOW,\"last_rc\":0}"
wt "$WAITING_HOME" list
{ grp 20260808-04 | grep -q "данные протухли"; }
is "неизвестный исход кэша → «данные протухли», а НЕ «ни разу не опрошена»" $?

# Ветка ~-сокращения display_path: в бою по ней идут 100% строк (корень ~/dev),
# а стенд жил в mktemp вне дома и кусал только ValueError-ветку.
mkdir -p "$ROOT/fakehome/repos"
Z="$ROOT/fakehome/repos/hm_bot"; mkdir -p "$Z"
git -C "$Z" init -q -b main .; git -C "$Z" config user.email t@t; git -C "$Z" config user.name t
echo x > "$Z/a.txt"; git -C "$Z" add -A; git -C "$Z" commit -qm init
out="$(cd "$Z" && HOME="$ROOT/fakehome" python3 "$W" new "строка под домашним каталогом" 2>&1)"; rc=$?
zf="$(one "$Z/.claude/waiting")"
{ [ "$rc" = 0 ] && inf "$Z/.claude/waiting/$zf" 'entry: "~/repos/hm_bot · main"'; }
is "entry сокращает домашний каталог до ~ — в бою по этой ветке идут все строки" $?

# Окончания строк переживают правку. Спаяно тройкой: дата появилась (её кладёт
# только работающий stamp), CRLF на месте у ВСЕХ строк, и голого LF в файле нет
# вовсе — до починки переписанная строка теряла \r, а соседние хранили.
printf 'x' > /dev/null
{ printf -- '---\r\ntitle: "файл с CRLF"\r\nstate: waiting\r\n'
  printf -- 'review_by: 2026-01-01     # комментарий человека\r\n'
  printf -- 'stamped_at: %s\r\nhost: mprz\r\ncwd: ~/dev/rk_bot\r\n' "$TODAY"
  printf -- 'probe: |\r\n  journalctl -u bot-rk\r\nripe_match: "ok"\r\n'
  printf -- 'ripe_when: "наступило"\r\nsample: "видел оба исхода"\r\n'
  printf -- 'entry: "rk_bot · main"\r\n---\r\n\r\nТело.\r\n'
} > "$HB/20260808-05.md"
crlf_n="$(tr -cd '\r' < "$HB/20260808-05.md" | wc -c | tr -d ' ')"
wt "$WAITING_HOME" stamp home/20260808-05
after="$(tr -cd '\r' < "$HB/20260808-05.md" | wc -c | tr -d ' ')"
{ [ "$rc" = 0 ] && inf "$HB/20260808-05.md" "review_by: $PLUS30" \
    && [ "$after" = "$crlf_n" ]; }
is "stamp сохранил CRLF: правка по ключу не переписывает файл в LF" $?
{ inf "$HB/20260808-05.md" "review_by: $PLUS30     # комментарий человека"; }
is "…и хвостовой комментарий с выравниванием уцелел и в CRLF-файле" $?

echo "=== три вопроса: код транспорта, код команды, совпадение по stdout ==="

prb() {  # prb <ящик> <имя> <host> <cwd> <команда> <ripe_match>
  line "$1" "$2" <<EOF
---
title: "проба $2"
state: waiting
review_by: $PLUS30
stamped_at: $TODAY
host: $3
cwd: $4
probe: |
  $5
ripe_match: "$6"
ripe_when: "то самое решение"
sample: "видел оба исхода 11.09"
entry: none
---
Тело.
EOF
}

# Укус 8 спеки — центральное утверждение поставки, три половины в одном месте.
prb "$HB" 20260707-11 local /tmp 'echo приёмник 10.0.0.1' 'приёмник'
prb "$HB" 20260707-12 local /tmp 'echo ничего интересного' 'приёмник'
prb "$HB" 20260707-13 local /tmp 'exit 7'                 'приёмник'
prb "$HB" 20260707-14 refuse /tmp 'echo приёмник'         'приёмник'
prb "$HB" 20260707-15 local /tmp 'grep приёмник /dev/null' 'приёмник'
wt "$WAITING_HOME" probe
{ [ "$rc" = 4 ] && has "20260707-11: fired"; }
is "probe вернул 4 — хоть одна строка не смогла спросить, и это не 0" $?
{ jq -er '.outcome=="fired" and .probe_rc==0' "$HC/home/20260707-11.json" >/dev/null; }
is "совпадение по stdout → fired, и код пробы записан нулём" $?
{ jq -er '.outcome=="silent" and .probe_rc==0' "$HC/home/20260707-12.json" >/dev/null; }
is "пусто кодом 0 → silent: проба спросила, ответ был пуст" $?
{ jq -er '.outcome=="unreachable" and .probe_rc==7' "$HC/home/20260707-13.json" >/dev/null \
    && has "20260707-13: unreachable — проба вышла кодом 7"; }
is "ненулевой код команды → unreachable, и код пробы назван" $?
{ jq -er '.outcome=="unreachable" and .probe_rc==255' "$HC/home/20260707-14.json" >/dev/null \
    && has "транспорт отказал (ssh: 255)"; }
is "ssh с кодом 255 → unreachable по транспорту, а не по команде" $?
# 🔴 Плановый укус требовал здесь silent — и противоречил и своему же probe_one,
# и таблице «Три вопроса» спеки («ненулевой код команды → unreachable»). Спека
# решает проблему грепа АРХИТЕКТУРНО: фильтрация уезжает из пробы в ripe_match, и
# проба обязана выходить нулём. Особый случай для кода 1 был бы ложью в сторону
# тишины — настоящий отказ, вышедший единицей, приезжал бы как «честно молчит».
# Укус перевёрнут и стал сторожем ровно этого соблазна: код 7 (ниже) однозначен,
# а единица — та, которую рука норовит простить.
{ jq -er '.outcome=="unreachable" and .probe_rc==1' "$HC/home/20260707-15.json" >/dev/null; }
is "🔴 код 1 у грепа — unreachable, а не silent: фильтрация живёт в ripe_match" $?
# 🔴 Р14 живьём: last_rc — код ПРОГОНА, а не пробы. Пара проверяет обе стороны:
# у недостижимой строки last_rc нуль, и list ставит её в «недостижима», а не в
# «данные протухли». Реализация, сунувшая код пробы в last_rc, красит оба укуса.
{ jq -er '.last_rc==0' "$HC/home/20260707-13.json" >/dev/null; }
is "last_rc нуль у НЕДОСТИЖИМОЙ строки: прогон состоялся, проба — нет" $?
wt "$WAITING_HOME" list
{ grp 20260707-13 | grep -q "недостижима"; }
is "…и list ставит её в «недостижима», а не в «данные протухли»" $?

# Потолок пробы. WAITING_PROBE_TIMEOUT_S=1, подставной ssh спит 3.
prb "$HB" 20260707-16 slow /tmp 'echo приёмник' 'приёмник'
wt "$WAITING_HOME" probe
{ [ "$rc" = 4 ] && has "20260707-16: unreachable — потолок пробы 1 с исчерпан"; }
is "проба, вышедшая за потолок, — unreachable с названной причиной" $?
{ jq -er '.probe_rc==124' "$HC/home/20260707-16.json" >/dev/null; }
is "…и код 124 тот же, каким отвечает timeout — контракт не выдуман" $?

# ripe_match, который не компилируется, — ГРОМКАЯ сторона.
prb "$HB" 20260707-17 local /tmp 'echo приёмник' 'приёмник((('
wt "$WAITING_HOME" probe
{ has "20260707-17: unreachable — ripe_match не компилируется"; }
is "непонятая регулярка → unreachable, а не «событие не наступило»" $?

# cwd, которого нет: код 91 и НАЗВАННАЯ причина вместо тихого «молчит».
prb "$HB" 20260707-18 local /nonexistent-dir-xyz 'echo приёмник' 'приёмник'
wt "$WAITING_HOME" probe
{ jq -er '.probe_rc==91' "$HC/home/20260707-18.json" >/dev/null \
    && has "cwd не нашёлся: /nonexistent-dir-xyz"; }
is "cwd не разрешился → unreachable кодом 91, причина названа (Р21)" $?

echo "=== кого фон НЕ спрашивает и замок ==="

# Р20: четыре класса. Положительная половина — у пятой строки кэш ПОЯВЛЯЕТСЯ.
prb "$HB" 20260707-21 local /tmp 'echo приёмник' 'приёмник'
line "$HB" 20260707-22 <<EOF
---
title: "взята в работу — фон её не спрашивает"
state: taken
review_by: $PLUS30
stamped_at: $TODAY
host: local
cwd: /tmp
probe: |
  echo приёмник
ripe_match: "приёмник"
ripe_when: "то самое"
sample: "видел оба исхода"
entry: none
taken_at: $TODAY
taken_because: "начали 11.09"
---
Тело.
EOF
full "$HB" 20260707-23            # probe: none — спрашивать нечем
line "$HB" 20260707-24 <<EOF
---
title: "недооформленная — полей пробы нет"
state: waiting
review_by: $PLUS30
stamped_at: $TODAY
entry: none
---
Тело.
EOF
rm -rf "$HC"
wt "$WAITING_HOME" probe
{ [ -f "$HC/home/20260707-21.json" ] && [ ! -f "$HC/home/20260707-22.json" ]; }
is "state: taken из фонового опроса выпала, а waiting — опрошена" $?
{ [ ! -f "$HC/home/20260707-24.json" ] && has "20260707-21: "; }
is "недооформленная не опрашивается — полей пробы у неё нет" $?
{ jq -er '.rows>=1' "$HC/_run.json" >/dev/null; }
is "квитанция прогона записана: сколько строк спросили — видно" $?

# Укус 15 спеки. Замок берётся ДО прогона, поэтому второй процесс не идёт в сеть.
mkdir -p "$WAITING_HOME/waiting-lock"
wt "$WAITING_HOME" probe
{ [ "$rc" = 3 ] && has "замок занят"; }
is "второй probe выходит 3 и в сеть не идёт — замок, а не гонка" $?
rmdir "$WAITING_HOME/waiting-lock"

# Протухший замок снимается — и ФАКТ снятия печатается (Р19).
mkdir -p "$WAITING_HOME/waiting-lock"
touch -A -020000 "$WAITING_HOME/waiting-lock" 2>/dev/null \
  || touch -t "$(date -v-2H +%Y%m%d%H%M)" "$WAITING_HOME/waiting-lock"
wt "$WAITING_HOME" probe
{ [ "$rc" != 3 ] && has "снят протухший замок пробы"; }
is "протухший замок снят, и снятие НАЗВАНО — тихое скрыло бы упавшую пробу" $?
{ jq -er '.stale_lock_broken==true' "$HC/_run.json" >/dev/null; }
is "…и записано в квитанцию прогона, а не только в stdout фона" $?

echo "=== третье состояние: taken не будит, но из list не исчезает ==="

# Укус 19 спеки. Пара: снятие ВИДНО в файле и группа СМЕНИЛАСЬ — оба даёт только
# работающий инструмент. Заглушка не пишет файл и печатает «з».
full "$HB" 20260808-11
wt "$WAITING_HOME" list
{ grp 20260808-11 | grep -q "ни разу не опрошена"; }
is "до taken строка стоит в обычной группе" $?
wt "$WAITING_HOME" taken home/20260808-11 "владелец сказал начинать"
{ [ "$rc" = 0 ] && has "взята в работу: home/20260808-11"; }
is "taken говорит, что строка взята, и называет ПОЛНЫЙ id" $?
{ inf "$HB/20260808-11.md" "state: taken" \
    && inf "$HB/20260808-11.md" 'taken_because: "владелец сказал начинать"'; }
is "taken пишет состояние И причину — правкой по ключу" $?
{ inf "$HB/20260808-11.md" "taken_at: $TODAY"; }
is "дату взятия ставит машина, а не человек" $?
wt "$WAITING_HOME" list
{ grp 20260808-11 | grep -q "взята в работу"; }
is "…и list печатает её в СЕДЬМОЙ группе, а не в вычисленной (Р8)" $?
{ has "взята в работу: владелец сказал начинать"; }
is "…и называет причину в самой строке вывода" $?

# taken без причины — отказ, а не запись с пустым полем.
full "$HB" 20260808-12
wt "$WAITING_HOME" taken home/20260808-12 "   "
{ [ "$rc" = 1 ] && nohas "взята в работу: home/20260808-12" \
    && ! grep -q "state: taken" "$HB/20260808-12.md"; }
is "taken без причины отказывает кодом 1 и файл не трогает" $?

# Р23, боевой случай приёмки: done → taken сохраняет надгробие.
line "$HB" 20260808-13 <<EOF
---
title: "закрыта, а работа только началась"
state: done
review_by: $PLUS7
stamped_at: $TODAY
host: none
cwd: none
probe: none
ripe_match: none
ripe_when: "слово владельца"
sample: none
entry: none
closed_at: 2026-09-11
closed_because: "ожидание кончилось, работа началась"
---
Тело.
EOF
wt "$WAITING_HOME" taken home/20260808-13 "перевод из ошибочного done"
{ [ "$rc" = 0 ] && inf "$HB/20260808-13.md" "state: taken" \
    && inf "$HB/20260808-13.md" 'closed_because: "ожидание кончилось'; }
is "Р23: done переводится в taken, и надгробие человека уцелело" $?
wt "$WAITING_HOME" list
{ grp 20260808-13 | grep -q "взята в работу"; }
is "…строка перестала быть снятой и печатается снова" $?
{ has "закрытие отменено"; }
is "…и list называет, что строка закрывалась — а не прячет это" $?

# state: taken без taken_because — брак формы, а не законное состояние.
line "$HB" 20260808-14 <<EOF
---
title: "taken без причины — откуда-то взялось руками"
state: taken
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
wt "$WAITING_HOME" list
{ grp 20260808-14 | grep -q "недооформленные"; }
is "taken без taken_because — недооформленная: форма громче состояния" $?

echo "=== квитанция: ключ — исход, а не дата ==="

# Класс «срок»: гасится пере-штампом, потому что серии у даты нет.
line "$HB" 20260808-21 <<EOF
---
title: "срок прошёл вчера, пробы нет"
state: waiting
review_by: $(date -v-1d +%Y-%m-%d)
stamped_at: $(date -v-8d +%Y-%m-%d)
host: none
cwd: none
probe: none
ripe_match: none
ripe_when: "ответ поддержки"
sample: none
entry: none
---
Тело.
EOF
wt "$WAITING_HOME" list
{ grp 20260808-21 | grep -q "созрело"; }
is "прошедший срок созревает строку — до квитанции" $?
wt "$WAITING_HOME" ack home/20260808-21
{ [ "$rc" = 0 ] && has "закрыто «срок»" && inf "$HB/20260808-21.md" "review_by: $PLUS7"; }
is "ack по сроку переклеивает review_by на +7 — у даты серии нет (Р9)" $?
{ inf "$HB/20260808-21.md" "acked_at: $TODAY"; }
is "…и записывает дату квитанции машиной" $?
wt "$WAITING_HOME" list
{ grp 20260808-21 | grep -q "ни разу не опрошена"; }
is "…и строка ушла из «созрело»: гашение видно в группе" $?

# Класс «исход пробы»: ключ — (исход, начало серии).
full "$HB" 20260808-22
cache home 20260808-22 "{\"outcome\":\"fired\",\"since\":\"2026-09-10T10:00:00\",\"last_run_at_ts\":$NOW,\"last_rc\":0}"
wt "$WAITING_HOME" ack home/20260808-22
{ [ "$rc" = 0 ] && has "закрыто «fired»" && inf "$HB/20260808-22.md" "acked_outcome: fired"; }
is "ack по исходу пишет класс исхода, а не «посмотрел»" $?
{ inf "$HB/20260808-22.md" "acked_key: "; }
is "…и ключ квитанции (Р10) — без него повторный исход неотличим от новой серии" $?
{ has "закрыто «fired»" && nohas "переклеен"; }
is "…и срок НЕ переклеивает: причина была не в сроке" $?

# Гасить нечего — и это сказано, а не сделано вид, что погасили.
full "$HB" 20260808-23
wt "$WAITING_HOME" ack home/20260808-23
{ [ "$rc" = 0 ] && has "гасить нечего" \
    && ! grep -q "acked_key" "$HB/20260808-23.md"; }
is "ack по строке вне дельты ничего не пишет и говорит об этом" $?

# Непарсящаяся строка: машина квитанцию не ставит (инвариант 7).
line "$HB" 20260808-24 <<EOF
---
title: "кавычка не закрыта
state: waiting
---
Тело.
EOF
wt "$WAITING_HOME" ack home/20260808-24
{ [ "$rc" = 1 ] && ! grep -q "acked_key" "$HB/20260808-24.md" \
    && has "квитанцию машина в такой файл не пишет"; }
is "ack в непарсящуюся строку отказывает кодом 1 — и говорит почему" $?

echo
echo "итог: ✅ $pass   ❌ $fail"
[ "$fail" = 0 ]
