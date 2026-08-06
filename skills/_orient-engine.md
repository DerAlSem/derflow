# _orient-engine — shared core for audit-code & adopt-code

**Not a skill.** A reference read by `audit-code` and `adopt-code` at start.
Do not invoke directly. Holds the model, the node schema, and the invariants
both obey so their output is consistent and trustworthy. **`explore-code` does
NOT read this** — orientation of an unknown repo is a lightweight discipline
(trace one intent-path, no graph/ranking/persistence); this machinery is for the
full-repo audit and its downstream spec-adoption, which measure and persist.

Design principle (why this exists): a large codebase is understood through
**edges** (who calls/depends on whom, data flow, blast radius) and **time**
(what's alive vs frozen) — not through a containment tree. So the model is a
graph; the tree is only an index over it. Importance is a graph/time property,
so it is **measured**, never guessed and never asked of a human who just cloned
the repo.

## Three representations

- **Graph — the model.** Edges = imports/calls. Enriched with `git log` churn and
  centrality. This is where importance, cycles, shared-leaf, and fan-in live —
  everything a tree cannot hold.
- **Tree — the index only.** A table-of-contents view over the graph for
  progressive disclosure (reading in chunks). Never mistake the tree for the
  understanding.
- **Cross-cutting registry — flat sidecar.** Concerns that don't nest (auth,
  logging, error handling, feature flags, tenancy): a flat list + "who
  references this" edges. These belong to every subtree and none, so they live
  outside the tree by design.

## Measurement layer — buy, don't build

Shell out to existing tools; the LLM's value-add is **judgment and tracing**,
not measurement. Every measured fact carries a provenance tag.

| Fact | Tool | provenance |
|---|---|---|
| edges / deps | `madge`, `dependency-cruiser` (JS/TS); `go list`; python import graph | `code` |
| size | `tokei`, `scc` | `code` |
| importance | `git log` churn × fan-in (from the graph) | `code` |
| no tool for the language | LLM-inferred, lower confidence | `inferred` |

If a tool isn't installed, say so and fall back to `inferred` — don't silently
pretend a measurement happened.

## Node schema — two-tier, provenance on every fact

```
LEAN (default — every node):
  id / name
  purpose      [prov: inferred|code|human|unknown]   ← agent's guess, marked as such
  location     [prov: code]                           ← paths; verifiable
  children     (index edges)
  importance   [prov: code]  fan-in × churn × centrality   ← MACHINE, never asked of a human
  liveness     live | dead | UNVERIFIED  (default UNVERIFIED)  ← static read can't prove it
  status       stub | lean | rich | verified | UNRESOLVED
  rev          <commit-SHA at last touch>             ← freshness anchor

RICH (on flag / during audit — appended, never replaces lean):
  deps in/out          (graph edges)
  size / health        [prov: code]
  smells/bad-decisions [prov: inferred, via gap-finder]
  expected-but-absent  checklist by node type          ← catches OMISSIONS, not just what's present
  open questions       → UNRESOLVED items (escalate to: git-blame author / PR / ticket)
  confidence
```

`purpose` is the agent's inference and is tagged as such so a reader never
confuses it with the verifiable `location`. A confidently-wrong `purpose`
otherwise poisons the whole subtree beneath a node.

## Four invariants (non-negotiable — this is why the critique layer exists)

1. **Importance is machine-derived.** fan-in × churn × centrality. Never ask a
   human "how important is X" — measure it; churn/fan-in is more objective than
   memory, and on a large repo the hotspots that carry risk are rarely where
   intuition points. Humans are asked only about **intent/goals**.
2. **Provenance is mandatory, even in lean.** Every fact tagged `code` /
   `inferred` / `human` / `unknown`. The reader must be able to tell measured
   from guessed.
3. **`UNRESOLVED` is a first-class status.** A question the code can't answer and
   the human didn't → it is carried explicitly, with an escalation target. It is
   never silently turned into a guess and never dropped.
4. **`rev` is a freshness mechanism, not a discipline.** Each node stamped with
   the commit-SHA it was derived from. Re-verify = `git diff HEAD ↔ rev` →
   re-derive only changed paths; flag stale nodes. A map that can't detect its
   own staleness must not be persisted.

## Cross-cutting rules (both skills)

1. **Secrets.** Traversing a fresh clone always meets `.env`, keys, dumps →
   **skip/redact** secret paths; stamp any persisted artifact "may contain
   sensitive structure — do not commit blindly."
2. **Fan-out ontology.** Parallel workers with no shared vocabulary produce a
   self-contradictory map (same concept named two ways). All workers obey **this
   fixed node schema + a run glossary**. Otherwise a later conformance-sweep
   catches map artifacts, not code facts.
3. **Done + budget.** No traversal without a stop condition. Per-node coverage
   `status` (stub→lean→rich→verified) + a token budget + a "which 20% first"
   priority (by importance). Incompleteness is shown explicitly (`log` what was
   dropped), never passed off as completeness.
4. **Boundary validation.** A node ≠ a filesystem accident. Criterion for a node
   = **cohesion / one purpose**, with a confirm step separate from directories.
   Boundaries are revisable: `reparent` / `merge` / `split` is an explicit
   operation that preserves children (so a wrong early decomposition can be
   fixed without redoing everything beneath it).
5. **Scope declaration.** A fresh clone sees one repo; the system may be split
   across many. Header every artifact: "orient = repo X of system Y"; represent
   cross-repo shoulders as **placeholder nodes**, never a silent omission.
6. **Docs-lead, code-verifies — but docs-lead ≠ docs-only.** Before/with the
   machine graph-pass, a cheap docs pre-pass: read README/docs/docstrings for
   *intent* — the leading hypothesis (a claim to verify against code, not truth;
   diverge → docs stale, same freshness as `rev`). But whole categories —
   user-facing / selling copy, UI strings — live in **code/templates, not docs**:
   "not in docs" ≠ "not in the repo." **Absence needs a coverage proof, not just
   a trail.** Before claiming anything is missing: (a) **enumerate the surface
   first** — `git ls-files` extensions + subprojects (a second `package.json` /
   frontend = a whole language you'd miss; a Python repo can hide 100+ `.vue`
   files); (b) search content **without an extension allowlist** — narrow only
   with a justification against that enumeration; (c) answer the challenge aloud —
   *"searched — but everywhere? which surfaces are untouched?"*. Only then,
   thin/exhausted → escalate / `UNRESOLVED`; never a silent "no" (invariant 3). A
   trail nobody interrogates won't catch a bad search — the challenge does.
