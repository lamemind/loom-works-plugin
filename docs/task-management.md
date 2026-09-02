# Task Management

Sistema a Lane e Task con worktree Git isolati.

## Struttura

```
MAIN ({project}/)                ← branch base, home di docs/tasks.md, task spot ammesse
  ├── LANE ({project}-{lane}/)   ← worktree lane (persistente, branch feat/{lane}), N task
  ├── LANE ({project}-{lane2}/)
  └── task spot                  ← direttamente su main, senza lane
```

## Task List

Una singola fonte di verità: `docs/tasks.md`. Contiene:
- **Tasks Overview** (tabella): ID, Priority, Progress, descrizione
- **Execution Plan** (grafo lane con cross-deps)

Task prefix `T` (hardcoded), counter unico, ID incrementali (T01, T02, …).

I task file stanno in `docs/tasks/T{N}-{slug}.md`; il materiale di supporto va in una **task folder**, o in una scratch folder se non ha una task — §Task Folder.

## Quale task è attiva

Una sola cascata, per ogni consumer: **`arg esplicito → $LOOM_TASK → symlink docs/current-task.md`**.

- **arg** — l'ID nominato nell'invocazione (`/loom-works:run-task T48`). In cima, o una sessione già vincolata non potrebbe più chiedere un'altra task.
- **`$LOOM_TASK`** — binding di **sessione**, esportato allo spawn (`deck-run`). Batte il symlink perché N sessioni parallele nello stesso worktree ne condividono uno solo: quale delle N sei tu lo sa solo l'env.
- **symlink `docs/current-task.md`** — binding di **worktree**, scritto da `start-task`. In detached non viene creato affatto.

Implementata **una volta**: `lw_resolve_task` in `scripts/utils/lib.sh`, e per chi non può sourcare bash (il markdown delle skill) il wrapper `scripts/task/resolve-task.sh`. Restituisce `TASK_ID` · `TASK_FILE` · `TASK_SRC` ∈ `arg|env|symlink`. `TASK_SRC` non è cosmetico: rende la provenienza dichiarata invece che silenziosa, ed è ciò che decide linked vs detached (§Detached), cioè `git add -A` contro stage selettivo.

**Un solo canale scrive la task in contesto**: l'hook `SessionStart` (`inject-task.sh`). Il symlink **non va @-importato** in `CLAUDE.md` — entrerebbe in parallelo all'iniezione e in una sessione con `$LOOM_TASK` il modello vedrebbe due task attive divergenti, l'iniettata e quella stale del worktree.

`start-task` **rifiuta di girare** quando `$LOOM_TASK` è settata, anche sullo stesso ID: scriverebbe un symlink che la sessione corrente ignora (l'env lo batte), cioè lo stale che la cascata esiste per non produrre.

## Lane

Percorso di task sequenziali con worktree condiviso: creato una volta, riusato. Senza lane: worktree nuovo ad ogni task (npm install, build, setup) poi distrutto al merge.

Le lane sono **design**, non emergono dagli script: si definiscono nel grafo di `docs/tasks.md` in pianificazione, in blocco o una alla volta (`create-task` chiede in quale lane). Task spot piccole vanno su main senza lane.

- **Naming**: worktree `{project}-{lane}` (es. `myproject-l1-feature`) · branch `feat/{lane}`.
- **Ciclo di vita**: ① `spawn-lane` crea worktree da main, avvia prima task → ② `start-task` → `run-task` → `checkpoint-task` nel worktree → ③ `merge-lane` mergia in main, aggiorna grafo, ricopia tasks nel worktree → ④ `spawn-lane` riusa worktree, crea solo nuovo branch task → ⑤ `merge-lane` chiede conferma rimozione worktree all'ultima task.
- **Comandi** (da main): `/loom-works:spawn-lane {lane}` crea/riusa worktree e avvia task · `/loom-works:merge-lane {lane}` merge in main, aggiorna grafo.

### Grafo dipendenze

```
Legend: 🟢 Ready  🟡 In Progress  ✔️ Done  🔒 Locked

Lane 1 (nome):   ✔️T01 → ✔️T02 → 🟡T03 → T04 → T05
Lane 2 (nome):   ✔️T06 → 🟡T07 → T08 → T09

Cross-deps:
| Task | Parent | Cross Deps |
| ---- | ------ | ---------- |
| T04  | T03    | ✔️T06       |
| 🔒T11 | T10    | ✔️T02, T09  |
```

Ciclo di vita: `🔵 → 🟢 preflight fatto → 🟡 → ✔️`. Tabella e grafo restano due alfabeti: 🔒 è esclusivo del grafo, 🔵 della tabella — nel grafo l'assenza di emoji marca la task in attesa.

**Aggiornamenti**: `preflight-task` → Prog 🟢 + emoji grafo, solo da 🔵 · `start-task` · `run-task` → Prog 🟡 + emoji grafo · `checkpoint-task` → Prog (🟡/✔️) + emoji grafo · `create-task` → aggiunge riga tabella · `merge-lane` → su conflitto git invoca `/loom-works:reconcile-tasks`.

## Task

Le task si gestiscono dal worktree lane o direttamente da main (task spot). Comandi (main/lane):

- `/loom-works:create-task {id} {name}` — crea task (può chiedere la lane)
- `/loom-works:start-task {id} [detach]` — attiva task, inizia tracking (file task + docs/tasks.md)
- `/loom-works:run-task [{id}] [perimetro]` — esegue i DLV (perimetro `1,3-5`; nudo = tutti gli aperti), promuove a 🟡, un commit leggero per DLV chiuso
- `/loom-works:checkpoint-task [{id}]` — checkpoint, commit (file task + docs/tasks.md)

Flusso: `spawn-lane → run-task ⇄ checkpoint-task → merge-lane → spawn-lane (next)`. Le lane lavorano in parallelo, ognuna nel proprio worktree.

**Parentela fra task**: il campo `**Parent Task**: T{N}` si scrive a mano nella figlia, e il parent porta `- [ ] T{N} (<maniglia>) chiusa` in Acceptance. Alla chiusura della figlia il suo `checkpoint-task` flagga indietro quella checkbox — matchando l'id, non la frase.

**Epiche (task cappello)**: `Size: Epic` marca il cappello. Serve un marker suo perché la parentela la scrive la **figlia** — il padre non sa di averne senza scandagliare gli altri task file. Nel cappello: visione, perimetro, ordine delle fasi, una checkbox per figlia in Acceptance. Nelle figlie: il lavoro eseguibile, coi propri DLV e AC. `run-task` **non esegue** un'epica, lo dichiara e si ferma. Figlie: `resolve-task.sh <id> --children` (word boundary sull'id, `T7` non matcha `T74`).

