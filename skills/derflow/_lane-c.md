# derflow · движок Lane C — openspec

Читается, когда роутер выбрал **C**, **C-bootstrap**, **C-adopt** или **C-drain**.
Полоса без прочитанного движка — не полоса, а угадывание.

Локальный `openspec/` в каждом репо. Формат артефактов, жизненный цикл, CLI и
восстановление после неверного архива — скилл **`openspec-rules`** (он же держит
проверяемую таблицу «открывать change или править напрямую», когда граница A/B/C
неочевидна). Шаги цикла — скиллы `openspec-explore/propose/apply-change/
archive-change/sync-specs`, все глобальные с v3.20.

```
explore → propose → [critique] → apply(+TDD, review, verify) → [sync-specs если долго] → archive
```

## Цикл

- **explore** (`openspec-explore`) — think, don't implement. One question at a time, 2-3 approaches with trade-offs. Borrow the *technique* of `superpowers:brainstorming` (satisfies think-first) but **derflow overrides its terminus**: brainstorming's checklist ends by writing a design doc to `docs/superpowers/specs/` and invoking `writing-plans` — in Lane C **both are void**. The design lands in **openspec via `openspec-propose`** (not a superpowers design doc), and `writing-plans` is **not** invoked (openspec-propose *is* the plan — the duplicate-artifact trap). **Re-assert this at the explore→propose handoff:** a correct openspec announce *drifts* into brainstorming's default terminus by the end of a long brainstorm if you don't restate it. Announce-right is not enough; the drift point is the finish.

- **«Explore» — это две разные вещи; запускай нужную и никогда обе по одним файлам.** Lane C's *explore* (выше) — **дизайн-мышление, засеянное живой спекой**: читай `openspec/specs` **первым** (карта — «что уже истинно / куда смотреть»), затем **только тот код, который фича мигрирует** (например точную сериализованную форму, которая ляжет в БД), напрямую и скоупленно. Это НЕ **Orient · `explore-code`**, который есть разведка *незнакомого* репо — маленький проект, который ты (или derflow) только что построил *с* `openspec/`, незнакомым не является, поэтому **не веерь фоновых explore-агентов, чтобы «замапить архитектуру» на нём.** И **никогда не делегируй explore-агентов И не читай те же файлы руками** — субагент существует ровно затем, чтобы держать это чтение *вне* твоего контекста и вернуть дистиллят; читая файлы ещё и сам, ты платишь дважды. Выбери границу один раз. (Боевое: первая с нуля Lane C задача на крошечном свежем SPA сожгла ~50k токенов — два широких фоновых explore-агента *плюс* ~10 ручных чтений той же поверхности — когда нужен был один факт: текущая сериализованная форма `PieceInstance`, ~2 файла.)

- **propose** (`openspec-propose`) — proposal / design / specs[SHALL] / tasks. Mocks, if any, feed `design.md`.

- **apply** (`openspec-apply-change`) — implement tasks + fold in the disciplines openspec lacks: **superpowers:test-driven-development**, **superpowers:requesting-code-review**, **superpowers:verification-before-completion**.

- **archive** (`openspec-archive-change`) — sync deltas into `openspec/specs/` (the living truth). **Обязательный шаг, не финальная формальность — см. reap-гейт ниже.**

- **Long multi-session change?** keep the living spec current mid-flight with `openspec-sync-specs`; don't defer all sync to archive.

- **Schema/contract change?** produce the migration + back-compat (expand/contract) + rollback *as part of the task* — never a bare schema edit.

## Reap-гейт — заявка жнётся, а не бросается (v3.18)

**Lane C кончается на `archive`, а не на «задачи отмечены».** `openspec archive`
делает две вещи, и первая — та, ради которой всё: **вливает дельту в
`openspec/specs/`**, и только потом убирает папку заявки в `changes/archive/`.
Аналогия точная — это смерженный PR: заявка закрывается, но её содержание уже в
живой спеке.

Незаархивированная заявка со всеми отмеченными задачами = работа сделана,
документация не обновлена. N таких = у проекта не живая спека, а N черновиков.

**Жатва принадлежит завершению задачи** — тот же момент, что снос ворктри (v3.15)
и `superpowers:finishing-a-development-branch`, а не периодическая уборка. Это
буквально v3.15 в другой обёртке: карвим и не жнём. Ворктри стоили читаемости
`git worktree list`; заявки стоят всей документации проекта.

Аудит долга — дёшево, в одну команду:

```
ls openspec/changes | grep -v archive | wc -l    # активные
ls openspec/changes/archive | wc -l              # влитые
```

Перекос в сторону первого — долг.

