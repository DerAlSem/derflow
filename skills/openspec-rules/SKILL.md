---
name: openspec-rules
description: Use when working in a project with `openspec/`, authoring or implementing a change, validating proposal.md, design.md, tasks.md, or spec.md, archiving completed work, or applying the OpenSpec-first rule to a bug. The format-and-lifecycle reference behind derflow's Lane C.
license: MIT
---

# OpenSpec rules — for projects with `openspec/` directory

**Tool:** [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) v1.5.0,
already installed globally. CLI: `openspec`.

**Schema:** `schema: spec-driven` (in `openspec/config.yaml`).

This skill is the canonical **format** reference. **Routing** — which lane a task
takes and when Lane C fires at all — lives in `derflow` (`skills/derflow/SKILL.md`
and its `_lane-c.md` engine). This file documents the format and lifecycle that
derflow's Lane C relies on; per-project overrides live in the project's
`CLAUDE.md`.

## Layout (one `openspec/` directory per project)

```
openspec/
├── config.yaml                         # schema: spec-driven, context, per-artifact rules
├── specs/<capability>/spec.md          # normative: how the system currently IS
└── changes/
    ├── <id>/proposal.md                # why + what changes (≤500 words typical)
    ├── <id>/design.md                  # technical shape, diagrams, trade-offs
    ├── <id>/tasks.md                   # numbered checklist, ≤2h chunks each
    └── archive/                        # completed changes — immutable, searchable
```

`<capability>` is a unit of business behavior, NOT a module name. Examples:
`booking` · `payments` · `analytics-capacity` · `participant-money-first-lifecycle`.

## Change ID convention

Active change IDs are **undated** kebab-case: `<short-kebab>`. Examples:
`add-dark-mode`, `booking-pos-handoff`, `analytics-period-comparison`.

`openspec archive` adds the completion date to the archive directory. **Do not put
a date in an active ID** — otherwise archive creates a double timestamp, and the
CLI rejects change names starting with a digit outright. If a legacy active ID
already starts with `YYYY-MM-DD-`, rename it and validate references before
archiving.

