---
name: checkpoint-task
description: Checkpoint task progress: analyze changes, commit, update tasks.md.
allowed-tools: Bash(*), Edit, Read
model: sonnet
---

Checkpoint di progresso sulla task attiva: analizza diff dall'ultimo tracked commit, aggiorna task/tasks.md, committa e pusha.

## Note utente
~~~human
$ARGUMENTS
~~~

## Modalità

Da `$ARGUMENTS` estrai un eventuale **taskId** (pattern `T\d+` o `D\d+`).

- **Linked** (taskId assente): la task attiva è quella puntata dal symlink `${user_config.doc_folder_name}/current-task.md`. Flusso classico con analisi diff.
- **Detached** (taskId presente): la task è specificata esplicitamente. Niente symlink. **L'analisi diff viene saltata**: l'agente deriva i deliverables completati e i file da committare dal contesto della conversazione corrente. Pensata per task piccole gestite in parallelo nello stesso worktree (sessioni Claude separate). Vedi `docs/task-management.md` §Detached.

Risolvi il task file:
- Linked: `readlink -f ${user_config.doc_folder_name}/current-task.md`
- Detached: Glob `${user_config.doc_folder_name}/tasks/${taskId}-*.md`

Leggi il campo `**Folder**:` dal task file. Se popolato, mostralo in output prefixato con 📁 (solo informativo, non cambia CWD né operazioni). Il path è root-relative (`./.YY-MM-DD-slug`): la folder vive in project root, **non** sotto `${user_config.doc_folder_name}/tasks/`.

## Flusso checkpoint

1. **Analisi modifiche**

   **Linked**: esegui `${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-analyze.sh --mode "${user_config.project_mode}" --docs-root "${user_config.doc_folder_name}"`. Lo script verifica symlink, legge metadata, mostra commit/file modificati.

   **Detached**: SKIP. Nessuno script di analisi. L'agente ricava dal contesto:
   - quali deliverables della task corrente sono completati
   - quali file vanno committati (subset di `git status --porcelain`)
   - sintesi delle modifiche per il Progress Log

2. **Valutazione progresso**
   Analizza l'output dello script (linked) o il contesto della conversazione (detached):
   1. Confronta file modificati con **solo** `Deliverables Checklist`
   2. Identifica items completati
   3. Calcola nuovo progresso %
   4. Chiedi conferma all'utente se necessario

   **IMPORTANTE**: Ignora la sezione `## Prod Validation` — item non checkati in quella sezione NON bloccano il completamento della task.

