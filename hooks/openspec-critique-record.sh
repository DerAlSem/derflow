#!/usr/bin/env bash
# Отметить, что критик-слой прошёл по ТЕКУЩЕЙ редакции спеки заявки openspec.
#
# Пишет openspec/changes/<id>/.critique с хешем содержимого specs/. Любая
# последующая правка спеки делает отметку недействительной — это и есть гейт.
#
# Использование:  openspec-critique-record.sh <change-id> [заметка]
set -euo pipefail

id=${1:?Укажи id заявки. Пример: openspec-critique-record.sh widget-venue-self-serve}
note=${2:-}

changes_dir=""
d=$PWD
while [ "$d" != "/" ]; do
  if [ -d "$d/openspec/changes" ]; then changes_dir="$d/openspec/changes"; break; fi
  d=$(dirname "$d")
done
[ -n "$changes_dir" ] || { echo "openspec/changes не найден вверх от $PWD" >&2; exit 1; }

specs="$changes_dir/$id/specs"
[ -d "$specs" ] || { echo "У заявки «${id}» нет specs/ — критиковать нечего" >&2; exit 1; }

cur=$(find "$specs" -type f -name '*.md' | LC_ALL=C sort | while IFS= read -r f; do
  shasum -a 256 "$f"
done | shasum -a 256 | cut -d' ' -f1)

{
  echo "$cur"
  echo "# критик-слой отмечен пройденным по этой редакции спеки"
  echo "# когда: $(date '+%F %T %z')"
  [ -n "$note" ] && echo "# что: $note"
  echo "# Хеш выше — содержимое specs/. Правка спеки после этой отметки снова"
  echo "# закрывает гейт: изменённый текст критики не проходил."
} > "$changes_dir/$id/.critique"

echo "Отмечено: $id ($cur)"
