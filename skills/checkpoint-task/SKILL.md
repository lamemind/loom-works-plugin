---
name: checkpoint-task
description: Checkpoint task progress: analyze changes, commit, update tasks.md.
allowed-tools: Bash(*), Edit, Read, Write
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `{docs_root}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

Checkpoint di progresso sulla task attiva: analizza il diff dall'ultimo avanzamento consolidato, aggiorna il task file e `{docs_root}/tasks.md`, committa e pusha.

## Note utente
~~~human
$ARGUMENTS
~~~

## Modalità

Da `$ARGUMENTS` estrai un eventuale **taskId** (pattern `T\d+` o `D\d+`), poi risolvi:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId}
```

Il `TASK_SRC` che lo script stampa **determina la modalità** — non la presenza dell'argomento:

- `symlink` → **linked**. Binding di *worktree*: la task è una sola, tutto il movimento del repo le appartiene → analisi diff + `git add -A`.
- `env` (`$LOOM_TASK`) → **detached**. Binding di *sessione*: N sessioni parallele nello stesso worktree, una task ciascuna. Un `git add -A` da qui rastrellerebbe nel commit i file su cui stanno lavorando le altre, in silenzio.
- `arg` → **detached**. Chi nomina una task esplicita non sta dichiarando di essere solo nel worktree.

