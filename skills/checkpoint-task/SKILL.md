---
name: checkpoint-task
description: Checkpoint task progress: analyze changes, commit, update tasks.md. Fase doc v2: riesame (rilegge le nozioni vive nella loro sede e toglie quelle che il codice ha smentito), trasloco nell'inbox della task e accensione di drainable alla chiusura. Su un'epica o una lista custom passa a checkpoint-perimeter.
allowed-tools: Bash(*), Edit, Read, Write, AskUserQuestion, Skill
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `{docs_root}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

Checkpoint di progresso sulla task attiva: analizza il diff dall'ultimo avanzamento consolidato, aggiorna il task file e `{docs_root}/tasks.md`, committa e pusha. **La doc segue il rilascio, non il commit**: le nozioni traslocano presto in un inbox WIP, che resta della task e si riesamina a ogni checkpoint, e la chiusura lo congela con `drainable`: da lì descrive un rilascio, e l'indice gli dà precedenza su `reference/`.

**Una task, un inbox.** Il primo trasloco lo crea (6.2); da lì è l'unica sede delle nozioni della task, e il riesame (6.1) ci lavora dentro — appende, riscrive, elimina. **Ogni file inbox nasce non-drainable**: la drenabilità la accende la **chiusura della task** (6.4), ed è il momento in cui il corpo si congela. Sede e drenabilità restano quindi due decisioni distinte — la prima dice *dove* vive la nozione, la seconda *da quando* il file descrive un rilascio chiuso.

## Note utente
~~~human
$ARGUMENTS
~~~

## Modalità

Da `$ARGUMENTS` estrai un eventuale **taskId** (pattern `T\d+`), poi risolvi:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId}
```

Il checkpoint è sempre **detached**: la task la lega la sessione (`$LOOM_TASK`) o l'argomento, mai il worktree, che ospita N sessioni parallele, una task ciascuna. Ne discendono due regole. Nessuna analisi del diff: il diff del worktree raccoglierebbe anche il lavoro delle altre sessioni, quindi i deliverables completati li ricavi dal contesto della conversazione. Nessun `git add -A`: rastrellerebbe nel commit i file su cui stanno lavorando le altre, quindi la lista dei file la passi tu come pathspec. Vedi `${CLAUDE_PLUGIN_ROOT}/docs/task-management.md` §Detached.

Da qui in avanti `${taskId}` = il `TASK_ID` **risolto** dallo script, non l'argomento grezzo.

`Read` di `TASK_FILE`, poi leggi due campi dalla mappa proprietà:

- `**Folder**:` — se popolato, mostralo in output prefixato con 📁 (solo informativo).
- `**Branch**:` — il branch su cui la task sviluppa; **assente o vuoto = `main`**. Governa i marker del trasloco (step 6).

## Epica e lista custom — passa a `checkpoint-perimeter`

Prima di ogni step del flusso, leggi `Size` dall'header di `TASK_FILE`. Su `Size: Epic`, `Size: Custom` o `Size: Mandate` (il nome di prima) la task è un **perimetro orchestrabile**: non ha codice né DLV propri, e il lavoro sta nei membri. Il checkpoint di un perimetro orchestrabile è un altro flusso — riallinea la sua prosa a ciò che i membri hanno scritto, senza analisi del diff, senza DLV e senza fase doc — e lo fa `checkpoint-perimeter`.

Stampa una riga sola, `→ checkpoint-perimeter ${taskId}`, poi invoca il tool `Skill` con `skill` = `loom-works:checkpoint-perimeter` e `args` = le Note utente **verbatim**: la parola «chiudi», se c'è, decide la chiusura del perimetro orchestrabile, e un riassunto la perderebbe. Senza un id nelle Note utente passa `${taskId}` davanti, perché la sotto-skill risolva lo stesso perimetro orchestrabile. Poi fermati: nessuno degli step sotto gira, nessun commit, nessun ping TTS — il report, il commit e le Segnalazioni li fa la sotto-skill.

Vale anche su un'epica con DLV propri ancora aperti: `run-task` rifiuta sempre un perimetro orchestrabile, quindi un'epica non produce mai codice da committare qui.

## Flusso checkpoint

