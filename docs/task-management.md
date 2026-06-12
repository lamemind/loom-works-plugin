# Task Management

Sistema organizzato a Lane e Task con worktree Git isolati. Una sola task list (`docs/tasks.md`) per progetto.

## Struttura

```
MAIN ({project}/)
  │
  ├── LANE ({project}-{lane}/)      ← worktree lane (persistente, branch feat/{lane})
  ├── LANE ({project}-{lane2}/)     ← worktree lane (persistente, branch feat/{lane2})
  └── task spot                     ← direttamente su main, senza lane
```

| Livello  | Ruolo                                                   |
| -------- | ------------------------------------------------------- |
| **Main** | Branch base, home di `docs/tasks.md`. Task spot ammesse |
| **Lane** | Worktree persistente + branch `feat/{lane}`, N task     |
| **Task** | Unità di lavoro, vive in `docs/tasks/{id}-*.md`         |

## Task List

Una singola fonte di verità: `docs/tasks.md`. Contiene:
- **Tasks Overview** (tabella): ID, Priority, Progress, descrizione
- **Execution Plan** (grafo lane con cross-deps)

Task prefix: `T` (hardcoded). ID sono incrementali (T01, T02, …). Le task documentali usano prefix `D{N}` con counter separato.

I singoli task file stanno in `docs/tasks/T{N}-{slug}.md`. Materiale di supporto (design docs, findings, analisi estemporanee) va in task folder dedicata (vedi §Task Folder) o scratch folder per attività estemporanee.

Symlink runtime: `docs/current-task.md` → task attiva (gestito da `/loom-works:start-task`). In modalità detached il symlink NON viene creato e il task ID viaggia esplicito sessione per sessione (vedi §Detached).

## Lane

Percorso di task sequenziali con worktree condiviso. Senza lane: worktree nuovo ad ogni task (npm install, build, setup) poi distrutto al merge. Con lane: worktree creato una volta, riusato.

Le lane sono **design**, non emergono dagli script. Definite nel grafo di `docs/tasks.md` in pianificazione. Bulk: grafo intero con cross-deps. Incrementale: `create-task` chiede in quale lane (o ne crea una). Task spot piccole vanno su main senza lane.

### Naming

| Elemento       | Pattern            | Esempio                |
| -------------- | ------------------ | ---------------------- |
| Worktree       | `{project}-{lane}` | `myproject-l1-feature` |
| Branch         | `feat/{lane}`      | `feat/l1-feature`      |
| Terminale/tmux | stabile per lane   | `myproject-l1-feature` |

### Ciclo di vita

1. `spawn-lane` crea worktree da main, avvia prima task
2. `start-task` → `run-task` → `checkpoint-task` nel worktree
3. `merge-lane` mergia in main, aggiorna grafo, ricopia tasks nel worktree
4. `spawn-lane` riusa worktree, crea solo nuovo branch task
5. `merge-lane` chiede conferma rimozione worktree all'ultima task

### Comandi

| Comando                         | Da   | Funzione                       |
| ------------------------------- | ---- | ------------------------------ |
| `/loom-works:spawn-lane {lane}` | main | Crea/riusa worktree, avvia task |
| `/loom-works:merge-lane {lane}` | main | Merge in main, aggiorna grafo  |

> **Stato**: `spawn-lane` e `merge-lane` pianificati (Fase 1, vedi `../INTEGRATION.md` §7).

### Grafo dipendenze

`docs/tasks.md` contiene il grafo lane con cross-deps. Source of truth per gli script.

```
Legend: ✔️ Done  🟡 In Progress  🔒 Locked

Lane 1 (nome):   ✔️T01 → ✔️T02 → 🟡T03 → T04 → T05
Lane 2 (nome):   ✔️T06 → 🟡T07 → T08 → T09
Lane 3 (nome):   ✔️T10 → 🔒T11 → T12
Lane 4 (nome):   🟡T13 → T14 → 🔒T15

Cross-deps:
| Task | Parent | Cross Deps |
| ---- | ------ | ---------- |
| T04  | T03    | ✔️T06       |
| 🔒T11 | T10    | ✔️T02, T09  |
| 🔒T15 | T14    | T07        |
```

Icone: ✔️ done, 🟡 in corso, 🔒 cross-deps non soddisfatte (sempre mostrato), nessuna = wait/ready. 🔒 esclusiva del grafo (non compare in task table).

### Aggiornamenti

- `start-task` → Prog 🟡 + emoji grafo
- `checkpoint-task` → Prog (🟡/✔️) + emoji grafo
- `merge-lane` → su conflitto git invoca `reconcile-tasks`
- `create-task` → aggiunge riga tabella

### reconcile-tasks

Su conflitto git, `merge-lane` invoca `/loom-works:reconcile-tasks`: operational transformation, estrae merge-base + diff da entrambi i lati via git history, LLM applica le ops al base per il risultato riconciliato.

> **Stato**: pianificato con `merge-lane` (Fase 1).

## Task

Le task si gestiscono dal worktree lane o direttamente da main (task spot).

| Comando                                  | Da dove   | Funzione                         |
| ---------------------------------------- | --------- | -------------------------------- |
| `/loom-works:create-task {id} {name}`    | main/lane | Crea task (può chiedere la lane) |
| `/loom-works:start-task {id} [detach]`   | main/lane | Attiva task, checkpoint tracking |
| `/loom-works:run-task [{id}]`            | main/lane | Esecuzione operativa della task  |
| `/loom-works:checkpoint-task [{id}]`     | main/lane | Checkpoint, commit               |

### Detached (più task in parallelo, stesso worktree)

