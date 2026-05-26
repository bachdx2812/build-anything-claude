# UBS v8.1 — Production Reality Companion

**Audience:** the AI agent executing the build. This document is a deep-dive into the production-reality layer of the charter. The canonical principal is `ubs-v8-1.md`; this companion expands the seven gates that turn "deployed" from claim into evidence.

**Scope:** the layers of a real production system that a UI-shaped demo or VM self-test cannot demonstrate — cloud / IaC, hosting / deploy, CI/CD seal, rate limiting, caching, scaling, availability.

---

## Section 1 — The 13-Layer Production Surface

A production system has 13 distinct layers. A vibe-coding workflow demonstrates 2 of them (frontend + a slice of backend logic) and silently relies on assumptions about the other 11. UBS v8.1 demands mechanical evidence on all 13.

| # | Layer | Gate | What the gate asserts |
|---|-------|------|------------------------|
| 1 | Frontend (UI) | GATE-14 | Lighthouse + CWV + bundle delta within budget |
| 2 | APIs & Backend Logic | GATE-18..21 | DB invariants, concurrency, atomicity, idempotency, API contract |
| 3 | Database & Storage | GATE-18a | user-defined invariants return 0 violation rows |
| 4 | Auth & Permissions | GATE-18f | anon → 401, wrong-user → 403, owner → 200 |
| 5 | Hosting & Deployment | **GATE-25** | rollback + health-check scripts run, log non-empty |
| 6 | Cloud & Compute (IaC) | **GATE-22** | `terraform plan` shows zero drift |
| 7 | CI/CD & Version Control | **GATE-27** | default-branch protection ON, gates required, admins enforced |
| 8 | Security & RLS | GATE-12 | 0 CRIT / 0 HIGH across SAST + dep audit + secret scan |
| 9 | Rate Limiting | **GATE-23** | burst → 429 + `Retry-After` header |
| 10 | Caching & CDN | **GATE-24** | required headers present + write-through correctness |
| 11 | Load Balancing & Scaling | **GATE-28** | k6 ramp p95 ≤ budget, fail rate < 1 % |
| 12 | Error Tracking & Logs | GATE-15 | log + metric + alert rule present in diff |
| 13 | Availability & Recovery | **GATE-26** | synthetic probe ≥ SLO target, RTO measured under chaos |

Seven gates (bold) are the production-reality additions. They are scripts living at `~/.claude/skills/build-anything/scripts/{cloud,backend}/`.

---

## Section 2 — The Seven Production-Reality Gates

Each gate has the same contract: one input (`--atom-dir`), one stdout line (`PASS` / `FAIL` / `N/A_PENDING_REVIEWER`), one JSON verdict on disk, one exit code (0 PASS or N/A, 1 FAIL, 4 budget exceeded, 127 missing tool).

### GATE-22 IaC Drift

- **When:** L4 review for any atom touching infra (`infra/`, `terraform/`, `pulumi/`).
- **PASS condition:** `terraform plan -detailed-exitcode` returns 0 (no diff), or `pulumi preview` reports zero changes.
- **Why it matters:** drift means a manual fix landed in a cloud console outside the IaC. Undeclared infra = ungoverned spend and surprise outages.
- **Script:** `cloud/iac-drift-check.sh`. Supports terraform / opentofu / pulumi.
- **N/A condition:** atom has no `cloud.iac.dir` configured AND reviewer confirms the atom does not deploy.

### GATE-23 Rate Limit

- **When:** L4 review for any endpoint that is auth-retry, cost-incurring, or write-heavy.
- **PASS condition:** burst of N parallel requests returns at least one `429` AND the `Retry-After` header is present.
- **Why it matters:** without rate limits, an attacker drains DB connections, auth-retry capacity, or paid-API budget.
- **Script:** `backend/rate-limit-test.sh`. Bursts via `xargs -P 20`.
- **N/A condition:** atom has no rate-sensitive surface (read-only, internal-only) AND reviewer confirms.

### GATE-24 Cache Invariant