## Lane C-drain — разгрести накопленный спек-долг (v3.18)

Вход: `changes/` распух, `specs/` отстала. **Цель — не «заархивировать всё», а
сделать живую спеку правдивой.** Заявка, чья дельта не подтверждена кодом, в
спеку не едет.

**Почему нельзя просто прогнать всё через archive.** Archive вливает дельту
**как истину**, без тега статуса — в отличие от `adopt-code`, где есть
`descriptive` / `unbacked` / `normative`. Заявка, реализованная наполовину,
влитая в `openspec/specs/`, заставит живую спеку утверждать то, чего код не
делает. **Это хуже нынешнего состояния:** тонкая спека честна, толстая врущая —
нет. И её читает Lane C explore первой (v3.14), и её энфорсит
`_conformance-sweep`, и по ней принимаются решения. Отравление расходится.

Правило: **archive — это утверждение, что дельта истинна в коде. Утверждать
можно только проверенное sweep'ом.**

**1. Триаж — дёшево, до всякого sweep'а** (`grep`/`wc`, не Workflow):
- нет `tasks.md` → это черновик, не заявка → вон из `changes/`;
- 0/N и старая → желание, а не изменение → в бэклог, **не** в спеку;
- 100% задач → кандидат на архив, идёт в sweep;
- частичная → самый дорогой случай, разбирается последним.

**2. Группируй по capability, не по `ls`.** Накопленный долг перекрывает сам
себя: поздняя заявка молча вытесняет раннюю. Слив в алфавитном порядке накатит
старую дельту поверх новой. Внутри группы — по времени; вытесненную отбраковывай,
а не вливай. **Активные ID бездатные by design** (см. конвенцию ниже), поэтому
порядок берётся только из git:
`git log --diff-filter=A --format='%ad %s' --date=short -- openspec/changes/<id>/`.

**3. Sweep перед архивом, не после.** Ось 1 (`code ↔ spec`) по SHALL'ам **самой
заявки**.

> **Цель диффа здесь — код, а не baseline.** `_conformance-sweep` написан под
> `adopt-code`, где SHALL'ы тегированы (`normative`/`descriptive`/`unbacked`), и
> оговаривает, что свипать можно лишь при наличии `normative` baseline. **В
> C-drain это условие неприменимо и блокировать не должно:** ты спрашиваешь не
> «согласуется ли дельта с живой спекой», а «**реализует ли код то, что дельта
> утверждает**». Это отвечается по коду напрямую, независимо от того, тегирована
> живая спека или нет. В проекте с обычным openspec-форматом (`### Requirement:`
> + `SHALL`, без тегов) — это нормальный случай, а не блокер.

Исходы по SHALL'ам заявки:
- все `backed` → архивируй;
- смешанно → влей подтверждённую часть, остальное пометь `unbacked` (известный
  пробел → Lane C фича);
- всё `unbacked` → это план, а не заявка → в бэклог;
- `contradicted` → громче всех: либо баг, либо заявку уже вытеснила соседняя.

**4. Стоимость — гейт до фанаута (v3.10).** Sweep это Workflow «один воркер на
SHALL». Десятки заявок × десятки SHALL = миллионы токенов. Триаж (шаг 1) обязан
отрезать **до** sweep'а; оценивай «N SHALL × ~50k ≈ X» и ставь потолок до
запуска, а не считай урон постфактум.

## Спека читается первой (v3.19)

**Живая спека — не архив для отчётности, а первый источник при любом
«сломалось / ведёт себя не так».** Порядок на полосе Dx и при любом баг-репорте:

1. `openspec/specs/<capability>` — покрывает ли спека эту область;
2. `openspec/changes/` (кроме `archive/`) — нет ли незакрытой работы по ней;
3. **и только потом** код.

**Код против спеки = права спека**, пока ты сознательно не решишь обратное — и
тогда это Lane C с обновлением SHALL, а не тихая правка кода под фактическое
поведение.

**Нет спеки → ленивая ретро-адаптация.** Почини по коду, затем напиши
`descriptive` SHALL на **затронутую capability** — не на весь seam, это
`adopt-code` и он дороже. Спека растёт по трафику: документируется в первую
очередь то, что реально ломается. Скажи человеку прямо: *«спеки на эту область не
было — задокументировал задним числом»*.

**Конвенция ID заявок: бездатный `<short-kebab>`.** Дату к архивной директории
добавляет сам `openspec archive`; дата в *активном* ID даёт двойной таймстамп, а
CLI вообще отвергает имена, начинающиеся с цифры. Следствие: упорядочить
конкурирующие заявки по имени нельзя — **порядок берётся из git**, см. C-drain
выше. Полный формат и жизненный цикл — скилл `openspec-rules`.

