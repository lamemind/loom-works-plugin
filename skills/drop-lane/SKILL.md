---
name: drop-lane
description: Destroy a lane WITHOUT merging — removes worktree, branch and Ptyxis profile.
allowed-tools: Bash(*), Read, AskUserQuestion, Edit
model: sonnet
---

Distrugge una lane senza mergiare. **Operazione distruttiva**: perde commit non mergiati e modifiche uncommitted.
Per lane abbandonate (esperimenti falliti, branch da buttare). Per mergiare invece usa `/loom-works:merge-lane`.

Eseguire dal worktree base (branch main).

Input utente:
~~~human
$ARGUMENTS
~~~

## Parsing input

Da `$ARGUMENTS` estrai:
- **lane** (obbligatorio): nome della lane da distruggere

Se lane assente, chiedi quale lane (mostra lista da `list-worktrees --filter lane`).

## Flusso

### 1. Dry-run (preview)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/drop-lane.sh \
    --docs-root "${user_config.doc_folder_name}" \
    "${lane}"
```

Senza `--yes` lo script NON tocca nulla: elenca i worktrees `*-{lane}`, il branch, i **commit non mergiati**, i **file dirty**. Mostra l'output all'utente.

### 2. Conferma distruttiva (obbligatoria)

Prima dell'AskUserQuestion esegui il TTS ping (vedi Convenzione TTS).

Mostra `AskUserQuestion` con il riepilogo di cosa verrà perso (commit non mergiati, file dirty dal dry-run). Opzioni:
- **Distruggi** — procedi
- **Annulla** — non fare nulla

**Mai** procedere senza conferma esplicita. Se anche un solo worktree ha commit non mergiati o file dirty, evidenzialo chiaramente nella domanda.

### 3. Esecuzione (solo se confermato)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/drop-lane.sh \
    --docs-root "${user_config.doc_folder_name}" \
    "${lane}" --yes
```

Lo script: rimuove profilo Ptyxis (best-effort) → `git worktree remove --force` → `git branch -D feat/{lane}`.

### 4. Pulizia sezione LANES in tasks.md

Se esiste la sezione `<!-- LANES:START -->...<!-- LANES:END -->` in `${user_config.doc_folder_name}/tasks.md`, rimuovi la riga della lane distrutta con Edit tool.

Inoltre, nel grafo Execution Plan, rimuovi eventuali marker 🟡 davanti ai task ID che erano in lavorazione su questa lane (tornano allo stato precedente). Se non sei certo dello stato pregresso, lascia il task come 🔵 Todo e segnalalo all'utente.

### 5. Feedback + TTS

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "lane ${lane} distrutta"
```

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

## Note

- **Distruttiva e non reversibile**: branch cancellato con `-D` (force), worktree con `--force`. Commit non mergiati persi.
- Eseguire dal worktree base, non dal worktree lane (non puoi rimuovere il worktree in cui ti trovi)
- Auto-detect: trova tutti i `*-{lane}` (multi-project rimuove tutti i sub-repo worktree della lane)
- Profilo Ptyxis rimosso automaticamente (best-effort, noop senza Ptyxis)
- Differenza da `merge-lane --cleanup`: quello **mergia poi** rimuove; drop-lane **NON mergia**
