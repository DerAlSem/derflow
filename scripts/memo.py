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
