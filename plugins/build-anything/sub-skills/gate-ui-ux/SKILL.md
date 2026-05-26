---
name: build-anything-gate-ui-ux
description: Stage 6.7 — UI/UX hard gate that invokes ui-ux-pro-max design-system + pre-delivery checklist; HALTs if visual quality, accessibility, or layout rules are violated
---

# gate-ui-ux — UI/UX Hard Gate (v8.2)

**Maps to:** stage 6.7 of `/build-anything` flow (between cloud-reality and security gates). Closes the loop where a previous v8.1 run shipped a "YouTube clone" with no real UI consideration. This gate makes UI quality a mechanical pass/fail concern.

## Trigger

Runs ONLY if `project_type` ∈ {`frontend`, `mixed`} OR `.build-anything.json` has `ui.enabled: true`. Backend-only atoms get N/A_PENDING_REVIEWER.

## Inputs

- `{atom_dir}/spec.md` — extract product type and UI keywords
- `.build-anything.json` — read `ui.stack` (`react` | `next` | `vue` | `svelte` | `react-native` | `html`) and `ui.pages[]` (declared pages/components)
- Frontend source files under `ui.source_root` (default `frontend/` or `src/`)

## Pipeline

```
1. ensure ui-ux-pro-max skill present     (errors out via gate-deps if not)
2. invoke design-system generation         (--design-system --persist)
3. read design-system/MASTER.md            (or relevant page override)
4. parse spec for declared pages          (e.g. "landing", "video-watch", "upload-form")
5. for each page → run rule audit:
   - emoji-as-icon check                  (rule §1 no-emoji-icons)
   - hex literal in component check       (rule §6 color-semantic)
   - touch-target audit                   (rule §2 touch-target-size)
   - inline style audit                   (rule §13 hardcoded values)
   - heading-hierarchy audit              (rule §1 heading-hierarchy)
   - missing alt text audit               (rule §1 alt-text)
   - missing aria-label on icon-only btn  (rule §1 aria-labels)
   - viewport meta presence               (rule §5 viewport-meta)
6. produce report → gate-ui-ux/ui-audit.json
7. PASS only if zero CRITICAL findings AND ≤ 3 HIGH findings (config-tunable)
```

## Outputs

- `{atom_dir}/gate-ui-ux/ui-audit.json` — full audit + per-page breakdown
- `{atom_dir}/gate-ui-ux/design-system.md` — generated design system master
- `{atom_dir}/verdicts.json` entry for stage 6.7

## Audit JSON shape

```json
{
  "gate": "GATE-UIUX",
  "verdict": "PASS|FAIL|N/A_PENDING_REVIEWER",
  "passed": true,
  "ran_at": "…",
  "evidence": {
    "design_system_path": "design-system/MASTER.md",
    "stack": "react",
    "pages_audited": ["landing", "video-watch", "upload"],
    "findings": [
      {"severity": "CRITICAL", "rule": "no-emoji-icons", "file": "src/Nav.tsx", "line": 42, "snippet": "<span>🎬</span>"},
      {"severity": "HIGH",     "rule": "color-semantic", "file": "src/App.css", "line": 17, "snippet": "color: #ff5500"}
    ],
    "counts_by_severity": { "CRITICAL": 1, "HIGH": 1, "MEDIUM": 0, "LOW": 0 }
  }
}
```

## Thresholds (config-tunable)

```json
"ui": {
  "enabled": true,
  "stack": "react",
  "source_root": "frontend/src",
  "pages": [
    { "name": "landing",      "spec": "homepage" },
    { "name": "video-watch",  "spec": "play video" },
    { "name": "upload",       "spec": "upload video" }
  ],
  "thresholds": {
    "max_critical": 0,
    "max_high":     3,
    "max_medium":  10
  }
}
```

## LAW-F6 Compliance

- No `ui.enabled` flag AND `project_type == backend` → emit **N/A_PENDING_REVIEWER**, NEVER vacuous PASS.
- `ui.enabled: true` but no source files found → **FAIL** (config lies about UI presence).
- ui-ux-pro-max not present → **FAIL** with `dep_missing: ui-ux-pro-max` (deps.json should have caught earlier).

## Script

Runner: `scripts/gate-ui-ux/audit.sh --atom-dir … --project-root …`

The runner:
1. Sources `_common.sh` (uses `cfg` helper from backend `_common.sh`).
2. Calls ui-ux-pro-max's `search.py --design-system --persist -p "<atom-name>"`.
3. Greps source files for known anti-patterns (regex from `audit-rules.json`).
4. Aggregates into ui-audit.json.

## When the gate triggers

| Atom kind | Triggers? |
|-----------|-----------|
| Frontend page atom | YES |
| Backend API atom + ui.enabled | YES (audits associated UI surface) |
| Pure backend, no UI | N/A_PENDING_REVIEWER |
| Library / SDK | N/A_PENDING_REVIEWER |

## Pre-delivery Checklist Enforcement

The ui-ux-pro-max skill ships a Pre-Delivery Checklist with ~25 items. This gate's `audit-rules.json` mechanically encodes the SUBSET that can be statically checked from source. The remaining items (visual review, dark-mode test on real device) escalate to the reviewer in stage 11.

Statically-checkable rules (CRITICAL + HIGH):
- `no-emoji-icons` — grep for emoji glyph in JSX/HTML
- `color-semantic` — flag raw hex/rgb in *.tsx, *.jsx (allow in tokens.css)
- `touch-target-size` — flag <button> / <a> with explicit width<44 height<44
- `viewport-meta` — assert `<meta name="viewport" content="width=device-width,initial-scale=1">` in index.html
- `image-alt-text` — flag `<img>` without `alt`
- `aria-icon-only` — flag icon-only buttons without `aria-label`
- `heading-skip` — parse h1→h6 in JSX; flag level skips
- `inline-style-discipline` — flag `style={{` with >3 props (suggest CSS class)

Reviewer-only rules (escalated to stage 11):
- design language coherence
- emotional tone match to product
- micro-interaction quality
- dark-mode visual review
