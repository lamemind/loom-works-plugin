---
name: reindex
description: Regenerate the reference INDEX.md from .md file TLDRs.
allowed-tools: Bash(*)
model: haiku
---

Esegui:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "${user_config.doc_folder_name}"
```

Riporta esito (file rigenerato, eventuali warning su stderr per file senza TLDR). Niente altro.
