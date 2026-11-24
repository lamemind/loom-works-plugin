# Task Management

Sistema di task tracciate in `docs/tasks.md`, eseguite nel worktree del progetto.

## Struttura

Una task vive nel worktree principale del progetto: su main, oppure su un branch dichiarato nel campo `**Branch**:` del task file (§Doc Impact). loom-works non crea, non mergia e non rimuove worktree: un worktree git aperto a mano resta possibile, ma nessuna skill lo gestisce.

## Task List

Una singola fonte di verità: `docs/tasks.md`. Contiene:
- **Tasks Overview** (tabella): ID, Priority, Progress, descrizione
- **Execution Plan** (grafo delle dipendenze con cross-deps)

Task prefix `T` (hardcoded), counter unico, ID incrementali (T01, T02, …).

I task file stanno in `docs/tasks/T{N}-{slug}.md`; il materiale di supporto va in una **task folder**, o in una scratch folder se non ha una task — §Task Folder.

## Quale task è attiva

Una sola cascata, per ogni consumer: **`arg esplicito → $LOOM_TASK`**. Senza i due nessuna task è attiva, e nessun file del worktree fa da ripiego.

- **arg** — l'ID nominato nell'invocazione (`/loom-works:run-task T48`). In cima, o una sessione già vincolata non potrebbe più chiedere un'altra task.
- **`$LOOM_TASK`** — binding di **sessione**, esportato allo spawn (`deck-run`). Il worktree non lega nessuna task: N sessioni parallele nello stesso worktree lavorano ognuna sulla sua, e quale delle N sei tu lo sa solo l'env.

Implementata **una volta**: `lw_resolve_task` in `scripts/utils/lib.sh`, e per chi non può sourcare bash (il markdown delle skill) il wrapper `scripts/task/resolve-task.sh`. Restituisce `TASK_ID` · `TASK_FILE` · `TASK_SRC` ∈ `arg|env`: la provenienza resta dichiarata invece che silenziosa.

**Un solo canale scrive la task in contesto**: l'hook `SessionStart` (`inject-task.sh`), che la legge da `$LOOM_TASK`. Un task file **non va @-importato** in `CLAUDE.md`: entrerebbe in ogni sessione del progetto, e una sessione legata a un'altra task vedrebbe due task attive divergenti.

## Grafo dipendenze

Le catene sono **design**, non emergono dagli script: si scrivono a mano nell'Execution Plan di `docs/tasks.md` in pianificazione, e nessuna skill ne aggiunge una. Ogni catena si intesta con un'etichetta libera seguita da `:` e almeno due spazi.

```
Legend: 🟢 Ready  🟡 In Progress  ✔️ Done  🔒 Locked

Epica T10 (nome):   ✔️T01 → ✔️T02 → 🟡T03 → T04 → T05
Spot:               ✔️T06 → 🟡T07 → T08 → T09

Cross-deps:
| Task | Parent | Cross Deps |
| ---- | ------ | ---------- |
| T04  | T03    | ✔️T06       |
| 🔒T11 | T10    | ✔️T02, T09  |
```

Ciclo di vita: `🔵 → 🟢 preflight fatto → 🟡 → ✔️`. Tabella e grafo restano due alfabeti: 🔒 è esclusivo del grafo, 🔵 della tabella — nel grafo l'assenza di emoji marca la task in attesa.

**Aggiornamenti**: `preflight-task` → Prog 🟢 + emoji grafo, solo da 🔵 · `run-task` → Prog 🟡 + emoji grafo · `checkpoint-task` → Prog (🟡/✔️) + emoji grafo · `create-task` → aggiunge riga tabella.

## Task

- `/loom-works:create-task {id} {name}` — crea task
- `/loom-works:run-task [{id}] [perimetro]` — esegue i DLV (perimetro `1,3-5`; nudo = tutti gli aperti), promuove a 🟡, un commit leggero per DLV chiuso
- `/loom-works:checkpoint-task [{id}]` — checkpoint, commit (file task + docs/tasks.md)

Flusso: `create-task → preflight-task → run-task ⇄ checkpoint-task`; il preflight è obbligatorio a Size L, alle altre Size serve quando emergono dubbi di design. Più task in parallelo nello stesso worktree: §Detached.

**Parentela fra task**: il campo `**Parent Task**: T{N}` si scrive a mano nella figlia, e il parent porta `- [ ] T{N} (<maniglia>) chiusa` in Acceptance. Alla chiusura della figlia il suo `checkpoint-task` flagga indietro quella checkbox — matchando l'id, non la frase.

