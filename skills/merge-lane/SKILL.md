---
name: merge-lane
description: Merge a lane into main, update the tasks.md graph, keep the worktree.
allowed-tools: Bash(*), Read, Edit
model: sonnet
---

Merge della lane corrente in main. Eseguire dal worktree base (branch main).
Auto-rileva tutti i worktrees `*-{lane}` in WORKTREE_BASE.
Default: mantiene i worktrees dopo il merge. `--cleanup` per rimuoverli.

Input utente:
~~~human
$ARGUMENTS
~~~

## Parsing input

Da `$ARGUMENTS` estrai:
- **lane** (obbligatorio): nome della lane (es. `l1`, `feat-auth`)
- **--cleanup** (opzionale): rimuove i worktrees dopo il merge

Se lane assente, chiedi all'utente quale lane mergiare (mostra lista da `list-worktrees`).

## Flusso

### 1. Esegui merge script

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/merge-lane.sh \
    --docs-root "${user_config.doc_folder_name}" \
    "${lane}" ${cleanup_flag}; echo "EXIT_CODE=$?"
```

Cattura **sia stdout che exit code** (`echo "EXIT_CODE=$?"` dopo il `;`).

### 2. Gestisci risultato

**Exit 0** (successo):
- Riporta output script
- Se `PENDING PROD VALIDATION` è presente → evidenzialo in sezione separata
- Mostra i path dei worktrees preservati (o conferma cleanup)

**Exit 2** (conflitto):
- Estrai `CONFLICT_DIR=...` dall'output dello script
- Invoca `/loom-works:reconcile-tasks ${conflict_dir}`
- Dopo reconcile, rilancia lo script (max 1 retry):
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/scripts/task/merge-lane.sh \
      --docs-root "${user_config.doc_folder_name}" \
      "${lane}" ${cleanup_flag}; echo "EXIT_CODE=$?"
  ```
- Se fallisce ancora → riporta errore dettagliato all'utente

**Exit 1** (errore validazione):
- Riporta l'errore, non ritentare

### 3. Sezione LANES in tasks.md (automatica)

`merge-lane.sh` invoca `render-lanes.sh` alla fine: rigenera la sezione gestita
`<!-- LANES:START -->...<!-- LANES:END -->` in `tasks.md` (add-or-replace), creandola
prima di `## Execution Plan` se assente. **Nessuna azione LLM richiesta.**

Detection branch-agnostica (D3, git=verità): scansiona i worktree via `list-worktrees.sh`,
aggrega per lane e include la task in esecuzione (letta dal symlink `current-task.md` nel
worktree, presente in single-project). Con `--cleanup` i worktree rimossi spariscono dalla
vista automaticamente.

## Note

- Esegui dal worktree base (branch main, non dal worktree lane)
- auto-detect: lo script trova tutti i `*-{lane}` in WORKTREE_BASE automaticamente
- Single-project: sync automatico di tasks.md nel worktree lane (per prossima task)
- Multi-project: nessun sync di tasks.md (è già unico e non branchato)
- `reconcile-tasks` serve solo in single-project (D5): in multi tasks.md non viene branchato
- **Profilo terminale Ptyxis**: con `--cleanup`, lo script rimuove anche il profilo Ptyxis associato al worktree. Best-effort, noop senza Ptyxis.
