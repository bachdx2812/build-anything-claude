# UBS Philosophy — Reference

This reference is a pointer, not a redefinition. Canonical sources:

- **v7.5 (boss's doc):** Google Doc — preserved verbatim. W1 LAW-01..10, W2 GATE-1..9, L1..L6, Atom shape, Allowlist, Evidence Law, Append-Only History, Automation Ladder AL-0..4.
- **v8.0 (this hardening):** `docs/ubs-v8-technical-hardening.md` in the project repo. Strict extension. LAW-11..17 + GATE-10..21 + Multi-Agent Review Protocol + AL hardening.

## Reading order for new operators

1. Read v7.5 first (the philosophy).
2. Read v8.0 Section G — "Boss Compatibility Statement" — to confirm v7.5 still binds.
3. Read v8.0 Section F — reverse-mapping — to see which v7.5 gap each new LAW/GATE addresses.
4. Read this skill's root `SKILL.md` for the 14-stage flow.
5. Only then read individual sub-skill SKILL.md files when invoking.

## Core terms (mnemonic)

- **Atom** — unit of work; `{code, layer, iter, allowlist, success, rollback}`.
- **Layer** — L1 spec → L2 schema → L3 build → L4 review → L5 merge → L6 prod-verify.
- **Gate** — mechanical or reviewer checkpoint. Pass criteria are mechanical where possible.
- **Law** — inviolable rule. Violation triggers HALT + AL demotion.
- **Evidence** — verifiable artifact; in v8.0 every artifact is SHA-hashed in a manifest (LAW-17).
- **Allowlist** — the binding contract; touching a file outside it invalidates the atom.
- **Automation Ladder** — AL-0..4; promotion earned, demotion automatic.

## Why this skill exists

Boss claims "Devin says done = done." UBS v7.5 itself says "merged alone is never PASS; tests green alone is never PASS." The skill exists to make that line **machine-enforced** rather than aspirational.

## Where the philosophy bends, where it does not

| Bends (extended) | Does NOT bend (preserved) |
|------------------|---------------------------|
| L4 substance (now multi-agent adversarial) | LAW-01..10 verbatim |
| Test rigor (now coverage + mutation + property) | LAW-10 NO AUTO-DESTRUCTIVE |
| Evidence (now crypto-bound manifest) | Allowlist binding |
| Security (now full OWASP / STRIDE) | Atom shape |
| Performance (now budgeted) | 6-layer chain |
| Observability (now mandatory) | Append-only history |
| Backend correctness (now 9 sub-gates) | Automation Ladder progression |
