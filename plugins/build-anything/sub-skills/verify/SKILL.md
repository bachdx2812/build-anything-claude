---
name: build-anything-verify
description: Stage 14 — L6 prod-verify with feature-flag flip + rollback drill + post-deploy smoke + DB invariant re-run on prod; enforces LAW-10 explicit user confirm
---

# verify — Stage 14 Prod-Verify (L6)

**Maps to:** stage 14 of `/build-anything`. Extends v7.5 GATE-6 with rollback drill (GATE-16), observability continuity (GATE-15), and post-deploy invariant re-run. Strictly enforces LAW-10 (no auto-destructive).

## When This Runs

Final stage before atom closure. After stages 1–13 PASS. Only when user (or AL ≥ 4 with manual kill-switch armed) authorises deploy.

## Inputs

- Sealed manifest from stage 13 (`manifest.sha256`)
- Rollback path declared in atom brief
- Feature flag identifier (if applicable)
- Prod environment access (read-only by default, write only via explicit confirm)

## Outputs

- `{atom_dir}/verify/preflight.json`
- `{atom_dir}/verify/deploy-log.json` (CI/CD pipeline ID, deploy SHA)
- `{atom_dir}/verify/post-deploy-smoke.json`
- `{atom_dir}/verify/db-invariant-prod.json` (re-run invariants read-only on prod)
- `{atom_dir}/verify/rollback-drill.json`
- `{atom_dir}/verify/error-rate.json` (baseline + first 5 min delta)
- `{atom_dir}/verify/latency.json` (baseline + first 5 min delta)
- Verdict `{ "stage": 14, "verdict": "PASS|FAIL|ROLLED_BACK", "findings": [...] }`

## LAW-10 Enforcement (HARD)

Before any prod write, this sub-skill MUST prompt the human (via AskUserQuestion) with:
- Atom code
- Manifest SHA
- Deploy SHA
- Rollback command (must be one-line and tested in staging within 24h)
- Estimated blast radius
- "Type the atom code to confirm deploy"

If user does not confirm verbatim, stage 14 HALTs. No agent override permitted. Even AL-4 cannot auto-deploy — AL-4 means agent autonomous within mechanical gates, NOT deploy authority (LAW-10 is preserved verbatim from v7.5).

## Rollback Drill (GATE-16)

The drill runs BEFORE the actual deploy. Steps:
1. Spin up staging mirror matching prod (or use a hot-staging slot)
2. Deploy atom to staging
3. Execute rollback path (feature-flag flip OFF, or migration reverse)
4. Measure rollback time
5. Re-run DB invariant queries post-rollback
6. Assert: rollback time ≤ threshold AND invariants hold post-rollback

If any step fails → atom HALT (cannot ship without proven rollback).

## Deploy + Post-Deploy Smoke

After confirmed deploy:
1. Hit prod URL with headless Puppeteer (via `/ck:chrome-devtools`); capture screenshot
2. Hit each endpoint in `endpoints_to_test` (anon + owner) — assert expected status codes
3. Re-run invariant queries on prod (read-only) — assert 0 violations
4. Sample error rate from observability system (per LAW-13 instrumentation) for first 5 min
5. Sample latency p95 for first 5 min
6. Both must be within budget (Section C thresholds or project overrides)

## Continuous-Validation Hook

This stage emits a post-verify watchdog that monitors observability for the next 24h. If error rate or latency degrades past threshold, auto-fire an alert (NOT auto-rollback — LAW-10 forbids; only flag for operator).

## HALT and ROLLBACK Conditions

| Condition | Action |
|-----------|--------|
| Pre-flight fail (manifest hash mismatch) | HALT before deploy |
| Rollback drill fail | HALT before deploy |
| Smoke fail post-deploy | trigger rollback prompt (operator confirms) |
| Error rate spike | trigger rollback prompt |
| DB invariant violation on prod | IMMEDIATE rollback prompt (data integrity) |
| User did not type atom code verbatim | HALT |

## Tool Delegation

- `/ck:ship` (Phase 01 Discovery 4) for the deploy pipeline orchestration — wrap rather than reimplement
- `/ck:chrome-devtools` for post-deploy screenshot + smoke
- `/ck:devops` for platform-specific deploy patterns (Cloudflare / GCP / K8s)

## Why LAW-10 Stays Hard

Boss's v7.5 explicit: "Agents never auto-merge, auto-deploy to prod, auto-publish, auto-send messages, auto-grant access, or auto-execute payments." v8.0 PRESERVES this verbatim. The cost of one wrong autonomous deploy (e.g. payment double-charge to N customers) is unbounded. The cost of a one-line human confirm is one line.

## Retry Policy

- Failed smoke: 1 retry (transient noise)
- Failed rollback drill: 0 retries (atom must add rollback first)
- User declined confirm: atom held at L5; user may resume later

## Outputs to BUILD ARCHIVE

On PASS, append to BUILD ARCHIVE:
```
Atom ATOM-...
| L6 | iter N | PASS
| evidence: manifest:{sha} | deploy:{sha} | smoke:{screenshot_sha} | invariant:{ok}
| rollback_drill: {time_ms} | rollback_path: {cmd}
```

## References

- v7.5 LAW-10: preserved
- v8.0 GATE-16: `docs/ubs-v8-technical-hardening.md`
- `/ck:ship` skill (Phase 01 catalogue)
- `/ck:chrome-devtools` for smoke
- `/ck:devops` for platform deploy
