#!/usr/bin/env python3
"""check — утверждения памяти и спек против кода.

Спека говорит, что ДОЛЖНО быть истинно; память — где ошибётся следующий. Обе
называют символы и пути. Файл переименовали — и обе тихо стали ложью: git этого
не заметит, критик читает текст против текста, а `openspec validate` проверяет
форму. Здесь текст читается против КОДА.

    check.py [repo]              # по умолчанию — cwd
    check.py --selftest          # укус сторожа на фикстуре

Отчёт, а не гейт: код возврата всегда 0, читает человек. Гоняется перед
архивацией заявки и на гигиене памяти.
"""

import argparse, os, pathlib, re, subprocess, sys, tempfile, shutil, collections

# ── формы токенов ─────────────────────────────────────────────────────────────
# Проза в бэктиках не проходит ни одну: русское слово не snake, не Camel, не путь.
TICK  = re.compile(r"`([^`\n]{2,100})`")
WIKI  = re.compile(r"\[\[([^\]\n]{1,120})\]\]")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
SNAKE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)+$")
CAMEL = re.compile(r"^[A-Z][A-Za-z0-9]*[a-z][A-Z][A-Za-z0-9]*$")
DOTT  = re.compile(r"^[A-Za-z_]\w*(\.[A-Za-z_]\w*)+$")

EXT = ("py js jsx ts tsx vue svelte html htm css scss sass sql sh bash zsh md yaml yml "
       "json toml ini cfg conf txt env mako jinja jinja2 j2 rb go rs java kt php lua tf").split()
PATHR = re.compile(r"^[\w][\w./@-]*\.(" + "|".join(EXT) + r")$")

# Каталоги, которых в дереве кода нет по смыслу: чужое, сборочное, изолированное.
SKIPDIR = {".git", "node_modules", ".venv", "venv", "env", "__pycache__", ".claude",
           "dist", "build", ".next", ".nuxt", ".mypy_cache", ".pytest_cache",
           ".ruff_cache", "site-packages", ".tox", "coverage", ".idea", ".vscode"}
BINARY  = {".png",".jpg",".jpeg",".gif",".webp",".ico",".svg",".pdf",".zip",".gz",".tar",
           ".woff",".woff2",".ttf",".otf",".eot",".mp4",".mp3",".wav",".db",".sqlite",
           ".sqlite3",".pyc",".pyo",".so",".dylib",".dll",".bin",".xlsx",".docx",".psd"}
LOCKS   = {"package-lock.json","yarn.lock","poetry.lock","pnpm-lock.yaml","Pipfile.lock",
           "uv.lock","composer.lock","Cargo.lock"}
MAXSIZE = 2 * 1024 * 1024


def shape(tok):
    """Какого рода утверждение это может быть; None — проза, не проверяем.

    Путь обязан нести расширение и не начинаться со слэша. Оба условия оплачены
    живым прогоном: без первого в «пути» проваливаются URL-маршруты (`/events/:id`)
    и команды оболочки, и 13 находок превращаются в 326 — отчёт, который не читают.
    """
    if re.search(r"\s", tok): return None
    if tok.startswith(("/", "http://", "https://")): return None
    if PATHR.match(tok.removeprefix("./")): return "path"
    if DOTT.match(tok):  return "dotted"
    if SNAKE.match(tok): return "snake"
    if CAMEL.match(tok): return "camel"
    return None


def build_index(repo):
    """Один проход. Идентификаторы — ТОЛЬКО из кода.

    Markdown в индекс идентификаторов не входит намеренно: пустив его туда,
    получишь спеку, которая удовлетворяет сама себя — символ найдётся в её же
    тексте, и чекер зазеленеет на всех настоящих находках. Пути при этом берутся
    из ВСЕХ файлов, включая `openspec/**/*.md`: ссылка на `tasks.md` заявки —
    законное утверждение о дереве.
    """
    idents, paths, basenames, ncode = set(), set(), set(), 0
    for root, dirs, files in os.walk(repo):
        dirs[:] = [d for d in dirs if d not in SKIPDIR]
        for name in files:
            p = pathlib.Path(root) / name
            try: rel = p.relative_to(repo).as_posix()
            except ValueError: continue
            paths.add(rel); basenames.add(name)
            if p.suffix.lower() in BINARY or name in LOCKS or p.suffix.lower() == ".md":
                continue
            try:
                if p.stat().st_size > MAXSIZE: continue
                idents.update(IDENT.findall(p.read_text(encoding="utf-8", errors="ignore")))
                ncode += 1
            except OSError:
                continue
    return {"idents": idents, "paths": paths, "basenames": basenames, "ncode": ncode}


