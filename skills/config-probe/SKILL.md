---
name: config-probe
description: Experimental probe for user_config resolution (skill body + script env).
allowed-tools: Bash(*)
model: haiku
---

Stampa quello che la skill vede e quello che lo script vede.

## Dalla skill (interpolazione markdown)

- `project_mode` (da `${user_config.project_mode}`): **${user_config.project_mode}**
- `doc_folder_name` (da `${user_config.doc_folder_name}`): **${user_config.doc_folder_name}**
- `CLAUDE_PLUGIN_ROOT`: **${CLAUDE_PLUGIN_ROOT}**

## Dallo script bash (env var)

Esegui:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/utils/probe-env.sh
```

## Report

Riporta all'utente in forma compatta:
1. Cosa è stato risolto inline qui sopra (se vedi i letterali `${...}` significa che NON è stato risolto)
2. Cosa lo script ha stampato per `CLAUDE_PLUGIN_OPTION_*`

Non fare altro.