Detached = analisi diff saltata (i deliverables li deriva l'agente dal contesto della conversazione) + stage selettivo. Vedi `${CLAUDE_PLUGIN_ROOT}/docs/task-management.md` §Detached.

Da qui in avanti `${taskId}` = il `TASK_ID` **risolto** dallo script, non l'argomento grezzo.

`Read` di `TASK_FILE`, poi leggi il campo `**Folder**:` dal task file. Se popolato, mostralo in output prefixato con 📁 (solo informativo, non cambia CWD né operazioni). Il path è root-relative (`./.YY-MM-DD-slug`): la folder vive in project root, **non** sotto `{docs_root}/tasks/`.

## Flusso checkpoint

1. **Analisi modifiche**

   **Linked**: esegui `${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-analyze.sh` — **senza** `--task`: lo script risolve dal symlink da sé, e passargli un id lo farebbe cadere nel ramo detached (un id esplicito *è* un binding di sessione). Legge metadata, mostra commit/file modificati.

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
      - Descrizione: ${sintesi_delle_modifiche}
      ```
      L'header `### Avanzamento N` non è cosmetico: è l'**ancora del baseline**. Il prossimo checkpoint deriva la finestra di diff dal commit che ha introdotto l'ultimo header di questa forma (`lw_task_baseline_sha`), quindi riscriverlo in altro formato allarga la finestra fino alla nascita della task.

4. **Task completata?**
   Se tutti gli item in `## Deliverables Checklist` **e** in `## Acceptance Criteria` sono `[x]` (la sezione `## Prod Validation` NON viene considerata):
   1. Imposta Progress a `✔️ Done` (nel file task)
   2. Se il symlink `{docs_root}/current-task.md` risolve a **questo** task file, eliminalo (`rm`) — in linked come in detached. Un puntatore di worktree a una task chiusa è il residuo stale che manda fuori strada la sessione dopo. Se punta altrove, o non esiste, **non toccarlo**: è il binding di un'altra task.
   3. **Se task corrente è una doc task (K=📝)** e nel task file esiste il campo `**Parent Task**: T{N}`:
      - Risolvi task parent: `{docs_root}/tasks/T{N}-*.md`
      - Flagga la riga della checkbox in `## Acceptance Criteria` del parent: `[ ]` → `[x]`. **Matcha sull'id, non sulla frase intera** — `doc-task` la scrive con la maniglia (`- [ ] D07 (unificare docs-root) chiusa`), quindi cercare `- [ ] D{taskId} chiusa` alla lettera non trova mai nulla e il flag-back muore nel ramo warning qui sotto. Riscrivi solo il box, lasciando maniglia e testo intatti.
      - Se nessuna riga porta l'id, log warning ma non bloccare (utente potrebbe averla rimossa manualmente)

5. **Aggiorna {docs_root}/tasks.md**
   1. Leggi `{docs_root}/tasks.md`
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
   - **Commit 2** `docs(${taskId}): …` → file doc-nozione (sotto `{docs_root}/` **tranne** `tasks.md` e `tasks/`). In questa fase ne esistono solo se la doc era già stata toccata **prima** del checkpoint: passa `--doc-message` che li descrive, oppure ometti il flag se l'analisi (step 1) non ne ha mostrati.

   **Linked**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh "checkpoint(${taskId}): ${descrizione}"
   ```
   Lo script: `git add -A` → split staged → commit(s) → push. Non tocca il task file dopo il commit: il working tree resta pulito.

   **Detached**:
   1. Stage selettivo: `git add <file1> <file2> ...` solo per i file **codice** della task corrente (identificati al punto 1).
   2. Esegui:
      ```bash
      ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh --task ${taskId} --no-add "checkpoint(${taskId}): ${descrizione}"
      ```
   `--task` fissa il task file all'ID risolto, `--no-add` salta `git add -A` (lo staging l'hai fatto tu). Lo split doc/codice opera sul set che hai messo in stage. Con `TASK_SRC=env` lo script forza comunque `--no-add` da sé: la contaminazione fra sessioni parallele è silenziosa e si scopre a push fatto, quindi il default sicuro non è delegato al chiamante.

7. **Fase doc — le voci `## Doc Impact` in inbox**

   Leggi la sezione `## Doc Impact` del task file. Se **vuota**, assente, o con tutte le voci già marcate → skip questo step e lo step 8.

   **Doc task (K=📝)**: step **saltato**. La doc è il loro obiettivo, non un side-effect.

   Nessuna domanda all'utente, nessuno spawn di subagent: la nozione la scrive questa sessione, che ha già il contesto della task in memoria. Un subagent dovrebbe ricostruirlo, ed è il costo che questa fase esiste per togliere.

   **7.1 — Filtra coi soli criteri indipendenti.** Sono quelli che si rispondono guardando la frase, senza aprire niente, e li hai già in contesto (`doc-management.md` §Imbuto): *sopravvive alla task* · *costo di scoperta* · le **sei parole** riconoscibili dal testo — cronaca, intenzione, ipotesi, cantiere, scarto, cornice.

   **Non giudicare il resto.** *Eco*, *inventario*, *calco*, *sorpresa* e «è già scritto altrove» dipendono dal codice, da una fonte viva o dal resto della doc, e aprirli qui rimette il pavimento di lettura. Una voce ridondante entra in inbox e muore allo smaltimento: è l'esito previsto, non una svista da anticipare.

   **7.2 — Riscrivi, non copiare.** Una voce mista si **pota**: la cronaca cade, il nucleo entra. Nel task file non tocchi il testo — l'unica scrittura lì è il marker.

   **7.3 — Marca ogni voce lavorata**, in coda alla voce nel task file:
   - entra → `→ ✔️ inbox`
   - non entra → `→ ✖️ <parola>`, una delle sei (es. `→ ✖️ cronaca`)

   Il marker impedisce al checkpoint successivo di riscansionare ciò che hai già deciso. Una voce senza marker è per costruzione «non ancora lavorata», ed è così che `align-doc` la ripesca sul perimetro task.

   **7.4 — Scrivi il file inbox.**

   ```bash
   mkdir -p "{docs_root}/inbox"
   ```
   `init.sh` la crea, ma un progetto registrato prima che esistesse non ce l'ha.

   Path: `{docs_root}/inbox/${taskId}-<slug>-<N>.md` — `<slug>` è quello del task file, `<N>` il numero dell'avanzamento che hai scritto allo step 3.

   **Un file per checkpoint, immutabile una volta scritto.** Mai appendere a un file inbox esistente: `drain-doc` lo elabora e poi lo rimuove, quindi un append arrivato nel frattempo sparirebbe senza essere mai stato letto.

   Forma: `# Titolo`, poi **esattamente sulla riga 3** `> **TLDR**: <perimetro>`, poi una voce per nozione. Fuori dalla riga 3 il file resta fuori dall'INDEX, e un file inbox non indicizzato non serve a nessuno. La formula del TLDR inbox è **perimetro**, non ancora, e sta in `${CLAUDE_PLUGIN_ROOT}/docs/tldr-formats.md`: leggilo prima di scrivere.

   Zero voci sopravvissute al filtro → **nessun file**. Restano i marker `→ ✖️`, che vanno comunque committati (step 8).

   **7.4b — Propaga la sentinella di drift, non dedurla.** Se almeno una delle voci entrate porta una riga `🚨 drift: <path...>` — scritta a monte da `create-task`, `preflight-task` o `run-task`, che erano nella stanza quando il drift è nato — scrivi sul file inbox, **esattamente sulla riga 4**:

   ```markdown
   > **PRIORITY**: 🚨 · drift: <l'unione dei path di tutte le voci entrate>
   ```

   Nessuna sentinella fra le voci entrate → **nessuna riga 4**, e la riga assente vale priorità normale. Non inventarne una: qui la decisione che ha generato il drift è già stata presa e il contesto che la riconosceva si è chiuso con la sessione. Dedurla significherebbe aprire `reference/` per giudicare, cioè rimettere dentro il costo che questa fase esiste per togliere — nessuno spawn di subagent, nessun criterio dipendente.

   Due conseguenze del «propaga, non deduce»:
   - **Una sentinella su una voce scartata non propaga niente.** Se la voce esce `→ ✖️ cronaca`, non entra nel file e la sirena muore con lei: la priorità ordina l'inbox, non forza l'ingresso.
   - **La riga `🚨 drift:` resta nel task file** insieme al resto della voce, come record datato. Non è un secondo stato da tenere allineato: dopo il marker `→ ✔️ inbox` nessuno la rilegge più, e l'unico posto su cui `drain-doc` ordina è la riga 4 del file inbox.

   Posizione fissa, non un grep sul corpo: `doc-metrics.sh --inbox` la legge con lo stesso `sed -n` del TLDR. E stando fuori dalla riga 3 non entra nell'INDEX, che è online — costo per-sessione zero.

   **7.5 — Rigenera l'indice**, solo se il file è nato:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh"
   ```
   **Exit 2** = indice scritto, ma un TLDR è oltre il cap di 600 char: violazione **bloccante** del contratto, non un comando fallito. Se è quello che hai appena scritto, accorcialo e rilancia.

   **Detached**: nessuna differenza di flusso.

8. **Commit e push — fase doc**

   Solo se lo step 7 ha girato. Se la sezione era vuota o tutte le voci erano già marcate, salta: il push della fase codice ha già chiuso il checkpoint.

   Stagia ciò che hai scritto — il file inbox e l'`INDEX.md` rigenerato:
   ```bash
   git add -- "{docs_root}/inbox/${taskId}-<slug>-<N>.md" "{docs_root}/reference/INDEX.md"
   ```

   Poi, **identico in linked e detached**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh --task ${taskId} --no-add --doc-message "docs(${taskId}): ${sintesi_doc}" "checkpoint(${taskId}): marker Doc Impact"
   ```

   Nessun file inbox nato → salta il `git add` e **ometti `--doc-message`**: restano solo i marker `→ ✖️`, che sono task tracking e vanno nel commit `checkpoint(...)`.

   Due flag obbligatori, per due motivi distinti:
   - **`--no-add`** — il push della fase codice è già avvenuto, quindi altre sessioni possono aver ripreso a lavorare nello stesso worktree: un `git add -A` qui rastrellerebbe lavoro non tuo. Lo stage lo fai tu, riga sopra; il task file coi marker lo aggiunge lo script da sé.
   - **`--task`** — anche in linked, dove di norma basterebbe il symlink: se la task si è chiusa allo step 4 il symlink è già stato rimosso, e senza `--task` lo script non risolverebbe il task file su cui hai appena appeso i marker.

9. **Allerta inbox** — solo se lo step 7 ha scritto un file:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-metrics.sh" --inbox
   ```
   Due righe da leggere, e sono trigger indipendenti:

   - `- file inbox: N / 8` — **oltre il tetto**, chiudi il feedback con una riga sola: quanti file, da quanti giorni è in coda il più vecchio, e l'invito a invocare `/loom-works:drain-doc`.
   - `- con sentinella di drift: N` — **presente a qualunque conteggio**, anche a 1 file su 8: invita a `/loom-works:drain-doc urgenti`, che prende solo quelli. Aspettare la soglia è il difetto che la sentinella esiste per togliere — un drift è vivo dall'istante in cui il codice cambia, e ogni giro saltato è un giorno di doc bugiarda.

   **Il checkpoint allerta, non invoca.** Auto-lanciare `drain-doc` da qui rimetterebbe dentro il costo che questa fase ha tolto; a smaltire è l'umano, o il driver notturno.

   L'allerta sta **qui** perché qui la soglia si supera — il checkpoint è l'unico produttore dell'inbox. Non è un gate e non blocca niente: il tetto è un trigger, mai un cap, e una nozione non si rifiuta perché la coda è lunga.

10. **Feedback finale**
   L'output dello script contiene tutte le info necessarie.
   Aggiungi eventuali note per l'utente.
   Esegui il ping TTS:
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

- **Due script**: analyze per raccogliere info (solo linked), commit per eseguire
- **Due fasi di commit**: la fase codice (step 6) chiude e **pusha** il lavoro prima che la doc cominci; la fase doc (step 8) ne fa una seconda con `--no-add`. Dentro ogni fase lo script separa comunque codice+tracking (`checkpoint(...)`) da doc-nozione (`docs(...)`) — partizione path-based: doc-nozione = sotto `docs-root/` ma fuori da `tasks.md` e `tasks/`. Zero file doc in stage → commit singolo.
- **Perché la fase doc sta dopo il commit**: il `git add -A` finale cadeva su una working copy ancora in scrittura — working copy inutilizzabile nel frattempo, lavoro di codice non ancora al sicuro. Committare e pushare per primo il codice è il commit di transazione che sblocca le altre sessioni; la doc arriva dopo, e un fallimento lì non porta con sé il codice.
- **Messaggi commit**: `checkpoint(taskId): descrizione breve` (commit 1) + `docs(taskId): sintesi doc` (commit 2, via `--doc-message`)
- **Baseline del diff**: derivato, mai storato. `checkpoint-task-analyze.sh` (solo linked) lo prende dal commit che ha introdotto l'ultimo `### Avanzamento` del Progress Log, letto da `HEAD` — zero avanzamenti → commit di creazione del task file.
- **Detached**: niente analyze script, niente symlink. L'agente è la fonte di verità per "cosa è stato fatto in questa sessione". Stage selettivo obbligatorio per non contaminare con file di altre task parallele.
- **Niente gate sulla fase doc**: serviva a decidere *quando* pagare il costo del consolidamento, e senza quel costo non resta una decisione da prendere. Tutto ciò che passa i criteri indipendenti va in inbox, sempre; dove atterri lo decide `drain-doc`, in differita.
- **Ogni voce lavorata porta un marker**, `→ ✔️ inbox` o `→ ✖️ <parola>`: è l'unico stato che distingue «già deciso» da «non ancora guardato», e senza il secondo marker una voce scartata tornerebbe a ogni checkpoint. Il flag-back della checkbox `- [ ] D{N} (<maniglia>) chiusa` (step 4.3) è un meccanismo distinto e resta: vale per le D create a mano con `parent=`.
