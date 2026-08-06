# derflow — changelog

**История, не живой документ.** Здесь лежит «почему так решили»; «что истинно
сейчас» живёт в `SKILL.md` и движках `_*.md`. Разделение — применение правила
v3.1 к самому derflow: датированная история не должна притворяться живой спекой
и не должна грузиться в контекст на каждой задаче.

Каждая запись — оплаченный боевой промах. Не удалять при рефакторинге: это
единственное место, где сохранена цена правила.

Текущая версия: **v3.19**.

---

- **v3: External-integration gate.** Get the real wire-contract (vendor ref or
  captured sample) before writing a parser/serializer; "verify-on-live" is not a
  substitute (KkmServer incident 2026-07). Critique/`code-review` check +
  `gap-finder` lens for a missing external response schema.

- **v3.1: openspec bootstrap, not abandon.** `openspec/` absent → `openspec init`
  (not a fallback to `docs/superpowers/specs`, which are dated design *history*, not
  a co-living spec). New subsystem → author in openspec directly. Existing unspecced
  seam → `adopt-code` warm-started from a design doc (intent head-start, verified vs
  code), then a supersede-pointer on the old doc. `audit-code` = optional drain
  accelerator, not an entry ticket.

- **v3.2: Project/context boundary — findings, not context.** Work happens in the
  project whose context it needs; across a boundary only the distillate travels.
  The meta-repo receives lessons, not product work. A cross-project skill runs in the
  project holding the material; its learned rules write back to the global store.

- **v3.3: openspec init timing + marketing≠SHALLs.** `init` lands at explore→propose
  (brainstorm-first without init is correct, not "behind"). Content/marketing-heavy
  work has two homes: openspec holds *behavior/contract* only; positioning/offer/copy
  live in marketing homes (`product-marketing.md`, offer/copy docs), never as SHALLs.

- **v3.4: External-gate binds claims, not just parsers.** Any statement that an
  external API can't do X / doesn't return Y — in design, architecture, or review —
  must come from the vendor doc or a captured sample, never from our own code (the
  parser shows what we extract, not what the API sends). Nearly cut a valid
  phone-match login: `system-architect` inferred "no payer phone" from our parser;
  the vendor doc had `payerMobileNumber`.

- **v3.5: Handing verify to the human is not verify.** Floor = one successful run of
  what you built, by you, before "done". "No auth" is not an exemption (test-client
  force-login catches a 500-on-load); genuinely unreachable contour → declare "NOT
  verified + risk", never "готово, проверяй". (GMB "Продажи" shipped as done → HTTP
  500 on first load.)

- **v3.6: UI placement is design, not free build.** Adding an element to a
  constrained surface (modal/toolbar/card) → propose 2-3 / consult `ui-ux-designer` /
  ask where it goes, don't cram silently; then visual-verify the render (a new
  scrollbar/overflow is a regression). Verify gate: for UI, the contour is *visual*.
  (GMB modal: a "ЮЛ не задана" line crammed in → a scrollbar appeared, unproposed.)

- **v3.7: A missing UI element can be a missing domain relationship.** "X isn't
  shown / who is X?" → first ask whether the model expresses X and what it derives
  from (`gap-finder` on the data), before drawing a field — else you ship a tidy
  field that still doesn't answer the question. ("орг я, а ЮЛ-то кто?" = no
  organizer→ЮЛ path, not a missing input.)

- **v3.8: Announce-right, then drift.** A delegated skill's terminus can override
  derflow's *after* a correct announce. `superpowers:brainstorming` (borrowed for
  Lane C explore) ends its checklist at "design doc → `docs/superpowers/specs/` →
  `writing-plans`" — that terminus reasserts at the end of a long brainstorm and
  sinks the openspec plan. Borrow its technique, **void its terminus**: spec →
  `openspec-propose`, no `writing-plans`; restate at the explore→propose handoff.
  (Live: a fresh session announced openspec perfectly — init-at-propose, SHALL in
  openspec — then finished into `docs/superpowers/specs` + writing-plans.)

