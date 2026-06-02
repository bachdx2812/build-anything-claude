# UBS v8.8 — Wiring-Verification Layer (audit remediation)

**Source:** `/Users/macos/Downloads/AUDIT_build-anything.md` (mandarin-learning build, audited 2026-06-02 vs build 2026-05-28).
**Status:** PLANNED. **Owner:** us (skill) + boss-stack (doc).
**Target version bump:** v8.7.2 → v8.8.

## One-line disease (still live in v8.7.2)
Spec-layer gates verify the **WISH** (declared JSON + markdown text), not the **WIRE** (built code/config). Behavioral gates (E2E/load/authz/rate-limit) are real now — big progress — but `stack.ai="openai-sdk"` PASSES with an empty `internal/ai/`, "GenerateLesson" in spec COUNTS even when the body is `fmt.Sprintf`, empty dirs count as delivered, and a low-automation build can still skip depth + sign its own homework.

## Already fixed (do NOT re-plan)
LAW-F6 vacuous-PASS, GATE-25-E2E mandatory+boots-stack, rate-limit burst, authz/idempotency/multi-tenant/api-contract/sql-inj/secret-scan, real k6 load+scaling, witness/LAW-17, LAW-INTENT-FS, LAW-12 adversarial review mandatory-by-default.

## Gap → Phase map
| Gap | Audit § | Phase |
|-----|---------|-------|
| G1 declared-vs-wired (STACK/PFC/PROD-DESIGN/PRD text-only) | §6 §7 §8 §16.1-2-5 | **P0** [phase-01](phase-01-wiring-verification.md) |
| G2 stub / provenance-lie body passes | §8 §15.3 | **P0** [phase-01](phase-01-wiring-verification.md) |
| G3 empty-dir / 0-byte counted as delivered | §10 | **P0** [phase-01](phase-01-wiring-verification.md) |
| G4 no seed / data-presence gate | §5 §8 | **P1** [phase-02](phase-02-behavioral-depth.md) |
| G5 no register→login roundtrip | §11.2 §16.3 | **P1** [phase-02](phase-02-behavioral-depth.md) |
| G6 E2E semantic floor weak (tautology/filename match) | §11.1 §11.3 §16.4 | **P1** [phase-02](phase-02-behavioral-depth.md) |
| G9 coverage/mutation gaming | §16.4 | **P1** [phase-02](phase-02-behavioral-depth.md) |
| G7 cloud artifacts unverified + not tier-mandatory | §6 §12 §16.5 | **P2** [phase-03](phase-03-cloud-reality-tier-mandate.md) |
| G8 self-attestation (no independent re-run, witness optional, --fast thins) | §1 §9 §14 §16.6-7 | **P2** [phase-04](phase-04-self-attestation-cure.md) |

## Phases
- **P0 [phase-01]** Wiring-verification layer — GATE-WIRE family + stub detection + empty-dir/size guard. *The core cure.* Status: ✅ WIRE-STACK + PFC-WIRE + PROD-DESIGN-ART + STUB + SUBSTANCE + verify-manifest 0-byte + chaining(both gates block) + LAW-WIRE/STUB
- **P1 [phase-02]** Behavioral depth — seed gate, auth-roundtrip, E2E semantic floor, mutation hardening. Status: ✅ GATE-SEED + GATE-AUTH-RT + GATE-E2E-SEM + GATE-ASSERT + mutation tier-floor (variance-probe + 1-hop-deps deferred)
- **P2 [phase-03]** Cloud reality + scale_tier→mandatory matrix. Status: ✅ GATE-CLOUD-ART + GATE-22/26/28 tier-aware FAIL + §C tier dimension + LAW-TIER-CLOUD
- **P2 [phase-04]** Self-attestation cure — independent re-verify, witness-mandatory-at-tier, bind --fast/automation_level. Status: ✅ GATE-REVERIFY (post-manifest) + witness-force-at-tier + --no-witness refusal + --fast HALT (provenance-ledger fields deferred)