- **When:** L4 review for any cacheable endpoint.
- **PASS condition:** required headers present (`Cache-Control`, optional `ETag` / `Vary`) AND write-through probe — after a write to the configured `write_path`, the cached read returns the new row.
- **Why it matters:** stale cache is the most common silent production bug. A header check alone is not enough; correctness requires read-after-write proof.
- **Script:** `backend/cache-invariant-test.sh`.
- **N/A condition:** atom has no cache layer configured AND reviewer confirms.

### GATE-25 Deploy Runbook

- **When:** L4 review for any deployed atom.
- **PASS condition:** `rollback_cmd` AND `health_check_cmd` both exit 0 with non-empty log output. A no-op detector rejects silent scripts. Rollback runs with `BA_DRY_RUN=true` by default to honour LAW-10 (no auto-destructive).
- **Why it matters:** "we'll roll back if needed" without a runnable script is wishful thinking.
- **Script:** `cloud/deployment-runbook-test.sh`.
- **N/A condition:** atom is a pure library or docs-only AND reviewer confirms.

### GATE-26 SLO + RTO

- **When:** L4 review for any production-facing atom.
- **PASS condition:** synthetic probe (N HTTP samples) hits ≥ `target_pct` (e.g. 99.9 %); optional chaos probe kills a pod or process and the endpoint recovers within `rto_seconds`.
- **Why it matters:** without an SLO, "available" is opinion. With an SLO, burn-rate is measurable.
- **Script:** `cloud/slo-availability-test.sh`. Chaos probe restricted to staging only (LAW-10).
- **N/A condition:** atom is non-prod or not yet deployable AND reviewer confirms.

### GATE-27 CI Gate Seal

- **When:** L4 review for any deployed atom, and at minimum once per project bootstrap.
- **PASS condition:** default-branch protection ON; `enforce_admins=true`; `strict=true`; every required gate is a required status check on the default branch.
- **Why it matters:** without the seal, AL-4 self-heal can merge straight to main with no gate running. Every other gate becomes theatre.
- **Script:** `cloud/ci-gate-seal-check.sh`. Uses `gh api repos/{owner}/{repo}/branches/{branch}/protection`.
- **N/A condition:** project not on GitHub OR atom is pre-bootstrap AND reviewer confirms.

### GATE-28 Scaling Proof

- **When:** L4 review for any atom claiming horizontal scalability or sitting behind a load balancer / autoscaler.
- **PASS condition:** k6 ramp from `start_vu` (default 1) to `peak_vu` (default 10) holds for `hold_seconds`; p95 ≤ `p95_budget_ms`; fail rate < 1 %.
- **Why it matters:** "scales horizontally" without a ramp test is a marketing claim.
- **Script:** `cloud/scaling-proof-test.sh`.
- **N/A condition:** atom is single-instance by design AND reviewer confirms.

---

## Section 3 — Pipeline Position

The production-reality gates run as a dedicated stage in the autonomous loop, after backend integrity and before security:

```
Stage 0   Pre-flight                    config + automation level + budget
Stage 1   Spec Atom (L1)                testable success criteria
Stage 2   Schema / Service (L2)         OpenAPI + DDL + invariants.sql
Stage 3   Red-team Spec                 spec-attacker pre-check
Stage 4   Build (L3)                    implementer in allowlist
Stage 5   Mechanical Gates              GATE-10 / 11 / 16
Stage 6   Backend Integrity             GATE-18a..f, 19, 20, 21, 23, 24
Stage 6.5 Production Reality            GATE-22, 25, 26, 27, 28
Stage 7   Security                      GATE-12
Stage 8   Architecture                  GATE-13
Stage 9   Code Patterns                 advisory
Stage 10  Spec-compliance + attacker    GATE-17 part A
Stage 11  Code-quality review           GATE-17 part B
Stage 12  Perf + Observability          GATE-14, 15
Stage 13  Evidence Bundle               LAW-17 manifest + witness
Stage 14  Prod-Verify                   GATE-6 + GATE-16 rollback drill
```

