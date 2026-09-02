#!/usr/bin/env bash
# Расщепление сессии: открыть свежую в нужном каталоге, накормив её хендоффом.
#
# Транспорт между сессиями не должен быть человеком. Состояние лежит в файле,
# поэтому промпт следующей сессии — КОНСТАНТА, а не сочинение на пике контекста.
#
#   hand.sh                      # хендофф ищется в текущем каталоге
#   hand.sh <каталог>            # ищется там
#   hand.sh <каталог> <файл>     # явный путь
#   hand.sh -n ...               # только показать команду, не открывать окно
#
# Каталог тот же? Терминал не нужен вовсе — `/clear` в текущей сессии и та же
# константная строка.
set -euo pipefail

dry=0
[ "${1:-}" = "-n" ] && { dry=1; shift; }

dir="${1:-$PWD}"
[ -d "$dir" ] || { echo "нет каталога: $dir" >&2; exit 1; }
dir="$(cd "$dir" && pwd)"

if [ "${2:-}" ]; then
  hand="$2"
else
  # Путь ключуется ЗАДАЧЕЙ, а не репозиторием. Общее имя в корне — общий
  # изменяемый ресурс: две сессии в одном дереве затрут хендоффы друг друга, и
  # преемник уверенно продолжит чужую работу. Порядок от уникального к общему.
  hand=""
  br="$(cd "$dir" && git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  # 1. заявка openspec — уникальна по задаче по построению
  if [ -z "$hand" ]; then
    hand="$(find "$dir/openspec/changes" -maxdepth 2 -name HANDOFF.md 2>/dev/null \
            | head -1 || true)"
  fi
  # 2. по ветке — уникальна, пока соблюдается «ветка на проблему»
  if [ -z "$hand" ] && [ -n "$br" ]; then
    c="$dir/.claude/handoff/${br//\//-}.md"
    [ -f "$c" ] && hand="$c"
  fi
  # 3. корень — совместимость со старой конвенцией, столкновению открыт
  if [ -z "$hand" ]; then
    for c in "$dir/HANDOFF.md" "$dir/ПРОДОЛЖИТЬ.md"; do
      [ -f "$c" ] && { hand="$c"
        echo "⚠️  хендофф лежит в корне — общее имя на весь репозиторий." >&2
        echo "    две сессии в одном дереве затрут его друг другу; перенеси в" >&2
        echo "    .claude/handoff/<ветка>.md либо к артефактам заявки." >&2
        break; }
    done
  fi
fi

if [ -z "$hand" ] || [ ! -f "$hand" ]; then
  echo "хендоффа не найдено в $dir" >&2
  echo "создай HANDOFF.md — без него расщеплять нечем: состояние передаётся файлом" >&2
  exit 1
fi
hand="$(cd "$(dirname "$hand")" && pwd)/$(basename "$hand")"

# Несвежий хендофф хуже отсутствующего: следующая сессия поверит устаревшему
# тексту и переделает сделанное. Сравниваем с самым новым изменением в дереве.
newest="$(cd "$dir" && git status --porcelain 2>/dev/null | awk '{print $NF}' \
          | while IFS= read -r f; do [ -f "$f" ] && stat -f '%m %N' "$f"; done \
          | sort -rn | head -1 | cut -d' ' -f1 || true)"
if [ -n "$newest" ] && [ "$newest" -gt "$(stat -f '%m' "$hand")" ]; then
  echo "⚠️  ХЕНДОФФ СТАРШЕ ПОСЛЕДНИХ ПРАВОК — обнови его до расщепления," >&2
  echo "    иначе свежая сессия начнёт с устаревшего состояния." >&2
  echo "    $hand" >&2
  exit 2
fi

# Чужой хендофф опаснее отсутствующего: он выглядит валидным. Если в шапке
# объявлена ветка и она не текущая — это хендофф другой задачи, стоп.
declared="$(grep -m1 -E '^ветка:' "$hand" 2>/dev/null | sed 's/^ветка:[[:space:]]*//' || true)"
cur="$(cd "$dir" && git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -n "$declared" ] && [ -n "$cur" ] && [ "$declared" != "$cur" ]; then
  echo "❌ ХЕНДОФФ ОТ ДРУГОЙ ЗАДАЧИ: в нём объявлена ветка «${declared}», текущая «${cur}»." >&2
  echo "   Это чужое состояние — продолжать по нему нельзя." >&2
  exit 3
fi
[ -z "$declared" ] && echo "⚠️  в хендоффе нет строки «ветка:» — принадлежность не проверяется" >&2

rel="${hand#$dir/}"
prompt="Прочитай ${rel} — там всё состояние и порядок шагов — и продолжай."

echo "каталог: $dir"
echo "хендофф: $rel"
echo "промпт:  $prompt"
# Ни ${var@Q} (нет в bash 3.2), ни printf %q (он разносит UTF-8 по байтам, а
# промпт русский). Оборачиваем в одинарные кавычки, экранируя только их сами.
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
q_dir="$(sq "$dir")"
q_prompt="$(sq "$prompt")"
if [ "$dry" = 1 ]; then
  echo "команда: open -na Ghostty.app --args --working-directory=$dir -e zsh -lc \"cd $q_dir && claude ${q_prompt}\""
  exit 0
fi
open -na Ghostty.app --args --working-directory="$dir" -e zsh -lc \
  "cd $q_dir && claude $q_prompt"
echo "окно Ghostty запрошено"
