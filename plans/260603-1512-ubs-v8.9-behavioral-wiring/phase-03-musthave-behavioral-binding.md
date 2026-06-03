# Phase 03 — must_have→Behavioral Binding + collab-docs archetype (P1)

**Gaps:** B3 (interactive must_have passes on static wire) + B4 (notion archetype absent).
**Symptoms:** "chỉ làm được UI k hoạt động" / "thiếu rất nhiều tính năng."
**Status:** ☐ PLANNED. After phase-01+02 (binds to their gates).

## Key insight
- v8.8 `feature-wiring-check.sh` (GATE-PFC-WIRE): must=true feature COVERED iff route literal + handler symbol + ≥1 test ref. For a **static CRUD** feature that's fine. For an **interactive** feature (realtime messaging, presence, live collab edit, call) route+handler+test-file existence is satisfied by a dead UI + a tautology test → PASS on broken behavior. The defining features are exactly the interactive ones.
- `feature-catalog.json` has `chat-app` (`:1888`) but **no `collab-docs`/notion archetype** (grep notion = only chat-app keyword hit). SKILL.md:76 already recorded the v8.7.1 miss: "Notion clone (missing comments/realtime/search/history/mentions)" — never modeled as an archetype, so coverage can't enforce the floor.

**Cure:** tag interactive must_have features `behavioral:<gate>`; binding gate requires that gate's verdict = PASS (static wire necessary, not sufficient). Add `collab-docs` archetype with the full must_have floor.

## Requirements
**Functional**
- F1 Catalog must_have entries gain optional `behavioral` tag:
  ```
  {name:"real-time messaging", behavioral:"rt_propagate", synonyms:[...]}
  {name:"presence",            behavioral:"presence_observe", ...}
  {name:"live collaborative editing", behavioral:"rt_propagate", ...}
  {name:"voice/video call",    behavioral:"call_connect", ...}   // chat-app, when declared
  ```
- F2 GATE-BEHAVIORAL-MUSTHAVE `scripts/spec/behavioral-binding-check.sh`: for each must_have w/ `behavioral:X` present in this build's feature set, read the mapped gate verdict (`rt_propagate`→rt-propagate.json, `call_connect`→e2e-call.json, etc.). Require verdict=PASS. Missing/absent gate run for a tagged feature ⇒ FAIL (static wire alone insufficient). Untagged features unchanged (static GATE-PFC-WIRE governs).
- F3 New `collab-docs` archetype in catalog:
  ```
  keywords: ["notion clone","google docs clone","collaborative editor","workspace docs","confluence clone"]
  must_have: live collaborative editing(behavioral:rt_propagate), comments, full-text search,
             version/edit history, mentions/@-notify, nested pages/blocks
  required_capabilities: [realtime_transport, relational_db_concurrent_writer, full_text_search]
  rationale: "v8.7.1 colleague miss (SKILL.md:76): notion clone shipped without comments/realtime/search/history/mentions — enumeration was delegated to research, never floored."
  ```
  (Add `full_text_search` capability if absent: accept_values postgres-fts/elasticsearch/meilisearch/typesense/algolia; disqualified `LIKE '%...%'` scan.)
**Non-functional**
- LAW-F6: tagged feature in must_have but its behavioral gate emitted N/A ⇒ binding verdict = N/A_PENDING_REVIEWER (propagate, never upgrade N/A→PASS). macOS bash 3.2. confidence/ambiguities.

## Related code files
**Create**
- `scripts/spec/behavioral-binding-check.sh` (GATE-BEHAVIORAL-MUSTHAVE)
- `scripts/meta/behavioral-binding-test.sh`, `scripts/meta/collab-docs-archetype-test.sh`
**Modify**
- `scripts/spec/feature-catalog.json` (behavioral tags on chat-app must_have; add collab-docs archetype; add full_text_search capability)
- `scripts/spec/product-feature-coverage.sh` (recognize collab-docs keywords → must_have floor)
- `scripts/orchestrator/run-all-gates.sh` (register `spec-behavioral-binding`)
- `scripts/meta/run-all-meta-gates.sh` (bump count)
- `docs/ubs.md` (LAW-BEHAVIORAL-MUSTHAVE + §B contract; collab-docs in archetype table)

## Implementation steps
1. Add `behavioral` tags to chat-app must_have; add `collab-docs` archetype + `full_text_search` capability to catalog.
2. `behavioral-binding-check.sh`: map tag→verdict-file; for each tagged must_have in build's feature set assert PASS; FAIL list = `feature → missing/failed behavioral gate`.
3. product-feature-coverage: register collab-docs keyword set so notion builds resolve the floor (comments/search/history/mentions can't be silently dropped).
4. Inversion meta-tests: (a) chat build w/ realtime-messaging must_have but rt-propagate.json=FAIL/absent → binding FAIL; (b) notion build missing comments+search → coverage FAIL; working notion → PASS.
5. Register orchestrator + bump meta count. LAW-BEHAVIORAL-MUSTHAVE in ubs.md. Regen docx.

## Todo
- [ ] behavioral tags on chat-app must_have
- [ ] collab-docs archetype + full_text_search capability
- [ ] `behavioral-binding-check.sh` (tag→verdict PASS required)
- [ ] product-feature-coverage collab-docs floor
- [ ] 2 inversion meta-tests
- [ ] orchestrator + meta count bump
- [ ] LAW-BEHAVIORAL-MUSTHAVE in ubs.md + docx regen

## Success criteria
Replay slack atom: binding FAILs (real-time-messaging must_have, rt-propagate FAIL). Replay notion atom: coverage FAILs (missing comments/search/history/mentions); collab-edit binding FAILs if not live. Honest builds pass. meta-suite green (target ~27/27).

## Risk
- Over-binding a legitimately-static feature → only `behavioral`-tagged entries bind; tag conservatively (realtime/presence/collab-edit/call only).
- N/A propagation must not mask a real gap → N/A surfaces to reviewer w/ the exact feature name (LAW-F6), distinct from PASS.

## Security
Floor enforcement stops "ship 20% of features, call it done" — the coverage-gaming class. Search floor blocks `LIKE` scan (perf + injection surface).

## Next steps
v8.9 complete: run change protocol (meta-suite → regen docx → commit+push → manual Drive upload). Update memory [[project-v8-8-wiring-verification-plan]] → note v8.9 behavioral layer.