1. **Analisi modifiche**

   Nessuno script di analisi. Ricava dal contesto della conversazione:
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
   1. Spunta ogni DLV completato con `${CLAUDE_PLUGIN_ROOT}/scripts/task/task-deliverables.sh ${taskId} --check <n>`, non a mano: la numerazione è posizionale, la stessa di `run-task`, e il numero serve all'evento `deliverableDone` (step 5). `task-deliverables.sh ${taskId}` elenca ogni DLV col suo numero. Annota i DLV che spunti in questo giro: uno già `[x]` l'ha chiuso `run-task`, che ha già sollevato l'evento.
   2. Aggiorna Progress % se cambiato
   3. Aggiungi sezione "## Progress Log" se non esiste
   4. Aggiungi entry nel Progress Log:
      ```markdown
      ### Avanzamento ${id_incrementale}
      - Descrizione: ${sintesi_delle_modifiche}
      ```
      Scrivi l'header `### Avanzamento N` in questa forma, la stessa di tutta la famiglia: su un perimetro orchestrabile (epica o lista custom) `checkpoint-perimeter` deriva la finestra di diff dal commit che ha introdotto l'ultimo header di questa forma (`lw_task_baseline_sha`), e un header in altro formato allarga la finestra fino alla nascita del file.

4. **Task completata?**
   Se tutti gli item in `## Deliverables Checklist` **e** in `## Acceptance Criteria` sono `[x]` (la sezione `## Prod Validation` NON conta):
   1. Imposta Progress a `✔️ Done` (nel file task)
   2. **Se nel task file esiste il campo `**Parent Task**: T{N}`**:
      - Risolvi task parent: `{docs_root}/tasks/T{N}-*.md`
      - Flagga la riga della checkbox in `## Acceptance Criteria` del parent: `[ ]` → `[x]`. **Matcha sull'id, non sulla frase intera**. Riscrivi solo il box, lasciando maniglia e testo intatti.
      - Se nessuna riga porta l'id, log warning ma non bloccare.

5. **Commit e push — fase codice**

   Il codice si committa **e si pusha prima** della fase doc: il push è il punto in cui il lavoro diventa visibile alle altre sessioni. **Il task file entra QUI, con le nozioni correnti in `## Doc Impact`** — è il commit su cui il trasloco (step 6) potrà puntare come storia.

   **`tasks.md` non è ancora stato toccato** e non entra in questo commit: la sua Prog si scrive allo step 7.

   Passa la lista dei file **codice** della task come pathspec dopo `--`, nessuno stage a mano:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh --task ${taskId} "checkpoint(${taskId}): ${descrizione}" -- <file1> <file2> ...
   ```
   `--task` fissa il task file all'ID risolto; lo script lo aggiunge da sé alla pathspec. Senza pathspec lo script esce in errore e non committa niente.

   **Hook `deliverableDone`** — dopo il push riuscito, per ogni DLV spuntato allo step 3.1 di questo giro, in ordine di numero:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/config/project-config.sh" hooks deliverableDone --task ${taskId} --dlv <n> --sha <sha>
   ```

   `<sha>` è quello che lo script di commit stampa in `-> commit 1 (codice+tracking, …): <sha>`, cioè il commit che porta le spunte. Le skill si invocano come dice §Hook di progetto. Nessuna invocazione se in questo giro non hai spuntato DLV, o se il push è fallito (nessuna riga `-> commit`): la skill hook riceverebbe un commit che le altre sessioni non vedono.

