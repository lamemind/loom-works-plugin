---
name: checkpoint-task
description: Checkpoint task progress: analyze changes, commit, update tasks.md. Fase doc v2: riesame (rilegge le nozioni vive nel task file e toglie quelle che il codice ha smentito) e trasloco in inbox al rilascio o alla chiusura.
allowed-tools: Bash(*), Edit, Read, Write, AskUserQuestion
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `{docs_root}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

Checkpoint di progresso sulla task attiva: analizza il diff dall'ultimo avanzamento consolidato, aggiorna il task file e `{docs_root}/tasks.md`, committa e pusha. **La doc segue il rilascio, non il commit**: le nozioni traslocano presto in un inbox WIP, che resta della task e si riesamina a ogni checkpoint, ma la doc lo assorbe solo quando diventa `drainable`.

**Una task, un inbox.** Il primo trasloco lo crea (6.2); da lì è l'unica sede delle nozioni della task, e il riesame (6.1) ci lavora dentro — appende, riscrive, elimina. **Ogni file inbox nasce non-drainable**: la drenabilità la accende la **chiusura della task** (6.4), ed è il momento in cui il corpo si congela. Sede e drenabilità restano quindi due decisioni distinte — la prima dice *dove* vive la nozione, la seconda *quando* la doc può assorbirla e chi ne è proprietario.

## Note utente
~~~human
$ARGUMENTS
~~~

## Modalità

Da `$ARGUMENTS` estrai un eventuale **taskId** (pattern `T\d+`), poi risolvi:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId}
```

Il `TASK_SRC` che lo script stampa **determina la modalità** — non la presenza dell'argomento:

- `symlink` → **linked**. Binding di *worktree*: la task è una sola, tutto il movimento del repo le appartiene → analisi diff + `git add -A`.
- `env` (`$LOOM_TASK`) → **detached**. Binding di *sessione*: N sessioni parallele nello stesso worktree, una task ciascuna. Un `git add -A` da qui rastrellerebbe nel commit i file su cui stanno lavorando le altre → la lista dei file la passi tu come pathspec.
- `arg` → **detached**. Chi nomina una task esplicita non sta dichiarando di essere solo nel worktree.

