# Phase 02 — Behavioral Depth (P1)

**Gaps:** G4 (seed/data-presence), G5 (register→login roundtrip), G6 (E2E semantic floor), G9 (coverage/mutation gaming).
**Audit:** §5, §8, §11.1, §11.2, §11.3, §16.3, §16.4.
**Status:** ☐ PLANNED. Independent of P0 — parallelizable.

## Key insight
Behavioral gates run real processes now, but assert too shallow:
- `db-invariant-check.sh`: only `expect_zero_rows` (constraint violations). No positive `expect_min_rows`. Empty `vocabulary` table → lesson-gen returns nothing, gate green.
- `authorization-test.sh`: uses pre-seeded fixture JWTs. No create-user→authenticate-same-creds path → the live P0 (`register` 201 then `login` 401) class is invisible.
- `e2e-playwright.sh`: journey "covered" = name appears in test filename (`grep -ic "$jname"`); vacuous(0/0) banned but tautology `expect(url).toBe(sameUrl)` passes. No content-non-empty, no content-variance, no error-code taxonomy.
- `coverage-check.sh`: pure line/branch %. Tautological test hits 80%. `mutation-test.sh` is the only semantic catcher — default 60%, not mandatory, 1-hop dependents not implemented.

## Requirements
**Functional**
- F1 GATE-SEED (extend `db-invariant-check.sh` or new `data-seed-check.sh`): support `expect_min_rows:N`. Atom declares `requires_seed:[{table,min_rows}]` per data-driven feature; assert `COUNT(*) ≥ N`. Empty seed = FAIL.
- F2 GATE-AUTH-RT (`auth-roundtrip-test.sh`): POST /register fresh random creds → expect 2xx+token → POST /login same creds → expect 2xx+token. Then login wrong-pwd → expect 401/403, login no-such-user → expect distinct 404/422 (error-code taxonomy, audit §11.3). Mandatory when `auth` ∈ feature_surface.
- F3 GATE-25-E2E semantic floor: each declared journey carries `semantic_assertions:[{selector,expect_text|state}]` the runner greps test source for; ban filename-only matching. For AI/generative endpoints add `variance_probe:{endpoint,calls:2,assert:differ}` → proves not constant template (catches `GenerateLesson` fmt.Sprintf at runtime).
- F4 mutation hardening: GATE-11 mandatory for files implementing must-have features (handlers[] from GATE-PFC-WIRE); **floor = 75% for must-have feature files, 60% elsewhere (DECIDED v8.8)**; add assertion-presence check in coverage (`expect|assert|should` count > 0 per test file — kills zero-assertion 80% coverage).

**Non-functional**
- All real-process gates auto-boot stack like e2e-playwright (reuse `_common.sh` boot helpers). Random creds via `$RANDOM`/uuid, never fixed fixture.
- macOS bash 3.2; `N/A_PENDING_REVIEWER` when feature absent (LAW-F6), never silent.

## Related code files
**Create**
- `scripts/backend/auth-roundtrip-test.sh` (GATE-AUTH-RT)
- `scripts/backend/data-seed-check.sh` (GATE-SEED) — or extend db-invariant
- meta: `scripts/meta/auth-roundtrip-test.sh`, `data-seed-test.sh`, `e2e-semantic-test.sh`
**Modify**
- `scripts/backend/db-invariant-check.sh` (`expect_min_rows`)
- `scripts/mechanical/e2e-playwright.sh` (semantic_assertions + variance_probe; drop filename-only)
- `scripts/mechanical/coverage-check.sh` (assertion-presence count)
- `scripts/mechanical/mutation-test.sh` (mandatory-for-must-have; floor bump; 1-hop dependents — red-team F1)
- `scripts/orchestrator/run-all-gates.sh`, `scripts/meta/run-all-meta-gates.sh`
- `docs/ubs.md` (LAW-SEED, LAW-AUTH-RT; GATE-25-E2E semantic-floor amendment; mutation mandate)

## Implementation steps
1. `db-invariant-check.sh`: branch on `expect_min_rows` → `[[ ROWS -lt MIN ]] && FAIL`.
2. `auth-roundtrip-test.sh`: boot stack; register random → capture token+id; login same → assert 2xx; negative cases for taxonomy; FAIL with the exact 401-after-register signature.
3. e2e-playwright: require `semantic_assertions[]` per journey; grep test source for each selector+assertion; add variance probe runner; FAIL filename-only journeys.
4. coverage-check: count assertions per test file; 0 → FAIL even if % high.
5. mutation-test: scope must-have feature files mandatory; bump floor; implement 1-hop dependent inclusion (madge/go list/py import-graph).
6. 3 inversion meta-tests (empty-seed→FAIL; register-then-login-401 fixture→FAIL; tautology-only E2E→FAIL).
7. ubs.md laws + docx regen.

## Todo
- [ ] GATE-SEED (expect_min_rows) + meta-test
- [ ] GATE-AUTH-RT + meta-test (incl. error-code taxonomy)
- [ ] E2E semantic_assertions + variance_probe, drop filename-only + meta-test
- [ ] coverage assertion-presence
- [ ] mutation mandatory-for-must-have + floor bump + 1-hop dependents
- [ ] orchestrator + meta registration
- [ ] LAW-SEED + LAW-AUTH-RT in ubs.md, regen docx
- [ ] meta-suite pass=N fail=0

## Success criteria
- Replay mandarin: GATE-SEED FAILs (vocabulary 0 rows). GATE-AUTH-RT FAILs (register 201 → login 401; reproduces the live P0). E2E variance_probe FAILs (lesson-gen identical across 2 calls → constant template). coverage assertion-presence FAILs zero-assertion tests.
- Honest build passes all.

## Risk
- Auth-RT needs working ephemeral DB → reuse e2e boot; if no auth feature → N/A.
- Variance probe false-negative if endpoint legitimately deterministic → only apply when capability tagged `generative:true`.

## Security
GATE-AUTH-RT negative cases double as brute-force/enumeration checks. Pair with existing `rate-limit-test.sh` on `/auth/*`.

## Next steps
Phase-04 independent re-verify will re-run GATE-AUTH-RT + GATE-SEED on a fresh agent.