6. **Fase doc — riesame e trasloco**

   Nessuno spawn di subagent. L'unica domanda ammessa all'utente è quella del punto 6.4 (drainable a chiusura incerta): il flusso è presidiato per natura.

   **La sede delle nozioni è una sola in ogni momento, e la dichiara il task file.** `## Doc Impact` porta le voci finché l'inbox della task non esiste; dal primo trasloco in poi porta la sola riga `- → inbox <basename> · storia: <sha>`, e la sede è quel file. **Leggila prima di tutto il resto**: decide su cosa gira il riesame e se il trasloco deve girare affatto.

   **6.1 — Riesame: rigiudica, non collocare.** Leggi ogni voce **nella sede corrente** — `## Doc Impact` finché l'inbox non esiste, il file inbox da lì in avanti. La voce è **viva**: riscrivila se il codice di questo checkpoint l'ha cambiata, eliminala se l'ha resa falsa o inutile. Applichi i **soli criteri indipendenti** — *sopravvive alla task* · *costo di scoperta* · le nove parole leggibili nel testo (cronaca, intenzione, ipotesi, cantiere, scarto, eco, inventario, calco, cornice: le prime cinque si giudicano qui, le altre dipendono da fonti e non le applica nessuno). **Nessun marker di esito**: una voce eliminata sparisce, non viene marcata.

   Sull'inbox le operazioni sono tre e hanno una regola sola non ovvia — **gli id non si rinumerano mai**, i buchi sono attesi. Apri `${CLAUDE_PLUGIN_ROOT}/docs/inbox-format.md` prima di scrivere: porta il formato, le tre operazioni e gli snippet.

   **Un inbox `drainable` non si tocca**: descrive un rilascio chiuso ed è congelato. Capita su una task riaperta dopo la chiusura — leggi la riga 3 con `inbox.sh parse`, e se il token c'è dichiara in output che il riesame è saltato e perché.

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
   5. Rigenera l'indice, solo se il progetto tiene una `reference/` propria:
      ```bash
      [[ -d "{docs_root}/reference" ]] && "${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "{docs_root}"
      ```
      Cartella assente = la doc del progetto vive in un corpus di gruppo, fuori da questo repo: l'indice lo rigenera chi lavora lì, e da qui non c'è niente da fare.

   **6.3 — Riconciliazione.** Se il puntatore esiste **e** `## Doc Impact` porta comunque delle voci, qualcuno ha scritto nella sede sbagliata (una skill non allineata, il modello in chat prima di leggere il puntatore). Spostale nell'inbox con `Edit`, con id `max+1`, e togli le righe dal task file. Non è un secondo trasloco: nessun file nuovo, nessuna riga puntatore in più.

   **6.4 — Accensione della drenabilità.** Gira **solo se la task si è chiusa** allo step 4, e **dopo** il 6.2: il trasloco ha appena scritto la propria riga puntatore, e questo giro la deve vedere.

   La lista degli inbox della task è già nel task file: il trasloco ha lasciato in `## Doc Impact` la riga `- → inbox <basename>.md · storia: <sha>`. Normalmente è una sola — una task ha un inbox — ma una task riaperta dopo la chiusura può averne una seconda, e il giro le prende tutte. È la fonte esatta, e risolve da sé il caso della figlia di un'epica: il file si chiama col cappello (`T74-…`), ma la riga sta nel task file della task che ha traslocato.

   ```bash
   grep -oP '^- → inbox \K\S+\.md' "${task_file}"
   ```

   Per ogni basename, se il file esiste ancora in `{docs_root}/inbox/`:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" marker --file "{docs_root}/inbox/<basename>" --set drainable
   ```

   - **File assente**, mai un errore: un file inbox può essere uscito dal repo, ma la riga puntatore resta nel task file per sempre (è l'indirizzo storico). Salta quel basename e prosegui.
   - **File con `branch:` → salta**, non accendere. I due token sono gate distinti e cumulativi: `pull-repos` accende `drainable` al merge quando il branch è la sola cosa che manca, ma un file che porta ancora `branch:` non è in esercizio comunque. Leggi il marker con `inbox.sh parse` prima di decidere.
   - **Materializzazione incerta** — non sai se la feature è davvero in esercizio: `AskUserQuestion` all'utente, drainable sì/no. `No` salta l'intero giro, inbox vecchi compresi: la task è chiusa ma il file non descrive ancora un rilascio.
   - Un `marker` su un file già drainable è un no-op scritto: nessun danno, la riga 3 si riscrive identica.

   **6.5 — Conteggio dell'inbox.** Ultimo passo della fase doc, sullo stato finale del file:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/docs/lib-doc.sh"
   n=$("${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" parse --file "{docs_root}/inbox/<basename>" --format tsv | grep -c $'^NOZIONE\t')
   (( n > LW_DOC_INBOX_NOZIONI )) && echo "[inbox] ${n} nozioni, soglia ${LW_DOC_INBOX_NOZIONI}"
   ```

   Sopra soglia riporta la riga in output e **prosegui**: non tagli, non splitti, non apri una task. È un dato per chi legge il checkpoint, non un cancello — la soglia vive in `lib-doc.sh` e l'avviso dichiara il numero contro cui ha misurato.

