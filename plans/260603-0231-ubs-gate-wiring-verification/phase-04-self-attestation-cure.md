# Phase 04 — Self-Attestation Cure (P2)

**Gap:** G8 — build can still sign its own homework + skip depth at low automation tier.
**Audit:** §1 (closing), §9, §14, §16.6, §16.7.
**Status:** ☐ PLANNED. After P0/P1 (re-verify samples those gates).

## Key insight (subagent-confirmed)
v8.7.2 mitigates but does NOT cure self-attestation:
- Evidence is **produced by the build's own stages 5–9**; reviewers (stages 10–11) read those outputs but do **not re-run gates or produce counter-evidence**. → audit §16.7 ("different agent refutes each claim") unmet.
- Witness optional: `witness-sign.sh` allows `--no-witness` when `env ∈ {local,dev,test,ci}`; missing cosign → `PLACEHOLDER_NOT_FOR_PROD` silently accepted. Hash binding detects tamper, does NOT prevent self-sign.
- `--fast` skips stage 3 (red-team spec) + stage 11 (code-quality review) → reviewer set can drop to 3, lose code-quality lens. **`--fast`/`automation_level` not bound to scale_tier** → exactly the audit-build path (level 2, deeper stages advisory, user never asked).

## Requirements
**Functional**
- F1 GATE-REVERIFY (independent re-run): a FRESH agent (no build history, `--skip-intent-check` style isolation) re-executes behavioral gates and MUST reproduce PASS. Verdict mismatch (build said PASS, re-verify FAIL) → atom FAIL + flag self-attestation breach. **Tier policy (DECIDED v8.8): `hyperscale` → FULL re-run of all behavioral gates; `mvp|growth|scale` → SAMPLED subset (GATE-25-E2E + GATE-AUTH-RT + GATE-SEED + 1 random backend gate).**
- F2 witness-mandatory-at-tier: when `scale_tier ∈ {scale,hyperscale}` OR `env=prod` → `refuse_placeholder=true` forced, `--no-witness` refused regardless of env. Placeholder witness = FAIL at tier.
- F3 bind --fast / automation_level: forbid `--fast` (⇒ no skipping stage 3 red-team, stage 11 code-quality) when `scale_tier ∈ {scale,hyperscale}`. Orchestrator preflight: high tier + --fast → HALT with "depth-skip not permitted at tier; confirm downgrade or remove --fast". Surfaces the choice the audit said the user was never asked.
- F4 evidence provenance ledger: `VERIFICATION_REPORT.md` must carry per-claim `{produced_by, reverified_by, witness_class}`; any claim with `reverified_by == produced_by` and tier≥scale → FAIL. Renames honest output ("SCAFFOLD VERIFICATION — files exist, smoke pass" vs "PRODUCTION VERIFIED") based on what re-verify confirmed.

**Non-functional**
- Re-verify agent dispatched via Task tool (us) / independent runner (boss-stack Devin-second-pass). Doc states it stack-agnostically: "an independent runner with no build state."
- Cost guard (DECIDED): sampled for mvp|growth|scale; FULL only at hyperscale.

## Related code files
**Create**
- `scripts/orchestrator/reverify-sample.sh` (GATE-REVERIFY dispatcher: pick gates, run isolated, diff verdicts)
- `scripts/meta/reverify-test.sh`, `scripts/meta/tier-depth-bind-test.sh`
**Modify**
- `scripts/orchestrator/witness-sign.sh` (tier/env → force refuse_placeholder + refuse --no-witness)
- `scripts/orchestrator/run-all-gates.sh` (preflight: tier vs --fast bind; invoke reverify post-gates)
- `sub-skills/verify/SKILL.md` (independent re-run protocol)
- `sub-skills/evidence/SKILL.md` (provenance ledger fields)
- `docs/ubs.md` (LAW-REVERIFY, LAW-WITNESS-TIER, amend LAW-12/§D — independent re-execution not just review; --fast tier-bind in §A laws)
- `scripts/meta/run-all-meta-gates.sh`

## Implementation steps
1. `reverify-sample.sh`: read gate verdicts; select sample by tier; for each, spawn isolated re-run (fresh env, no prior artifacts) ; compare PASS/FAIL; mismatch → FAIL + `self_attestation_breach:true`.
2. Patch `witness-sign.sh`: tier/env gate on placeholder + --no-witness.
3. Orchestrator preflight: `scale_tier≥scale && --fast` → HALT.
4. Evidence ledger: add provenance fields; assert `reverified_by != produced_by` at tier.
5. ubs.md: LAW-REVERIFY + LAW-WITNESS-TIER; amend §D (review = critique AND independent re-execute at tier); §A --fast bind. Boss tone: "independent runner", not "Task tool".
6. meta-tests: build-says-PASS / re-verify-FAIL fixture → atom FAIL; hyperscale+--fast → HALT.
7. docx regen.

## Todo
- [ ] GATE-REVERIFY dispatcher + meta-test
- [ ] witness mandatory-at-tier (refuse placeholder + --no-witness)
- [ ] --fast / automation_level tier-bind (HALT) + meta-test
- [ ] evidence provenance ledger (produced_by ≠ reverified_by)
- [ ] LAW-REVERIFY + LAW-WITNESS-TIER + §D/§A amendments in ubs.md
- [ ] regen docx, meta-suite green

## Success criteria
- Replay mandarin: re-verify re-runs E2E/auth-RT/seed independently → FAILs (reproduces broken login + empty vocab) → atom FAIL even though build self-reported PASS. Hyperscale + --fast → HALT (no silent skip). Placeholder witness at hyperscale → FAIL.
- Honest build: re-verify reproduces PASS, real witness present, no --fast at tier → atom PASS, ledger shows `reverified_by != produced_by`.

## Risk
- Cost: full re-run doubles gate time at hyperscale → accept (tier opted into spend); sample at lower tiers.
- Re-verify flakiness (port clashes on second boot) → isolated ports/temp DB per run; retry-once before FAIL.
- Boss-stack has no Task tool → doc phrases as "second independent Devin pass / separate runner"; skill uses Agent dispatch.

## Security
Independent re-verify is the structural defense against the core disease: "scaffold passes its own self-checks." This is the highest-leverage law in v8.8.

## Next steps
With P0–P04 landed: re-run full meta-suite, replay the mandarin atom end-to-end as regression fixture (expect FAIL at GATE-WIRE/STUB/SEED/AUTH-RT/CLOUD-ART/REVERIFY), commit v8.8, regen docx → Drive.