def memory_dir(repo, override=None):
    """Каталог памяти привязан к слагу рабочего каталога: не-буквенно-цифровое → дефис."""
    if override: return pathlib.Path(override).expanduser()
    slug = re.sub(r"[^a-zA-Z0-9]", "-", str(repo))
    return pathlib.Path.home() / ".claude" / "projects" / slug / "memory"


def changes(repo):
    live, arch = set(), set()
    c = repo / "openspec" / "changes"
    if c.is_dir():
        for d in c.iterdir():
            if d.is_dir() and d.name != "archive": live.add(d.name)
        a = c / "archive"
        if a.is_dir():
            arch = {d.name for d in a.iterdir() if d.is_dir()}
    return live, arch


def verify(tok, kind, idx):
    """(ок, пояснение). Не найдено — значит в коде правда нет: индекс полон по построению."""
    if kind == "path":
        tok = tok.removeprefix("./")
        if tok in idx["paths"]:                  return True, "точно"
        if tok.split("/")[-1] in idx["basenames"]: return True, "по имени файла"
        return False, "файла нет в дереве"
    if kind == "dotted":
        segs = [s for s in tok.split(".") if len(s) > 2]
        miss = [s for s in segs if s not in idx["idents"]]
        return (not miss), ("нет: " + ", ".join(miss) if miss else "")
    return (tok in idx["idents"]), "нет в коде"


def scan(files, label, idx, mem_names, arch, findings):
    """Разбирает корпус и складывает находки в общий список."""
    for f in files:
        try: text = f.read_text(encoding="utf-8")
        except OSError: continue
        src = f"{label}: {f.parent.name if f.name == 'spec.md' else f.name}"

        for m in TICK.finditer(text):
            tok = m.group(1).strip()
            kind = shape(tok)
            if not kind: continue
            ok, why = verify(tok, kind, idx)
            if not ok:
                findings["путь" if kind == "path" else "символ"].append((tok, why, src))

        if label == "память":
            for m in WIKI.finditer(text):
                name = m.group(1).strip()
                if name not in mem_names:
                    findings["связь"].append((f"[[{name}]]", "такой памяти нет", src))

        for cid in arch:
            if re.search(r"(?<![\w-])" + re.escape(cid) + r"(?![\w-])", text):
                findings["заявка"].append((cid, "в archive/", src))


def report(repo, idx, mem, memfiles, specfiles, findings):
    print(f"\ncheck · {repo.name}")
    print(f"  индекс   {idx['ncode']} файлов кода, {len(idx['idents'])} идентификаторов, "
          f"{len(idx['paths'])} путей")
    if memfiles is None:
        print(f"  ПАМЯТЬ НЕ ПРОВЕРЕНА — каталога нет или он пуст: {mem}")
        print( "           в ворктри память по слагу пуста всегда; пусто ≠ чисто")
    else:
        print(f"  память   {len(memfiles)} файлов")
    print(f"  спеки    {len(specfiles)} файлов")

    order = [("путь",   "ПУТИ — файла нет в дереве"),
             ("связь",  "СВЯЗИ ПАМЯТИ — битые"),
             ("заявка", "ЗАЯВКИ — названы, но заархивированы"),
             ("символ", "СИМВОЛЫ — нет в коде  ·  здесь живёт чужой словарь, читай глазами")]
    total = 0
    for key, title in order:
        rows = collections.OrderedDict()
        for tok, why, src in findings[key]:
            rows.setdefault((tok, why), []).append(src)
        print(f"\n{title} ({len(rows)})")
        if not rows:
            print("  —")
        for (tok, why), srcs in sorted(rows.items()):
            mark = "→" if key == "заявка" else "✗"
            print(f"  {mark} {tok}{('  — ' + why) if why else ''}")
            seen = sorted(set(srcs))
            print(f"      {', '.join(seen[:3])}" + (f" и ещё {len(seen)-3}" if len(seen) > 3 else ""))
        total += len(rows)
    print(f"\nитого {total} находок\n")
    return total