- **v3.9: Parallel isolation is structural + by-default, not agent-noticed.** A
  session is blind to its siblings — so when a repo is worked in parallel, every
  file-editing task carves its own worktree+branch *before* the first edit (isolation
  replaces coordination — git's 1000-dev model). The declared fact lives in the
  project `CLAUDE.md` (always-loaded, survives drift); the agent can't self-detect
  parallelism. Inherent limit: same-line edits conflict at merge (sequence + resolve).

- **v3.10: "Аудит" is a false friend + audit-code costs by design.** "Аудит" meaning
  "orient me so I can change area X" is **scoped `explore-code`** on that seam, not
  the whole-repo `audit-code` — which is a Workflow fan-out (one worker per hotspot),
  expensive *by design*. And `audit-code` itself now **caps N (≈10–15) and estimates
  tokens before fanning out** (a `+Nk` directive is a hard `budget.total` ceiling) —
  "top-N of the hot 20%" without a cap is 50+ workers. (Live: "аудит код" to prep a
  tournament feature → 55-worker Workflow ≈ 2.9M tokens; the ask was scoped explore.)

- **v3.11: Resolutions land in the normative spec, not design-prose.** When a critique
  returns numbered resolutions (N1, N2…), verify each is a **SHALL in `spec.md`**, not
  just prose in `design.md` — the normative spec governs and `_conformance-sweep`
  enforces it; a fix that lives only in design quietly reopens at implementation. Map
  each N → SHALL before accepting "closed." (Live: architect's N2/N3/N5/N8/N11/N12 on
  the tournament spec were verified *in the SHALLs*, not on the summary's word.)

- **v3.12: Isolation covers the git tree, not the deploy target.** Worktree-per-problem
  (v3.9) stops working-tree collisions, but the running server (built `dist/`, artifact on
  the box) is a *second* shared mutable surface isolation never reaches — two sessions build
  from different branches and the last push wins. Deploy = a serialized op on shared state:
  **build only from merged `main`, never deploy an unmerged branch to shared prod, serialize
  deploys, verify the active served chain (index→chunk→marker) + re-check after a delay.**
  (Live: a merged frontend deploy was overwritten 15 min later by a parallel session building
  from its unmerged branch — backend intact, buttons gone; the clobbering build wasn't from main.)

- **v3.13: A new request mid-session is a new problem — re-decide the branch.** v3.9 fires at
  the start; the trap is mid-session — on feature-branch X the human points at a nearby bug and
  the agent fixes it *in X*, polluting the feature (can't ship alone). Before the first edit of
  any new request: `git branch --show-current` + "same problem or new?"; new → branch from `main`,
  not from X. The agent can't self-detect, so branch + dirty state is surfaced every turn via a
  `UserPromptSubmit` hook (settings.json). (From a live recurring miss: nearby-bug fixes kept
  landing in the active feature branch.)

- **v3.14: "Explore" is overloaded — Lane C explore ≠ Orient explore-code, and never run both
  over the same files.** Lane C *explore* is design-thinking seeded by the living spec: read
  `openspec/specs` first (the map — "what's already true / where to look"), then only the code
  the feature migrates, scoped and by hand. It is not `explore-code` (recon of an *unfamiliar*
  repo) — a small spec'd project you just built is not unfamiliar, so no "map the architecture"
  fan-out on it. And delegating explore-agents *and* hand-reading the same files pays twice (the
  subagent exists to keep that reading out of your context — do one or the other, not both).
  (Live: a first-from-scratch Lane C task on a tiny fresh SPA burned ~50k tokens — two broad
  background explore-agents + ~10 hand-reads of the same surface — for one needed fact: the
  current serialized piece shape, ~2 files.)

- **v3.15: Worktrees are reaped, not just carved.** v3.9 said create one per problem and
  never said destroy it — so they accumulate silently (a session is blind to siblings'
  leftovers too). Reaping belongs to *task completion* (alongside
  `finishing-a-development-branch`): `git worktree remove` + `git branch -d` (which refuses
  if unmerged — that's the safety) + `prune`; scratchpad/detached trees die with their
  session. Audit by classifying, not counting (`merge-base --is-ancestor … origin/main`).
  (Live: gmb_v2 at 24 trees — 11 of 18 branch-worktrees fully merged = dead, plus 3 stale
  `/tmp` scratchpad trees; the handoff doc for the next session was invisible among them.)

- **v3.16: A sibling's code in your worktree is integration, not contamination.** Pulling
  others' commits is a shared trunk working as designed and can't be isolated away. Safety
  comes from an **invariant — `main` always green and deployable** — not from more
  isolation. Two corollaries agents get wrong: a deploy releases *the trunk*, not your
  feature ("my fix shipped by someone else's deploy" = correct); and a red `main` is not
  your problem alone — it hands risk to every session that deploys next. What *is*
  avoidable is interleaving inside the merge/deploy window → serialization (`flock`, one
  promoter), the Ops lane's job.

- **v3.17: Expedited ≠ untested — name the path, cut the right corner.** "Срочно, блокер у
  клиента" is legitimate and needs a declared lane, not a silent bypass. It skips the
  **soak** (demo dwell, review layer, openspec cycle → retro-spec after) and never the
  **suite + prod-smoke** — because under parallel sessions the suite is everyone else's net
  (v3.16). Mark it (`prod-<ts>-hotfix`) and land the commit on `develop` too so the skip is
  visible and `develop` doesn't fall behind. And if every release takes the fast path,
  that's an unnamed default, not an emergency — Lane D process consult.

- **v3.18: Заявка жнётся, а не бросается — и накопленный долг разгребается, а не сливается.**
  *Профилактика:* Lane C кончается на `openspec archive`, а не на «задачи отмечены» —
  archive это шаг, где дельта вливается в `openspec/specs/` и знание становится живой
  правдой. Жатва принадлежит завершению задачи (тот же момент, что снос ворктри в v3.15),
  не периодической уборке. Это v3.15 в другой обёртке: карвим и не жнём — только ворктри
  стоили читаемости `git worktree list`, а заявки стоят всей документации проекта.
  *Лечение (Lane C-drain):* archive — это **утверждение, что дельта истинна в коде**,
  значит вливать можно только после sweep'а. Ложная живая спека хуже тонкой: отсутствие
  документации честно, врущая — нет (и её читает Lane C explore, и её энфорсит
  `_conformance-sweep`). Триаж до фанаута (v3.10), группировка по capability — накопленный
  долг перекрывает сам себя, поздняя заявка молча вытесняет раннюю.
  (Боевое: gmb_v2 — 59 активных заявок против 11 заархивированных, 18 868 строк знания
  мимо 1 733 в живой спеке; 4 заявки с отметкой 100% задач так и не доехали; 7 заявок
  вокруг POS перекрывают друг друга.)

- **v3.19: Спека читается первой, иначе умирает правдивой.** v3.18 делает живую спеку
  правдивой — и этого мало: спека, которую никто не открывает, умирает второй раз, просто
  медленнее. Полоса Dx шла сразу в `systematic-debugging` (воспроизведи → корневая причина)
  и ни разу не говорила «сначала открой `openspec/specs/<capability>`» — агент грепал код
  по проекту, где спека уже отвечала на вопрос. Теперь: спека → `changes/` (кроме
  `archive/`) → и только потом код; **код против спеки = права спека**, пока не решено
  обратное сознательно (тогда это Lane C с обновлением SHALL, а не тихая правка).
  И ленивая ретро-адаптация: нет спеки → почини, затем `descriptive` SHALL на затронутую
  capability (не на весь seam — это `adopt-code`, он дороже). Спека растёт по трафику:
  документируется то, что реально ломается.
  (Источник: собственное правило из `~/.opencode/templates/PROJECT_AGENTS.md`, написанное
  для другого харнесса и не занесённое обратно в derflow.)

- **v3.20: openspec-скиллы подняты в глобальные — derflow ссылался на отсутствующее.**
  Движок Lane C называл `openspec-explore/propose/apply-change/archive-change/sync-specs`,
  а глобально их не было: жили только в `rk_bot/.claude/skills` и `mprz.ru/.github/skills`
  (побайтово одинаковые копии). В gmb_v2 — самом большом проекте — derflow указывал на
  несуществующие скиллы. CLI (`openspec` 1.5.0) стоял глобально, отсутствовала обучающая
  обвязка. Подняты пять скиллов + перенесён формат-референс `openspec-rules` (318 строк:
  шаблоны артефактов, жизненный цикл, «apply это не archive», восстановление после
  неверного архива, таблица «открывать change или править напрямую»).
  **И правка v3.19:** конвенция ID была записана неверно — `<YYYY-MM-DD>-<kebab>` взята
  из `PROJECT_AGENTS.md` без сверки с поведением инструмента. Правда обратная: активные ID
  **бездатные**, дату к архивной директории добавляет сам `openspec archive`, а CLI
  отвергает имена с цифры в начале. Следствие для C-drain усиливается: порядок заявок
  внутри capability берётся из git не «когда даты нет», а **всегда**.
  (Промах ровно того класса, против которого стоит внешне-контрактный гейт: утверждение
  о поведении инструмента взято из документа, а не из его собственной спецификации.)

- **v3.21: Ростер расширен — и маршрут не должен обещать больше, чем агент умеет.**
  Из `~/.config/opencode` перенесены шесть агентов той же коллекции `wshobson/agents`:
  `sql-pro` (ad-hoc SQL и медленные запросы — дыра, аналога не было), `docs-architect`
  (длинные архитектурные руководства по существующей системе), `reference-builder`
  (исчерпывающие справочники), `tutorial-engineer` (онбординг-гайды), `legal-advisor`,
  `payment-integration`. Один `documentation-expert` больше не отвечает за четыре разные
  роли. Проверяемая таблица «открывать change или править напрямую» приехала не сюда, а
  в `openspec-rules` (v3.20) — там ей место, а Lane C на неё ссылается.
  **Главный урок не в агентах, а в том, как их выбирали.** Два из шести обещают домен,
  которого не знают: `legal-advisor` написан под GDPR/EU (152-ФЗ, ОФД/ФНС — вне его),
  `payment-integration` под Stripe/PCI (СБП, ККТ, KkmServer — вне). Обнаружилось это
  только при чтении самих файлов: маршрутная таблица `workflow-cadence` в opencode
  объявляет `legal-advisor` агентом «узкого РФ-комплаенса», и я повторил это обещание,
  не открыв агента. **Описание агента в чужой маршрутной таблице — не контракт агента;
  контракт — его собственный промпт.** Ограничения продублированы в таблице
  дисамбигуации, чтобы derflow не отправлял к специалисту, которого нет.
  (Третий за сессию промах одного класса — вместе с конвенцией ID (v3.20) и вердиктом
  об SBP (v3.4): утверждение берётся из документа, описывающего вещь, вместо самой вещи.)