7. **Aggiorna {docs_root}/tasks.md**
   1. Cella Prog della Tasks Overview e glifo dei nodi nel grafo dell'Execution Plan li scrivono le stesse due funzioni di `promote-ready` e `promote-wip`, mai tu a mano. `G` vale `✔️` se la task si è chiusa allo step 4, altrimenti `🟡`:

      ```bash
      source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
      G="✔️"   # 🟡 se la task non si è chiusa allo step 4
      if lw_tasks_md_prog_set "{docs_root}/tasks.md" "${taskId}" "$G"; then
          echo "-> tasks.md aggiornato: ${taskId} $G"
      else
          echo "WARN: nessuna riga ${taskId} sotto un header con colonna Prog — Prog NON aggiornata" >&2
      fi
      lw_tasks_md_graph_set "{docs_root}/tasks.md" "${taskId}" "$G"
      ```

   2. `lw_tasks_md_graph_set` stampa da sé i nodi riscritti, e un `WARN` per ogni riga che porta l'id con un altro glifo in una posizione che non riconosce come nodo. Exit 1 senza nessuna riga è la task assente dal grafo, il caso normale di una task spot. Ogni `WARN` dei due comandi va nelle Segnalazioni: non correggi il grafo a mano, e non togli il 🔒 ai dipendenti — lo sblocco richiede di leggere tutte le dipendenze del dipendente.
   3. L'ordine fra questo step e la fase doc è **libero**: la Prog in `tasks.md` non è un cancello per niente — a governare le sezioni dell'indice è il marker dentro il file inbox, che il 6.4 accende alla chiusura.

8. **Commit e push — fase tracking e doc**

   **Gira sempre**, anche se lo step 6 non ha traslocato niente: `tasks.md` è stato toccato allo step 7. Unica eccezione, working tree già pulito sul perimetro tracking+doc:

   ```bash
   git status --porcelain -- "{docs_root}/tasks.md" "{docs_root}/tasks/" "{docs_root}/inbox/" "{docs_root}/reference/INDEX.md"
   ```

   Output vuoto → salta lo step. Altrimenti pathspec esplicita:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh --task ${taskId} --doc-message "docs(${taskId}): trasloco in inbox" "checkpoint(${taskId}): Prog + riesame" -- "{docs_root}/tasks.md" "{docs_root}/inbox/<ogni file inbox toccato>.md" "{docs_root}/reference/INDEX.md"
   ```

   La pathspec nomina **ogni file inbox toccato**, non solo quello appena creato: il riesame (6.1) riscrive il corpo di un inbox nato in un checkpoint precedente e il 6.4 ne riscrive la riga marker, e un file modificato ma fuori pathspec resta dirty nel worktree, con un riesame che nessun commit porta su main.

   Nessun file sotto `inbox/` toccato → pathspec col solo `tasks.md` e **ometti `--doc-message`**.

   - **la pathspec dopo `--`** è obbligatoria: il push della fase codice è già avvenuto e altre sessioni possono aver ripreso a lavorare — un `git add -A` qui rastrellerebbe lavoro non tuo.
   - **`--task`** è obbligatorio: senza `$LOOM_TASK`, cioè con la task nominata per argomento, lo script non avrebbe altro modo di risolvere il task file.

   **Hook `taskDone`** — solo se lo step 4 di questo giro ha portato Progress a `✔️ Done`, dopo il push riuscito dello step 8:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/config/project-config.sh" hooks taskDone --task ${taskId} --sha <sha>
   ```

   `<sha>` è l'ultimo commit che lo step 8 stampa — `-> commit 2 (doc-nozione, …)` se c'è, altrimenti `-> commit 1 (…)` — cioè lo stato finale della chiusura; con lo step 8 saltato, l'ultimo dello step 5. Le skill si invocano come dice §Hook di progetto. Un checkpoint che non chiude non solleva `taskDone`.

