# Task Management

Sistema a Lane e Task con worktree Git isolati. Una sola task list (`docs/tasks.md`) per progetto.

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

Task prefix `T` (hardcoded), ID incrementali (T01, T02, …). Le task documentali usano prefix `D{N}` con counter separato.

I task file stanno in `docs/tasks/T{N}-{slug}.md`. Materiale di supporto (design docs, findings, analisi estemporanee) va in **task folder dedicata** — vive in **project root**, dot-prefixed `.YY-MM-DD-slug`, **mai** sotto `docs/tasks/` (lì stanno solo i task *file* `.md`) — vedi §Task Folder; o scratch folder per attività estemporanee.

Symlink runtime: `docs/current-task.md` → task attiva (gestito da `/loom-works:start-task`). In modalità detached il symlink NON viene creato e il task ID viaggia esplicito sessione per sessione (vedi §Detached).

## Lane

Percorso di task sequenziali con worktree condiviso: creato una volta, riusato. Senza lane: worktree nuovo ad ogni task (npm install, build, setup) poi distrutto al merge.

Le lane sono **design**, non emergono dagli script: definite nel grafo di `docs/tasks.md` in pianificazione. Bulk: grafo intero con cross-deps. Incrementale: `create-task` chiede in quale lane (o ne crea una). Task spot piccole vanno su main senza lane.

- **Naming**: worktree `{project}-{lane}` (es. `myproject-l1-feature`) · branch `feat/{lane}` · terminale/tmux stabile per lane.
- **Ciclo di vita**: ① `spawn-lane` crea worktree da main, avvia prima task → ② `start-task` → `run-task` → `checkpoint-task` nel worktree → ③ `merge-lane` mergia in main, aggiorna grafo, ricopia tasks nel worktree → ④ `spawn-lane` riusa worktree, crea solo nuovo branch task → ⑤ `merge-lane` chiede conferma rimozione worktree all'ultima task.
- **Comandi** (da main): `/loom-works:spawn-lane {lane}` crea/riusa worktree e avvia task · `/loom-works:merge-lane {lane}` merge in main, aggiorna grafo.

> **Stato**: `spawn-lane` e `merge-lane` pianificati (Fase 1).

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

Icone: ✔️ done · 🟡 in corso · 🔒 cross-deps non soddisfatte (sempre mostrato) · nessuna = wait/ready. 🔒 esclusiva del grafo (non compare in task table).

**Aggiornamenti**: `start-task` → Prog 🟡 + emoji grafo · `checkpoint-task` → Prog (🟡/✔️) + emoji grafo · `create-task` → aggiunge riga tabella · `merge-lane` → su conflitto git invoca `/loom-works:reconcile-tasks` (operational transformation: merge-base + diff da entrambi i lati via git history, LLM applica le ops al base per il risultato riconciliato — pianificato con `merge-lane`, Fase 1).

## Task

Le task si gestiscono dal worktree lane o direttamente da main (task spot). Comandi (main/lane):

- `/loom-works:create-task {id} {name}` — crea task (può chiedere la lane)
- `/loom-works:start-task {id} [detach]` — attiva task, inizia tracking (file task + docs/tasks.md)
- `/loom-works:run-task [{id}]` — esecuzione operativa (validazione → implementazione → test → build). Può essere lanciato più volte. Definition of Done: test passano, build OK
- `/loom-works:checkpoint-task [{id}]` — checkpoint, commit (file task + docs/tasks.md)

Flusso: `spawn-lane → run-task ⇄ checkpoint-task → merge-lane → spawn-lane (next)`. Le lane lavorano in parallelo, ognuna nel proprio worktree.

### Detached (più task in parallelo, stesso worktree)

Più task piccole in parallelo nello stesso worktree, una per sessione Claude: `/loom-works:start-task T102 detach` attiva la task SENZA creare il symlink `docs/current-task.md`; il task ID resta esplicito in ogni comando (`run-task T102`, `checkpoint-task T102`). Una sessione gestisce una singola task: l'agente sa cosa appartiene alla task corrente perché la conversazione lo dice.

Differenze vs linked:
- **Symlink**: non creato → risoluzione task da taskId esplicito (Glob), non da symlink
- **Analisi diff** (`checkpoint-task-analyze.sh` su `TRACKED_SHA..HEAD`): **skippata** — deliverables dal contesto conversazione
- **Staging commit**: stage selettivo manuale + `--no-add` (linked: `git add -A` da script)
- **Concorrenza**: N task per worktree, sessioni separate (linked: 1 task per worktree)

Vincoli:
- **Task piccole**: ogni sessione fa una task auto-contenuta. Se diventa grande, non usare detached.
- **No file overlap**: se due task detached toccano gli stessi file, evita conflitti tu (sequenza, non parallelismo reale).
- **Checkpoint sequenziali**: due `checkpoint-task` simultanei possono fare race su `tasks.md` e `git`. Coordinali tu.
- **Tasks.md row**: ogni task detached ha la sua riga 🟡 normalmente. Più 🟡 contemporanei = scenario voluto.

### Doc Impact gate al checkpoint

Ogni `checkpoint-task` su code task (K=⚙️) legge `## Doc Impact` del task file. Per ogni voce non marcata `→ ✔️`, l'utente sceglie:

- `[1] capture inline` — invoca `capture-doc`; il file doc modificato entra nello stesso commit del checkpoint. Voce marcata `→ ✔️ capture`.
- `[2] D-task` — invoca `doc-task parent=T{N}`; append `- [ ] D{N} chiusa` in Acceptance del task. Voce marcata `→ ✔️ D{N}`.
- `[3] skip` — lascia la voce non consolidata. Reentry al prossimo checkpoint. Nessun enforcement.

**Gate morbido**: scelta utente su _quando_ documentare (subito vs differito), ma l'esistenza di un ref è enforced. Se sceglie D-task, la checkbox in Acceptance impedisce il done del task finché la D non passa done; la chiusura della D flagga indietro la checkbox via `**Parent Task**: T{N}` nel D-file. Doc task (K=📝) **non** triggerano il gate (la doc è l'obiettivo, non un side-effect).

## Task Folder

Folder dedicata per task con molto materiale (artefatti, dump, analisi, script). Affianca (non sostituisce) `docs/` per contenuto AI-meta strutturato.

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
