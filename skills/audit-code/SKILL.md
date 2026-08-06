---
name: audit-code
description: Use when you want a full pass over YOUR OWN project for documentation, debugging, and catching bad decisions — "прогони мой проект", "document/audit this repo", "where are the hotspots / bad decisions". Machine-measured graph + git-churn + gap-finder on top-N hotspots, freshness-bound persisted output that feeds spec-archaeology. NOT a quick unknown-repo look (that is explore-code) and NOT bug-hunting a diff (that is /code-review).
---

# audit-code — illuminate your own repo

**Read `~/.claude/skills/_orient-engine.md` first** — node schema, four
invariants, and cross-cutting rules (secrets, ontology, done+budget) all apply.

Goal: a full pass for documentation, debugging, and catching **bad decisions** —
but prioritised by what carries risk, not a blind full-depth fan-out (the least
defensible mode). Machine measures; the LLM judges and traces.

## Flow

1. **Docs-lead pre-pass, then machine-measure the whole repo** (engine). First
   read README/docs/docstrings for *intent* — the leading hypothesis to verify
   against code (docs are a claim; divergence = stale docs, same freshness logic
   as `rev`). Then measure: graph, churn, size, importance, secrets skip/redact →
   a full node inventory with lean fields machine-filled. Docs-lead ≠ docs-only —
   user-facing/selling copy and UI strings live in code/templates. Claiming
   "undocumented / absent" → first enumerate the surface (`git ls-files`
   extensions + subprojects), search **without an assumed-stack allowlist**, and
   answer "searched — everywhere?" (thin/exhausted → escalate / `UNRESOLVED`, not
   a silent "no"; engine rule 6).
2. **Prioritise — top-N hotspots** by fan-in × churn (the ~20% that carry risk),
   **with a hard default cap (≈10–15 nodes).** "The hot 20%" is a *ratio*, not a
   licence — on a big subsystem 20% is still 50+ nodes, and one worker per node is
   how a "quick audit" becomes millions of tokens. **Log dropped nodes explicitly**:
   "audited N of M; the rest are `stub`." No silent truncation (invariant + done/
   budget rule).
3. **Fan-out the rich pass** over hotspots via **Workflow** (one worker per node)
   → `gap-finder` for smells/bad-decisions + the `expected-but-absent` checklist
   by node type (this is what catches omissions, the worst bad decisions). All
   workers obey the fixed node schema + run glossary (fan-out ontology rule) so
   the result isn't self-contradictory.
   - **Estimate before you fan out — done+budget rule made concrete.** One worker ≈
     tens of k tokens; **N workers × ~50k ≈ the whole run** (a real tournament-
     subsystem audit fanned to 55 workers ≈ **2.9M tokens, unasked**). Before
     launching Workflow, **state the estimate out loud** — "N nodes × ~50k ≈ X
     tokens" — and if it exceeds the run's budget (a `+Nk` directive sets
     `budget.total` as a **hard** ceiling; wire it into the Workflow) **or** the
     default cap, **stop and confirm / cap to top-K.** Never silently fan out over
     every hotspot — the opening line of this skill calls blind full-depth fan-out
     "the least defensible mode"; the cap + the estimate are what enforce it.
4. **Roll-up.** Fill the cross-cutting registry; flag cycles; mark dead-code
   candidates (`liveness`); rank bad-decisions by impact.
5. **Persist, freshness-bound.** Stamp each node with `rev` (commit-SHA). The
   artifact lives **in-repo** (git-tracked, diffable) — regenerable, not hand-
   maintained. Re-verify = `git diff HEAD ↔ rev` → re-audit only changed paths;
   flag stale nodes. Header carries the scope declaration + secrets warning.
6. **Feed downstream.** Output → Lane C-adopt (spec-archaeology per seam +
   conformance-sweep: code↔spec, spec↔memory, memory↔code). Split what's
   captured by the **spec-vs-memory rule**: product truth checkable by code →
   openspec spec (in git); how-to-work-here / dead-ends / gotchas the repo
   doesn't record → memory (which points at the spec, never duplicates it).

## Not this

- Not a lazy one-path look — that's `explore-code`.
- Not a blind fan-out over every node — measure cheaply, spend the LLM on the
  hot 20%, and say what you skipped. **Cap it (≈10–15) and estimate the token cost
  before launching Workflow; confirm past the cap.** (A tournament-subsystem audit
  once fanned to 55 workers ≈ 2.9M tokens, unasked — 2026-07.)
- **Not pre-feature orientation.** "Аудит" meaning "help me understand this area so
  I can change it" is scoped `explore-code` on that seam, not a whole-repo audit.
  Reaching here to warm up a feature spends millions to answer a one-seam question.
