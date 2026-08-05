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

Da `$ARGUMENTS` estrai un eventuale **taskId** (pattern `T\d+` o `D\d+`), poi risolvi:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId} --docs-root "${user_config.doc_folder_name}"
```

Il `TASK_SRC` che lo script stampa **determina la modalità** — non la presenza dell'argomento:

- `symlink` → **linked**. Binding di *worktree*: la task è una sola, tutto il movimento del repo le appartiene → analisi diff + `git add -A`.
- `env` (`$LOOM_TASK`) → **detached**. Binding di *sessione*: N sessioni parallele nello stesso worktree, una task ciascuna. Un `git add -A` da qui rastrellerebbe nel commit i file su cui stanno lavorando le altre, in silenzio.
- `arg` → **detached**. Chi nomina una task esplicita non sta dichiarando di essere solo nel worktree.

Detached = analisi diff saltata (i deliverables li deriva l'agente dal contesto della conversazione) + stage selettivo. Vedi `docs/task-management.md` §Detached.

Da qui in avanti `${taskId}` = il `TASK_ID` **risolto** dallo script, non l'argomento grezzo.

`Read` di `TASK_FILE`, poi leggi il campo `**Folder**:` dal task file. Se popolato, mostralo in output prefixato con 📁 (solo informativo, non cambia CWD né operazioni). Il path è root-relative (`./.YY-MM-DD-slug`): la folder vive in project root, **non** sotto `${user_config.doc_folder_name}/tasks/`.

## Flusso checkpoint

1. **Analisi modifiche**

   **Linked**: esegui `${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-analyze.sh --mode "${user_config.project_mode}" --docs-root "${user_config.doc_folder_name}"` — **senza** `--task`: lo script risolve dal symlink da sé, e passargli un id lo farebbe cadere nel ramo detached (un id esplicito *è* un binding di sessione). Legge metadata, mostra commit/file modificati.

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

3. **Aggiornamento task documentation**
   1. Aggiorna checklist con [x] items completati
   2. Aggiorna Progress % se cambiato
   3. Aggiungi sezione "## Progress Log" se non esiste
   4. Aggiungi entry nel Progress Log:
      ```markdown
      ### Avanzamento ${id_incrementale}
      - Start Commit: ${TRACKED_SHA}
      - Descrizione: ${sintesi_delle_modifiche}
      ```

4. **Task completata?**
   Se tutti gli item in `## Deliverables Checklist` **e** in `## Acceptance Criteria` sono `[x]` (la sezione `## Prod Validation` NON viene considerata):
   1. Imposta Progress a `✔️ Done` (nel file task)
   2. Se il symlink `${user_config.doc_folder_name}/current-task.md` risolve a **questo** task file, eliminalo (`rm`) — in linked come in detached. Un puntatore di worktree a una task chiusa è il residuo stale che manda fuori strada la sessione dopo. Se punta altrove, o non esiste, **non toccarlo**: è il binding di un'altra task.
   3. **Se task corrente è una doc task (K=📝)** e nel task file esiste il campo `**Parent Task**: T{N}`:
      - Risolvi task parent: `${user_config.doc_folder_name}/tasks/T{N}-*.md`
      - Flagga la riga della checkbox in `## Acceptance Criteria` del parent: `[ ]` → `[x]`. **Matcha sull'id, non sulla frase intera** — `doc-task` la scrive con la maniglia (`- [ ] D07 (unificare docs-root) chiusa`), quindi cercare `- [ ] D{taskId} chiusa` alla lettera non trova mai nulla e il flag-back muore nel ramo warning qui sotto. Riscrivi solo il box, lasciando maniglia e testo intatti.
      - Se nessuna riga porta l'id, log warning ma non bloccare (utente potrebbe averla rimossa manualmente)

5. **Aggiorna ${user_config.doc_folder_name}/tasks.md**
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

6. **Commit e push — fase codice**

   Il codice si committa **e si pusha prima** della fase doc. Il push è il punto in cui il lavoro diventa visibile alle **altre sessioni** — altre task nello stesso worktree o in worktree paralleli, che da qui possono ripartire mentre questa sessione finisce la doc. La doc si allinea dopo, con commit e push propri (step 8).

   Lo script partiziona comunque i file staged in due commit:
   - **Commit 1** `checkpoint(${taskId}): ${descrizione}` → codice + task tracking (task file, `tasks.md`).
   - **Commit 2** `docs(${taskId}): …` → file doc-nozione (sotto `${user_config.doc_folder_name}/` **tranne** `tasks.md` e `tasks/`). In questa fase ne esistono solo se la doc era già stata toccata **prima** del checkpoint: passa `--doc-message` che li descrive, oppure ometti il flag se l'analisi (step 1) non ne ha mostrati.

   **Linked**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh --mode "${user_config.project_mode}" --docs-root "${user_config.doc_folder_name}" "checkpoint(${taskId}): ${descrizione}"
   ```
   Lo script: `git add -A` → split staged → commit(s) → push + aggiorna Last tracked commit (HEAD finale) + mostra link compare.

   **Detached**:
   1. Stage selettivo: `git add <file1> <file2> ...` solo per i file **codice** della task corrente (identificati al punto 1).
   2. Esegui:
      ```bash
      ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh --mode "${user_config.project_mode}" --docs-root "${user_config.doc_folder_name}" --task ${taskId} --no-add "checkpoint(${taskId}): ${descrizione}"
      ```
   `--task` fissa il task file all'ID risolto, `--no-add` salta `git add -A` (lo staging l'hai fatto tu). Lo split doc/codice opera sul set che hai messo in stage. Con `TASK_SRC=env` lo script forza comunque `--no-add` da sé: la contaminazione fra sessioni parallele è silenziosa e si scopre a push fatto, quindi il default sicuro non è delegato al chiamante.

7. **Doc Impact gate (morbido)**

   Leggi la sezione `## Doc Impact` del task file. Se **vuota** o assente → skip step (e salta anche lo step 8).

   Se contiene voci non ancora consolidate (vedi marker sotto), per **ogni voce** chiedi all'utente via `AskUserQuestion`:

   - `[1] capture-doc inline (apply-first)` → invoca skill `capture-doc` con la voce come hint, contesto = conversazione corrente. **capture-doc applica** la patch al working tree, mostra i file toccati (marker NEW/MOD) e chiede lei stessa `ok/edit/skip`:
     - su **ok** stagia i file approvati (`git add`) → restano staged per il commit doc dello step 8. Solo qui appendi il marker `→ ✔️ capture` alla voce.
     - su **skip/edit** capture-doc restora il working tree (nessun residuo). Se l'utente scarta, la voce resta **non consolidata**: **niente marker**, reentry al prossimo checkpoint.

     Non ri-chiedere `ok/edit/skip` qui: quel gate è dentro capture-doc. Leggi il suo esito (accettata/scartata) per decidere il marker.
   - `[2] skip` → lascia la voce non consolidata. Niente enforcement. Reentry al prossimo checkpoint.

   **Non offrire un terzo ramo "apri una D-task"**: il gate non crea task. Una voce rinviata resta senza marker, e l'assenza del marker è già il segnale che `align-doc` legge come indice d'ingresso sul perimetro task — il rinvio è quindi tracciato senza che serva un ref proprio.

   **Marker di consolidamento**: a fine handling, in coda alla voce processata appendi `→ ✔️ capture`, e solo se capture-doc ha **accettato**. Voci con marker `→ ✔️` sono saltate ai checkpoint successivi. Voce scartata dentro capture-doc = nessun marker.

   **Multi-voce, ordine e restore**: processa le voci **in sequenza**, non in parallelo. Lo stage-su-ok di capture-doc è il *punto di ripristino* condiviso: se una voce successiva tocca un file già approvato da una precedente e viene scartata, il `git restore` di capture-doc torna allo stato **staged** (l'approvato), non a HEAD → l'approvazione precedente è protetta. Vale solo se le voci non si sovrappongono in parallelo.

   **Doc task (K=📝)**: questo step viene **saltato** — le doc task non hanno Doc Impact (la doc è l'obiettivo).

   **Detached**: il gate si applica uguale. Nessuna differenza di flusso.

8. **Commit e push — fase doc**

   Solo se il gate ha consolidato almeno una voce. Se erano tutte skippate, o la sezione era vuota, salta: il push della fase codice ha già chiuso il checkpoint.

   Invocazione **identica in linked e detached**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh --mode "${user_config.project_mode}" --docs-root "${user_config.doc_folder_name}" --task ${taskId} --no-add --doc-message "docs(${taskId}): ${sintesi_doc}" "checkpoint(${taskId}): marker Doc Impact"
   ```

   Due flag obbligatori, per due motivi distinti:
   - **`--no-add`** — il push della fase codice è già avvenuto, quindi altre sessioni possono aver ripreso a lavorare nello stesso worktree: un `git add -A` qui rastrellerebbe lavoro non tuo. I file doc sono già staged da capture-doc (stage = approvazione); il task file coi marker lo aggiunge lo script da sé.
   - **`--task`** — anche in linked, dove di norma basterebbe il symlink: se la task si è chiusa allo step 4 il symlink è già stato rimosso, e senza `--task` lo script non risolverebbe il task file su cui hai appena appeso i marker.

9. **Feedback finale**
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
- **Due fasi di commit**: la fase codice (step 6) chiude e **pusha** il lavoro prima che la doc cominci; la fase doc (step 8) ne fa una seconda con `--no-add`. Dentro ogni fase lo script separa comunque codice+tracking (`checkpoint(...)`) da doc-nozione (`docs(...)`) — partizione path-based: doc-nozione = sotto `docs-root/` ma fuori da `tasks.md` e `tasks/`. Zero file doc in stage → commit singolo.
- **Perché il gate doc sta dopo il commit**: prima veniva eseguito prima, e il `git add -A` finale cadeva su una working copy in cui `doc-writer` stava ancora scrivendo — checkpoint lungo quanto la fase doc, working copy inutilizzabile nel frattempo, lavoro di codice non ancora al sicuro. Committare e pushare per primo il codice è il commit di transazione che sblocca le altre sessioni; la doc arriva dopo, e un fallimento lì non porta con sé il codice.
- **Messaggi commit**: `checkpoint(taskId): descrizione breve` (commit 1) + `docs(taskId): sintesi doc` (commit 2, via `--doc-message`)
- **Link compare**: Generato automaticamente dallo script commit (spanna entrambi i commit: TRACKED_SHA…HEAD)
- **Detached**: niente analyze script, niente symlink. L'agente è la fonte di verità per "cosa è stato fatto in questa sessione". Stage selettivo obbligatorio per non contaminare con file di altre task parallele.
- **Doc Impact gate morbido**: scelta utente quando consolidare (capture inline / skip), due rami soli — il gate non apre task. Voci marcate `→ ✔️` saltano i checkpoint successivi; una voce senza marker è per costruzione «non consolidata» e resta pescabile da `align-doc` sul perimetro task. Il flag-back della checkbox `- [ ] D{N} (<maniglia>) chiusa` (step 4.3) sopravvive per le D create a mano con `parent=`, non per un ramo del gate.
- **Apply-first (opzione [1])**: capture-doc non ritorna una proposta testuale (invisibile) — **applica** la patch al working tree, la review è sul diff reale (pannello git). Stage = approvazione (marker `→ ✔️ capture`), restore = rifiuto (nessun marker). I file approvati arrivano allo step 8 **già staged**, ed è ciò che rende possibile il `--no-add`: lo stage è l'unica lista di cosa committare.
