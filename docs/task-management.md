# Task Management

Sistema a Lane e Task con worktree Git isolati.

## Struttura

```
MAIN ({project}/)                ← branch base, home di docs/tasks.md, task spot ammesse
  ├── LANE ({project}-{lane}/)   ← worktree lane (persistente, branch feat/{lane}), N task
  ├── LANE ({project}-{lane2}/)
  └── task spot                  ← direttamente su main, senza lane
```

Task = unità di lavoro, vive in `docs/tasks/{id}-*.md`.

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

**Un solo canale scrive la task in contesto**: l'hook `SessionStart` (`inject-task.sh`). Il symlink **non va @-importato** in `CLAUDE.md` — entrerebbe in parallelo all'iniezione e in una sessione con `$LOOM_TASK` il modello vedrebbe due task attive divergenti, l'iniettata e quella stale del worktree. È una primitiva di *risoluzione*, non un canale di *iniezione*.

`start-task` **rifiuta di girare** quando `$LOOM_TASK` è settata, anche sullo stesso ID: scriverebbe un symlink che la sessione corrente ignora (l'env lo batte), cioè lo stale che la cascata esiste per non produrre.

## Lane

Percorso di task sequenziali con worktree condiviso: creato una volta, riusato. Senza lane: worktree nuovo ad ogni task (npm install, build, setup) poi distrutto al merge.

Le lane sono **design**, non emergono dagli script: definite nel grafo di `docs/tasks.md` in pianificazione. Bulk: grafo intero con cross-deps. Incrementale: `create-task` chiede in quale lane (o ne crea una). Task spot piccole vanno su main senza lane.

- **Naming**: worktree `{project}-{lane}` (es. `myproject-l1-feature`) · branch `feat/{lane}` · terminale/tmux stabile per lane.
- **Ciclo di vita**: ① `spawn-lane` crea worktree da main, avvia prima task → ② `start-task` → `run-task` → `checkpoint-task` nel worktree → ③ `merge-lane` mergia in main, aggiorna grafo, ricopia tasks nel worktree → ④ `spawn-lane` riusa worktree, crea solo nuovo branch task → ⑤ `merge-lane` chiede conferma rimozione worktree all'ultima task.
- **Comandi** (da main): `/loom-works:spawn-lane {lane}` crea/riusa worktree e avvia task · `/loom-works:merge-lane {lane}` merge in main, aggiorna grafo.

### Grafo dipendenze

`docs/tasks.md` contiene il grafo lane con cross-deps. Source of truth per gli script.

```
Legend: ✔️ Done  🟡 In Progress  🔒 Locked

Lane 1 (nome):   ✔️T01 → ✔️T02 → 🟡T03 → T04 → T05
Lane 2 (nome):   ✔️T06 → 🟡T07 → T08 → T09

Cross-deps:
| Task | Parent | Cross Deps |
| ---- | ------ | ---------- |
| T04  | T03    | ✔️T06       |
| 🔒T11 | T10    | ✔️T02, T09  |
```

🔒 = cross-deps non soddisfatte, sempre mostrato ed esclusivo del grafo (non compare in task table); nessuna emoji = wait/ready.

**Aggiornamenti**: `start-task` → Prog 🟡 + emoji grafo · `checkpoint-task` → Prog (🟡/✔️) + emoji grafo · `create-task` → aggiunge riga tabella · `merge-lane` → su conflitto git invoca `/loom-works:reconcile-tasks`.

## Task

Le task si gestiscono dal worktree lane o direttamente da main (task spot). Comandi (main/lane):

- `/loom-works:create-task {id} {name}` — crea task (può chiedere la lane)
- `/loom-works:start-task {id} [detach]` — attiva task, inizia tracking (file task + docs/tasks.md)
- `/loom-works:run-task [{id}]` — esecuzione operativa (validazione → implementazione → test → build). Può essere lanciato più volte. Definition of Done: test passano, build OK
- `/loom-works:checkpoint-task [{id}]` — checkpoint, commit (file task + docs/tasks.md)

Flusso: `spawn-lane → run-task ⇄ checkpoint-task → merge-lane → spawn-lane (next)`. Le lane lavorano in parallelo, ognuna nel proprio worktree.

**Parentela fra task**: il campo `**Parent Task**: T{N}` si scrive a mano nella figlia, e il parent porta `- [ ] T{N} (<maniglia>) chiusa` in Acceptance. Alla chiusura della figlia il suo `checkpoint-task` flagga indietro quella checkbox — matchando l'id, non la frase.

**Materiale della task**: la sezione `## Materiale` dichiara i file di **alto rilievo**, non l'inventario della folder. Voce = glifo + path + maniglia verbo+oggetto. 📖 fonte · 🔬 analisi · 📤 prodotto · `📁/` = radice della task folder (campo `Folder`).

### Detached (più task in parallelo, stesso worktree)

Più task piccole in parallelo nello stesso worktree, una per sessione Claude. Due modi di entrarci, stesso regime: `/loom-works:start-task T102 detach` (task ID esplicito in ogni comando) oppure una sessione spawnata dal deck, che porta `$LOOM_TASK`.

**Lo decide `TASK_SRC`, non l'argomento**: `symlink` → linked · `env`/`arg` → detached. Il criterio è chi possiede il binding — il *worktree* (una task sola, tutto il movimento del repo è suo) o la *sessione* (il repo si muove anche per mano d'altri).