9. **Feedback finale**
   Riporta: avanzamento registrato, su quale sede è girato il riesame e cosa ha riscritto o eliminato, se il trasloco ha creato l'inbox e con quali marker, e — se la task si è chiusa — quali inbox sono diventati drainable e quali sono stati saltati (assenti, o congelati da `branch:`). Se il progetto dichiara hook, riporta anche quelli invocati in questo giro, evento per evento, col loro esito. Il feedback chiude con la sezione `🚦 Segnalazioni` (§🚦 Segnalazioni, sotto), sempre. Poi il ping TTS:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "checkpoint $(say_id ${taskId}) done"
   ```
   In caso di errore nel commit/push: `say_auto "checkpoint $(say_id ${taskId}) failed"`.

## Hook di progetto — come si invocano

Gli step 5 e 8 sollevano due eventi che il progetto può legare a skill proprie in `.claude/loom-works.json` (`hooks.deliverableDone`, `hooks.taskDone`). Lo script dello step stampa:

- **nessuna riga, exit 0** → il progetto non dichiara hook su quell'evento: niente da fare.
- **righe `HOOK|<i>|<skill>` e una riga `ARGS=<argomenti>`** → per ogni `HOOK`, nell'ordine di `<i>`, invoca il tool `Skill` con `skill` = `<skill>` e `args` = il valore di `ARGS` copiato tale e quale. Una skill alla volta: la successiva parte quando la precedente ha dichiarato il suo esito.
- **exit non-zero** → nessuna skill per quell'evento. Il messaggio nomina il guasto: blocco `hooks` invalido, jq assente, task, DLV o sha non risolvibili.

**Un hook non ferma mai il checkpoint.** Commit e push sono già avvenuti, e l'hook non li riapre. Una skill che non esiste, che dà errore o che dichiara un esito di fallimento produce un avviso in linea — `⚠ hook <skill> fallito su DLV<n>: <motivo>`, o `su taskDone` — e una riga nelle Segnalazioni; le skill successive della lista e il resto del flusso girano comunque. Nessun secondo tentativo: un hook fallito a metà ha già potuto scrivere fuori dal repo (un commento sulla issue), e lo scriverebbe due volte. Un exit non-zero dello script vale uguale: `⚠ hook <evento> non invocati: <messaggio>`.

Il body di una skill hook entra nel contesto a ogni invocazione e vale per quell'hook soltanto: quando la skill ha dichiarato l'esito, riprendi dallo step che segue. Ciò che la skill hook fa resta suo, e nessun suo file entra nelle pathspec del checkpoint.

## 🚦 Segnalazioni — la sezione fissa del report

> Stato e requisiti rinviati: factory · T12 §Custodia — un limite del triage si segnala lì, non si apre una task qui.

Una segnalazione è un problema incontrato durante il checkpoint che chiede una decisione: un difetto fuori perimetro, un rischio, un residuo, una cosa che hai lasciato com'era, una cosa che hai corretto di tua iniziativa. Ogni segnalazione ha quattro uscite — **subito** (si risolve ora), **task** (diventa una task), **scarto** (non si fa, e se torna deve tacere: un motivo nel registro degli scarti), **ignora** (non si fa, e se torna parla: nessun record nel registro) — e ogni decisione diventa uno **scenario** su disco. Formato e sede: `${CLAUDE_PLUGIN_ROOT}/docs/triage-format.md`.

**La sezione c'è sempre, anche vuota**: l'assenza di segnalazioni è un fatto dichiarato, non una dimenticanza. La forma è fissa, perché è ciò che chi rilegge i transcript cerca:

```
**🚦 Segnalazioni**

**S{N}** — <la segnalazione, su una riga>
  subito · task · scarto · ignora
**S{N}** — <ciò che hai corretto di tua iniziativa, su una riga>
  ☑ subito (agente) · task · scarto · ignora
```

A zero segnalazioni, una riga sola: `**🚦 Segnalazioni** — nessuna`.

- **`S{N}` numera da 1 dentro questo report**, e la riga porta l'id e la segnalazione, nient'altro: il testo dopo `— ` è quello che lo scenario cita byte per byte.
- **Prima di stampare, interroga il registro degli scarti** su ogni segnalazione (`scarti.sh cerca`, regola in contesto): exit `0` vuol dire già scartata con un motivo, e non la riporti.
- **Un hook di progetto fallito è sempre una segnalazione** (§Hook di progetto): `S{N} — hook <skill> fallito su DLV<n>: <motivo>` (o `su taskDone`), oppure `S{N} — hook <evento> non invocati: <messaggio dello script>`. L'avviso in linea si perde nel transcript; la riga qui è ciò che l'umano decide.
- **Ciò che hai corretto di tua iniziativa sta dentro la sezione, con «subito» già marcato e chi = agente — mai in un inciso del report.** «Ho corretto un difetto pre-esistente» è una decisione che hai già preso: resta ribaltabile solo se l'umano la vede fra le segnalazioni. Prima di stampare la sezione ne scrivi lo scenario:

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/task/triage.sh" scenario --slug <slug> --uscita subito --chi agente \
    --momento flusso --skill checkpoint-task --no-commit <<'SCENARIO'
  <la segnalazione, identica al testo della riga S{N}>
  SCENARIO
  ```

- **Tu non scarti e non ignori.** Una segnalazione che ritieni irrilevante la riporti comunque con le quattro uscite: uno scarto sbagliato è un segnale perso che nessuno recupera, un tuo ignora è una segnalazione non stampata, e lo script rifiuta entrambi con `--chi agente`.