**Consensus:** ANY gate FAIL → atom FAIL. ANY reviewer FAIL → atom FAIL. `N/A_PENDING_REVIEWER` requires explicit reviewer signoff before the stage advances.

---

## Section 4 — Config Block (model-derived)

During the PLAN stage the agent writes a `cloud` block to `.build-anything.json`. The seven gates read from it. Minimal example:

```jsonc
"cloud": {
  "iac": { "dir": "infra/", "kind": "terraform" },
  "deploy": {
    "runbook": {
      "rollback_cmd": "./scripts/rollback.sh",
      "health_check_cmd": "./scripts/health.sh",
      "dry_run": true
    }
  },
  "slo": {
    "target_pct": 99.9,
    "window_days": 30,
    "probe_url": "https://staging/healthz",
    "probe_samples": 20,
    "rto_seconds": 60,
    "chaos_cmd": "kubectl delete pod -l app=api --grace-period=0"
  },
  "github": {
    "repo": "org/repo",
    "branch": "main",
    "required_checks": ["GATE-10","GATE-11","GATE-16","GATE-18a","GATE-22","GATE-27"]
  },
  "scaling": {
    "target_url": "https://staging/api/orders",
    "start_vu": 1,
    "peak_vu": 10,
    "ramp_seconds": 30,
    "hold_seconds": 30,
    "p95_budget_ms": 500
  }
}
```

When a block is absent, the dependent gates report `N/A_PENDING_REVIEWER` and a reviewer must justify the absence or HALT the atom.

---

## Section 5 — Tooling Required

| Tool | Used by | Install |
|------|---------|---------|
| `terraform` (or `tofu` / `pulumi`) | GATE-22 | per IaC choice |
| `gh` (GitHub CLI) | GATE-27 | `brew install gh` + `gh auth login` |
| `k6` | GATE-28 | `brew install k6` |
| `curl` | GATE-23/24/25/26 | preinstalled |
| `jq` | every script | `brew install jq` |
| `kubectl` (optional) | GATE-26 chaos | per cluster |

Missing tool → `N/A_PENDING_REVIEWER`. The reviewer must install or justify.

---

## Section 6 — Production Claim → Evidence

| Claim | Evidence type |
|-------|---------------|
| "It works" | mechanical gates + adversarial reviewers + IaC declared, rate-limited, cache-correct, runbook executable, SLO probed, CI sealed, scale-tested |
| "It rolls back" | GATE-25 script executes, log is non-empty, dry-run-aware |
| "It scales" | GATE-28 k6 ramp p95 ≤ budget, fail rate < 1 % |
| "Infra is correct" | GATE-22 `terraform plan` exit 0 |
| "Main is sealed" | GATE-27 `gh api` confirms required checks ON, admins enforced |
| "It recovers" | GATE-26 chaos probe + RTO measured against staging |

Every row's evidence is a single shell script that returns an integer. The reviewer does not have to trust the claim; the reviewer runs the script.

---

## Section 7 — Adoption order

If a project is starting from scratch on v8.1, the recommended order to bring up production-reality gates is:

1. **GATE-27 first.** Without branch protection, no other gate matters because AL-4 self-heal could merge garbage straight to main.
2. **GATE-22.** IaC drift is a slow leak; surfacing it early avoids weeks of "works on my machine, broken in cloud."
3. **GATE-25.** Without a runnable rollback, every other gate's PASS is one bad deploy away from a 3 a.m. recovery.
4. **GATE-23 + 24.** Apply once the API surface stabilises; they bite when traffic patterns shift.
5. **GATE-26.** Requires a probe URL; runs against staging continuously.
6. **GATE-28.** Last because it needs a target environment that can sustain the ramp.

A new atom in an established project triggers whichever gates apply to its diff. Atoms touching no infra leave GATE-22 as `N/A_PENDING_REVIEWER`; the reviewer justifies.

---

**End of production-reality companion.** Canonical principal: `ubs-v8-1.md`. Mechanical / integrity companion: `ubs-v8-1-technical-hardening.md`.
