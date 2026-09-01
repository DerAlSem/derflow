#!/usr/bin/env bash
# Гейт критик-слоя (derflow v4.3).
#
# Не даёт войти в реализацию или архивацию заявки openspec, пока её spec.md
# правился после последнего отмеченного прогона критиков.
#
# Правило, которое он держит: слой закрыт, когда проход по ИТОГОВОЙ редакции не
# породил правок. «Спека была свежей на момент запуска» выполнением не является.
#
# Молчит везде, где не применим: не тот инструмент, нет openspec/, заявка не
# опознана, у заявки нет дельты спек (skip_specs).
set -uo pipefail

payload=$(cat)
tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0

gated=0
args=""
case "$tool" in
  Skill)
    skill=$(printf '%s' "$payload" | jq -r '.tool_input.skill // empty')
    case "$skill" in
      opsx:apply|opsx:archive|opsx:bulk-archive|\
      openspec-apply-change|openspec-archive-change|openspec-bulk-archive-change)
        gated=1 ;;
    esac
    args=$(printf '%s' "$payload" | jq -r '.tool_input.args // empty')
    ;;
  Bash)
    cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
    case "$cmd" in
      *"openspec archive"*) gated=1; args="$cmd" ;;
    esac
    ;;
esac
[ "$gated" -eq 1 ] || exit 0

# Корень openspec ищем вверх от текущего каталога — работает и в ворктри.
changes_dir=""
d=$PWD
while [ "$d" != "/" ]; do
  if [ -d "$d/openspec/changes" ]; then changes_dir="$d/openspec/changes"; break; fi
  d=$(dirname "$d")
done
[ -n "$changes_dir" ] || exit 0

# Какая заявка названа в аргументах. Не опознали — не блокируем вслепую.
id=""
for c in "$changes_dir"/*/; do
  name=$(basename "$c")
  [ "$name" = "archive" ] && continue
  case "$args" in *"$name"*) id="$name"; break ;; esac
done
[ -n "$id" ] || exit 0

specs="$changes_dir/$id/specs"
[ -d "$specs" ] || exit 0

# Хеш = СОДЕРЖИМОЕ спеки плюс ОТНОСИТЕЛЬНЫЕ пути внутри specs/.
#
# ⚠️ Абсолютный путь сюда попадать не должен. Репозиторий работается ворктри на
# задачу, и заявка регулярно переезжает между деревьями; с абсолютным путём в
# хеше отметка о пройденной критике переставала сходиться на ровном месте, хотя
# текст спеки не менялся ни на символ (поймано 14.08.2026 перед архивацией).
# Относительный путь при этом остаётся в расчёте намеренно: перенос спеки в
# другую capability — это изменение дельты, и критику оно требует заново.
cur=$(cd "$specs" && find . -type f -name '*.md' | LC_ALL=C sort | while IFS= read -r f; do
  printf '%s ' "$f"
  shasum -a 256 "$f" | cut -d' ' -f1
done | shasum -a 256 | cut -d' ' -f1)
[ -n "$cur" ] || exit 0

marker="$changes_dir/$id/.critique"
rec=""
[ -f "$marker" ] && rec=$(head -n1 "$marker" | tr -d '[:space:]')

[ "$cur" = "$rec" ] && exit 0

if [ -z "$rec" ]; then
  reason="критик-слой по заявке «${id}» не отмечен ни разу"
else
  reason="spec.md заявки «${id}» правился после последнего прогона критиков"
fi

cat >&2 <<EOF
ГЕЙТ derflow (критик-слой): $reason.

Слой закрыт, когда проход по ИТОГОВОЙ редакции не породил правок. Слияние
резолюций — само по себе источник дефектов: прогон, читавший прежний текст, о
них не знает по построению.

Что сделать:
  1. Прогнать system-architect и gap-finder по ТЕКУЩЕМУ тексту спеки.
  2. Приземлить принятые резолюции в SHALL'ы (не в прозу design.md).
  3. Отметить прогон:  ~/.claude/hooks/openspec-critique-record.sh ${id}

Отметка привязана к содержимому specs/ — любая последующая правка спеки снова
закроет гейт. Это и есть смысл: правка после критики означает некритикованный
текст.
EOF
exit 2