Gli scenari si scrivono con `--no-commit`, uno per segnalazione, e si committano insieme — i path sono quelli che lo script stampa (`-> scenario scritto:`, e `-> record dello scarto:` sullo scarto):

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
  && lw_git_add_n_commit "triage(${taskId}): <N> scenari" <path>... \
  && lw_git_push "$(lw_current_branch)"
```

### La risposta — prosa libera, lo scenario lo scrivi tu

L'umano risponde come vuole: in prosa, dettando a voce, in ordine sparso, su una parte sola delle segnalazioni. Nessuna domanda a scelta e nessuna griglia da compilare — nessuno strumento presidia la risposta, la leggi tu nel turno dopo. Riconosci la segnalazione da `S1`, `s1`, `1` o «la prima», e per ogni segnalazione decisa scrivi uno scenario `--chi umano --momento flusso`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/triage.sh" scenario --slug <slug> --uscita subito|task|scarto|ignora --chi umano \
  --momento flusso --skill checkpoint-task [--ancora <path>]... --no-commit <<'SCENARIO'
<la segnalazione, identica al testo della riga S{N}>
<le parole dell'umano su quella segnalazione: il perché sullo scarto, l'approfondimento sulle altre uscite>
SCENARIO
```

`--ancora` va solo con `--uscita scarto` e `ignora`, dove è obbligatoria: su `subito` e `task` lo script la rifiuta ed esce `1`. Poi un commit solo per tutti, con lo snippet sopra.

- **Nessun default.** La segnalazione su cui l'umano non dice niente non produce niente: non la decidi tu e non la ripresenti. Il recupero delle segnalazioni rimaste senza risposta si fa a posteriori, fuori da questa conversazione.
- **L'approfondimento è obbligatorio quando la risposta lo porta.** Sono le parole con cui l'umano accompagna l'uscita — il criterio con cui la sceglie, la forma dell'azione, il progetto dove eseguirla — e lo script le scrive alla lettera nel campo `Approfondimento` dello scenario: senza, due scenari `task` della stessa sessione restano indistinguibili. Il ritaglio di una `S{N}` è tutto ciò che l'umano dice su quella segnalazione, parola d'uscita compresa; restano fuori solo l'identificatore (`S1`, «la prima») e la punteggiatura che la separa dalle vicine. Non ritocchi niente, refusi compresi; parole dettate su più righe le unisci con uno spazio, perché il campo sta su una riga. Un'uscita nuda, una conferma o un rifiuto nudo («subito», «ok», «no») non hanno approfondimento: la seconda riga non si scrive. Una frase che vale per più segnalazioni entra nello scenario di ognuna, e i pezzi non contigui della stessa segnalazione si uniscono nell'ordine in cui compaiono con ` […] ` a segnare il salto: «S1 subito, S2 ignora ; AUTORIZZO» dà a S1 `subito […] AUTORIZZO`. Sullo scarto le parole dell'umano sono il perché e vanno nel record dello scarto; con `--chi agente` non c'è nessuna risposta da citare — in entrambi i casi lo script rifiuta il campo.
- **Le parole dell'umano dettano la forma dell'esecuzione, non solo l'uscita.** «task» con «aggiungi un DLV alla task corrente» aggiunge il DLV e non apre nessuna task; «ci penso io» non esegue niente. Vale anche per il modo: «fallo subito ma in un subagente» resta `subito`, il modo sta nell'approfondimento, e `Uscita` resta il solo campo che si conta.
- **«subito» nel flusso è operativo**: scrivi lo scenario ed esegui, nella forma che le parole dicono.
- **«task» nel flusso è operativo come «subito»**: scrivi lo scenario e fai senza chiedere niente ciò che le parole dicono. Quando non dicono altro, apri la task: invoca `/loom-works:create-task` in modalità YOLO, con `yolo <la segnalazione>` come argomento, una task per segnalazione. «task» è già la richiesta della task: aspettare una seconda conferma lascerebbe la decisione registrata e il lavoro da nessuna parte.
- **«scarto»** vuole il perché e un'ancora. Lo scrivi solo quando la risposta nomina lo scarto o porta un perché («S2 scarto: capita una volta l'anno», «S2 no, capita una volta l'anno»); nominato senza perché, chiedilo una volta sola, poi scrivi. L'ancora è il path che la segnalazione tocca. Lo script scrive anche il record dello scarto, e stampa il suo path da mettere nel commit.
- **«ignora», e ogni rifiuto nudo** — «S2 no», «lascia perdere», «non vale la pena»: nessun motivo e nessuna parola «scarto» — lo scrivi subito, senza chiedere niente. Vuole l'ancora, il path che la segnalazione tocca, e nessun perché: lo script rifiuta `--perche` sull'ignora. Le parole con cui l'umano lo nomina («S5 ignora: già gestito in S4») sono l'approfondimento, non un perché. Non scrive nessun record nel registro degli scarti, quindi se la segnalazione torna la riporti di nuovo. Nel dubbio fra i due scegli l'ignora, perché è l'errore che si recupera: un ignora scritto dove l'umano voleva uno scarto torna nel report se la segnalazione torna, uno scarto scritto dove voleva un ignora è un record dello scarto che nessuna query colpirà.
- **La conferma e il ribaltamento valgono uguale.** Sulla segnalazione che avevi marcato `☑ subito (agente)`, «ok» è uno scenario `subito` e «fanne una task» uno scenario `task`, entrambi `--chi umano`, accanto al tuo: non si riscrive niente, i due record sono il dato.
- **Detta a posteriori, la stessa parola è un esito e non un'azione.** Chi rilegge il report da un'altra sessione registra con `--momento posteriori` e non esegue niente.

