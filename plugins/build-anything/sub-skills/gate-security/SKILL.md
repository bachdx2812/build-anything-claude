---
name: build-anything-gate-security
description: Stage 7 — STRIDE + OWASP A01..A10 + dep audit + secret scan; thin wrapper around `/ck:security-scan` + `/ck:security` with reviewer escalation
---

# gate-security — Stage 7 Security Gate

**Maps to:** stage 7 of `/build-anything`. Implements LAW-16 + GATE-12. LAW-04 (no secrets) is enforced independently inside `implementer` self-review; this gate is the wider OWASP surface.

## Inputs

- Atom diff
- Endpoint list from `.build-anything.json` (entry points for STRIDE per-route)
- Dependency manifest (package.json / pyproject / go.mod / Cargo.toml)

## Outputs

- `{atom_dir}/gate-security/sast.json`
- `{atom_dir}/gate-security/dep-audit.json`
- `{atom_dir}/gate-security/secret-scan.json`
- `{atom_dir}/gate-security/threat-model.json` (reviewer output)
- Verdict `{ "stage": 7, "verdict": "PASS|FAIL", "findings": [...] }`

## Sub-Checks

| Check | Tool | Pass criteria |
|-------|------|---------------|
| SAST | `/ck:security-scan` (semgrep underneath) | 0 CRITICAL, 0 HIGH on changed files |
| Dependency audit | `npm audit` / `pip-audit` / `govulncheck` / `cargo audit` | 0 CRITICAL, 0 HIGH |
| Secret scan | `gitleaks` (also run in stage 4) | 0 findings |
| Threat model | adversarial reviewer prompt `security-bridge.md` | reviewer PASS |
| OWASP coverage | per-route STRIDE checklist | reviewer attests A01..A10 considered |

## Tool Delegation

This stage primarily DELEGATES — it does not reimplement scanners. Delegations:

- `/ck:security-scan` provides SAST + secret + dep audit in one call (Phase 01 Discovery)
- `/ck:code-review --security` (Phase 01 Discovery) for code-level review
- `security-bridge.md` reviewer prompt covers STRIDE per entry point + OWASP A01..A10

## HALT Conditions

- Any CRITICAL or HIGH finding in any sub-check
- Reviewer threat model marks any OWASP category as "not considered"
- Secret detected (immediate HALT + AL demote to 0)

## Severity Routing

| Severity | Action |
|----------|--------|
| CRITICAL | HALT, demote AL one rung, evidence captured |
| HIGH | HALT |
| MEDIUM | PASS with finding logged; spawn follow-up atom |
| LOW | PASS with finding logged |

## STRIDE Coverage Required

Per new entry point in the atom, the security reviewer must produce a row in the threat model table:

| Threat | Considered? | Mitigation |
|--------|-------------|------------|
| Spoofing | yes/no | auth check |
| Tampering | yes/no | input validation / signing |
| Repudiation | yes/no | audit log |
| Information disclosure | yes/no | authz check + minimal response shape |
| Denial of service | yes/no | rate limit / quota |
| Elevation of privilege | yes/no | authz on every path |

A row marked "no" without justification → reviewer FAIL.

## Retry Policy

- 0 retries on CRITICAL or HIGH (atom must be re-built to fix)
- AL ≥ 3: spawn follow-up atom for MEDIUM / LOW

## LAW-04 Relationship

LAW-04 is enforced in stage 4 (implementer self-review) AND here. This gate is a second pass; the secret scan re-runs on the merged diff state.

## References

- v8.0 LAW-16 + GATE-12: `docs/ubs-v8-technical-hardening.md`
- `/ck:security-scan` skill (catalogued Phase 01)
- Reviewer prompt: `references/reviewer-prompts/security-bridge.md`
- STRIDE / OWASP cheat: `references/security-checklist.md`
