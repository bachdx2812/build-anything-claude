# UBS v8.2 — Skill Composition Contract

This document is the canonical contract between `build-anything` and the three composed skills introduced in v8.2:

| Skill | Source | Where invoked | What it produces | Halt condition |
|-------|--------|---------------|-------------------|-----------------|
| `ck:research` | local `~/.claude/skills/research/` | Stage 1.A | `{atom_dir}/research/product-features-<slug>.md` | research returns 0 sources |
| `bmad-method` | npx package — auto-installed by Stage 0.5 | Stage 1.B | `docs/prd.md`, `docs/architecture.md`, `docs/ux-spec.md` | install fail AND `--no-bmad` not passed |
| `ck:ui-ux-pro-max` | local `~/.claude/skills/ui-ux-pro-max/` | Stage 6.7 | `{atom_dir}/design-system/MASTER.md`, `gate-ui-ux/ui-audit.json` | CRITICAL findings > 0 OR HIGH > threshold |

## Motivation

A v8.1 audit on a "YouTube clone" build shipped with **NO video upload** and **NO video playback**. The Stage 1 spec passed because the success criteria it declared were testable in isolation, but the *product category gap* (a YouTube clone with no upload+play is not a YouTube clone) was invisible to the pipeline. Three structural fixes:

1. **Pre-spec research** — before drafting criteria, discover what the product type canonically requires. Run via `ck:research`.
2. **Multi-agent PRD** — instead of a single-author atom brief, use BMAD's PM + Architect + UX agent personas to produce a layered PRD that exposes feature gaps as structured stories.
3. **UI quality gate** — once code is built, statically audit UI for accessibility, semantic colour, alt-text, touch-target, viewport, and emoji-as-icon violations using ui-ux-pro-max's catalog.

Plus two new mechanical gates:
- **GATE-PFC** — matches spec text against `scripts/spec/feature-catalog.json`; FAILs if a recognised product type is missing must-have features.
- **GATE-25-E2E** — enforces Playwright E2E coverage per declared user journey from the PRD.

## Auto-install protocol (Stage 0.5)

Runner: `scripts/ensure-deps.sh --project-root <root> --atom-dir <atom_dir>`

```
1. Verify research skill present at ~/.claude/skills/research/SKILL.md  → HALT if missing
2. Verify ui-ux-pro-max present at ~/.claude/skills/ui-ux-pro-max/SKILL.md → HALT if missing
3. Detect bmad-method:
   - if project has bmad/, .bmad-core/, or bmad-modules.yaml → PRESENT
   - else if `npx` available → run `npx --yes bmad-method install --directory <root> --modules bmm --tools claude-code --yes`
   - if install rc=0 AND artefacts detected → INSTALLED
   - else → MISSING (degraded mode; pipeline continues with local PM-substitute unless --strict)
4. Emit {atom_dir}/deps.json
```

`deps.json` shape:

```json
{
  "deps_ok": true,
  "checked_at": "…",
  "deps": {
    "research":      { "status": "PRESENT", "path": "…" },
    "ui-ux-pro-max": { "status": "PRESENT", "path": "…" },
    "bmad-method":   { "status": "INSTALLED|PRESENT|MISSING|INSTALL_FAILED", "install_path": "…", "version": "…" }
  }
}
```

## Stage 1.A — Research invocation contract

```
Skill: ck:research
Args:
  topic = "<product type from user description>"
  prompt:
    "Research what features are canonical/expected for a <product type>.
     Identify MVP feature set, secondary features, common gaps. Be concrete.
     Cap: 5 searches max.
     Save to {atom_dir}/research/product-features-<slug>.md"
```

The research output is consumed by Stage 1.B (PRD generation) and Stage 1.C (feature-coverage check).

## Stage 1.B — BMAD invocation contract

If BMAD installed:

```bash
cd $PROJECT_ROOT
npx bmad-method run --module bmm --workflow prd \
  --input "{atom_dir}/research/product-features-<slug>.md" \
  --out   "docs/"
```

