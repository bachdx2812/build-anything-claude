# build-anything — UBS v8.1 Claude Code Skill

> **Mechanical evidence over agent narration.** When Devin/Comet/Codex/Claude says "done," prove it with cryptographically-witnessed gate verdicts — not a screenshot of a VM.

This repository ships:

1. **UBS v8.1 spec** — 17 Hard Laws + 28 Hard Gates that define what "done" means (`docs/`).
2. **`/build-anything` Claude Code skill** — executable expression of the spec, 28 gate scripts + orchestrator + cryptographic witnessing (`skill/`).
3. **Two worked examples** — `toy-project/` (atom-on-existing) + `toy-bootstrap/` (greenfield), both with full manifest + cosign-signed evidence (`examples/`).

---

## Why this exists

The "AI builds anything" stack (Devin / Comet / Kimi / Codex / Claude Code) ships features rapidly but produces no auditable evidence beyond the agent's own claim of success. UBS v8.1 fixes that with three discipline layers:

| Layer | What it adds |
|-------|--------------|
| **17 Hard Laws** | Behavioural rules (LAW-04 no secret echoing, LAW-10 no auto-destructive, LAW-15 missing tool = N/A_PENDING_REVIEWER, LAW-17 cryptographic witness, LAW-F6 no vacuous PASS, …) |
| **28 Hard Gates** | Mechanical checks that emit a *single integer score* + a JSON verdict — lint, type, coverage, mutation, perf, observability, secret scan, SQLi, arch-bridge, DB invariants, idempotency, concurrency, transaction atomicity, audit log, authorization, multi-tenant isolation, API contract, cache invariant, rate limit, IaC drift, CI seal, deployment runbook, SLO availability, scaling proof |
| **Cryptographic seal** | After all gates emit verdicts, the orchestrator aggregates them into `manifest.json`, computes `SHA-256`, and signs with `cosign` (keyless OIDC in CI, key-based locally) — producing `manifest.cosign-bundle.json` that anyone can verify with `cosign verify-blob`. |

Result: a tamper-evident bundle that proves *this specific code* passed *these specific gates* at *this specific time* — independent of what the agent claims.

---

## Install

```bash
git clone git@github.com:bachdx2812/build-anything-claude.git
cd build-anything-claude
./install.sh
```

That symlinks `skill/` into `~/.claude/skills/build-anything/`. After install, in any Claude Code session:

```
/build-anything
```

The skill activates and inspects your repo (or scaffolds a new one).

### Manual install

If you prefer not to symlink:

```bash
cp -R skill/ ~/.claude/skills/build-anything/
```

### Required tools (host machine)

The skill degrades gracefully when tools are missing (each gate emits `N/A_PENDING_REVIEWER` per LAW-15 — never a vacuous PASS). For full coverage, install:

```bash
# macOS (Homebrew)
brew install jq cosign gitleaks semgrep k6
npm install -g madge dependency-cruiser @stryker-mutator/core stryker-cli c8

# Linux (apt + npm)
sudo apt install -y jq
curl -sSfL https://raw.githubusercontent.com/sigstore/cosign/main/install.sh | sh
# (semgrep, k6, gitleaks via their own installers)
npm install -g madge dependency-cruiser @stryker-mutator/core stryker-cli c8
```

---

## Update

```bash
cd build-anything-claude
git pull --ff-only
./install.sh    # idempotent; re-syncs symlink
```

To pin a version:

```bash
git checkout v8.1.0   # or whatever tag
./install.sh
```

---

## Usage

### Mode 1: atom-on-existing (default)

Inside an existing repo. The skill scopes its checks to your current diff (+ 1-hop dependents via `madge`/`importlab`/`go list`/`cargo tree`).

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
bash ~/.claude/skills/build-anything/scripts/orchestrator/run-all-gates.sh \
  --atom-dir atom/MY-ATOM-001 \
  --project-root .