**Una risposta firmata «su delega» è dell'orchestrator, non dell'umano.** Un messaggio che apre con `Risposte alle segnalazioni di T<id> — decise dall'orchestrator di T<id del perimetro orchestrabile> su delega dell'utente.` arriva dall'orchestrator del perimetro orchestrabile, che decide al posto dell'umano perché l'umano gliel'ha delegato; la riga sotto la firma porta le parole con cui l'ha delegato, alla lettera. Ogni scenario di quella risposta si scrive con `--chi delega` e quelle parole intere in `--delega`, senza ritaglio: le legge prima una variabile da un heredoc fra apici, così backtick e apostrofi restano testo.

```bash
DELEGA="$(cat <<'DELEGA'
<le parole della delega, dalla riga sotto la firma, intere>
DELEGA
)"
"${CLAUDE_PLUGIN_ROOT}/scripts/task/triage.sh" scenario --slug <slug> --uscita subito|task|scarto|ignora --chi delega \
  --delega "$DELEGA" --momento flusso --skill checkpoint-task [--ancora <path>]... --no-commit <<'SCENARIO'
<la segnalazione, identica al testo della riga S{N}>
<le parole dell'orchestrator su quella segnalazione: il perché sullo scarto, l'approfondimento sulle altre uscite>
SCENARIO
```

`--ancora` va solo con `--uscita scarto` e `ignora`, dove è obbligatoria: su `subito` e `task` lo script la rifiuta ed esce `1`.

- **Sotto delega valgono le regole dell'umano.** Le quattro uscite, le parole dell'orchestrator come approfondimento o come perché sullo scarto, l'ancora sull'ignora e sullo scarto, «subito» e «task» operativi: le parole dell'orchestrator stanno al posto di quelle dell'umano, e lo script le tratta allo stesso modo.
- **Firma senza le parole della delega → nessuno scenario.** Non scrivi niente e lo dici nel testo finale: le parole mancano, e senza non c'è uno scenario `delega` da scrivere. Non ripieghi su `--chi umano`, che dichiarerebbe una risposta che l'umano non ha dato, né su `--chi agente`, che farebbe di uno scarto affidato uno scarto autonomo.
- **Una risposta firmata «approvate dall'utente» resta `--chi umano`**: l'ha decisa l'umano, l'orchestrator l'ha solo portata.

### L'uscita che riguarda un altro progetto

**Il destinatario lo porta la segnalazione.** Una segnalazione nomina di norma il progetto o i file che riguarda, e «subito» e «task» agiscono lì, senza una conferma prima del lancio. Quando l'umano nomina un progetto nelle sue parole vince quello; quando nessuno ne nomina uno resta il progetto della sessione, e si esegue qui. Lo scenario si scrive comunque qui: il destinatario sta nella segnalazione o nell'approfondimento, e non ha un campo suo.

Un altro progetto non lo scrivi da questa sessione: può tenerti in sola lettura, e una scrittura da Bash aggirerebbe il suo confine. Lo esegue una sessione figlia lanciata nella sua cartella, che ne carica `CLAUDE.md`, settings, skill e regole di commit. In ordine, con `A="${CLAUDE_PLUGIN_ROOT}/scripts/task/triage-altrove.sh"` in testa a ogni invocazione Bash — lo stato della shell non passa da una all'altra:

1. `"$A" risolvi <progetto>` stampa la cartella. Exit `2`: nessun progetto con quel nome, o più d'uno — chiedi la cartella all'umano e non lanciare. Se la cartella è quella di questa sessione, nessun figlio: esegui qui.
2. `"$A" prima --dest <cartella> --atteso task|commit` stampa lo sha di `HEAD`, da passare al gate. `--atteso task` quando il figlio apre una task nuova, `commit` per «subito» e per ogni altra forma, come un DLV aggiunto a una task che c'è già. Exit `2`: l'uscita lì non parte (una task vuole la lista task del destinatario) — dillo all'umano.
3. Scrivi il prompt del figlio in un file fuori dai due repo. Per una task nuova: `/loom-works:create-task yolo <la segnalazione, il contesto che serve a chi non ha questa conversazione, le parole dell'umano>`. Altrimenti: cosa fare, con la segnalazione e le parole dell'umano alla lettera, e la richiesta di committare con le regole del progetto e di chiudere dichiarando l'hash del commit.
4. `"$A" lancia --dest <cartella> --prompt <prompt> --out <out>` lancia il figlio: entra nella cartella, toglie all'ambiente le variabili con cui questa conversazione descrive sé stessa — `LOOM_TASK`, `PROJECT_ROOT`, `PTYXIS_PROFILE`, `LOOM_ORCHESTRATOR` e `CLAUDE_EFFORT` fra le altre —, e lancia `claude -p --permission-mode auto --output-format text` col prompt su stdin e l'output in `<out>`. Esce con l'exit code del figlio; prima del lancio, exit `1` o `2` col motivo su stderr, e il figlio non parte. La lista e cosa sposta ogni variabile: `${CLAUDE_PLUGIN_ROOT}/docs/triage-format.md` §L'uscita eseguita in un altro progetto.
5. `"$A" verifica --dest <cartella> --prima <sha> --atteso task|commit [--hash <l'hash che il figlio dichiara>]`. Il ritorno del figlio è self-report: il gate legge i commit nati nel destinatario dopo `prima`, e per una task vuole il task file aggiunto e la sua riga in `tasks.md`. Verde (exit `0`): riporta all'umano cosa è nato, id e hash. Rosso (exit `2`): nessun secondo lancio — riporta il motivo del gate e il path di `<out>`.

Due figli sullo stesso destinatario girano in sequenza, perché condividono l'intervallo del gate e il contatore degli id; su destinatari diversi vanno in parallelo.

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici.

## Note

- **Uno script, di commit**: nessuno script di analisi, i deliverables chiusi si ricavano dalla conversazione.
- **Due fasi di commit**: la fase codice (step 5) chiude e pusha il lavoro prima che la doc cominci; la seconda (step 8) porta `tasks.md` e l'eventuale trasloco con pathspec esplicita. Un fallimento della fase doc non porta con sé il codice.
- **Due eventi, ognuno dopo il proprio push**: `deliverableDone` dopo lo step 5, solo per i DLV spuntati in questo giro; `taskDone` dopo lo step 8, solo nel giro che chiude. Un checkpoint che non spunta e non chiude non invoca niente.
- **Riesame ≠ archivio**: il riesame (6.1) è il lavoro della fase doc anche quando nessun trasloco scatta — ed è il grosso del lavoro dopo il primo, perché da lì in avanti c'è solo lui. Un checkpoint che non riscrive mai niente sta saltando la fase, non risparmiandola. Sull'inbox vale di più che sul task file: rigiudica un file già pubblicato e indicizzato, letto da chi non ha la task in mano.
- **Il file inbox è WIP finché la task è aperta**: l'owner è la task, e il corpo si appende, si riscrive e si pota a ogni checkpoint — le tre operazioni e la regola degli id stanno in `${CLAUDE_PLUGIN_ROOT}/docs/inbox-format.md`. Il congelamento arriva con `drainable` (6.4): da lì l'unica scrittura ammessa è la riga marker (lo sblocco di `pull-repos`).
- **Solo detached**: niente analisi del diff, stage selettivo obbligatorio — ogni commit porta la propria pathspec.
- **Nessuna allerta sul numero di file**: l'accumulo degli inbox è libero — nessun cap, nessun tetto. L'unico conteggio è quello del 6.5, dentro un singolo file, e stampa un numero senza chiedere niente.