## Внешние API и контракты

**External / third-party API / SDK / device integration? (любая полоса — B тоже)** Before writing any parser or serializer against it, get the **real wire-contract**: (a) the vendor's official reference with exact request/response field names, **or** (b) a captured live sample of the actual response. A parser built on *guessed* field names with a `// verify on live` comment does **not** enter the build — "verify-on-live" is not a substitute for knowing the contract, and a plan step that says "confirm exact fields on the live device later" is guessing wearing a plan's authority. Wire it *after* you hold the contract, not before. (Real cost: a KkmServer integration shipped parsing `Name` / top-level `SessionState` instead of `NameDevice` / nested `Info.SessionState` — plan-sanctioned guessing → days of one-field-at-a-time prod whack-a-mole with the owner.)

**This binds claims, not just code:** any statement that the external API *can't* do X, or *doesn't* return field Y — made in **design, architecture, or review** — is under the same gate. Our own parser reflects what we *extract*, not what the API *sends*; a feasibility verdict sourced from our code (not the vendor doc / a captured sample) is a guess that can kill a valid feature. (Real cost: `system-architect` ruled "SBP webhook returns no payer phone → phone-match login impossible" from our `payload.get('payerName')`; the vendor doc had `payerMobileNumber` all along — the feature was nearly cut on a false premise.)

## Что openspec НЕ держит

**Content / marketing-heavy work? (selling site, landing, campaign)** Two layers, two homes. **openspec holds only the *system behavior/contract*** — routes, lead/ticket flows, validation, events. The **marketing layer — positioning, ICP, offer, pricing, copy, narrative — lives in its own homes** (`.agents/product-marketing.md`, offer/copy docs owned by the `marketing-skills`), **never as openspec SHALLs** (a SHALL is code-checkable; "the hero conveys 'built by practitioners'" is not). Route the marketing layer to `product-marketing` → `offers`/`pricing` → `copywriting` (+ `dertext` for native Russian); openspec captures what the site *does*, not what it *says*.

## Входы в openspec

- **Нет `openspec/` в репо?** Run `openspec init` — это **bootstrap**, не блокер и не откат к дизайн-докам. openspec — *один живой хребет*; `docs/superpowers/specs` это **датированные дизайн-доки (история / почему), не со-живущая спека** — они информируют работу, но их никогда не спрашивают «что истинно сейчас». **Тайминг:** `init` приземляется на переходе **explore→propose** — `explore`/брейншторм не пишет в openspec *ничего*, поэтому брейнштормить *до* всякого init корректно, а не промах; init только когда собираешься авторить первые артефакты спеки.
- **Новая подсистема?** Авторь её спеку в openspec **напрямую** — у гринфилда нечего адаптировать (`adopt-code` только для изменения *существующего неспецированного* кода).
- **Меняешь существующую неспецированную сшивку? — реверс-вход через `adopt-code`, тёплый старт.** Вклинь `adopt-code` на этой сшивке *первым*: `code → archaeology → descriptive SHALLs → [conformance-sweep] → ты промоутишь в normative → archive → baseline`, дальше изменение течёт как обычный C выше. Если дизайн-док в `docs/superpowers/specs` покрывает область — используй его как **фору по намерению** (тёплый старт, а не холодная археология кода), но **проверь его против текущего кода** (docs-lead, code-verifies: док — *датированное утверждение*, код — истина). Затем оставь на старом доке **supersede-указатель** (`→ openspec/specs/<x>`), чтобы история не могла притворяться живой спекой. (Полный проход `audit-code` — *опциональный* ускоритель, чтобы осушить много сшивок разом, а не входной билет: хребет ленивый, по одной затронутой сшивке.)
- **Адаптированные сшивки гейтятся `_conformance-sweep`.** Изменение, трогающее адаптированную сшивку, гоняет мини-свип затронутых `normative` SHALL'ов *до* archive — ловит «твоё изменение противоречит SHALL» (обнови спеку сознательно, либо изменение неверное).

## Критик-слой (втыкается в переходы)

Вставляй после: **brainstorm** · **mocks** · **spec/propose** · **code**.