## Cross-cutting (every phase)
1. New gate ⇒ new **MUST law** in `docs/ubs.md` (stack-agnostic bash contract, boss-doc tone — no Claude-only phrasing).
2. New gate ⇒ new **inversion meta-test** in `scripts/meta/` (feed unwired/stub/empty fixture → assert FAIL). Bump `run-all-meta-gates.sh` expected count.
3. Follow change protocol: edit skill → edit ubs.md → `run-all-meta-gates.sh` (pass=N fail=0) → regen `ubs.docx` → commit+push. (docx→Drive manual.)

## Dependencies / order
P0 first (unblocks honest spec gates). P1 independent of P0, parallelizable. P2 (phase-03/04) after P0 (re-verify samples P0 gates). 

## Key risk
Wiring checks are language-specific (go.mod vs package.json vs Cargo.toml vs requirements.txt). Mitigate: per-language adapter table + `N/A_PENDING_REVIEWER` (LAW-F6) for unknown stacks — never silent PASS.

## Completion status (260603) — v8.8 SHIPPED to skill (NOT yet committed)
**11 new gates + 4 modifies, all meta-verified: `run-all-meta-gates.sh` → pass=23 fail=0 error=0.**
- New gates: GATE-WIRE-STACK, GATE-PFC-WIRE, GATE-PROD-DESIGN-ART, GATE-STUB, GATE-SUBSTANCE, GATE-SEED, GATE-AUTH-RT, GATE-E2E-SEM, GATE-ASSERT, GATE-CLOUD-ART, GATE-REVERIFY (+ shared `_wiring-lang-adapters.sh`). Each has an inversion meta-test reproducing the exact mandarin failure.
- Modifies: verify-manifest 0-byte FAIL; mutation tier-floor 60→75 at scale+; iac/slo/scaling tier-aware FAIL; witness force-refuse-placeholder at scale+/prod; orchestrator --no-witness tier-refusal + --fast tier-HALT + GATE-REVERIFY post-manifest hook.
- Doc-sync: ubs.md += 9 laws + §B.5 gate contracts + §C scale_tier dimension + TL;DR + canonical table + meta-count(→23). docx regenerated (101KB).

**Done (260603 follow-up):** catalog AI gap closed — added `llm_inference` + `multi_provider_ai` capability defs (with precise `wiring{}` blocks, multi_provider min_impls=2) + new `ai-app` product type (multi_provider_ai mandatory at scale+). WIRE-STACK meta-test extended to 6 cases: hyperscale-AI-declared-but-unwired→FAIL (mandarin §16.1) + fully-wired-2-providers→PASS. Also fixed a latent `set -e` bug in `declared_value_for` (crashed when a required cap was undeclared — youtube fixtures masked it). Fixed witness env-default→prod bug (force-refused placeholder on dev runs). meta still 23/23.

**Deferred (honest):** E2E variance-probe (static GATE-E2E-SEM shipped instead); mutation 1-hop-deps (pre-existing F1 TODO); evidence provenance-ledger fields (GATE-REVERIFY enforces the re-run = the substance); consolidated mandarin regression fixture (per-gate meta-tests cover each failure individually). **Not committed/pushed** (awaiting go); docx→Drive manual.

## Resolved decisions (locked 2026-06-03)
1. **Mutation floor = 75%** for files implementing must-have features; **60%** elsewhere. (feature lõi chặt, không phạt code phụ)
2. **Re-verify = hybrid by tier:** `hyperscale` → FULL independent re-run of behavioral gates; `mvp|growth|scale` → SAMPLED subset (E2E + auth-RT + seed + 1 random backend gate). (cost gấp đôi là thật; boss chi tiền ở tier cao)
3. **Cloud-gate mandatory threshold = `scale`** (covers `scale` + `hyperscale`), with `cloud.artifact_kind ∈ {k8s,ecs,nomad,helm,terraform,serverless}` so serverless stacks aren't punished. ("khai to giao nhỏ" chặn từ scale)
