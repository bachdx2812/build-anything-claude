---
name: build-anything-gate-cloud
description: Stage 6.5 (v8.1) — cloud / production-reality gates (IaC drift, deployment runbook, SLO + RTO, CI-required-checks seal, scaling proof) — the layers that "vibe coding" never touches
---

# gate-cloud — Stage 6.5 Production Reality (v8.1)

**Why this exists.** UBS v8.0 covered code-integrity and backend-integrity. The image "Vibe Coders vs Full-Stack Production Reality" exposes the layers Devin never demonstrates: Cloud & Compute, Rate Limiting, Caching & CDN, Hosting & Deployment, Availability & Recovery, CI/CD, Load-Balancing & Scaling. **v8.1 adds the gates that move those layers from "Devin says so" → evidence on disk.**

## When This Stage Runs

Always — unless the atom is pure library code (no deploy target). Frontend-only atoms still need GATE-25 (deploy runbook) + GATE-27 (CI seal). All gates support `N/A_PENDING_REVIEWER` when not configured.

## Inputs

`.build-anything.json#cloud` block:

```jsonc
{
  "cloud": {
    "iac":    { "dir": "infra/", "kind": "terraform" },          // GATE-22
    "deploy": { "runbook": { "rollback_cmd": "...", "health_check_cmd": "...", "dry_run": true } }, // GATE-25
    "slo":    { "target_pct": 99.9, "window_days": 30,
                "probe_url": "https://staging.example.com/healthz",
                "probe_expect_status": 200, "probe_samples": 20,
                "rto_seconds": 60, "chaos_cmd": "kubectl delete pod -l app=api --grace-period=0" }, // GATE-26
    "github": { "repo": "org/repo", "branch": "main",
                "required_checks": ["GATE-10","GATE-11","GATE-16","GATE-18a","..."] },              // GATE-27
    "scaling":{ "target_url": "...", "start_vu": 1, "peak_vu": 10,
                "ramp_seconds": 30, "hold_seconds": 30, "p95_budget_ms": 500 }                      // GATE-28
  }
}
```

## Sub-Gates Executed

| ID | Script | Pass criteria |
|----|--------|---------------|
| GATE-22 IaC drift | `scripts/cloud/iac-drift-check.sh` | `terraform plan -detailed-exitcode` exits 0 (no drift) — or `pulumi preview` diff == 0 |
| GATE-25 Deploy runbook | `scripts/cloud/deployment-runbook-test.sh` | rollback_cmd + health_check_cmd both exit 0 AND non-empty output (no-op detector) |
| GATE-26 SLO + RTO | `scripts/cloud/slo-availability-test.sh` | synthetic probe success_pct ≥ target_pct AND chaos recovery ≤ rto_seconds |
| GATE-27 CI gate seal | `scripts/cloud/ci-gate-seal-check.sh` | default-branch protection ON, enforce_admins=true, strict=true, all required gate contexts present |
| GATE-28 Scaling proof | `scripts/cloud/scaling-proof-test.sh` | k6 ramp 1x→Nx, p95 ≤ budget, fail-rate < 1 % |

## HALT Conditions

- Any sub-gate FAIL
- IaC drift detected (manual hotfix in prod)
- Default branch not protected OR can be merged without gates
- p95 budget breached under ramp
- Recovery time exceeds RTO

## Why "N/A" Requires Reviewer Signoff

`N/A_PENDING_REVIEWER` is reserved for atoms that *legitimately* have no deploy / cache / rate-limit surface. Reviewer (architecture-bridge role) must justify each N/A. **The orchestrator counts pending verdicts separately and fails an atom when more than 30 % of cloud gates are pending without justification.**

## Outputs

- `{atom_dir}/gate-cloud/{gate-id}.json` per sub-gate
- Verdict `{ "stage": 6.5, "verdict": "PASS|FAIL", "findings": [...], "n_a_pending": [...] }`

## Cost Notes

- GATE-22 / 25 / 27: free (local tools + gh API)
- GATE-26 SLO: cheap (~20 HTTP probes) unless chaos_cmd kills real pods → can incur restart cost on cloud
- GATE-28 scaling: k6 ramp can hit upstream cost (~$0.10–$1.00 per run against managed services). Budget caps in `cost-tracker.sh`.

## References

- Canonical doc (production-reality section): `docs/ubs.md` Section B.3 + C
- Scripts: `scripts/cloud/*.sh`
- LAW-10 NO AUTO-DESTRUCTIVE: chaos_cmd MUST run on staging or ephemeral env only
