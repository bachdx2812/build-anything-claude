# build-anything — UBS Claude Code Skill

> **Mechanical evidence over agent narration.** When Devin/Comet/Codex/Claude says "done," prove it with cryptographically-witnessed gate verdicts — not a screenshot of a VM.

This repository ships:

1. **UBS charter** — single canonical spec (`docs/ubs.md`): 18 Hard Laws + ~30 Hard Gates + Stage 0.1 INTENT DECLARATION that define what "done" means.
2. **`/build-anything` Claude Code skill** — executable expression of the charter, gate scripts + orchestrator + cryptographic witnessing (`plugins/build-anything/`).
3. **Two worked examples** — `toy-project/` (atom-on-existing) + `toy-bootstrap/` (greenfield), both with full manifest + cosign-signed evidence (`examples/`).

---

## Why this exists

The "AI builds anything" stack (Devin / Comet / Kimi / Codex / Claude Code) ships features rapidly but produces no auditable evidence beyond the agent's own claim of success. UBS fixes that with these discipline layers:

| Layer | What it adds |
|-------|--------------|
| **18 Hard Laws** | Behavioural rules (LAW-04 no secret echoing, LAW-10 no auto-destructive, LAW-15 missing tool = N/A_PENDING_REVIEWER, LAW-17 cryptographic witness, LAW-CL-95 per-stage confidence contract, LAW-F6 no vacuous PASS, …) |
| **Hard Gates** | Mechanical checks emitting `{verdict, confidence: 0-100, ambiguities[]}` — lint, type, coverage, mutation, perf, observability, secret scan, SQLi, arch-bridge, DB invariants, idempotency, concurrency, transaction atomicity, audit log, authorization, multi-tenant isolation, API contract, cache invariant, rate limit, IaC drift, CI seal, deployment runbook, SLO availability, scaling proof, product-feature coverage (PFC), UI/UX, E2E playwright |
| **Stage 0.1 INTENT** | Mandatory first stage: agent self-scores intent confidence, declares product_type / primary_user / core_flows / success_criteria. Orchestrator refuses to run gates without `intent/verdict.json#next_action=READY`. |
| **Meta-gates** | Regression spine for the skill itself: `no-vacuous-pass-test`, `real-atom-smoke-test`, `intent-preflight-test`. Picked up by `run-all-meta-gates.sh`. Catches "the skill stopped enforcing its own laws". |
| **Cryptographic seal** | After all gates emit verdicts, orchestrator aggregates them into `manifest.json`, computes `SHA-256`, signs with `cosign` (keyless OIDC in CI, key-based locally) → `manifest.cosign-bundle.json` that anyone can verify with `cosign verify-blob`. |

Result: tamper-evident bundle proving *this specific code* passed *these specific gates* at *this specific time* — independent of what the agent claims.

---

## Install

### Recommended — Claude Code plugin marketplace

In any Claude Code session:

```
/plugin marketplace add bachdx2812/build-anything-claude
/plugin install build-anything@build-anything-claude
```

After install, the skill activates with:

```
/build-anything
```

Claude Code clones the repo, reads `.claude-plugin/marketplace.json`, wires `plugins/build-anything/SKILL.md` into your skill registry. Update later with `/plugin update build-anything@build-anything-claude`.

### Alternative — symlink install (manual)

```bash
git clone git@github.com:bachdx2812/build-anything-claude.git
cd build-anything-claude
./install.sh
```

Symlinks `plugins/build-anything/` into `~/.claude/skills/build-anything/`.

### Required tools (host machine)

Skill degrades gracefully when tools are missing (each gate emits `N/A_PENDING_REVIEWER` per LAW-15 — never a vacuous PASS). For full coverage:

```bash
# macOS (Homebrew)
brew install jq cosign gitleaks semgrep k6 pandoc
npm install -g madge dependency-cruiser @stryker-mutator/core stryker-cli c8 @playwright/test

# Linux (apt + npm)
sudo apt install -y jq pandoc
curl -sSfL https://raw.githubusercontent.com/sigstore/cosign/main/install.sh | sh
# (semgrep, k6, gitleaks via their own installers)
npm install -g madge dependency-cruiser @stryker-mutator/core stryker-cli c8 @playwright/test
```

---

## Update

### Marketplace install

```
/plugin update build-anything@build-anything-claude
```

### Symlink install

```bash
cd build-anything-claude
git pull --ff-only
./install.sh    # idempotent; re-syncs symlink
```

---

## Usage

### Mode 1: atom-on-existing (default)

Inside an existing repo. Skill scopes its checks to your current diff (+ 1-hop dependents via `madge`/`importlab`/`go list`/`cargo tree`).

```bash
cd your-existing-repo
# (1) declare config — one-time
cp ~/.claude/skills/build-anything/templates/build-anything-config.json .build-anything.json
$EDITOR .build-anything.json

# (2) start an atom — talk to Claude:
#     "Use /build-anything to add feature X to module Y."
```

### Mode 2: bootstrap (greenfield)

For new projects. Set `scope.mode = "bootstrap"` + `scope.bootstrap_glob` listing dirs to walk.

See `examples/toy-bootstrap/.build-anything.json` for a complete example.

### Running the orchestrator standalone

You can also invoke the gate orchestrator directly without Claude:

```bash
# Stage 0.1 — declare intent first
bash ~/.claude/skills/build-anything/scripts/intent/declare-intent.sh \
  --atom-dir atom/MY-ATOM-001

# All gates
bash ~/.claude/skills/build-anything/scripts/orchestrator/run-all-gates.sh \
  --atom-dir atom/MY-ATOM-001 \
  --project-root .
```