def run(repo, mem_override=None, quiet=False):
    repo = pathlib.Path(repo).expanduser().resolve()
    try:
        top = subprocess.run(["git", "-C", str(repo), "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True)
        if top.returncode == 0 and top.stdout.strip():
            repo = pathlib.Path(top.stdout.strip())
    except OSError:
        pass

    idx = build_index(repo)
    mem = memory_dir(repo, mem_override)
    memfiles = sorted(mem.glob("*.md")) if mem.is_dir() else []
    mem_names = {f.stem for f in memfiles}
    specfiles = sorted((repo / "openspec" / "specs").glob("*/spec.md"))
    _, arch = changes(repo)

    findings = collections.defaultdict(list)
    scan(memfiles, "память", idx, mem_names, arch, findings)
    scan(specfiles, "спека", idx, mem_names, arch, findings)

    if quiet:
        return findings
    return report(repo, idx, mem, memfiles or None, specfiles, findings)


# ── укус сторожа ──────────────────────────────────────────────────────────────
def selftest():
    """Оба контроля обязательны.

    Положительный ловит чекер, который не находит ничего вообще; отрицательный —
    который кричит на всё. Мутация проверяет, что сторож краснеет ИМЕННО от
    поломки того, что охраняет: живой путь ломается переименованием, и находка
    обязана появиться.
    """
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="check-selftest-"))
    ok = True
    try:
        repo, memd = tmp / "repo", tmp / "memory"
        (repo / "src").mkdir(parents=True); memd.mkdir()
        (repo / "src" / "app.py").write_text(
            "class UserDao:\n    def get_balance(self):\n        price_amount = 0\n        return price_amount\n")
        (repo / "openspec" / "specs" / "billing").mkdir(parents=True)
        (repo / "openspec" / "specs" / "billing" / "spec.md").write_text(
            "# billing\n\nСистема SHALL звать `UserDao.get_balance`, см. `src/app.py`.\n"
            "Ещё она SHALL звать `PromotionService`.\n")
        (memd / "live.md").write_text(
            "---\nname: live\n---\n\nБаланс считает `get_balance` в `src/app.py`.\n"
            "Связано: [[stale]].\n")
        (memd / "stale.md").write_text(
            "---\nname: stale\n---\n\nСмотри `src/gone.py` и `RenamedService`.\n"
            "Связано: [[never-existed]].\n")

        def toks(f):
            return {t for k in f for t, _, _ in f[k]}

        got = toks(run(repo, mem_override=memd, quiet=True))

        # положительный контроль: живое не обвиняем
        clean = {"get_balance", "src/app.py", "UserDao.get_balance", "[[stale]]"}
        false_alarm = clean & got
        if false_alarm:
            print(f"✗ ложная тревога на живом: {sorted(false_alarm)}"); ok = False
        else:
            print("✓ положительный контроль: живые символ, путь и связь не обвинены")

        # отрицательный контроль: мёртвое ловим
        must = {"src/gone.py", "RenamedService", "PromotionService", "[[never-existed]]"}
        missed = must - got
        if missed:
            print(f"✗ пропущено мёртвое: {sorted(missed)}"); ok = False
        else:
            print("✓ отрицательный контроль: мёртвые путь, символ и связь пойманы")

        # мутация: ломаем охраняемое — сторож обязан покраснеть
        (repo / "src" / "app.py").rename(repo / "src" / "app2.py")
        bitten = toks(run(repo, mem_override=memd, quiet=True))
        if "src/app.py" in bitten and "get_balance" not in bitten:
            print("✓ укус: переименование файла даёт находку по пути, символ уцелел")
        else:
            print(f"✗ укус не сработал: путь={'src/app.py' in bitten}, "
                  f"символ ложно={'get_balance' in bitten}"); ok = False
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\nselftest:", "ЗЕЛЁНЫЙ" if ok else "КРАСНЫЙ")
    return 0 if ok else 1


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("repo", nargs="?", default=".", help="корень репозитория (по умолчанию cwd)")
    ap.add_argument("--memory-dir", help="каталог памяти, если слаг cwd ведёт не туда (ворктри)")
    ap.add_argument("--selftest", action="store_true", help="укус сторожа на фикстуре")
    a = ap.parse_args()
    sys.exit(selftest() if a.selftest else (run(a.repo, a.memory_dir) and 0))
