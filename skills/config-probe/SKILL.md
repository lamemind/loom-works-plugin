---
name: config-probe
description: Experimental probe for user_config resolution (skill body + script env).
allowed-tools: Bash(*)
model: haiku
---

Stampa quello che la skill vede e quello che lo script vede.

## Dalla skill (interpolazione markdown)

- `on_lane_spawned_hook` (da `${user_config.on_lane_spawned_hook}`): **${user_config.on_lane_spawned_hook}**
- `CLAUDE_PLUGIN_ROOT`: **${CLAUDE_PLUGIN_ROOT}**

## Dallo script bash (env var)

Esegui:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/utils/probe-env.sh
```

## Docs root (non passa da user_config)

La docs-root **non** è un userConfig: è per-progetto, sta in `.claude/loom-works.json` → `docsRoot`. Sondala col comando, che è l'unico canale corretto:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh" && "${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh" --abs
```

## Report

Riporta all'utente in forma compatta:
1. Cosa è stato risolto inline qui sopra (se vedi i letterali `${...}` significa che NON è stato risolto)
2. Cosa lo script ha stampato per `CLAUDE_PLUGIN_OPTION_*`
3. La docs-root risolta, e se corrisponde a quella reale del progetto

Non fare altro.
