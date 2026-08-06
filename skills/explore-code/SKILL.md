---
name: explore-code
description: Use when you need to understand an unfamiliar or freshly-cloned codebase — "разберись в этом репо", "help me onboard", "what does this repo do / how does it work", "где тут вход". Lazy, path-driven orientation of an UNKNOWN repo via golden-path tracing + seam discovery, asking the human only about intent. NOT for auditing your own project (that is audit-code) and NOT bug-hunting a diff (that is /code-review).
---

# explore-code — trace one path through an unfamiliar repo

A **discipline layer, not machinery.** The model already traces a path well once it
is scoped, fenced, and issued in few round-trips — this skill fixes the scope, the
fence, and how it spends turns, so every run is reproducible and cheap. Goal: follow
**one real action end-to-end** through the layers — the way a senior onboards — *not*
survey the tree.

## Execution discipline

Minimize the number of model turns.

Before calling tools, identify all information needs that can be investigated independently. Group independent searches and file reads into batched tool calls in the same turn.

Use no more than 5 tool calls unless additional calls are necessary to resolve a concrete gap that prevents completing the trace.

## Evidence budget

Trace the narrowest path that can answer the question with confidence.

Prefer the minimum sufficient evidence over exhaustive coverage:
- locate the entry point;
- follow the primary execution path;
- inspect only files required to resolve that path;
- stop when the mechanism can be explained end-to-end.

Do not inspect adjacent implementations, tests, migrations, ownership, edge cases,
or potential defects unless they are necessary to answer the user's question.

Expand the investigation only when the current evidence leaves a concrete unresolved
gap in the primary path.

## Flow

1. **Get the intent — at most ONE question, only about the goal.** If the human
   already named a concrete behaviour ("how does saving work"), don't ask — you have
   it. Otherwise ask one plain-goal question ("what are you trying to do / understand
   here?") — **never** make them name a path / file / component / entry point; on an
   unknown repo they can't, and it isn't their job. Intent **scopes the hunt for**
   the entry, it does not hand it to you: **you** then cheaply locate the likely
   entry (grep the route / handler / command / UI action it names; read the manifest)
   and trace from there. Intent is not importance — never measure centrality, never
   ask "how important is X".
2. **Trace THAT path end-to-end:** entry → … → data/side-effect. Name concrete
   **`file:line` and functions** at each hop. The trace — not a directory listing —
   *is* the comprehension.
3. **Do NOT** survey the whole tree, read the whole repo, or **hunt** for
   security / quality / tests / dead-code / cross-cutting concerns. A defect met
   **on the traced path** (double-write, race, N+1, odd semantics) — **flag it in
   passing.** A concern **off the path** — out of scope; that is `audit-code` /
   `/code-review` / `/security-review`. On-path: flag. Off-path: forbidden.
4. **Hand off:** the traced path + the **seams it crossed** (module boundaries) +
   **ownership** (who owns each table / event / API on the path) + **UNRESOLVED**
   items — each with an **escalation target** (git-blame author / PR / ticket),
   never a silent guess. Mark every claim **guess vs verified**. Secrets:
   skip/redact. Notes are **disposable** (scratch for the task, not a persisted map).
5. **Terminate** the moment the path is traced and its seams are presented — hand the
   outputs to the current task (A/B/C/Dx via **derflow**). Catching yourself building
   a *general picture* of the repo = you have drifted into `audit-code`; **stop.**