Differenze vs linked:
- **Analisi diff** (`checkpoint-task-analyze.sh`, finestra `<baseline>..HEAD`): **skippata** — il diff raccoglierebbe anche il lavoro delle altre task. Deliverables dal contesto conversazione
- **Staging commit**: stage selettivo manuale + `--no-add` (linked: `git add -A` da script). Su `TASK_SRC=env` lo script forza `--no-add` da sé: la contaminazione è silenziosa e si scopre a push fatto
- **Concorrenza**: N task per worktree, sessioni separate (linked: 1 task per worktree)

Vincoli:
- **Task piccole**: ogni sessione fa una task auto-contenuta. Se diventa grande, non usare detached.
- **No file overlap**: se due task detached toccano gli stessi file, evita conflitti tu (sequenza, non parallelismo reale).
- **Checkpoint sequenziali**: due `checkpoint-task` simultanei possono fare race su `tasks.md` e `git`. Coordinali tu.
- **Tasks.md row**: ogni task detached ha la sua riga 🟡 normalmente. Più 🟡 contemporanei = scenario voluto.

### Doc Impact al checkpoint

Ogni `checkpoint-task` legge le voci `## Doc Impact` **da lavorare**, le riscrive applicando i **soli criteri indipendenti** (`doc-management.md` §Imbuto), le porta nel file inbox del **cappello** — il parent se la task ne dichiara uno ancora aperto, la task stessa altrimenti — e le marca: `→ ✔️ inbox` se entrano, `→ ✖️ <parola>` se una delle sei le tiene fuori, `⏳ <evento>` se la nozione è vera ma il suo referente si sta ancora muovendo. Nessuna scelta all'utente, nessuno spawn di subagent: la nozione la scrive la sessione che ha già il contesto della task in memoria.

**`⏳` è l'unico marker non terminale**, quindi «da lavorare» sono le voci senza marker **e** quelle `⏳`. L'evento è una condizione verificabile (`⏳ F7`), mai un momento, e cade dentro il ciclo di vita della task: il checkpoint che la chiude forza ogni residuo a decisione, o l'attesa resta senza nessuno che la rilegga.

**Niente gate**: c'era per decidere *quando* pagare il costo del consolidamento, e senza costo non resta niente da decidere. Dove la nozione atterri lo decide `drain-doc`, in differita.

**La fase doc gira dopo il commit e il push del codice**, mai prima: il push è ciò che rende il lavoro visibile alle altre sessioni, che ripartono mentre questa finisce. Committare per primo il codice toglie anche il `git add -A` dalla finestra della scrittura doc — la working copy resta usabile, e un fallimento della fase doc non porta con sé il codice.

## Task Folder

Folder dedicata per task con molto materiale (artefatti, dump, analisi, script).

```
{project}/
├── .26-05-22-brt-invoice-error/   ← task folder (size L)   [project ROOT]
├── docs/tasks/                    ← qui SOLO i task file .md (NO folder)
└── ...                            ← codice progetto
```

Naming `.YY-MM-DD-{slug}` (dot-prefix → sort top, slug = task slug). **Posizione = project root, sempre** — mai sotto `docs/tasks/`; il nome dotted è solo il nome, il parent è la root. Non crearla a mano (`mkdir`): usa `set-task-folder` / `scratch-new`, che la collocano giusta.

- **Quando esiste**: auto-creata da `create-task` per size **L**; S/M solo se specificato (`"with folder"` / `"con folder"` nelle Note utente).
- Campo `**Folder**:` nel task file: sempre presente, vuoto se no folder.
- **Comandi**: folder retroattiva (riusa se esiste) `/loom-works:set-task-folder {taskId}` · folder orfana senza task `/loom-works:scratch-new <slug>`.
- **CWD invariato**: le skill workflow non cambiano mai `cwd`; resta sempre project root (dove sta `CLAUDE.md`). Il campo Folder (📁) è informativo: lavoro dentro la folder su scelta esplicita dell'utente.
