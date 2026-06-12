---
name: preflight-task
description: Interactive Q&A to freeze design decisions on a task before execution.
allowed-tools: Bash(*), Read, Edit, Glob, AskUserQuestion
model: opus
---

Fase di preparazione prima di `run-task`. Identifica ambiguità nella task, le risolve via Q&A con l'utente, scrive le risposte come decisioni congelate nel task file e **committa immediatamente** il task file. Le decisioni restano così tracciate separatamente dall'implementazione.

## Note utente
~~~human
$ARGUMENTS
~~~

## 0. Risoluzione task file

Stessa precedenza di `run-task`:

1. Se l'utente ha specificato un task ID nelle Note utente (es. `T310`), cercalo con Glob `${user_config.doc_folder_name}/tasks/${taskId}-*.md`.
2. Altrimenti leggi il symlink `${user_config.doc_folder_name}/current-task.md` (modalità linked).

Detached: taskId obbligatorio. Se manca symlink e manca taskId, chiedi quale task.

**No subagent. Glob + Read diretti.**

Stampa header compatto identico a run-task:

```
📋 ${taskId} — ${titolo}
📐 Size: ${size} | ⚡ ${priority}
📝 ${prima riga della Description, troncata a ~100 char}
📦 ${numero deliverables} deliverables
📁 Folder: ${campo Folder se popolato, altrimenti ometti riga}
🛫 Preflight
```

## 1. Analisi ambiguità

Leggi tutto il task file. Identifica punti dove l'esecuzione richiederebbe scelte non documentate:

- **Description vaga**: termini astratti senza concretizzazione operativa
- **Acceptance Criteria non misurabili**: criteri qualitativi senza metrica/check verificabile
- **Dependencies implicite**: la task riferisce moduli/librerie/task non listate
- **Scope incerto**: confine tra cosa è "in" e cosa è "out" non chiaro
- **Scelte architetturali aperte**: dove mettere il nuovo codice, quale pattern, quali tradeoff
- **Deliverables ambigui**: item che ammettono più interpretazioni
- **Edge case non considerati**: comportamento atteso su input borderline

Per ogni punto, formula una domanda **concreta e decidibile** (non aperta tipo "come faresti X?"). Le domande aperte vengono trasformate in opzioni discrete dove possibile.

## 2. Q&A con utente

Usa `AskUserQuestion` per ogni ambiguità. Prima di ogni chiamata, esegui il ping TTS:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici.

### Convenzioni domande all'utente (AskUserQuestion)

L'iterazione standard richiede context-switching effort continuo e procura affaticamento mentale. Riduci il costo:

1. **Raggruppa** le domande per vicinanza tematica, no salti tra argomenti scorrelati.
2. Fornisci **contesto strutturato** prima di `AskUserQuestion`.
3. Una chiamata `AskUserQuestion` per **singola** domanda, prompt nudo.

`AskUserQuestion` non renderizza markdown → contesto in chat prima, tool dopo.
No prosa densa: produci un **layout visivo facilitatore**: bullet points, grassetti, emoji, righe vuote, ascii tree, tabelle.

### Pattern domande

- Domanda chiusa (2-4 opzioni) → `AskUserQuestion` con options
- Domanda aperta inevitabile → singola chiamata con un'opzione "Other"

Per ogni risposta, registra **internamente**:
- domanda originale
- risposta utente (incluso testo "Other")
- razionale se l'utente lo fornisce

**Non procedere all'esecuzione**: questa skill si ferma allo step 4 (write + commit del task file). Niente implementazione.

## 3. Aggiornamento task file

Aggiungi/aggiorna la sezione `## Decisions` nel task file. Posizionamento: tra `## Deliverables Checklist` e `## Implementation Notes`. Se la sezione non esiste, creala. Se esiste, **appendi** in fondo (non sovrascrivere — preflight può essere ri-eseguito su task evolute).

Formato:

```markdown
## Decisions

### Preflight ${YYYY-MM-DD HH:mm}

- **D1** — ${domanda compatta}
  - **Scelta**: ${risposta}
  - **Razionale**: ${se presente, altrimenti omettere riga}

- **D2** — ...
```

Numerazione `D{N}` locale alla sezione, ripartendo da `D1` ad ogni esecuzione preflight (è la data che disambigua i giri).

## 4. Commit del task file

Appena scritte le decisioni, committa **subito** il solo task file (commit dedicato, separato dall'implementazione). Usa gli helper di `lib.sh` (no-op silenzioso in no-repo mode):

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
lw_git_add "${task_file}"
lw_git_commit "task(${taskId}): preflight - ${N} decisioni congelate"
lw_git_push
```

- Committa **solo** il task file, non altri file pending nel working tree.
- Messaggio: `task(${taskId}): preflight - ${N} decisioni congelate`.
- `${N}` = numero decisioni di **questo** giro preflight.
- Push subito dopo il commit, coerente con `create-task` / `doc-task` / `checkpoint-task` (tutte pushano). In no-repo mode add/commit/push degradano a no-op.

Dopo commit+push, mostra all'utente:

```
✅ Preflight completato: ${N} decisioni congelate in ${task_file}
   📌 Committate e pushate: task(${taskId}): preflight - ${N} decisioni congelate
   Pronta per /loom-works:run-task
```

## Note

- **Non esegue codice**: preflight è solo decisioni. Implementazione resta a `run-task`.
- **Idempotenza parziale**: ri-eseguire preflight su una task aggiunge un nuovo blocco datato. Lo storico delle decisioni resta intatto. Ogni giro produce il suo commit dedicato.
- **Task piccole**: se l'analisi (step 1) non trova ambiguità reali, comunicalo all'utente e termina senza Q&A, **senza update e senza commit**. Pattern: `🛫 Nessuna ambiguità rilevata. Task pronta per run-task.`
- **Commit + push automatici**: lo step 4 committa **solo** il task file (commit dedicato) e pusha, come le altre skill task-level. Decisioni tracciate separatamente dall'implementazione. In no-repo mode gli helper degradano a no-op.