Detached = analisi diff saltata (i deliverables li deriva l'agente dal contesto della conversazione) + stage selettivo. Vedi `${CLAUDE_PLUGIN_ROOT}/docs/task-management.md` §Detached.

Da qui in avanti `${taskId}` = il `TASK_ID` **risolto** dallo script, non l'argomento grezzo.

`Read` di `TASK_FILE`, poi leggi due campi dalla mappa proprietà:

- `**Folder**:` — se popolato, mostralo in output prefixato con 📁 (solo informativo).
- `**Branch**:` — il branch su cui la task sviluppa; **assente o vuoto = `main`**. Governa i marker del trasloco (step 6).

## Flusso checkpoint

1. **Analisi modifiche**

   **Linked**: esegui `${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-analyze.sh` — **senza** `--task`: lo script risolve dal symlink da sé, e passargli un id lo farebbe cadere nel ramo detached. Legge metadata, mostra commit/file modificati.

   **Detached**: SKIP. Nessuno script di analisi. L'agente ricava dal contesto:
   - quali deliverables della task corrente sono completati
   - quali file vanno committati (subset di `git status --porcelain`)
   - sintesi delle modifiche per il Progress Log

2. **Valutazione progresso**
   1. Confronta file modificati con **solo** `Deliverables Checklist`
   2. Identifica items completati
   3. Calcola nuovo progresso %
   4. Chiedi conferma all'utente se necessario

   **IMPORTANTE**: Ignora la sezione `## Prod Validation` — item non checkati lì NON bloccano il completamento.

3. **Aggiornamento task documentation**
   1. Aggiorna checklist con [x] items completati
   2. Aggiorna Progress % se cambiato
   3. Aggiungi sezione "## Progress Log" se non esiste
   4. Aggiungi entry nel Progress Log:
      ```markdown
      ### Avanzamento ${id_incrementale}
      - Descrizione: ${sintesi_delle_modifiche}
      ```
      L'header `### Avanzamento N` non è cosmetico: è l'**ancora del baseline**. Il prossimo checkpoint deriva la finestra di diff dal commit che ha introdotto l'ultimo header di questa forma (`lw_task_baseline_sha`), quindi riscriverlo in altro formato allarga la finestra fino alla nascita della task.

4. **Task completata?**
   Se tutti gli item in `## Deliverables Checklist` **e** in `## Acceptance Criteria` sono `[x]` (la sezione `## Prod Validation` NON conta):
   1. Imposta Progress a `✔️ Done` (nel file task)
   2. Se il symlink `{docs_root}/current-task.md` risolve a **questo** task file, eliminalo (`rm`) — in linked come in detached. Se punta altrove, o non esiste, **non toccarlo**: è il binding di un'altra task.
   3. **Se nel task file esiste il campo `**Parent Task**: T{N}`**:
      - Risolvi task parent: `{docs_root}/tasks/T{N}-*.md`
      - Flagga la riga della checkbox in `## Acceptance Criteria` del parent: `[ ]` → `[x]`. **Matcha sull'id, non sulla frase intera**. Riscrivi solo il box, lasciando maniglia e testo intatti.
      - Se nessuna riga porta l'id, log warning ma non bloccare.

5. **Commit e push — fase codice**

   Il codice si committa **e si pusha prima** della fase doc: il push è il punto in cui il lavoro diventa visibile alle altre sessioni. **Il task file entra QUI, con le nozioni correnti in `## Doc Impact`** — è il commit su cui il trasloco (step 6) potrà puntare come storia.

   **`tasks.md` non è ancora stato toccato** e non entra in questo commit: la sua Prog si scrive allo step 7.

   **Linked**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh "checkpoint(${taskId}): ${descrizione}"
   ```
   Lo script: `git add -A` → split doc/codice sulla lista staged → commit(s) con pathspec → push.

   **Detached** — passa la lista dei file **codice** della task come pathspec dopo `--`, nessuno stage a mano:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh --task ${taskId} "checkpoint(${taskId}): ${descrizione}" -- <file1> <file2> ...
   ```
   `--task` fissa il task file all'ID risolto; lo script lo aggiunge da sé alla pathspec. Con `TASK_SRC=env` e nessuna pathspec lo script esce in errore.

6. **Fase doc — riesame e trasloco**

   Nessuno spawn di subagent. L'unica domanda ammessa all'utente è quella del punto 6.4 (drainable a chiusura incerta): il flusso è presidiato per natura.

   **La sede delle nozioni è una sola in ogni momento, e la dichiara il task file.** `## Doc Impact` porta le voci finché l'inbox della task non esiste; dal primo trasloco in poi porta la sola riga `- → inbox <basename> · storia: <sha>`, e la sede è quel file. **Leggila prima di tutto il resto**: decide su cosa gira il riesame e se il trasloco deve girare affatto.

   **6.1 — Riesame: rigiudica, non smaltire.** Leggi ogni voce di `## Doc Impact`. La voce è **viva**: riscrivila se il codice di questo checkpoint l'ha cambiata, eliminala se l'ha resa falsa o inutile. Applichi i **soli criteri indipendenti** — *sopravvive alla task* · *costo di scoperta* · le nove parole leggibili nel testo (cronaca, intenzione, ipotesi, cantiere, scarto, eco, inventario, calco, cornice: le prime cinque si giudicano qui, le altre dipendono da fonti e le paga il drain). **Nessun marker di esito, nessun inbox automatico**: il default è che le voci restano qui.

   **6.2 — Il trasloco: una volta sola per task.** Scatta al **primo** checkpoint che trova voci in `## Doc Impact`, e crea l'inbox della task. Non è condizionato al rilascio né alla chiusura: quelle governano `drainable` (6.4), non *dove* vive la nozione. Se il puntatore c'è già, il trasloco non gira — le nozioni sono già nella loro sede.

   Ordine vincolante:

   1. **Commit del task file CON le voci**, se ha modifiche non committate (il riesame 6.1 lo sporca): 
      ```bash
      source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
      lw_git_add_n_commit "task(${taskId}): riesame nozioni pre-trasloco" "${task_file}"
      ```
      Poi lo sha di storia: `sha=$(git log -1 --format=%h -- "${task_file}")`.
   2. **Risolvi il cappello**: leggi `**Parent Task**: T{N}` dal task file. Il cappello è `T{N}` se il campo c'è, `{docs_root}/tasks/T{N}-*.md` esiste, e la sua Prog in `tasks.md` **non** è `✔️`. Altrimenti è la task corrente — dichiaralo in output con quale ramo è scattato.
   3. **Crea il file inbox**:
      ```bash
      printf '%s\n' "<voce 1 per esteso>" "<voce 2 per esteso>" | \
        "${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" new --docs-root "{docs_root}" \
          --cappello <cappello> --slug <tema-della-task> --natura nozioni \
          --titolo "<cappello> — <tema>" --tldr "<perimetro, formula inbox di tldr-formats.md>" \
          --indexed [--branch <nome>]
      ```
      Una voce = una riga su stdin, **per esteso** (il fatto, il perché, le condizioni; l'ancora in coda alla voce). Lo script assegna gli id `n1..nN`, valida i marker e stampa `INBOX_PATH=`. Exit 1 = input malformato: correggi, non aggirare.

      Lo slug descrive **la task**, non il tema di queste voci: il file le assorbirà tutte fino alla chiusura. Stessa ragione per il TLDR — perimetro della task, scritto qui una volta e **mai più riscritto** (`docs/inbox-format.md` §Struttura). `--branch <nome>` se la task dichiara `**Branch**:`: lo sblocco è di `pull-repos`, al merge, ed è un gate suo indipendente dalla drenabilità.
   4. **Nel task file, al posto delle voci traslocate**, due righe:
      ```markdown
      - → inbox <basename del file creato> · storia: <sha>
      - Le nozioni nuove di questa task si scrivono **nell'inbox**, non qui.
      ```
   5. Rigenera l'indice — `"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "{docs_root}"`. Exit 2 = indice scritto ma un TLDR sfora il cap: se è il tuo, accorcialo e rilancia.

   **6.3 — Riconciliazione.** Se il puntatore esiste **e** `## Doc Impact` porta comunque delle voci, qualcuno ha scritto nella sede sbagliata (una skill non allineata, il modello in chat prima di leggere il puntatore). Spostale nell'inbox con `Edit`, con id `max+1`, e togli le righe dal task file. Non è un secondo trasloco: nessun file nuovo, nessuna riga puntatore in più.

   **6.4 — Accensione della drenabilità.** Gira **solo se la task si è chiusa** allo step 4, e **dopo** il 6.2: il trasloco ha appena scritto la propria riga puntatore, e questo giro la deve vedere.

   La lista degli inbox della task è già nel task file: il trasloco ha lasciato in `## Doc Impact` la riga `- → inbox <basename>.md · storia: <sha>`. Normalmente è una sola — una task ha un inbox — ma una task riaperta dopo un drain ne ha una seconda, e il giro le prende tutte. È la fonte esatta, e risolve da sé il caso della figlia di un'epica: il file si chiama col cappello (`T74-…`), ma la riga sta nel task file della task che ha traslocato.

   ```bash
   grep -oP '^- → inbox \K\S+\.md' "${task_file}"
   ```

   Per ogni basename, se il file esiste ancora in `{docs_root}/inbox/`:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" marker --file "{docs_root}/inbox/<basename>" --set drainable
   ```

   - **File assente = già drenato**, mai un errore: `drain-notions` cancella il file a fine ciclo, ma la riga puntatore resta nel task file per sempre (è l'indirizzo storico). Una task riaperta e ri-chiusa ripassa sugli stessi basename e ne trova una parte sparita.
   - **File con `branch:` → salta**, non accendere. I due token sono gate distinti e cumulativi: `pull-repos` accende `drainable` al merge quando il branch è la sola cosa che manca, ma un file che porta ancora `branch:` non è in esercizio comunque. Leggi il marker con `inbox.sh parse` prima di decidere.
   - **Materializzazione incerta** — non sai se la feature è davvero in esercizio: `AskUserQuestion` all'utente, drainable sì/no. `No` salta l'intero giro, inbox vecchi compresi: la task è chiusa ma la doc non deve ancora assorbirla.
   - Un `marker` su un file già drainable è un no-op scritto: nessun danno, la riga 3 si riscrive identica.

7. **Aggiorna {docs_root}/tasks.md**
   1. Nella tabella Tasks Overview trova la riga `| {taskId} |`
   2. Aggiorna la colonna Prog: `✔️` se completata (step 4), altrimenti `🟡`
   3. Se la task appare nel grafo Execution Plan, allinea l'emoji davanti all'ID
   4. L'ordine fra questo step e la fase doc è **libero**: la Prog in `tasks.md` non è un cancello per niente — a governare le code è il marker dentro il file inbox, che il 6.4 accende alla chiusura.

8. **Commit e push — fase tracking e doc**

   **Gira sempre**, anche se lo step 6 non ha traslocato niente: `tasks.md` è stato toccato allo step 7. Unica eccezione, working tree già pulito sul perimetro tracking+doc:

   ```bash
   git status --porcelain -- "{docs_root}/tasks.md" "{docs_root}/tasks/" "{docs_root}/inbox/" "{docs_root}/reference/INDEX.md"
   ```

   Output vuoto → salta lo step. Altrimenti pathspec esplicita, identica in linked e detached:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh --task ${taskId} --doc-message "docs(${taskId}): trasloco in inbox" "checkpoint(${taskId}): Prog + riesame" -- "{docs_root}/tasks.md" "{docs_root}/inbox/<ogni file inbox toccato>.md" "{docs_root}/reference/INDEX.md"
   ```

   La pathspec nomina **ogni file inbox toccato**, non solo quello appena creato: il riesame (6.1) riscrive il corpo di un inbox nato in un checkpoint precedente e il 6.4 ne riscrive la riga marker, e un file modificato ma fuori pathspec resta dirty nel worktree — dove la guardia d'ingresso di `drain-notions` lo trova e ferma il drain.

   Nessun file sotto `inbox/` toccato → pathspec col solo `tasks.md` e **ometti `--doc-message`**.

   - **la pathspec dopo `--`** è obbligatoria: il push della fase codice è già avvenuto e altre sessioni possono aver ripreso a lavorare — un `git add -A` qui rastrellerebbe lavoro non tuo.
   - **`--task`** è obbligatorio anche in linked: se la task si è chiusa allo step 4 il symlink non c'è più.

9. **Feedback finale**
   Riporta: avanzamento registrato, su quale sede è girato il riesame e cosa ha riscritto o eliminato, se il trasloco ha creato l'inbox e con quali marker, e — se la task si è chiusa — quali inbox sono diventati drainable e quali sono stati saltati (già drenati, o congelati da `branch:`). Poi il ping TTS:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "checkpoint $(say_id ${taskId}) done"
   ```
   In caso di errore nel commit/push: `say_auto "checkpoint $(say_id ${taskId}) failed"`.

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici.

## Note

- **Due script**: analyze per raccogliere info (solo linked), commit per eseguire.
- **Due fasi di commit**: la fase codice (step 5) chiude e pusha il lavoro prima che la doc cominci; la seconda (step 8) porta `tasks.md` e l'eventuale trasloco con pathspec esplicita. Un fallimento della fase doc non porta con sé il codice.
- **Riesame ≠ archivio**: il riesame (6.1) è il lavoro della fase doc anche quando nessun trasloco scatta. Un checkpoint che non riscrive mai niente sta saltando la fase, non risparmiandola.
- **Il file inbox è WIP finché la task è aperta**: l'owner è la task, e il corpo si appende, si riscrive e si pota a ogni checkpoint — le tre operazioni e la regola degli id stanno in `${CLAUDE_PLUGIN_ROOT}/docs/inbox-format.md`. Il congelamento arriva con `drainable` (6.4), quando la proprietà passa al sistema documentale: da lì le uniche scritture ammesse sono la riga marker (lo sblocco di `pull-repos`) e il registro del drain.
- **Baseline del diff**: derivato, mai storato — dal commit che ha introdotto l'ultimo `### Avanzamento` del Progress Log, letto da `HEAD`.
- **Detached**: niente analyze script, niente symlink. Stage selettivo obbligatorio.
- **Nessuna allerta di coda**: l'accumulo in inbox è libero — nessun cap, nessun tetto. A drenare sono `drain-notions` / il giro notturno, non un invito a fine checkpoint.