Expected outputs after BMAD run:
- `docs/prd.md` (required)
- `docs/architecture.md` (required)
- `docs/ux-spec.md` (optional, if `--with-ux`)

If BMAD missing → invoke local PM-substitute (`references/local-pm-substitute.md`).

## Stage 1.C — Product Feature Coverage Gate

Runner: `scripts/spec/product-feature-coverage.sh --atom-dir <atom_dir>`

Catalog at `scripts/spec/feature-catalog.json`. Currently catalogued:
- youtube-clone, twitter-clone, instagram-clone, amazon-clone, uber-clone
- todo-app, blog-platform, chat-app, airbnb-clone

Adding a new product type: append to `feature-catalog.json` with `{keywords[], must_have[{name, synonyms[]}]}`.

## Stage 5 (mechanical) — GATE-25-E2E

Runner: `scripts/mechanical/e2e-playwright.sh`

Reads `.build-anything.json`:
```json
"e2e": {
  "enabled": true,
  "tool": "playwright",
  "root": "tests/e2e",
  "run_cmd": "npx playwright test --reporter=line",
  "min_per_journey": 1,
  "journeys": [
    { "name": "upload-video",  "must_visit": ["/upload", "/videos/$id"] },
    { "name": "watch-video",   "must_visit": ["/videos/$id"] },
    { "name": "auth-register", "must_visit": ["/register"] }
  ]
}
```

Vacuous-PASS guard: if Playwright exits 0 but reports 0 passed + 0 failed, the gate FAILs. If 0 test files found under `e2e.root` while `e2e.enabled=true`, FAIL.

## Stage 6.7 — UI/UX Hard Gate (GATE-UIUX)

Runner: `scripts/gate-ui-ux/audit.sh`

Pipeline:
1. Trigger check: `ui.enabled=true` OR `project_type ∈ {frontend, mixed}`. Backend-only → N/A_PENDING_REVIEWER.
2. Verify `ui-ux-pro-max` skill present (Stage 0.5 should have ensured this; this is a defence-in-depth check).
3. Run `python3 ~/.claude/skills/ui-ux-pro-max/scripts/search.py "<query from spec>" --design-system --persist -p "<atom-name>" -f markdown` → produces `design-system/MASTER.md`.
4. Static-rule audit on source files under `ui.source_root`:
   - `no-emoji-icons` (CRITICAL) — emoji glyphs in JSX/HTML
   - `color-semantic` (HIGH) — raw hex/rgb in *.tsx/*.jsx outside token files
   - `viewport-meta` (HIGH) — `<meta name=viewport>` missing in any index.html
   - `image-alt-text` (HIGH) — `<img>` without alt
   - `aria-icon-only` (HIGH) — `<button><svg/i/Icon>` without aria-label
   - `inline-style-discipline` (MEDIUM) — `style={{...}}` with 3+ props
5. PASS thresholds: `max_critical=0`, `max_high=3`, `max_medium=10` (config-tunable).

## Backward compatibility

- v8.1 atoms that lack `prd_ref` / `research_refs` / `canonical_features_covered` will fail GATE-0 in v8.2 strict mode but get N/A_PENDING_REVIEWER in auto/fast mode (give existing repos a migration window).
- `--no-bmad` flag forces local PM-substitute path; GATE-PFC still enforced.
- `--no-uiux` flag downgrades GATE-UIUX to N/A_PENDING_REVIEWER (must be acknowledged by reviewer).

## Failure modes addressed

| v8.1 failure | v8.2 control |
|--------------|--------------|
| "YouTube clone" with no upload/play | GATE-PFC catches missing features against catalog |
| Single-author spec misses domain features | BMAD PM/Architect/UX agents cross-check |
| UI not considered in audit | GATE-UIUX runs design system + static rules |
| No E2E coverage | GATE-25-E2E enforces Playwright tests per journey |
| "Test was probably fine" rationalization | All new gates emit JSON verdict to disk + LAW-F6 N/A_PENDING_REVIEWER on empty input |
