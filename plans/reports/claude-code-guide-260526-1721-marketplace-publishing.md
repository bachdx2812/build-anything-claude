# Claude Code Marketplace Publishing Guide

## 1. Installation Command & Discovery

**Install from marketplace:**
```bash
/plugin install build-anything@your-marketplace-name
```

**Discovery methods:**
- Add marketplace: `/plugin marketplace add bachdx2812/build-anything-claude`
- Install: `/plugin install build-anything@bachdx2812` (uses org/repo format as marketplace ID)
- Or create `.claude-plugin/marketplace.json` for formal marketplace registration

**Official registries:**
- Anthropic official: `claude-plugins-official` (curated, submission via in-app form only)
- Community marketplace: `anthropics/claude-plugins-community` (pass automated validation)
- Custom marketplaces: self-host via GitHub/GitLab (no central registry like npm)

**Action:** Add `.claude-plugin/marketplace.json` to repo root for marketplace compatibility.

---

## 2. No Central Registry—Distribution via GitHub

Claude Code 2026 has **no centralized plugin registry** like npm/PyPI. Distribution works through:
- **Direct GitHub repo**: Users add `owner/repo` format → Claude Code clones & reads `.claude-plugin/marketplace.json`
- **Community submission**: GitHub repo → Anthropic validates → added to `anthropics/claude-plugins-community`
- **Custom marketplaces**: Users manually add your marketplace URL per instructions

**For `bachdx2812/build-anything-claude`:**
1. Publish `.claude-plugin/marketplace.json` to repo root
2. Users discover via community marketplace OR manually add: `/plugin marketplace add bachdx2812/build-anything-claude`
3. Install: `/plugin install build-anything@bachdx2812`

---

## 3. Exact Required Changes to Repo

**Directory structure (move skill):**
```
build-anything-claude/
├── .claude-plugin/
│   └── marketplace.json          ← CREATE THIS
├── skill/                         ← RENAME to plugins/build-anything/
│   ├── SKILL.md
│   ├── scripts/
│   ├── sub-skills/
│   ├── references/
│   └── templates/
├── plugins/
│   └── build-anything/           ← Move skill/ contents here
├── docs/
├── examples/
└── README.md
```

**Create `.claude-plugin/marketplace.json`:**
```json
{
  "$schema": "https://json.schemastore.org/claude-code-marketplace.json",
  "name": "build-anything-claude",
  "version": "8.1.0",
  "description": "UBS v8.1 atomic build orchestrator: 15-stage production pipeline with mechanical gates",
  "owner": {
    "name": "Bach Dang",
    "email": "bachdx.hut@gmail.com"
  },
  "plugins": [
    {
      "name": "build-anything",
      "description": "15-stage atomic build pipeline (spec→red-team→build→security→prod-verify) with multi-agent orchestration",
      "version": "8.1.0",
      "author": {
        "name": "Bach Dang"
      },
      "source": "./plugins/build-anything",
      "category": "development"
    }
  ]
}
```

**Update plugin manifest:** Move/rename skill to `plugins/build-anything/SKILL.md` with frontmatter:
```yaml
---
name: build-anything
version: 8.1.0
description: >
  15-stage atomic build orchestrator (spec→build→mechanical-gates→security→prod-verify)
  with multi-agent adversarial review and production-reality gates
---
```

---

## 4. Plugin vs Skill—Claude Code 2026 Terminology

**Skill** = single capability (a SKILL.md file + scripts/references)
**Plugin** = bundled container (marketplace entry) distributing 1+ skills

**Installation flow:**
- Plugin → marketplace entry → contains skill(s) → user installs plugin → skills added to Claude

**Your case:** `build-anything` plugin contains single primary skill + sub-skills in `sub-skills/` dir.

**Both install** via marketplace; "plugin" is the distribution unit, "skill" is the functional unit.

---

## 5. Real-World Examples

Official reference implementations:
1. **[anthropics/claude-code](https://github.com/anthropics/claude-code)** — Official demo plugins, `.claude-plugin/marketplace.json` format
2. **[anthropics/skills](https://github.com/anthropics/skills)** — Anthropic agent skills marketplace, shows multi-skill plugin structure
3. **[daymade/claude-code-skills](https://github.com/daymade/claude-code-skills)** — Production-ready 52 skills, community marketplace model

All use `.claude-plugin/marketplace.json` + `plugins/` subdirectories.

---

## Submission Path (Optional)

To get into `anthropics/claude-plugins-community`:
1. Finalize repo with `.claude-plugin/marketplace.json`
2. Submit GitHub repo URL to community marketplace (Anthropic website form)
3. Automated validation + safety screen
4. If approved → listed in community marketplace (users: `/plugin marketplace add anthropics/claude-plugins-community`)

---

**Summary:** Rename `skill/` → `plugins/build-anything/`, add `.claude-plugin/marketplace.json`, push to GitHub. Install: `/plugin marketplace add bachdx2812/build-anything-claude` then `/plugin install build-anything@bachdx2812`.

