# Phase 01 — Wiring-Verification Layer (P0, the core cure)

**Gaps:** G1 (declared-vs-wired), G2 (stub/provenance-lie), G3 (empty-dir/0-byte).
**Audit:** §6, §7, §8, §10, §15.3, §16.1, §16.2, §16.5.
**Status:** ☐ PLANNED.

## Key insight
Every spec gate today is a document-structure validator. Evidence (from subagent reads, line-quoted):
- `stack-fitness-check.sh`: accept = `declared_lc == accept_value` (catalog text match). Package scan only checks *disqualified* packages — never affirms required dep present.
- `product-feature-coverage.sh`: feature COVERED = substring in `spec.md` (`grep -qF`). No route/handler/test search.
- `production-design-gate.sh`: section + digits + "p95" keyword. Never reads k8s/prometheus/terraform.
- `verify-manifest.sh`: hashes files listed IN manifest; 0-byte hashes fine; empty dirs never listed → invisible.

Cure = a **wiring layer**: declared capability/feature MUST resolve to (a) dependency present, (b) code symbol reachable, (c) config/artifact file non-empty. Text presence NEVER sufficient.

## Requirements
**Functional**
- F1 GATE-WIRE-STACK: each tier `required_capabilities[]` row maps to `{dep_packages[], code_symbols[], config_globs[], min_impls?}`; gate verifies all present in built repo. `multi_provider_ai` ⇒ `min_impls ≥ 2`.
- F2 GATE-PFC-WIRE: each `feature_surface[] must=true` declares `wiring:{routes[],handlers[],test_refs[]}`; gate verifies route literal in router source, handler symbol defined, ≥1 test references it. Substring-in-spec demoted to necessary-but-insufficient.
- F3 GATE-PROD-DESIGN-ART: each infra-claiming section cites artifact path that exists+non-empty (SLO→prometheus rule/monitor; Deployment→k8s manifest; Failure-modes→chaos test or runbook). Text + artifact both required.
- F4 GATE-STUB: scan must-have feature function bodies for stub smells — comment-only, `TODO`, `return …not configured`, AI/LLM claimed but body is `fmt.Sprintf`-only/no SDK call, provenance-lie (`IsAIGenerated:true`/`Provider:"azure"` set with no outbound call in same fn).
- F5 verify-manifest hardening: every artifact size>0 (0-byte=FAIL); every dir in atom allowlist contains ≥1 non-empty source file OR explicit `empty_dir_waived[]` with reason.

**Non-functional**
- Per-language adapter table (go.mod / package.json / requirements.txt|pyproject / Cargo.toml). Unknown stack ⇒ `N/A_PENDING_REVIEWER` (LAW-F6) — never silent PASS.
- All checks single-number stdout + JSON verdict (existing gate contract). macOS bash 3.2 compatible.

## Related code files
**Create**
- `scripts/spec/capability-wiring-check.sh` (GATE-WIRE-STACK)
- `scripts/spec/feature-wiring-check.sh` (GATE-PFC-WIRE)
- `scripts/spec/prod-design-artifact-check.sh` (GATE-PROD-DESIGN-ART)
- `scripts/mechanical/stub-detection.sh` (GATE-STUB)
- `scripts/spec/_wiring-lang-adapters.sh` (dep/symbol resolvers per language)
- meta: `scripts/meta/capability-wiring-test.sh`, `feature-wiring-test.sh`, `prod-design-artifact-test.sh`, `stub-detection-test.sh`
**Modify**
- `scripts/mechanical/verify-manifest.sh` (size>0 + empty-dir guard)
- `scripts/spec/stack-fitness-check.sh` (chain to wiring after text PASS)
- `scripts/spec/product-feature-coverage.sh` (chain to feature-wiring)
- `scripts/spec/production-design-gate.sh` (chain to artifact check)
- `scripts/orchestrator/run-all-gates.sh` (register new gate ids)
- `scripts/meta/run-all-meta-gates.sh` (bump expected pass count)
- `docs/ubs.md` (LAW-WIRE, LAW-STUB; GATE-WIRE-STACK/PFC-WIRE/PROD-DESIGN-ART contracts in §B)

## Implementation steps
1. Write `_wiring-lang-adapters.sh`: `dep_present(pkg)`, `symbol_present(regex)`, `count_impls(iface)` resolving by detected manifest. Unknown → emit N/A.
2. GATE-WIRE-STACK: read catalog tier row + atom `stack.capability_wiring{}` map; per capability assert dep+symbol+config-glob; FAIL list with capability→missing-artifact.
3. GATE-PFC-WIRE: read `feature_surface must=true` + `wiring{}`; assert route/handler/test; FAIL `feature → missing wiring kind`.
4. GATE-PROD-DESIGN-ART: parse 8 sections; for infra sections require `artifact:` citation, assert file exists+non-empty.
5. GATE-STUB: per-language stub-smell regex set; scope = files implementing must-have features (from PFC-WIRE handlers[]); FAIL file:line + smell.
6. Harden verify-manifest: add 0-byte FAIL + allowlist-dir-non-empty check + `empty_dir_waived[]` honor.
7. Chain spec gates: text PASS → wiring PASS required (text-only = demote to N/A_PENDING_REVIEWER if wiring map absent, FAIL if wiring map present but unresolved).
8. Write 4 inversion meta-tests (unwired/stub/empty fixtures → assert FAIL; wired fixture → assert PASS). Bump run-all-meta-gates count.
9. ubs.md: author LAW-WIRE + LAW-STUB (MUST rules + bash contract, boss tone). Regen docx.

## Todo
- [x] `_wiring-lang-adapters.sh` — dep/symbol/glob/footprint resolvers (excludes .build-anything.json)
- [x] GATE-WIRE-STACK (`spec/capability-wiring-check.sh`) + meta-test (4 cases green)
- [ ] GATE-PFC-WIRE + meta-test
- [ ] GATE-PROD-DESIGN-ART + meta-test
- [x] GATE-STUB (`mechanical/stub-detection.sh`) + meta-test (4 cases green — provenance-lie + not-impl)
- [ ] verify-manifest size>0 + empty-dir guard
- [ ] chain spec gates text→wiring
- [~] orchestrator registration — spec-wire-stack + mech-stub registered; PFC-WIRE/PROD-DESIGN-ART pending
- [ ] LAW-WIRE + LAW-STUB in ubs.md, regen docx
- [x] meta-suite green so far: **pass=14 fail=0 error=0** (added capability-wiring-test, stub-detection-test)

## Success criteria
- Replay mandarin atom: GATE-WIRE-STACK FAILs (`multi_provider_ai` declared, `internal/ai/` empty, no SDK in go.mod). GATE-PFC-WIRE FAILs (adaptive-lesson handler is `fmt.Sprintf`). GATE-STUB FAILs (`AzureSpeechEvaluate` comment body; `IsAIGenerated:true` lie). verify-manifest FAILs (empty `internal/notification`, `internal/social`).
- Wired fixture passes all.
- meta-suite green.

## Risk
- False positives on legit thin wrappers → allow `wiring.waived{capability,reason}` (LAW-F6: reason mandatory, surfaces to reviewer, never silent).
- Symbol regex brittle across languages → start with go/ts/py/rust; others N/A_PENDING_REVIEWER.

## Security
Stub/provenance-lie detection also catches security theater (e.g., `validateState()` that returns true). Feed OAuth-state + rate-limit fns into GATE-STUB scope.

## Next steps
Unblocks honest spec verdicts that phase-04 independent re-verify will sample.
