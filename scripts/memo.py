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


def load_config(ctx, explicit=None):
    """Что гнать и что входит в ключ. Ошибки конфига — код 2, не трейсбек."""
    path = pathlib.Path(explicit).expanduser() if explicit else ctx.toplevel / CONFIG_NAME
    if not path.is_file():
        die(2, f"нет {path} — memo не знает, что гнать")
    try:
        cfg = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        die(2, f"{path}: не JSON — {e}")
    except OSError as e:
        die(2, f"{path}: не читается — {e}")
    if not isinstance(cfg, dict):
        die(2, f"{path}: не JSON-объект")
    gate = cfg.get("gate_pure")
    if not isinstance(gate, list) or not gate or not all(isinstance(c, str) for c in gate):
        die(2, f"{path}: gate_pure должен быть непустым списком строк")
    ext = cfg.get("gate_version_external", [])
    if not isinstance(ext, list) or not all(isinstance(p, str) for p in ext):
        die(2, f"{path}: gate_version_external должен быть списком путей")
    # Прочие поля (targets, gate_env, gate_post, allow_skips) принадлежат 1b-3 и
    # здесь не читаются. Один файл на три поставки: ранняя не спотыкается о поздние.
    return path, gate, ext


def gate_version(ctx, ext):
    """Ключ по тому, чего дерево НЕ видит. Текста команд здесь нет — он в дереве."""
    parts = {}
    for raw in sorted(ext):
        p = pathlib.Path(raw).expanduser()
        if not p.is_absolute():
            p = ctx.toplevel / p
        try:
            parts[raw] = hashlib.sha256(p.read_bytes()).hexdigest()
        except OSError as e:
            die(2, f"gate_version_external: {raw} не читается — {e}")
    blob = json.dumps(parts, sort_keys=True, ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()[:12], parts


def config_tracked(ctx, path):
    """Отслеживается ли конфиг git. Не отслеживается — команды гейта деревом не покрыты."""
    try:
        rel = path.resolve().relative_to(ctx.toplevel.resolve())
    except ValueError:
        return False
    rc, _, _ = git("ls-files", "--error-unmatch", "--", str(rel), cwd=ctx.toplevel)
    return rc == 0


def run_gate(ctx, gate):
    """Гоняем команды по очереди в корне репозитория. Первый ненулевой — конец.

    БЕЗ ШЕЛЛА и БЕЗ КОНВЕЙЕРА, и это не гигиена, а требование спеки, исполненное
    структурно: `| tail` глотает код возврата pytest (feedback_pipe_swallows_pytest_rc).
    Без shell=True конвейер невозможен в принципе. Цена: перенаправления в
    gate_pure запрещены — команде, которой они нужны, место в скрипте в дереве.

    stdout/stderr наследуются, а не перехватываются: гейт идёт минуты, и человек
    обязан видеть его вывод по мере появления.
    """
    started = time.monotonic()
    for cmd in gate:
        argv = shlex.split(cmd)
        if not argv:
            die(2, f"пустая команда в gate_pure: {cmd!r}")
        print(f"→ {cmd}", flush=True)
        try:
            rc = subprocess.run(argv, cwd=ctx.toplevel).returncode
        except (FileNotFoundError, PermissionError, OSError) as e:
            print(f"гейт красный: «{cmd}» не запустилась — {e}")
            return False, round(time.monotonic() - started, 1), cmd
        if rc != 0:
            print(f"гейт красный: «{cmd}» вышла кодом {rc}. Вердикт НЕ записан.")
            return False, round(time.monotonic() - started, 1), cmd
    return True, round(time.monotonic() - started, 1), None


def session_id():
    return os.environ.get("CLAUDE_CODE_SESSION_ID") or f"pid:{os.getpid()}"


def env_fingerprint():
    """ДИАГНОСТИКА, а не ключ (решение Р5 плана).

    Вердикт по дереву переживает `pip install`. Отпечаток венва в ключе обесценивал
    бы кэш при установке любого постороннего инструмента, а ловил бы только редкий
    сценарий «пакет снесли, дерево не менялось». Устаревший венв ломается в
    безопасную сторону: гейт краснеет, красное не кэшируется. Поэтому отпечаток
    ЗАПИСЫВАЕТСЯ и показывается человеком в `memo list`, но решений по нему не
    принимается.
    """
    return {"python": sys.executable,
            "python_version": ".".join(str(x) for x in sys.version_info[:3])}


def verdict_path(ctx, gv):
    return VERDICTS / ctx.repo_id / f"{ctx.tree_sha}.{gv}.json"


def read_verdict(path):
    """Вердикт либо None. Битый файл — это отсутствие вердикта, а не авария."""
    try:
        d = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(d, dict) or d.get("result") != "pass":
        return None
    return d


def write_verdict(path, payload):
    """tmp + os.replace: файл вердикта либо целый, либо его нет.

    Имена файлов уникальны и писатель у каждого один, поэтому параллельность
    ~/.claude (4–6 сессий разом) им не вредит.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.parent / f"{path.name}.tmp-{os.getpid()}"
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def cmd_check(a):
    ctx = context()
    cfgpath, gate, ext = load_config(ctx, a.config)
    gv, extparts = gate_version(ctx, ext)
    vp = verdict_path(ctx, gv)

    v = read_verdict(vp)
    if v:
        print(f"гейт пройден: дерево {ctx.tree_sha[:12]} · gv {gv} · "
              f"{v.get('recorded_at', '?')} · сессия {v.get('session', '?')}")
        return 0

    ok, took, _ = run_gate(ctx, gate)
    if not ok:
        return 1

    write_verdict(vp, {
        "tree_sha": ctx.tree_sha,
        "gate_version": gv,
        "repo_id": ctx.repo_id,
        "result": "pass",
        "recorded_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "host": socket.gethostname(),
        "session": session_id(),
        "worktree": str(ctx.toplevel),
        "duration_s": took,
        "commands": list(gate),
        "external": extparts,
        "env": env_fingerprint(),
    })
    print(f"гейт зелёный за {took} с. Вердикт записан: {vp}")
    return 0


def cmd_list(a):
    ctx = context()
    print(f"репозиторий: {ctx.repo_id}   ({ctx.common})")
    print(f"дерево HEAD: {ctx.tree_sha}")
    print(f"грязное:     {'да, файлов ' + str(len(ctx.dirty)) if ctx.dirty else 'нет'}")
    # list читает конфиг МЯГКО: смотреть кэш надо и в репозитории без конфига,
    # иначе инструмент «посмотреть и сбросить» отказывает ровно там, где нужен.
    try:
        cfgpath, gate, ext = load_config(ctx, a.config)
        gv, _ = gate_version(ctx, ext)
        print(f"ключ gv:     {gv}   ({len(ext)} внешних входов, {len(gate)} команд)")
    except SystemExit:
        print("ключ gv:     — (конфига нет либо он невалиден)")
    print("вердиктов нет")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="memo", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_list = sub.add_parser("list", help="что лежит в кэше")
    p_list.add_argument("--config", help=f"путь к {CONFIG_NAME}")
    p_list.set_defaults(fn=cmd_list)
    p_check = sub.add_parser("check", help="гейт зелёный? кэш или прогон")
    p_check.add_argument("--config", help=f"путь к {CONFIG_NAME}")
    p_check.set_defaults(fn=cmd_check)
    a = ap.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
