# loom-works plugin

Plugin source repository. Install via `/plugin install loom-works@lamemind`.

## Structure

- `skills/` — Skill definitions (SKILL.md per skill)
- `scripts/` — Bash scripts invoked by skills
- `agents/` — Subagent definitions
- `hooks/` — Plugin hooks (auto-loaded) and optional hooks
- `docs/` — Methodology documentation (injected at SessionStart)
- `output-styles/` — Output style imposto ai client (`force-for-plugin`), auto-caricata
- `templates/` — Task and doc templates
- `.claude-plugin/` — Plugin manifest (plugin.json, marketplace.json)