3. **Doc Impact gate (morbido)**

   Leggi la sezione `## Doc Impact` del task file. Se **vuota** o assente → skip step.

   Se contiene voci non ancora consolidate (vedi marker sotto), per **ogni voce** chiedi all'utente via `AskUserQuestion`:

   - `[1] capture-doc inline` → invoca skill `capture-doc` con la voce come hint, contesto = conversazione corrente. Applica subito; il file doc modificato finirà nel **commit doc separato** del checkpoint (vedi step 7, commit 2).
   - `[2] D-task` → invoca skill `doc-task` con `Parent Task: ${taskId}` e la voce come Description seed. Append in `## Acceptance Criteria` del task corrente la riga: `- [ ] D{N} chiusa` (sostituisci `D{N}` con l'ID restituito). Il gate "task non chiudibile" è gratis: la checkbox in Acceptance impedisce il done finché la D non viene chiusa (chiusura della D flagga la checkbox — vedi step 4).
   - `[3] skip` → lascia la voce non consolidata. Niente enforcement. Reentry al prossimo checkpoint.

   **Marker di consolidamento**: a fine handling, in coda alla voce processata appendi `→ ✔️ capture` oppure `→ ✔️ D{N}`. Voci con marker `→ ✔️` sono saltate ai checkpoint successivi.

   **Doc task (K=📝)**: questo step viene **saltato** — le doc task non hanno Doc Impact (la doc è l'obiettivo).

   **Detached**: il gate si applica uguale. Nessuna differenza di flusso.

4. **Aggiornamento task documentation**
   1. Aggiorna checklist con [x] items completati
   2. Aggiorna Progress % se cambiato
   3. Aggiungi sezione "## Progress Log" se non esiste
   4. Aggiungi entry nel Progress Log:
      ```markdown
      ### Avanzamento ${id_incrementale}
      - Start Commit: ${TRACKED_SHA}
      - Descrizione: ${sintesi_delle_modifiche}
      ```

5. **Task completata?**
   Se tutti gli item in `## Deliverables Checklist` **e** in `## Acceptance Criteria` sono `[x]` (la sezione `## Prod Validation` NON viene considerata):
   1. Imposta Progress a `✔️ Done` (nel file task)
   2. **Linked**: Elimina symlink: `rm ${user_config.doc_folder_name}/current-task.md`
   3. **Detached**: nessun symlink da rimuovere
   4. **Se task corrente è una doc task (K=📝)** e nel task file esiste il campo `**Parent Task**: T{N}`:
      - Risolvi task parent: `${user_config.doc_folder_name}/tasks/T{N}-*.md`
      - Flagga la riga `- [ ] D{taskId} chiusa` → `- [x] D{taskId} chiusa` nella sezione `## Acceptance Criteria` del parent
      - Se la riga non esiste, log warning ma non bloccare (utente potrebbe averla rimossa manualmente)

6. **Aggiorna ${user_config.doc_folder_name}/tasks.md**
   1. Leggi `${user_config.doc_folder_name}/tasks.md`
   2. Nella sezione Tasks Overview (formato: `| ID | Pri | K | Prog | Task (max 100) |`), trova la riga che inizia con `| {taskId} |`
   3. Aggiorna la colonna Prog (solo emoji):
      - Se task completata (step 4): `✔️`
      - Altrimenti: `🟡` (emoji sola, niente percentuali)
   4. Se la task appare nel grafo Execution Plan (dentro il blocco ``` dopo "Legend:"):
      - Se completata: metti ✔️ davanti al task ID (es. `T199` → `✔️T199`, `🟡T199` → `✔️T199`)
      - Se in progress: metti 🟡 davanti al task ID (se non già presente)
   5. Usa Edit tool per applicare le modifiche

   Nota: le eventuali divergenze tra branch vengono riconciliate da `reconcile-tasks` in `merge-lane`.

7. **Commit e push** — **doppio commit**

   Lo script partiziona i file in due commit:
   - **Commit 1** `checkpoint(${taskId}): ${descrizione}` → codice + task tracking (task file, `tasks.md`).
   - **Commit 2** `docs(${taskId}): ${sintesi_doc}` → file doc-nozione (tutto sotto `${user_config.doc_folder_name}/` **tranne** `tasks.md` e `tasks/`, es. `reference/*.md` toccati da capture-doc inline allo step 3).

   Se non c'è nessun file doc-nozione, viene fatto solo il commit 1 (comportamento a commit singolo).

   **Linked**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh --mode "${user_config.project_mode}" --docs-root "${user_config.doc_folder_name}" --doc-message "docs(${taskId}): ${sintesi_doc}" "checkpoint(${taskId}): ${descrizione}"
   ```
   Lo script: `git add -A` → split staged → commit 1 + commit 2 → push (unico) + aggiorna Last tracked commit (HEAD finale) + mostra link compare.

   **Detached**:
   1. Stage selettivo: `git add <file1> <file2> ...` solo per i file della task corrente (identificati al punto 1)
   2. Esegui:
      ```bash
      ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh --mode "${user_config.project_mode}" --docs-root "${user_config.doc_folder_name}" --task ${taskId} --no-add --doc-message "docs(${taskId}): ${sintesi_doc}" "checkpoint(${taskId}): ${descrizione}"
      ```
   `--task` risolve il task file via Glob (no symlink), `--no-add` salta `git add -A` (lo staging l'hai fatto tu). Lo split doc/codice opera sul set che hai messo in stage.

8. **Feedback finale**
   L'output dello script contiene tutte le info necessarie.
   Aggiungi eventuali note per l'utente.
   Esegui il ping TTS:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "checkpoint $(say_id ${taskId}) ok"
   ```
   In caso di errore nel commit/push: `say_auto "checkpoint $(say_id ${taskId}) fallito"`.

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici.

## Note

- **Due script**: analyze per raccogliere info (solo linked), commit per eseguire
- **Doppio commit**: lo script commit separa codice+tracking (`checkpoint(...)`) da doc-nozione (`docs(...)`). Partizione path-based: doc-nozione = sotto `docs-root/` ma fuori da `tasks.md` e `tasks/`. Push unico finale. Zero file doc → commit singolo.
- **Messaggi commit**: `checkpoint(taskId): descrizione breve` (commit 1) + `docs(taskId): sintesi doc` (commit 2, via `--doc-message`)
- **Link compare**: Generato automaticamente dallo script commit (spanna entrambi i commit: TRACKED_SHA…HEAD)
- **Detached**: niente analyze script, niente symlink. L'agente è la fonte di verità per "cosa è stato fatto in questa sessione". Stage selettivo obbligatorio per non contaminare con file di altre task parallele.
- **Doc Impact gate morbido**: scelta utente quando consolidare (capture inline / D-task / skip), ma se sceglie D-task la checkbox `- [ ] D{N} chiusa` in Acceptance impedisce il done finché la D non passa done — quando la D passa done, il suo checkpoint flagga indietro la checkbox usando il campo `**Parent Task**: T{N}` del D-file. Voci marcate `→ ✔️` saltano i checkpoint successivi.