**Materiale della task**: la sezione `## Materiale` dichiara i file di **alto rilievo**, non l'inventario della folder. Voce = glifo + path + maniglia verbo+oggetto. 📖 fonte · 🔬 analisi · 📤 prodotto · `📁/` = radice della task folder (campo `Folder`).

### Detached (più task in parallelo, stesso worktree)

Più task piccole in parallelo nello stesso worktree, una per sessione Claude. Due modi di entrarci, stesso regime: `/loom-works:start-task T102 detach` (task ID esplicito in ogni comando) oppure una sessione spawnata dal deck, che porta `$LOOM_TASK`.

**Lo decide `TASK_SRC`, non l'argomento**: `symlink` → linked · `env`/`arg` → detached. Il criterio è chi possiede il binding — il *worktree* (una task sola, tutto il movimento del repo è suo) o la *sessione* (il repo si muove anche per mano d'altri).

Differenze vs linked:
- **Analisi diff** (`checkpoint-task-analyze.sh`, finestra `<baseline>..HEAD`): **skippata** — il diff raccoglierebbe anche il lavoro delle altre task. Deliverables dal contesto conversazione
- **Staging commit**: la lista dei file passa allo script come pathspec (linked: `git add -A` da script). Ogni commit porta la propria pathspec: lo stage altrui resta in stage. Su `TASK_SRC=env` senza pathspec lo script esce in errore: la contaminazione è silenziosa e si scopre a push fatto
- **Concorrenza**: N task per worktree, sessioni separate (linked: 1 task per worktree)

Vincoli:
- **Task piccole**: ogni sessione fa una task auto-contenuta. Se diventa grande, non usare detached.
- **No file overlap**: se due task detached toccano gli stessi file, evita conflitti tu (sequenza, non parallelismo reale).
- **Checkpoint sequenziali**: due `checkpoint-task` simultanei possono fare race su `tasks.md` e `git`. Coordinali tu.

### Doc Impact — sede unica, riesame, trasloco

Le nozioni di una task vivono in **un posto solo per volta**, e il task file dichiara quale: `## Doc Impact` finché porta le voci, il file inbox della task quando al loro posto porta `→ inbox <basename> · storia: <sha>`. Ogni `checkpoint-task` **riesamina** la sede corrente — riscrive o elimina — coi soli criteri indipendenti (`doc-management.md` §Imbuto). Nessun marker di esito.

Il **trasloco** gira **una volta sola**, al primo checkpoint con voci da spostare, e crea l'inbox della task (`inbox.sh new`, cappello = parent aperto o task stessa). Ordine vincolante: commit del task file **con** le voci, poi il file inbox, poi la riga puntatore. Da lì l'inbox è WIP e appartiene alla task — si appende, si riscrive, si pota (`inbox-format.md`) — finché la **chiusura** accende `drainable` e lo congela.

Una task su branch dichiara `**Branch**:` nel task file (si scrive a mano come `Parent Task`; assente = `main`); il suo inbox porta `branch:<nome>` e mai `drainable` — lo sblocco è di `pull-repos`, quando trova il file su main. `branch:` non congela per la task che ne è owner. Dove una nozione atterri lo decide `drain-notions`, in differita.

**La fase doc gira dopo il commit e il push del codice**, mai prima: il push rende il lavoro visibile alle altre sessioni, e un fallimento della fase doc non porta con sé il codice.

## Task Folder

Dove sta il materiale di una task (artefatti, dump, analisi, script). Naming `.YY-MM-DD-{slug}` (dot-prefix → sort top). **Posizione = project root, sempre** — mai sotto `docs/tasks/`, che tiene solo i task file `.md`. Nome e posizione le assegnano `set-task-folder` / `scratch-new`.

- **Assegnata, non creata**: `create-task` e `set-task-folder` scrivono il campo `**Folder**:` senza `mkdir` — la directory nasce col primo file che ci scrivi (`Write` crea le dir intermedie; da bash `mkdir -p` sul path del campo). Campo popolato + directory assente = materiale non ancora prodotto, mai un errore. Il campo è sempre presente, vuoto se la task non ha folder.
- **Quando**: `create-task` la assegna a size **L**/**Epic**; S/M solo se chiesto (`"con folder"` nelle Note utente).
- **Comandi**: retroattiva `/loom-works:set-task-folder {taskId}` · orfana senza task `/loom-works:scratch-new <slug>`.
- **CWD invariato**: le skill workflow non fanno mai `cd`: il cwd resta project root. Dentro la folder si lavora solo su scelta esplicita dell'utente.
