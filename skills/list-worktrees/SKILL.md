---
name: list-worktrees
description: List project worktrees (main + lanes) with branch, dirty count, last commit and active task.
allowed-tools: Bash(*)
model: sonnet
---

Mostra una panoramica dei worktree del progetto corrente: tipo (main/lane/other), branch, file dirty, ultimo commit, task in esecuzione e path.

Per una vista d'insieme più ampia (doc↔git/fs, incongruenze, next step) usa invece `/loom-works:recap-status`.

Input utente:
~~~human
$ARGUMENTS
~~~

## Parsing input

Da `$ARGUMENTS` estrai (tutti opzionali):
- **filter**: `main` | `lane` | `all` (default `all`) — limita per tipo di worktree
- **lane**: nome lane specifica — mostra solo i worktree `*-{lane}`

Se l'utente non specifica nulla, esegui senza filtri (mostra tutto).

## Flusso

Esegui lo script passando `LOOM_DOCS_ROOT` (serve a risolvere il symlink `current-task.md` → campo Task):

```bash
LOOM_DOCS_ROOT="${user_config.doc_folder_name}" \
    bash "${CLAUDE_PLUGIN_ROOT}/scripts/utils/list-worktrees.sh" \
    [--filter <main|lane|all>] [--lane <name>]
```

Aggiungi `--filter` / `--lane` solo se l'utente li ha richiesti. Mostra l'output così com'è.

## Note

- **Single-project**: esegue sul project root corrente. Per multi-project, una panoramica completa richiede di lanciarlo da ciascun sub-repo (lo script lavora su un repo per volta).
- Il campo **Task** è popolato solo dove `docs/current-task.md` è branchato (single-project); altrimenti `(none)`.
- Read-only: nessuna modifica, nessuna conferma necessaria.
- Stesso script usato internamente da `merge-lane` e `drop-lane` per elencare le lane.
