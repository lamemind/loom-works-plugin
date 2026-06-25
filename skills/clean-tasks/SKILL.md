---
name: clean-tasks
description: Clean tasks on demand — by ID (T15), range (T15-T20 / T15-20), or age ("older than N days"). Removes task file, dot-prefixed folder, and tasks.md row, one commit per task. Supersedes cleanup-done-tasks.
allowed-tools: Bash(*), Read, AskUserQuestion
model: haiku
---

Pota task **su indicazione diretta**. Operazione **distruttiva ma recuperabile via git history** (un commit per task, restore con `git checkout <commit>~1 -- <path>`).

Input utente:
~~~human
$ARGUMENTS
~~~

## Classificazione (3 modi)

Interpreta `$ARGUMENTS` e scegli **uno** dei modi:

| Modo | Trigger | Esempi |
|------|---------|--------|
| **A — ID/range** | uno o più token task `Tnn`, `Tnn-Tmm`, `Tnn-mm` (anche separati da virgola/spazio) | `T15` · `T15-20` · `T15-T20` · `T03 T07` |
| **B — età** | linguaggio naturale su anzianità Done | `più vecchie di 15 giorni` · `older than 30 days` · `--days 60` |
| **C — vuoto/ambiguo** | nessun token riconoscibile | — |

- **Modo C** → chiedi cosa pulire (inline, no AskUserQuestion): «Quali task? ID/range (es. `T15-20`) o età (es. "più vecchie di 30 giorni")».
- Conferma policy: **A** chiede conferma *solo se* ci sono task NON-Done nel target. **B** chiede conferma *sempre*.

---

## Modo A — ID / range diretto

Front-end: `clean-tasks.sh`. Normalizza i token in SPEC (`Tnn` / `Tnn-Tmm` / `Tnn-mm`); virgole → spazi. Il range viene espanso dallo script (ID inesistenti nel range → riportati `[missing]`, non bloccano).

### 1. Dry-run (sempre prima)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/clean-tasks.sh \
    --mode "${user_config.project_mode}" \
    --docs-root "${user_config.doc_folder_name}" \
    <SPEC...>
```

Mostra l'output. Lo script elenca i target con tag `[Done]` / `[NOT Done]` / `[orphan row]` / `[missing]` ed emette una riga:

```
SUMMARY candidates=A non_done=B orphans=C missing=D
```

Se `candidates=0 orphans=0` → niente da rimuovere, chiudi (nessuna conferma).

### 2. Conferma — **solo se `non_done > 0`**

- `non_done == 0` (tutti Done) → **nessuna conferma**, vai diretto all'esecuzione.
- `non_done > 0` → TTS ping poi `AskUserQuestion`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "conferma purge task non completate"
```

`AskUserQuestion`:
- Elenca i target, **evidenzia le NON-Done** (eliminazione forzata).
- Avviso: un commit per task, recuperabile via `git checkout <commit>~1 -- <path>`.
- Opzioni: **Procedi** / **Annulla**.

### 3. Esecuzione (diretta, o se confermata)

Stesso comando con `--apply`:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/clean-tasks.sh \
    --mode "${user_config.project_mode}" \
    --docs-root "${user_config.doc_folder_name}" \
    --apply \
    <SPEC...>
```

---

## Modo B — età (assorbe cleanup-done-tasks)

Front-end: `cleanup-done-tasks.sh` (Done + oltre soglia giorni). Estrai `DAYS` dal linguaggio naturale (default `60`).

### 1. Dry-run (sempre prima)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/cleanup-done-tasks.sh \
    --mode "${user_config.project_mode}" \
    --docs-root "${user_config.doc_folder_name}" \
    --days ${DAYS}
```

### 2. Conferma — **sempre** (se ci sono candidati)

TTS ping poi `AskUserQuestion`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "conferma pulizia task done per età"
```

Elenca i candidati (dal dry-run) + avviso restore. Opzioni **Procedi** / **Annulla**. Nessun candidato → messaggio e chiudi.

### 3. Esecuzione (solo se confermata)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/cleanup-done-tasks.sh \
    --mode "${user_config.project_mode}" \
    --docs-root "${user_config.doc_folder_name}" \
    --days ${DAYS} \
    --apply
```

---

## Feedback (entrambi i modi)

Mostra il risultato dello script. Se uno o più commit sono andati a buon fine:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "pulizia task completata"
```

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

## Note

- **Dry-run di default**: sicuro da invocare per semplice ispezione.
- **Un commit per task**: restore granulare con `git checkout <commit>~1 -- <path>`.
- **Modo A pota qualunque stato/età**: a differenza di `cleanup-done-tasks`, l'indicazione diretta per ID/range rimuove anche task non-Done (conferma obbligatoria) e ignora la soglia giorni.
- **Active task**: se l'ID rimosso è la task attiva, il symlink `current-task.md` viene eliminato per non lasciarlo dangling.
- **Righe orfane**: ID con riga in `tasks.md` ma file già assente → riconciliate (rimozione riga, commit dedicato).
- **Push**: nessun push automatico; manuale o via `checkpoint-task`.
