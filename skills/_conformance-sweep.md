# _conformance-sweep — shared reference

**Not a skill.** A reference read by derflow's Lane C gate (C-drain).
Do not invoke directly. Guards **only `normative` SHALLs** — `descriptive`,
`unbacked`, and `UNRESOLVED` items sit outside trust and are not enforced.

Purpose: detect contradictions across the three places a claim can live — the
code, the spec, and memory. You can only sweep once a `normative` baseline
exists; there is nothing to diff against otherwise.

> **Exception — derflow's Lane C-drain.** When draining unarchived changes, axis 1
> runs against the **change's own delta SHALLs**, asking "does the code implement
> what this delta claims?" The diff target is the code, not a baseline, so an
> untagged living spec (plain openspec `### Requirement:` + `SHALL`) is **not** a
> blocker there. The `normative`-only guard governs what gets *enforced*, not
> whether backing can be checked.

## Three axes

| Axis | Check | Outcomes |
|---|---|---|
| **code ↔ spec** | for each `normative` SHALL, find the backing code | `backed` (code implements it) · `contradicted` (code does the opposite) · `unbacked` (no code — aspirational / a gap) |
| **spec ↔ memory** | memory claims that disagree with a SHALL | conflict → reconcile by the spec-vs-memory rule (product truth → spec; how-to-work-here → memory, pointing at the spec) |
| **memory ↔ code** | `grep` every path/symbol a memory line names | present → ok · missing → memory is stale → fix or delete |

## Mechanic

- **Axis 1 — fan-out via Workflow.** One checker per `normative` SHALL; each
  returns its outcome + evidence (file:line). This scales to a large baseline —
  the slowest single SHALL, not the sum.
- **Axes 2/3 are cheap** — read both sides (spec↔memory) or a mechanical `grep`
  (memory↔code). No fan-out needed.

## When it runs

2. **Lane C gate** — a Lane C change touching an adopted seam runs a **mini-sweep**
   of the affected SHALLs *before* `archive`. Catches "your change contradicts a
   `normative` SHALL" → either update the spec deliberately, or the change is
   wrong. This is what keeps spec↔code from drifting (enforced, unlike a plain
   openspec-archive).
3. **On-demand** — always available ("check for contradictions").

## Output

A **transient report** (not the living spec), ranked by severity:
- `contradicted` — worst: code contradicts a `normative` SHALL → a bug or a
  wrong spec.
- `unbacked` — a SHALL with no code → a gap → Lane C feature.
- stale memory (`memory↔code` miss) → fix/delete.
- spec↔memory conflict → reconcile.

Findings do not sit in a report — each **re-enters as an A/B/C task** through
derflow, the same way health-track findings do.
