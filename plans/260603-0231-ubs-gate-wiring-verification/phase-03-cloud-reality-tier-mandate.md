# Phase 03 — Cloud Reality + scale_tier Mandate (P2)

**Gaps:** G7 (cloud artifacts unverified + not tier-mandatory).
**Audit:** §6, §12, §16.5.
**Status:** ☐ PLANNED. After P0 (reuses artifact-existence pattern).

## Key insight
Cloud gates run real behavior where configured (k6 scaling-proof, executed rollback/health scripts, GitHub API seal) — but:
- `iac-drift-check.sh`, `slo-availability-test.sh`, `scaling-proof-test.sh`: if `cloud.*` config unset → `N/A_PENDING_REVIEWER` (exit 0), **never FAIL**. So "hyperscale" build with zero infra config silently slides to N/A.
- No gate does `find k8s/ -name '*.yaml' | wc -l > 0`. SLO gate never checks a Prometheus rule file. Deployment gate runs scripts but never verifies a k8s manifest exists.
- **Section C threshold matrix is keyed by `project_type` only — NO `scale_tier` column.** `scale_tier=hyperscale` does NOT auto-mandate any cloud gate. This is exactly the audit-build hole: declared hyperscale, delivered single-host dev box, gates green.

## Requirements
**Functional**
- F1 scale_tier→mandatory matrix: when `intent.declared.scale_tier ∈ {scale,hyperscale}` (**threshold = `scale`, DECIDED v8.8**), GATE-22 (IaC), GATE-26 (SLO), GATE-28 (scaling) become MANDATORY — config-unset flips N/A → **FAIL** ("tier declares scale+ but no IaC/SLO/scaling config").
- F2 GATE-CLOUD-ART (`artifact-existence-check.sh`): when tier mandates infra — require manifest artifacts exist+non-empty:
  - any capability `horizontal_scaling`/`auto_scaling` declared ⇒ ≥1 k8s Deployment manifest + HPA manifest (or ECS task def / equivalent).
  - `multi_region` ⇒ ≥2 distinct region identifiers across config.
  - `cdn` ⇒ CDN config block present.
  - `distributed_cache` ⇒ cluster/sentinel config, not single-node.
  - SLO section (from GATE-PROD-DESIGN-ART) ⇒ Prometheus rule / monitor file exists.
- F3 reconcile with GATE-PROD-DESIGN-ART (phase-01 F3): design claim and cloud artifact checked by the same artifact resolver (DRY).

**Non-functional**
- Artifact globs declared in atom `cloud.artifacts{}`; unknown orchestrator (not k8s) ⇒ atom declares `cloud.artifact_kind` + globs, else N/A_PENDING_REVIEWER.
- Stack-agnostic: k8s/ECS/Nomad/Helm/Terraform/Pulumi all acceptable kinds.

## Related code files
**Create**
- `scripts/cloud/artifact-existence-check.sh` (GATE-CLOUD-ART)
- `scripts/meta/cloud-artifact-test.sh`, `scripts/meta/tier-mandate-test.sh`
**Modify**
- `scripts/cloud/iac-drift-check.sh`, `slo-availability-test.sh`, `scaling-proof-test.sh` (tier-aware: unset+mandated → FAIL not N/A)
- `scripts/orchestrator/run-all-gates.sh` (read scale_tier → set mandatory set)
- `docs/ubs.md` §C threshold matrix — **add scale_tier dimension**; §B.3 cloud gate contracts; LAW-TIER-CLOUD
- `scripts/meta/run-all-meta-gates.sh`

## Implementation steps
1. Add `scale_tier` read in orchestrator preflight; compute mandatory-gate set.
2. Patch 3 cloud gates: accept `--tier-mandated` flag; when set + config absent → FAIL (not N/A).
3. GATE-CLOUD-ART: map declared capabilities → required artifact globs; assert exist+non-empty; reuse phase-01 artifact resolver.
4. ubs.md §C: add tier rows/column (mvp|growth|scale|hyperscale → which GATE-22..28 mandatory). Author LAW-TIER-CLOUD.
5. meta-tests: hyperscale-without-infra fixture → assert FAIL; honest infra fixture → PASS.
6. docx regen.

## Todo
- [ ] orchestrator scale_tier → mandatory set
- [ ] tier-aware FAIL in iac-drift / slo / scaling
- [ ] GATE-CLOUD-ART + meta-test
- [ ] §C matrix scale_tier dimension + LAW-TIER-CLOUD in ubs.md
- [ ] tier-mandate meta-test
- [ ] regen docx, meta-suite green

## Success criteria
- Replay mandarin (declared hyperscale): GATE-22/26/28 FAIL (no IaC/SLO/scaling config). GATE-CLOUD-ART FAILs (empty `k8s/`, no HPA, single-node redis). 
- mvp-tier build with no infra: still N/A (not punished) — tier gate only bites at scale+.

## Risk
- Over-strict for legit serverless (no k8s) → `cloud.artifact_kind=serverless` accepts platform config (vercel.json/serverless.yml) instead of k8s.
- Region-count heuristic noisy → require explicit `cloud.regions[]` declaration cross-checked vs config.

## Security
Secret-manager presence check (no plaintext creds in manifests) — extend `secret-scan.sh` to scan cloud artifacts dir.

## Next steps
Feeds phase-04: tier also gates witness + review depth.