Modalità per fare più task piccole in parallelo nello stesso worktree, una per sessione Claude.

**Come funziona**

- `/loom-works:start-task T102 detach` attiva la task SENZA creare il symlink `docs/current-task.md`. Il task ID resta esplicito: ogni sessione Claude lo passa a `run-task` e `checkpoint-task`.
- Si possono attivare N task detached contemporaneamente nello stesso worktree (sessioni separate).
- Una sessione singola gestisce una singola task: l'agente sa cosa appartiene alla task corrente perché la conversazione lo dice.

**Comandi in modalità detached**

```
/loom-works:start-task T102 detach        # attiva senza symlink
/loom-works:run-task T102                 # esegui (taskId esplicito)
/loom-works:checkpoint-task T102          # checkpoint (taskId esplicito)
```

**Differenze chiave vs linked**

| Aspetto             | Linked                              | Detached                                    |
| ------------------- | ----------------------------------- | ------------------------------------------- |
| Symlink             | `docs/current-task.md` creato       | Non creato                                  |
| Risoluzione task    | Da symlink                          | Da taskId esplicito (Glob)                  |
| Analisi diff        | `checkpoint-task-analyze.sh` su `TRACKED_SHA..HEAD` | **Skippata**: deliverables dal contesto conversazione |
| Staging commit      | `git add -A` (script)               | Stage selettivo manuale + `--no-add`        |
| Concorrenza         | 1 task per worktree                 | N task per worktree (sessioni separate)     |

**Vincoli**

- **Task piccole**: ogni sessione fa una task auto-contenuta. Se diventa grande, non usare detached.
- **No file overlap**: se due task detached toccano gli stessi file, evita conflitti tu (sequenza, non parallelismo reale).
- **Checkpoint sequenziali**: due `checkpoint-task` simultanei possono fare race su `tasks.md` e `git`. Coordinali tu.
- **Tasks.md row**: ogni task detached ha la sua riga 🟡 normalmente. Più 🟡 contemporanei = scenario voluto.

## Workflow Interno Task

Ciclo di vita dall'attivazione al merge. Le lane lavorano in parallelo, ognuna nel proprio worktree.

```
spawn-lane ──► run-task ──► checkpoint-task ──► merge-lane ──► spawn-lane (next)
                  │               │
                  └───────────────┘
                    (itera se necessario)
```

| Comando                          | Responsabilità                                                      |
| -------------------------------- | ------------------------------------------------------------------- |
| `/loom-works:start-task`         | Attiva task, inizia tracking (file task + docs/tasks.md)            |
| `/loom-works:run-task`           | Esecuzione operativa (validazione → implementazione → test → build) |
| `/loom-works:checkpoint-task`    | Checkpoint, commit (file task + docs/tasks.md)                      |
| `/loom-works:merge-lane`         | Merge in main, aggiorna grafo, mantiene worktree                    |

**run-task**: esegue il lavoro. Può essere lanciato più volte. Definition of Done: test passano, build OK.

### Doc Impact gate al checkpoint

Ogni `checkpoint-task` su code task (K=⚙️) legge `## Doc Impact` del task file. Per ogni voce non marcata `→ ✔️`, l'utente sceglie:

| Opzione               | Effetto                                                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `[1] capture inline`  | Invoca `capture-doc`; il file doc modificato entra nello stesso commit del checkpoint. Voce marcata `→ ✔️ capture`.       |
| `[2] D-task`          | Invoca `doc-task parent=T{N}`. Append `- [ ] D{N} chiusa` in Acceptance del task. Voce marcata `→ ✔️ D{N}`.               |
| `[3] skip`            | Lascia la voce non consolidata. Reentry al prossimo checkpoint. Nessun enforcement.                                      |

**Gate morbido**: scelta utente su _quando_ documentare (subito vs differito), ma esistenza di un ref è enforced. Se sceglie D-task, la checkbox in Acceptance impedisce il done del task finché la D non passa done. La chiusura della D flagga indietro la checkbox via `**Parent Task**: T{N}` nel D-file.

Doc task (K=📝) **non** triggerano il gate (la doc è l'obiettivo, non un side-effect).

## Task Folder

Folder dedicata per task con molto materiale (artefatti, dump, analisi, script). Affianca (non sostituisce) `docs/` per contenuto AI-meta strutturato.

### Pattern

```
{project}/
├── .26-05-22-brt-invoice-error/   ← task folder (size L)
├── .26-04-15-granterre/           ← task folder (size L)
├── docs/                          ← doc loom-works
└── ...                            ← codice progetto
```

Naming: `.YY-MM-DD-{slug}`. Dot-prefix → sort top. Slug = task slug.

### Quando esiste

| Size | Comportamento |
|------|--------------|
| **L** | Auto-creata da `create-task` |
| **S, M** | Solo se specificato (`"with folder"` / `"con folder"` nelle Note utente) |

Campo `**Folder**:` nel task file: sempre presente, vuoto se no folder.

### Comandi

| Azione | Comando |
|--------|---------|
| Crea task con folder (auto size L) | `/loom-works:create-task` |
| Aggiungi folder retroattiva | `/loom-works:set-task-folder {taskId}` |
| Promuovi scratch pre-esistente | `/loom-works:set-task-folder {taskId} --existing <path>` |
| Crea folder orfana (no task) | `/loom-works:scratch-new <slug>` |

### CWD invariato

Le skill workflow non cambiano mai `cwd`. CWD resta sempre project root (dove sta `CLAUDE.md`). Il campo Folder viene mostrato in output (📁) ma è informativo: lavoro dentro la folder avviene su scelta esplicita dell'utente.
