---
name: clean-tasks
description: Clean tasks on demand — by ID (T15), range (T15-T20 / T15-20), or age ("older than N days"). Removes task file, dot-prefixed folder, and tasks.md row, one commit per task.
allowed-tools: Bash(*), Read, AskUserQuestion
model: sonnet
---

Pota task su indicazione diretta. Operazione distruttiva ma recuperabile via git history.

Tutto il lavoro lo fa lo script: per ogni task elimina il task file, la folder dot-prefixed e la riga in `tasks.md` (Overview + nodo Execution Plan), e fa **un commit atomico per task**. Il tuo compito è solo interpretare l'input, lanciare il dry-run, chiedere conferma quando serve, eseguire `--apply`. Non fare git/rm a mano e non aggiungere commit tuoi: lo script possiede l'intero flusso, range inclusi.

Input utente:
~~~human
$ARGUMENTS
~~~

## Modi

Interpreta `$ARGUMENTS` e scegli **uno** dei modi:

| Modo | Trigger | Front-end | Conferma |
|------|---------|-----------|----------|
| **A — ID/range** | token `Tnn`, `Tnn-Tmm`, `Tnn-mm` (virgola/spazio) | `clean-tasks.sh` | solo se ci sono NON-Done |
| **B — età** | linguaggio naturale su anzianità Done | `cleanup-done-tasks.sh` | sempre |
| **C — vuoto/ambiguo** | nessun token riconoscibile | — | chiedi cosa pulire |

**Modo C** → chiedi inline (no AskUserQuestion): «Quali task? ID/range (es. `T15-20`) o età (es. "più vecchie di 30 giorni")».

In Modo B estrai `DAYS` dal linguaggio naturale (default `60`).

## Flusso — dry-run → conferma → apply

Passa l'intero SPEC/range in **una sola invocazione**: lo script espande i range da solo (gli ID inesistenti finiscono `[missing]`, non bloccano).

### 1. Dry-run

**Modo A:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/clean-tasks.sh \
    --mode "${user_config.project_mode}" \
    --docs-root "${user_config.doc_folder_name}" \
    <SPEC...>
```

**Modo B:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/cleanup-done-tasks.sh \
    --mode "${user_config.project_mode}" \
    --docs-root "${user_config.doc_folder_name}" \
    --days ${DAYS}
```

Mostra l'output. Lo script elenca i target con tag `[Done]` / `[NOT Done]` / `[orphan row]` / `[missing]`. Il Modo A chiude con una riga riassuntiva:

```
SUMMARY candidates=A non_done=B orphans=C missing=D
```

Nessun candidato e nessuna riga orfana → niente da rimuovere, chiudi.

### 2. Conferma

- **Modo A**: salta la conferma se `non_done == 0` (tutti Done) e vai diretto all'apply. Se `non_done > 0`, conferma obbligatoria.
- **Modo B**: conferma sempre, se ci sono candidati.

Quando serve, TTS ping poi `AskUserQuestion`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "conferma pulizia task <topic 3-7 parole>"
```

Nell'`AskUserQuestion`: elenca i target dal dry-run (in Modo A evidenzia le NON-Done, eliminazione forzata), ricorda il restore `git checkout <commit>~1 -- <path>`, opzioni **Procedi** / **Annulla**.

### 3. Apply

Stesso comando con `--apply`. Lo script cicla i target e committa uno per uno.

**Modo A:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/clean-tasks.sh \
    --mode "${user_config.project_mode}" \
    --docs-root "${user_config.doc_folder_name}" \
    --apply \
    <SPEC...>
```

**Modo B:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/cleanup-done-tasks.sh \
    --mode "${user_config.project_mode}" \
    --docs-root "${user_config.doc_folder_name}" \
    --days ${DAYS} \
    --apply
```

### 4. Esito

Mostra l'output dello script. Atteso: un commit `chore(tasks): purge …` per ogni task rimossa (più eventuali `reconcile orphan …`), e nessun commit unico che ripulisce `tasks.md` in blocco. Se l'esito diverge, segnalalo invece di dichiarare successo.

Se almeno un commit è andato a buon fine:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "pulizia task completata"
```

## Note

- **Dry-run di default**: sicuro da invocare per sola ispezione.
- **Restore granulare**: ogni commit include file + folder + riga della stessa task → `git checkout <commit>~1 -- <path>`.
- **Modo A ignora stato ed età**: rimuove anche task non-Done (con conferma) e non guarda la soglia giorni; il Modo B pota solo Done oltre `--days`.
- **Active task**: se rimuovi la task attiva, lo script elimina il symlink `current-task.md` per non lasciarlo dangling.
- **Righe orfane**: ID con riga in `tasks.md` ma file già assente → riconciliate con commit dedicato.
- **Push**: nessun push automatico; manuale o via `checkpoint-task`.