- **`system-architect`** — структурная критика: границы, трейд-оффы, «как декомпозировать». Гоняй на свежей спеке.
- **`gap-finder`** — линза отсутствия: чего НЕ хватает (пропуски, unknown-unknowns). Находки → триаж → A/B/C.
- **External-contract check (на любом коде ИЛИ утверждении о внешнем API).** Явный ревью + `code-review` гейт-вопросы: *имена полей парсера из вендорского референса или захваченного сэмпла — или угаданы?* **и** *блокирующее утверждение об API («не возвращает X», «нельзя сделать Y») ссылается на вендорский док / захваченный сэмпл — или на наш собственный код?* Линза `gap-finder`: **«реальная схема ответа внешнего API отсутствует — а вердикт о выполнимости опирается на наш парсер, а не на контракт».** «В плане было написано проверить позже» **не проходит** — контракт идёт до парсера и до вердикта.
- **Резолюции обязаны приземлиться в *нормативную* спеку, не в дизайн-прозу.** Когда критика (`system-architect` / `gap-finder`) возвращает нумерованные резолюции (N1, N2…), не принимай «закрыто» на слово ревьюера — **прочитай `openspec/.../spec.md` и сопоставь каждый N → SHALL.** Нормативная спека — то, что governs и что энфорсит `_conformance-sweep`; резолюция, живущая только в прозе `design.md`, **не связывает и тихо переоткрывается** на реализации. design.md объясняет *почему*, spec.md — *что истинно*; проверь, что фикс во втором, и отметь те, что не приземлились. (Боевое: архитектор закрыл N2/N3/N5/N8/N11/N12 — все были проверены *в SHALL'ах*, а не приняты на веру; это и есть гейт, а не саммари.)

**Триггер B — на входе решение, а не проблема.** Когда человек приносит
*предназванный подход* («сделаем через карту X», «let's build it as Y») вместо
проблемы, гоняй frame-challenge от `system-architect` (+ `gap-finder`) **ДО**
брейншторма деталей — сначала оспорь рамку, потом уточняй. Не жди, что вспомнишь;
поданное решение и есть сигнал.

## Ошибки этой полосы

- **Анонсировать openspec, потом сдрейфовать в `docs/superpowers/specs` + `writing-plans`** — терминус `superpowers:brainstorming` переутверждается в *конце* длинного брейншторма и перебивает верно объявленный план. Его техника заимствована; его док-терминус в Lane C ничтожен — спека идёт в `openspec-propose`, `writing-plans` не вызывается никогда. Переутверждай это на переходе explore→propose, а не только в анонсе.
- **Откатываться к дизайн-докам (или блокироваться), когда `openspec/` отсутствует** — ответ `openspec init`; новая подсистема авторится в openspec напрямую (никакого `adopt-code`).
- **`openspec init` до брейншторма, а потом считать себя «отстающим»** — init приземляется на explore→propose; брейншторм не пишет в openspec ничего.
- **Гнать не тот «explore» — или оба сразу.** Lane C *explore* = дизайн-мышление по живой спеке; Orient *explore-code* = разведка незнакомого репо. Не веерь агентов на маленький проект, который сам же и построил со спекой, и никогда не гоняй агентов И руками по одним файлам (двойная оплата).
- **Заявка доведена до 100% задач и брошена в `changes/`** — это v3.15 в другой обёртке: карвим и не жнём. Ворктри стоили читаемости `git worktree list`; заявки стоят всей документации проекта. Archive принадлежит завершению задачи.
- **Слить накопленный долг через archive скопом** — archive утверждает истинность дельты в коде. Непроверенная дельта делает живую спеку врущей, а это хуже тонкой: тонкая честна. Триаж → группировка по capability → sweep → и только тогда archive.
- **Грепать код по баг-репорту, не открыв спеку** — в проекте со спекой первый источник это `openspec/specs/<capability>`, потом незакрытые `changes/`, и только потом код. Код против спеки = права спека.
- **Парсить внешний API по угаданным полям, «verify-on-live» как оправдание** — wire-контракт (вендорский референс или захваченный сэмпл) добывается ДО парсера, никогда после.
- **Заключать, что внешний API *не может* X, из нашего собственного кода** — наш парсер показывает, что мы *извлекаем*, а не что API *шлёт*. Вердикт о выполнимости обязан идти из вендорского дока или сэмпла, иначе убьёт валидную фичу на ложной посылке.
- **Голая правка схемы без миграции/back-compat** — всегда парой.
- **Принять «резолюции закрыты» на слово ревьюера** — резолюция в прозе `design.md`, отсутствующая в SHALL'ах `spec.md`, не связывает и переоткроется на реализации.
- **Загонять маркетинг/копирайт/оффер/позиционирование в SHALL'ы** — им место в маркетинговых домах; openspec держит поведение и контракт сайта, не то, что сайт *говорит*.
- **Считать `docs/superpowers/specs` со-живущей спекой** — это датированная дизайн-*история* (почему/как решили), никогда не «что истинно сейчас». Один живой источник: `openspec/specs`. При миграции сшивки оставь supersede-указатель на старом доке.
