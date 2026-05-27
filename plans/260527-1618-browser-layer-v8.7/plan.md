# v8.7 — Desktop-browser layer

## Goal

Close coverage gap: a Devin commit declaring "we built a browser" silently passed v8.6 (no project_type for it; falls under `frontend` → Playwright drives it as a web app, which is wrong — browser binary ≠ web page). v8.7 introduces `desktop-browser-*` project_type with two mandatory gates: CDP E2E + WPT conformance.

## Scope (in)

- 5 new project_types: `desktop-browser-chromium|electron|tauri|gecko|novel`
- GATE-25-E2E-BROWSER (CDP / WebDriver smoke against own binary)
- GATE-BROWSER-WPT (Web Platform Tests subset conformance)
- N/A short-circuits in playwright / maestro / ui-ux / mobile-perms gates for `desktop-browser-*`
- Browser-aware SLO regex in `production-design-gate.sh` (TTFR, V8-startup, paint-jank, tab-crash-free)
- Feature-catalog rows: `desktop-browser-generic`, `desktop-browser-privacy`
- 10th meta-gate: `browser-e2e-test.sh` (LAW-F6 fixtures)
- Charter doc: Section Z + Section B inventory + Section O meta-gate count
- SKILL.md: Stage 5 row + meta-gate table

## Scope (deferred → v8.8)

- GATE-BROWSER-COMPAT (top-1000 sites smoke — needs corpus infra)
- GATE-BROWSER-CRASH (Crashpad/Breakpad ingestion — needs platform-specific glue)
- GATE-BROWSER-FUZZ (libFuzzer corpus — needs build-system integration)
- GATE-COMP-COV (compensating coverage law — orthogonal, separate ship)
- Cross-OS pixel-parity tests (needs reference renders)

## Gates contract (stack-agnostic)

| Gate | Trigger | Inputs | PASS rule | FAIL rule |
|------|---------|--------|-----------|-----------|
| GATE-25-E2E-BROWSER | `project_type=desktop-browser-*` | `browser.binary_path`, `browser.journeys_dir`, `browser.driver` (cdp\|webdriver) | journeys ≥1 passed, 0 failed, no crash | declared-but-skipped, binary missing, 0 journeys, vacuous run, journey failed |
| GATE-BROWSER-WPT | `project_type=desktop-browser-*` AND `browser.wpt.enabled=true` | `browser.wpt.runner_cmd`, `browser.wpt.subset`, `browser.wpt.threshold` (default 0.95) | pass-rate ≥ threshold | declared-but-skipped, subset empty, pass-rate below |

Both gates emit `confidence: 100` on PASS, `null` on N/A (LAW-CL-95).

## Dispatch matrix

| project_type | playwright | maestro | ui-ux | mobile-perms | e2e-browser | wpt |
|--------------|-----------|---------|-------|--------------|-------------|-----|
| backend | N/A | N/A | N/A | N/A | N/A | N/A |
| frontend | RUN | N/A | RUN | N/A | N/A | N/A |
| mobile-* | N/A | RUN | N/A | RUN | N/A | N/A |
| desktop-browser-* | N/A | N/A | N/A | N/A | RUN | RUN |

## LAW-F6 mandates (no vacuous PASS)

- `desktop-browser-*` AND `browser.binary_path` empty → FAIL
- `desktop-browser-*` AND `browser.journeys_dir` absent OR empty → FAIL
- `desktop-browser-*` AND `wpt.enabled=false` → FAIL (you can't ship a browser without standards conformance)
- WPT runner exits 0 with 0 tests run → FAIL (vacuous)

## Boring-tech justification

- CDP / WebDriver: 15-year-old protocols, every major browser supports
- WPT: maintained by W3C/WHATWG; pinning a subset is industry standard (Chrome, Firefox, Safari all run WPT in CI)
- No new external skill deps — gates shell out to declared runner commands

## Files to touch

```
plugins/build-anything/scripts/intent/declare-intent.sh         # enum
plugins/build-anything/sub-skills/intent/SKILL.md               # docs
plugins/build-anything/scripts/mechanical/e2e-browser.sh        # NEW
plugins/build-anything/scripts/mechanical/browser-wpt-check.sh  # NEW
plugins/build-anything/scripts/mechanical/e2e-playwright.sh     # short-circuit
plugins/build-anything/scripts/mechanical/e2e-maestro.sh        # short-circuit
plugins/build-anything/scripts/mechanical/mobile-perms-check.sh # short-circuit
plugins/build-anything/scripts/gate-ui-ux/audit.sh              # short-circuit
plugins/build-anything/scripts/spec/production-design-gate.sh   # SLI dialect
plugins/build-anything/scripts/spec/feature-catalog.json        # +products +caps
plugins/build-anything/sub-skills/gate-mechanical/SKILL.md      # dispatch docs
plugins/build-anything/scripts/meta/browser-e2e-test.sh         # NEW
plugins/build-anything/SKILL.md                                 # Stage 5 + meta table
docs/ubs.md                                                     # Section Z + B + O
docs/ubs.docx                                                   # regenerated
```

## Meta-gate fixtures (browser-e2e-test.sh)

1. `project_type=backend` → e2e-browser N/A_PENDING_REVIEWER
2. `project_type=desktop-browser-chromium` no `browser.binary_path` → FAIL
3. `project_type=desktop-browser-chromium` binary set but `journeys_dir` empty → FAIL
4. `project_type=frontend` → wpt N/A_PENDING_REVIEWER
5. `project_type=desktop-browser-chromium` `wpt.enabled=false` → FAIL (LAW-F6 declared-but-skipped)
6. `project_type=desktop-browser-chromium` `wpt.enabled=true` no `wpt.subset` → FAIL
7. `project_type=desktop-browser-chromium` `wpt.runner_cmd` returns 0 tests → FAIL (vacuous)

## Acceptance

- All 10 meta-gates PASS
- Charter doc Section Z present, ubs.docx regenerated
- Commit + push, no Word lock files staged
- No `AskUserQuestion` mid-flow (caveman + boss rule)

## Open questions

- WPT runner default: bundled wpt checkout vs declared external repo? → declared external (no skill bundle bloat)
- desktop-browser-novel (Servo / Ladybird / from-scratch): WPT runner must be project-supplied (`browser.wpt.runner_cmd`) since they don't ship Chrome's `wpt run`
