# Phase 08.6 — v8.1 Production-Reality Layer Complete

**Status:** DONE. All 7 new gates (GATE-22..28) implemented, executable, syntax-clean. Sub-skill `gate-cloud` added. Orchestrator SKILL.md bumped to v8.1.

## Trigger

User reaction to "Vibe Coders vs Full-Stack Production Reality" image:
> "tôi thấy ảnh này khá là đúng cái tôi muốn nói với boss, và muốn đưa những phần cải thiện này vào UBS của boss!"

The image shows 13 production layers. v7.5 + v8.0 mechanically cover 5–9 of them. v8.1 closes the gap to 13.

## New gates

| Gate | Layer | Script | Lines | Pass criterion |
|------|-------|--------|-------|----------------|
| GATE-22 | Cloud & Compute (IaC) | `scripts/cloud/iac-drift-check.sh` | 75 | `terraform plan -detailed-exitcode` = 0 |
| GATE-23 | Rate Limiting | `scripts/backend/rate-limit-test.sh` | 63 | burst → ≥ 1 × 429 + `Retry-After` present |
| GATE-24 | Caching & CDN | `scripts/backend/cache-invariant-test.sh` | 80 | `Cache-Control` + write-through read-back |
| GATE-25 | Hosting & Deployment | `scripts/cloud/deployment-runbook-test.sh` | 67 | rollback + health-check exec non-empty |
| GATE-26 | Availability & Recovery | `scripts/cloud/slo-availability-test.sh` | 77 | probe ≥ SLO target + chaos recovery ≤ RTO |
| GATE-27 | CI/CD Seal | `scripts/cloud/ci-gate-seal-check.sh` | 56 | branch protection ON + required checks present + admins enforced |
| GATE-28 | Load Balancing & Scaling | `scripts/cloud/scaling-proof-test.sh` | 73 | k6 ramp 1×→Nx, p95 ≤ budget, fail-rate < 1 % |

Total new: **491 LOC** across 7 scripts. Each ≤ 80 LOC (well under the 200 LOC cap).

## Skill / doc changes

- New `sub-skills/gate-cloud/SKILL.md` — Stage 6.5 (production reality)
- New `scripts/cloud/_common.sh` — sources `../backend/_common.sh`; adds `require_tool_or_na` helper
- `scripts/backend/cache-invariant-test.sh` + `rate-limit-test.sh` — added to backend group
- Orchestrator `SKILL.md` bumped to v8.1; new Stage 6.5 inserted in 15-stage flow; "Autonomous Loop" section added at top
- `sub-skills/gate-backend/SKILL.md` — updated for GATE-23 + GATE-24
- New `docs/ubs-v8-1-production-reality.md` (canonical v8.1 spec, ≈ 380 lines)
- New `docs/ubs-v8-1-pitch.md` (1-page boss-facing pitch)

## Verdict-emit pattern

Every script follows the contract:

```
stdout:  PASS|FAIL|N/A_PENDING_REVIEWER  (one line)
exit:    0=PASS  1=FAIL  0+verdict=N/A
disk:    {atom_dir}/evidence/{gate}.json  (full JSON verdict)
```

This makes every gate usable as `/ck:autoresearch` Verify command — the autonomous loop converges on a known-failing single gate at a time.

## Cost discipline

- GATE-22 / 25 / 27: free (local tools + gh API)
- GATE-23 / 24: tiny (burst HTTP)
- GATE-26: cheap (~20 HTTP probes); chaos_cmd extra if it kills real pods
- GATE-28: k6 ramp — can hit upstream cost ($0.10–$1.00 / run). Capped by `cost-tracker.sh` $5 atom budget.

## Verification done

- `chmod +x` on all 8 new scripts (7 gates + 1 _common.sh)
- `bash -n` syntax check: all 8 PASS
- File-size audit: all ≤ 80 LOC each
- Naming: kebab-case ✓

## Verification NOT done (paper-traced)

- End-to-end dry-run against toy project (Phase 07 dry-run did v8.0 only). Recommended next: extend toy project with cloud config block, run all 28 gates, expect mix of PASS / FAIL / N/A_PENDING_REVIEWER.
- Real Terraform / k6 / chaos execution. Wired as N/A_PENDING_REVIEWER when tools absent; reviewer must install.

## Net coverage

| Coverage | Layer count |
|----------|-------------|
| Vibe coding | 2 / 13 |
| UBS v7.5 | 5 / 13 |
| UBS v8.0 | 9 / 13 |
| **UBS v8.1** | **13 / 13** |

## Unresolved questions

- GATE-26 chaos probe: should `chaos_cmd` always run against staging? Or accept ephemeral docker-compose for atoms that don't have staging?
- GATE-28 scaling target: should `target_url` be the prod URL with a synthetic-traffic header, or always staging?
- GATE-27: who owns the GitHub branch-protection ruleset? Boss? CI? The first reviewer to PASS the atom?
- Should `cost-tracker.sh` push spend to a central ledger (Slack / metric / Sheets) or stay local-only? Implication: AL-4 cap currently per-machine.