**Consequence for ordering.** Because active IDs carry no date, you cannot order
competing changes by name. When several changes touch the same capability and you
need to know which supersedes which (see derflow's Lane C-drain), **git is the
only source of order** — `git log --diff-filter=A --format='%ad %s' --date=short
-- openspec/changes/<id>/`.

## Core principle: apply is not archive

`apply` means implement the tasks in `tasks.md`. `archive` means close a completed
change and merge its spec deltas into the living specs. They are separate user
actions and separate lifecycle stages.

OpenSpec v1.5.0 has no `openspec apply` CLI command. `/opsx:apply` is an AI
workflow command, not a terminal command. Use
`openspec instructions apply --change <id>` to load implementation guidance
into the agent prompt; the agent then writes the code and ticks off tasks. The
CLI does not execute code.

## The change lifecycle

```
openspec new change <id>                  # scaffold change/<id>/ artifacts
    ↓
openspec validate <id> --strict           # schema check; fix-then-revalidate
    ↓
openspec show <id>                        # author reads the proposal once more
    ↓
STOP gate 1: wait for explicit «go» / «apply» / «открываем change»
    ↓
openspec status --change <id>             # tripwire 1: artifacts exist, tasks not started
openspec instructions apply --change <id> # loads enriched guidance into the prompt
    ↓
implement tasks with TDD; check off tasks.md as each task completes
    ↓
run tests, lint, typecheck, and gap-finder
    ↓
STOP gate 2: wait for explicit «archive» / «архивируй change»
    ↓
openspec status --change <id>             # tripwire 2: artifacts complete, all tasks - [x]
    ↓
openspec archive <id>                     # interactive; archive/<YYYY-MM-DD>-<id>/
```

The first `openspec status` confirms artifacts and makes the agent see an
empty task list before writing code. The second `openspec status` is the
hard tripwire: if any task is `- [ ]`, stop. `--yes` skips the interactive
prompt but does not invalidate the status check; never use `--yes` to push
past an incomplete change.

## Формат артефактов — НЕ здесь (v4.0)

**Источник правды по формату — схема инструмента**, а не этот файл:
`openspec/schemas/<name>/schema.yaml` плюс `templates/`. Схема задаёт набор
артефактов, их зависимости, инструкции и шаблоны; `openspec instructions`
отдаёт их агенту.

Раньше здесь лежал собственный образец формата с требованиями вида
`### SHALL-001:` и Given/when. **Он был неверен и приводил к тихому отказу.**
Канон — `### Requirement: <имя>` плюс `#### Scenario: <имя>` с WHEN/THEN, и
сценарий обязан иметь **ровно четыре решётки**: с тремя он не распознаётся,
требование остаётся без сценариев, а валидатор требует минимум один. В
проверенном проекте `SHALL-NNN` не встречался ни разу — формат существовал
только в этом файле.

Три правила формата, которые стоит помнить, потому что их нарушение теряет
данные молча:

- **`## Purpose` обязателен в дельте НОВОЙ capability** (50+ символов).
  Archive копирует его в создаваемую главную спеку; без него остаётся
  `TBD … Update Purpose after archive`, и починить это можно **только прямой
  правкой** `openspec/specs/<capability>/spec.md` — дельтой нельзя.
- **`MODIFIED` содержит ПОЛНЫЙ блок требования** со всеми сценариями.
  Частичный теряет содержимое при слиянии через CLI.
- **Изменение без изменения поведения** — `skip_specs: true` в
  `.openspec.yaml` заявки. Иначе `openspec validate` отвергнет нулевую
  дельту. Не выдумывай требование ради валидации.

## When to OPEN a change vs fix directly

| Situation | Action |
|---|---|
| Bug in code that matches existing spec | Fix code; spec doesn't change. **DO NOT** open a change. |
| Bug in code where NO spec covers the area | Fix code + write `descriptive` spec after. |
| Bug exposes a spec that's wrong | Open a change. Proposal explains why spec was wrong. |
| New feature / behavior change | Always open a change. |
| Schema / API / contract change | Always open a change (incl. migration strategy in `design.md`). |
| Trivial typo / off-by-one / formatting | Fix directly. No change. |

This table is the **checkable** form of derflow's A/B/C boundary — when the lane
is ambiguous, decide here and announce accordingly.

## The "OpenSpec-first lookup" rule

When a user reports a problem — *"shows 1000₽, should be 28°"* — the agent's
first move is **NOT to grep the code**. It's:

1. Check `openspec/specs/<capability>/spec.md` for the affected area.
2. Run `openspec list` and check `openspec/changes/<id>/` (excluding `archive/`)
   for in-flight work.
3. If a spec exists — **read it**, fix per spec, **the spec is the source of truth**.
4. If no spec — read the code, fix it, **then write a `descriptive` spec** for
   the affected capability so next time we don't repeat the archaeology.

This is derflow v3.19 (`_lane-c.md` → «Спека читается первой»); here is the full
form with its rationale. Tokens saved by reading 1–2K of spec instead of 3–10K of
code per fix. Compounded over time: each fix thickens the spec layer, so
archaeology happens less.

## Drift detection

After implementing a change that touches an adopted seam, run
`openspec validate <spec-path>` to ensure no SHALL was contradicted.

For projects using `adopt-code`, the `_conformance-sweep` reference (in skills)
gives the full `code ↔ spec ↔ memory` 3-axis check.

## Recovery from a wrong archive

If `openspec archive` ran on an incomplete change (most often because `--yes`
pushed past a warning, or because the agent substituted `archive` for `apply`):

1. **Confirm scope of damage.** `git status` and `git diff HEAD~N..HEAD --
   openspec/specs/` for each affected capability. If the live spec already
   received deltas that the unimplemented code does not back, revert those
   spec files.
2. **Move the archive directory out of `changes/archive/`.** OpenSpec CLI
   rejects change names starting with a digit, so any leading date prefix
   must be dropped before the directory is reusable:
   ```
   mv openspec/changes/archive/<YYYY-MM-DD>-<id> openspec/changes/<id>
   ```
   Repeat in every worktree that mirrors the change.
3. **Re-validate and re-status.**
   ```
   openspec validate <id> --strict
   openspec status --change <id>
   ```
4. **Resume the proper lifecycle.** Continue with `openspec instructions apply
   --change <id>`, implement the remaining tasks, and archive only after the
   status tripwire shows 100% complete and verification is green.

If the proposal/design/tasks are not worth preserving, drop the mis-archived
directory and start fresh with `openspec new change <id>`.

## Plain CLI recipe (no `/opsx:` slashes)

Use this when `/opsx:propose`, `/opsx:apply`, `/opsx:archive` are not available —
the canonical terminal flow, identical on any harness:

```
# Author
openspec new change <id>                    # <id> is undated kebab-case
$EDITOR openspec/changes/<id>/proposal.md
$EDITOR openspec/changes/<id>/tasks.md
[opt] $EDITOR openspec/changes/<id>/design.md
openspec validate <id> --strict

# STOP gate 1: wait for explicit «go» / «apply».
# Apply
openspec show <id>
openspec status --change <id>               # expect artifacts present, 0/N tasks
openspec instructions apply --change <id>   # loads guidance into the prompt
# ↑ The output is a PROMPT — read it, write the code, tick off tasks.
# Run project tests, lint, typecheck per verification-before-completion.

# STOP gate 2: wait for explicit «archive».
# Archive
openspec status --change <id>               # MUST show all tasks - [x]
openspec archive <id>                       # interactive prompts
# result: openspec/changes/archive/<YYYY-MM-DD>-<id>/  (single date, today)
```

When the user does not name the change, run `openspec list` to find active
changes before doing anything else.

## Per-artifact rules — override via `openspec/config.yaml`

```yaml
schema: spec-driven
context: |
  <freeform: tech stack, conventions, domain knowledge. Injected into AI
  prompts so agents don't have to re-derive it. Example from mprz.ru:
  "FastAPI (Python, async SQLAlchemy) + Vue 3 front. Alembic migrations.
   pg_hba gated per venue. PrimeVue DatePicker, format dd.mm.yy.">
rules:
  proposal:
    - Keep proposals under 500 words
    - Always include a "Non-goals" section
  tasks:
    - Break tasks into chunks of max 2 hours
```

## CLI quick reference

```bash
openspec --help
openspec list
openspec show <id>
openspec new change <id>
openspec validate <id> --strict
openspec status --change <id>
openspec instructions apply --change <id>
openspec archive <id>
```

Useful `--change` and `--spec` flags: see `openspec <subcommand> --help`.

## Common mistakes

| Temptation | Required action |
|---|---|
| User says `apply`, so run `openspec archive` | Implement `tasks.md`; never archive in the same step. |
| `openspec apply` is missing, so substitute the closest CLI command | Do not substitute. Use `openspec instructions apply --change <id>` and implement the code. |
| `--yes` looks like a way to silence warnings | Skip the interactive prompt only when `openspec status --change <id>` already shows 100% tasks. Never bypass incomplete-task warnings. |
| Archive ran on an unfinished change | Follow the "Recovery from a wrong archive" section; do not leave the change archived. |
| Active change ID already contains a date | Rename before any archive (CLI rejects names starting with a digit): `git mv changes/<YYYY-MM-DD>-<id> changes/<id>`, then `openspec validate <id> --strict`. |
| Implementation looks complete | Run `openspec status` and the project tests, lint, typecheck; then obtain explicit archive authorization. |
| Change finished and left in `changes/` | Archiving IS the step that updates the living spec. A 100%-done change sitting unarchived means the docs never learned anything (derflow v3.18). |

## Rationalizations to reject

| Rationalization | Reality |
|---|---|
| "Archive must be the new name for apply." | Archive closes completed work; it does not implement tasks. |
| "`--yes` means the user authorized everything." | It skips one CLI prompt; it does not waive lifecycle gates. |
| "Updating the living spec applies the feature." | Specs can update while code remains untouched; implementation comes first. |
| "I'll archive the backlog later, in one sweep." | Archive asserts the delta is true in code. A bulk archive without a per-change check writes fiction into the living spec (derflow Lane C-drain). |

## Red flags — stop

- About to run `openspec archive` after the user said only `apply` or `go`.
- Looking for a replacement command after `openspec apply` fails.
- `openspec status --change <id>` reports `0/N tasks` or any `- [ ]` task before archive.
- An active change ID begins with a date — CLI rejects it.
- A wrong archive already happened; leaving it in `changes/archive/` and starting a new change hides the incident.
- User did not name the change and you have not run `openspec list`.

Any red flag means: leave the change active, report the blocker, and do not modify
living specs or `changes/archive/` until the user authorizes the next step.
