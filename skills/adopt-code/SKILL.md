---
name: adopt-code
description: Use when a repo (or a seam of it) has no openspec spec and you need one — "адаптировать легаси в openspec", "нет спека, а надо менять X", "reverse-engineer a spec baseline", "завести спек из существующего кода". Reads code → descriptive SHALLs → you promote to normative → a conformance-sweep guards it → then features flow as normal Lane C. The back half of brownfield adoption (front half: explore-code / audit-code).
---

# adopt-code — reverse-engineer an openspec baseline

**Read `~/.claude/skills/_orient-engine.md` and
`~/.claude/skills/_conformance-sweep.md` first** — the node schema, seams (from
`audit-code`), the expected-but-absent checklist, provenance, and the 3-axis
sweep all apply here.

Goal: turn code that has no spec into a **living openspec baseline** of
`normative` SHALLs, so features can then flow as normal Lane C. Reverse-
engineering from code yields only *description* ("what the code does"); the
*intent* layer ("what it SHALL do") needs you — hence two statuses and an
explicit promotion. See the SHALL primer in the design spec if unfamiliar: a
SHALL is a binding, code-checkable requirement.

## Rhythm — one primitive "adopt a seam", two wrappers

- **on-demand (the spine).** About to change a seam that has no spec → adopt
  *that seam* first, then your change flows as normal Lane C on top of a fresh
  baseline. derflow wedges this automatically (see its router).
- **baseline (optional).** An explicit pass: loop `adopt-code` over the top-N
  seams from an `audit-code` run to build an initial baseline. Same primitive,
  in a loop.

Unit of adoption is a **seam** (a capability), not a file-leaf.

## Flow

1. **Archaeology** (per seam). Read the seam's surface via the graph —
   entry points, public API, ownership (tables/events). Derive **descriptive
   SHALLs**: observed behavior as `The system SHALL …`, tagged `descriptive` +
   **evidence** (file:line) + confidence. What the code can't reveal (intent,
   "why") → `UNRESOLVED`, never a guessed SHALL. Run the **expected-but-absent**
   checklist by seam type → `absent?` candidates (should exist but the code
   doesn't do it) → also `UNRESOLVED`. Output a draft `openspec/specs/<seam>`.
2. **Promotion** (default-safe — nothing becomes `normative` without an explicit
   flip). Per SHALL: **promote** → `normative` (a contract, enters the baseline);
   **bug** → the code does this but shouldn't → an issue/`UNRESOLVED`, feeds a
   Lane B/C fix, *not* the spec; **defer** → stays `descriptive`, outside trust.
   Answer `UNRESOLVED` intent questions → a SHALL or a bug. Confirm an `absent?`
   → an `unbacked normative` SHALL (a known gap → Lane C feature). Review is
   evidence-anchored (each SHALL links to code) so it's fast; batch high-
   confidence, promote money/auth one-by-one.
3. **Sweep at adoption.** Run `_conformance-sweep` immediately after promotion.
   A promoted SHALL that returns `contradicted`/`unbacked` surfaces the "you
   promoted what the code doesn't do" case on the spot.

## SHALL format (openspec/specs, in-place status tag — one store)

```
- The system SHALL reject a charge whose amount is ≤ 0.
  [normative · evidence: payments/charge.py:42 · conf: high]
- The system SHALL retry a failed webhook up to 3 times.
  [descriptive · evidence: webhooks/send.py:88 · conf: med]
- The system SHALL make charge creation idempotent.
  [unbacked · absent? · promoted 2026-07-03]
```
Only `normative` is the living truth; `descriptive`/`unbacked` sit in the same
file, tagged — no parallel shadow tree (derflow's one-source-of-truth rule).

## Reuse openspec, reverse-entry

Reuse `openspec-propose` (the draft shape — this is "propose in reverse", from
code not intent) and `openspec archive` — the CLI, never a manual `mv` (fold the promoted deltas into the
baseline). The only new primitive is the sweep. For an unspecced seam the Lane C
cycle runs in reverse first:

```
code → archaeology → descriptive → [sweep] → promotion → archive → baseline
                                                                      ↓
                                              then normal Lane C: explore → propose → …
```

## Not this

- Not "measure/understand the repo" — that's `audit-code` (it feeds this).
- Not a change to code — that's the Lane C task that follows.
- Never trust a `descriptive` SHALL; only `normative` is enforced.