```

Output:
- `atom/MY-ATOM-001/manifest.json` — aggregated verdicts (28 gates)
- `atom/MY-ATOM-001/manifest.sha256` — SHA-256 of manifest
- `atom/MY-ATOM-001/manifest.cosign-bundle.json` — cosign signature
- `atom/MY-ATOM-001/witness.json` — witness metadata
- `atom/MY-ATOM-001/gate-{mechanical,security,backend,cloud}/*.json` — per-gate verdicts

To verify a manifest someone else produced:

```bash
cosign verify-blob \
  --bundle manifest.cosign-bundle.json \
  --key cosign.pub \
  manifest.sha256
# → "Verified OK"
```

---

## Worked example — `examples/toy-project/`

A toy Node.js Express orders API with **13 seeded bugs** (see `examples/seeded-bugs.md`). After running `/build-anything` on it:

| Bug | Caught by |
|-----|-----------|
| BUG-01 missing input validation | `mech-mutation` (Stryker 2.59% kill rate FAIL) |
| BUG-02 dead code branch | `mech-coverage` (c8 36.14% FAIL) |
| BUG-03 hardcoded OpenAI key | `sec-secret` (gitleaks `openai-key` rule HIT) |
| BUG-04 SQL injection | `sec-sqli` (semgrep + grep complement) |
| BUG-05 N+1 query latency | `mech-load` (k6 p95=109ms vs threshold 50ms FAIL) |
| BUG-06 missing tenant isolation | `be-tenant` |
| BUG-07 missing idempotency key | `be-idempotency` |
| BUG-08 cross-layer FE→DB import | `sec-arch` (dependency-cruiser) |
| BUG-09 no audit log on POST /orders | `be-audit` |
| BUG-10 race on inventory decrement | `be-concurrency` |
| BUG-11 broken DB invariant on totals | `be-invariant` |
| BUG-12 missing rate limit | `be-ratelimit` |
| BUG-13 OpenAPI schema drift | `be-contract` |

All 13 caught **by real tools**, not stubs. The `manifest.cosign-bundle.json` in that directory is a real cosign-signed bundle — verifiable with the included `cosign.pub`.

---

## Repository layout

```
build-anything-claude/
├── README.md                          ← you are here
├── LICENSE
├── install.sh                         ← symlinks skill/ → ~/.claude/skills/build-anything/
├── docs/                              ← UBS v8.1 spec (the philosophy)
│   ├── ubs-v8-1.md                    ← core spec (17 Laws + 28 Gates)
│   ├── ubs-v8-1-pitch.md              ← exec summary
│   ├── ubs-v8-1-technical-hardening.md
│   └── ubs-v8-1-production-reality.md
├── skill/                             ← the executable skill
│   ├── SKILL.md
│   ├── references/                    ← knowledge files loaded on demand
│   ├── scripts/                       ← 28 gate scripts + orchestrator + witness
│   │   ├── orchestrator/run-all-gates.sh
│   │   ├── orchestrator/witness-sign.sh
│   │   ├── mechanical/                ← lint, type, coverage, mutation, bundle, lighthouse, load, obs, property
│   │   ├── security/                  ← secret-scan, sql-injection, architecture-bridge
│   │   ├── backend/                   ← invariant, idempotency, concurrency, tx, bgjob, audit, authz, tenant, contract, cache, ratelimit
│   │   └── cloud/                     ← iac-drift, ci-seal, deploy-runbook, slo, scaling
│   ├── sub-skills/                    ← composable skill steps (spec, build, verify, review, evidence, …)
│   └── templates/                     ← config + spec + tracker templates + .gitleaks.toml
└── examples/
    ├── seeded-bugs.md
    ├── toy-project/                   ← atom-on-existing example
    └── toy-bootstrap/                 ← greenfield example
```

---

## Philosophy — what the document does well, what it's missing

(For a programmer's audit of why "the doc + Devin/Comet/Kimi" is not enough on its own, and what this repo adds, see `docs/ubs-v8-1-production-reality.md`.)

**TL;DR**: the document is a *philosophy*; this repo is the *enforcement layer*. The doc tells you what "done" should mean. The skill makes it impossible to *claim* done without producing the evidence.

---

## License

MIT — see `LICENSE`.
