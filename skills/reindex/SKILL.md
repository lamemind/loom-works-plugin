---
name: reindex
description: Regenerate the reference INDEX.md from .md file TLDRs.
allowed-tools: Bash(*)
model: haiku
---

Esegui:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh"
```

Riporta esito (file rigenerato, eventuali warning su stderr per file senza TLDR). Niente altro.

**Exit 2** = indice scritto, ma i TLDR elencati su stderr sono oltre il cap: violazione **bloccante** del contratto doc, non un comando fallito. Non rilanciare — elenca i file e dichiara che vanno riscritti come ancora. Exit 1 = indice non scritto, quello sì è un errore.