**Epiche (task cappello)**: `Size: Epic` marca il cappello. Serve un marker: la parentela la scrive la **figlia**, il padre non sa di averne. Nel cappello: visione, ordine delle fasi, una checkbox per figlia in Acceptance; nelle figlie il lavoro eseguibile. Un **mandato** (`Size: Mandate`) elenca nel suo file membri anche di epiche diverse. Nessuno dei due copia stato o cifre dei membri, e `run-task` non li esegue. Membri: `resolve-task.sh <id> --members`; formato: `mandate-format.md`.

**Materiale della task**: la sezione `## Materiale` dichiara i file di **alto rilievo**, non l'inventario della folder. Voce = glifo + path + maniglia verbo+oggetto. 📖 fonte · 🔬 analisi · 📤 prodotto · 🎬 stato dell'orchestrator · `📁/` = radice della task folder (campo `Folder`).

### Detached (più task in parallelo, stesso worktree)

Ogni task è detached: la lega la sessione, mai il worktree. Una sessione entra in una task in due modi, stesso regime: aperta dal deck, che porta `$LOOM_TASK`, oppure con l'ID esplicito in ogni comando. Il worktree ospita N task in parallelo, una per sessione Claude, e il repo si muove anche per mano d'altri. Ne discendono due regole:

- **Nessuna analisi del diff** al checkpoint: il diff del worktree raccoglierebbe anche il lavoro delle altre task. I deliverables chiusi si ricavano dal contesto della conversazione.
- **Ogni commit porta la propria pathspec**: la lista dei file passa allo script, e lo stage altrui resta in stage. Senza pathspec `checkpoint-task-commit.sh` esce in errore e non committa niente: un `git add -A` rastrellerebbe il lavoro delle altre sessioni, e la contaminazione è silenziosa — si scopre a push fatto.

Vincoli:
- **Task auto-contenute**: ogni sessione lavora su una task sola.
- **No file overlap**: se due task toccano gli stessi file, evita conflitti tu (sequenza, non parallelismo reale).
- **Checkpoint sequenziali**: due `checkpoint-task` simultanei possono fare race su `tasks.md` e `git`. Coordinali tu.

### Doc Impact — sede unica, riesame, trasloco

Le nozioni di una task vivono in **un posto solo per volta**, e il task file dichiara quale: `## Doc Impact` finché porta le voci, il file inbox della task quando al loro posto porta `→ inbox <basename> · storia: <sha>`. Ogni `checkpoint-task` **riesamina** la sede corrente — riscrive o elimina — coi soli criteri indipendenti (`doc-management.md` §Imbuto). Nessun marker di esito.

Il **trasloco** gira **una volta sola**, al primo checkpoint con voci da spostare, e crea l'inbox della task (`inbox.sh new`, cappello = parent aperto o task stessa). Ordine vincolante: commit del task file **con** le voci, poi il file inbox, poi la riga puntatore. Da lì l'inbox è WIP e appartiene alla task — si appende, si riscrive, si pota (`inbox-format.md`) — finché la **chiusura** accende `drainable` e lo congela.

Una task su branch dichiara `**Branch**:` nel task file (si scrive a mano come `Parent Task`; assente = `main`); il suo inbox porta `branch:<nome>` e mai `drainable` — lo sblocco è di `pull-repos`, quando trova il file su main. `branch:` non congela per la task che ne è owner. L'inbox congelato resta dov'è, indicizzato.

**La fase doc gira dopo il commit e il push del codice**, mai prima: il push rende il lavoro visibile alle altre sessioni, e un fallimento della fase doc non porta con sé il codice.

## Task Folder

Dove sta il materiale di una task (artefatti, dump, analisi, script). Naming `.YY-MM-DD-{slug}` (dot-prefix → sort top). **Posizione = project root, sempre** — mai sotto `docs/tasks/`, che tiene solo i task file `.md`. Nome e posizione le assegnano `set-task-folder` / `scratch-new`.

- **Assegnata, non creata**: `create-task` e `set-task-folder` scrivono il campo `**Folder**:` senza `mkdir` — la directory nasce col primo file che ci scrivi (`Write` crea le dir intermedie; da bash `mkdir -p` sul path del campo). Campo popolato + directory assente = materiale non ancora prodotto, mai un errore. Il campo è sempre presente, vuoto se la task non ha folder.
- **Quando**: `create-task` la assegna a size **L**/**Epic**; S/M solo se chiesto (`"con folder"` nelle Note utente).
- **Comandi**: retroattiva `/loom-works:set-task-folder {taskId}` · orfana senza task `/loom-works:scratch-new <slug>`.
- **CWD invariato**: le skill workflow non fanno mai `cd`: il cwd resta project root. Dentro la folder si lavora solo su scelta esplicita dell'utente.
