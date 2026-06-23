---
name: cleanup-done-tasks
description: Purge Done tasks older than N days — removes task file, dot-prefixed folder, and tasks.md row. Dry-run by default, one commit per task.
allowed-tools: Bash(*), Read, AskUserQuestion
model: haiku
---

Pota le task `✔️ Done` più vecchie di N giorni. Operazione **distruttiva ma recuperabile via git history**.

Input utente:
~~~human
$ARGUMENTS
~~~

## Parsing argomenti

Da `$ARGUMENTS` estrai:
- **DAYS**: intero da `--days N` (default `60`)
- **TASK_IDS**: lista opzionale di ID task (es. `T02 T03`) per filtrare l'operazione a queste sole task

## Flusso

### 1. Dry-run (sempre prima)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/cleanup-done-tasks.sh \
    --mode "${user_config.project_mode}" \
    --docs-root "${user_config.doc_folder_name}" \
    --days ${DAYS} \
    ${TASK_IDS}
```

Senza `--apply` lo script NON tocca nulla: elenca task candidati (ID, età in giorni, file task, folder) e task skippate (dati mancanti).

Mostra l'output all'utente.

### 2. Conferma (obbligatoria se ci sono candidati)

Prima dell'AskUserQuestion esegui il TTS ping:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "conferma pulizia task done"
```

Se ci sono candidati, mostra `AskUserQuestion` con:
- Elenco candidati (da dry-run)
- Avviso: ogni task viene eliminata con un commit dedicato; recuperabile via `git checkout <commit>~1 -- <path>`

Opzioni:
- **Procedi** — esegui con `--apply`
- **Annulla** — non fare nulla

Se non ci sono candidati, chiudi con un messaggio ("nessuna task da potare") senza chiedere conferma.

### 3. Esecuzione (solo se confermato)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/cleanup-done-tasks.sh \
    --mode "${user_config.project_mode}" \
    --docs-root "${user_config.doc_folder_name}" \
    --days ${DAYS} \
    --apply \
    ${TASK_IDS}
```

Lo script per ogni task candidata:
- Rimuove `runtime/tasks/Tnn-slug.md` (git rm)
- Rimuove folder dot-prefixed se presente (git rm -r)
- Rimuove la riga da `tasks.md` Tasks Overview (e nodo nel grafo Execution Plan)
- Fa un commit con messaggio ricercabile: `chore(tasks): purge done Tnn (slug) — Done >Ndays`

### 4. Feedback

Mostra il risultato dello script. Se uno o più commit sono andati a buon fine:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "pulizia task done completata"
```

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

## Note

- **Dry-run di default**: sicuro da invocare per semplice ispezione
- **Un commit per task**: restore granulare con `git checkout <commit>~1 -- <path>`
- **Skip sicuro**: task la cui data Done non è determinabile vengono saltate con warning, mai eliminate
- **Filtro ID**: `cleanup-done-tasks T02 T03` opera solo sulle task indicate (devono essere Done e oltre soglia)
- **Push**: lo script non fa push automatico; l'utente fa push manualmente o via checkpoint-task