Output:
- `atom/MY-ATOM-001/intent/verdict.json` — declared intent + confidence
- `atom/MY-ATOM-001/manifest.json` — aggregated verdicts (all gates)
- `atom/MY-ATOM-001/manifest.sha256` — SHA-256 of manifest
- `atom/MY-ATOM-001/manifest.cosign-bundle.json` — cosign signature
- `atom/MY-ATOM-001/witness.json` — witness metadata
- `atom/MY-ATOM-001/gate-{mechanical,security,backend,cloud,ui-ux}/*.json` — per-gate verdicts

To verify a manifest someone else produced:

```bash
cosign verify-blob \
  --bundle manifest.cosign-bundle.json \
  --key cosign.pub \
  manifest.sha256
# → "Verified OK"
```

### Skill self-regression check

Before relying on the skill in production, run the meta-gate suite:

```bash
bash ~/.claude/skills/build-anything/scripts/meta/run-all-meta-gates.sh
# exit 0 = no regression
# exit 1 = LAW-F6 or LAW-CL-95 or GATE-INTENT broken
# exit 2 = a meta-gate itself broke (harness rot)
```

---

## Worked example — `examples/toy-project/`

A toy Node.js Express orders API with **13 seeded bugs** (see `examples/seeded-bugs.md`). After running `/build-anything` on it:

| Bug | Caught by |
|-----|-----------|
| BUG-01 missing input validation | `mech-mutation` (Stryker low kill rate FAIL) |
| BUG-02 dead code branch | `mech-coverage` (c8 below threshold FAIL) |
| BUG-03 hardcoded OpenAI key | `sec-secret` (gitleaks `openai-key` rule HIT) |
| BUG-04 SQL injection | `sec-sqli` (semgrep + grep complement) |
| BUG-05 N+1 query latency | `mech-load` (k6 p95 over threshold FAIL) |
| BUG-06 missing tenant isolation | `be-tenant` |
| BUG-07 missing idempotency key | `be-idempotency` |
| BUG-08 cross-layer FE→DB import | `sec-arch` (dependency-cruiser) |
| BUG-09 no audit log on POST /orders | `be-audit` |
| BUG-10 race on inventory decrement | `be-concurrency` |
| BUG-11 broken DB invariant on totals | `be-invariant` |
| BUG-12 missing rate limit | `be-ratelimit` |
| BUG-13 OpenAPI schema drift | `be-contract` |

All 13 caught **by real tools**, not stubs. The `manifest.cosign-bundle.json` in that directory is a real cosign-signed bundle — verifiable with the included `cosign.pub`.

### Empty-atom regression demo

For a proof that v8.3 cannot be tricked into claiming success on an empty atom, see `plans/reports/youtube-build-demo-260526-2151-from-scratch.md`. Running the orchestrator against an atom whose only input is the literal sentence "build cho tôi youtube" produces 0 PASS / 1 FAIL / 29 N/A_PENDING_REVIEWER — exactly what LAW-F6 mandates.

---

## Repository layout

```
build-anything-claude/
├── README.md                          ← you are here
├── LICENSE
├── install.sh                         ← fallback symlink installer
├── .claude-plugin/
│   └── marketplace.json               ← Claude Code plugin manifest
├── docs/                              ← UBS charter (single source of truth)
│   ├── ubs.md                         ← canonical spec (18 Laws + all Gates + 17-stage pipeline)
│   └── ubs.docx                       ← boss-handoff format
├── plans/
│   └── reports/                       ← journals, demos, audits
├── plugins/
│   └── build-anything/                ← executable skill
│       ├── SKILL.md
│       ├── references/                ← knowledge files loaded on demand
│       ├── scripts/                   ← gate scripts + orchestrator + witness + meta
│       │   ├── intent/                ← Stage 0.1 declare-intent.sh (LAW-CL-95)
│       │   ├── orchestrator/          ← run-all-gates.sh + witness-sign.sh
│       │   ├── meta/                  ← skill self-regression spine
│       │   ├── mechanical/            ← lint, type, coverage, mutation, bundle, lighthouse, load, obs, property, e2e-playwright
│       │   ├── security/              ← secret-scan, sql-injection, architecture-bridge
│       │   ├── backend/               ← invariant, idempotency, concurrency, tx, bgjob, audit, authz, tenant, contract, cache, ratelimit
│       │   ├── cloud/                 ← iac-drift, ci-seal, deploy-runbook, slo, scaling
│       │   ├── gate-ui-ux/            ← UI/UX product-discovery gate
│       │   └── spec/                  ← product-feature-coverage (PFC) catalog
│       ├── sub-skills/                ← composable skill steps (intent, spec, build, verify, review, evidence, gate-*)
│       └── templates/                 ← config + spec + tracker templates + .gitleaks.toml
└── examples/
    ├── seeded-bugs.md
    ├── toy-project/                   ← atom-on-existing example
    └── toy-bootstrap/                 ← greenfield example
```

---

## Philosophy — what the charter does, what the skill enforces

**TL;DR**: `docs/ubs.md` is the *philosophy*; this repo is the *enforcement layer*. The charter tells you what "done" should mean. The skill makes it impossible to *claim* done without producing the evidence — and the meta-gate spine makes it impossible for the skill to *quietly lose* that ability.

For full detail (laws, gates, stages, confidence-loop, manifest schema, witness classes, operating modes, cost ladder), read `docs/ubs.md` — it is the only document required to operate the system.

---

## License

MIT — see `LICENSE`.
