# Task Management - Dettagli Tecnici

---

Per l'overview del sistema (struttura, grafo dipendenze, ciclo di vita lane, comandi principali) vedi [Task Management](./task-management.md).

---

## Esempi Comandi

### Ciclo Lane

```bash
# Da main: crea task
/loom-works:create-task T319 "Setup database models"
/loom-works:create-task T320 "Implement login API"

# Spawn lane (crea/riusa worktree, avvia prossima task)
/loom-works:spawn-lane l1
# -> Crea worktree ../{project}-l1/ (o riusa se esiste), branch feat/l1 da main
# -> Avvia prima task non-done della lane

# Lavoro nel worktree lane
/loom-works:run-task
/loom-works:checkpoint-task

# Merge (dal worktree main!)
/loom-works:merge-lane l1
# -> Merge branch feat/l1 → main
# -> Aggiorna grafo lane in docs/tasks.md
# -> Copia docs/tasks.md aggiornato nel worktree lane
# -> Worktree lane RIMANE attivo

# Prossima task nella lane
/loom-works:spawn-lane l1
# -> Riusa worktree esistente, avvia prossima task

# Task spot (direttamente su main, senza lane)
/loom-works:start-task T321
/loom-works:run-task
/loom-works:checkpoint-task
```

---

## Workflow Interno Task - Dettagli

### run-task (Esecutore)

Esecuzione operativa della task. Può essere lanciato più volte.

**Fasi**:

1. **Validazione** — Requisiti chiari? Dipendenze soddisfatte? Dubbi → chiedi all'utente
2. **Scomposizione** — Suddividi in step con TodoWrite
3. **Pianificazione** — Piano top-down, micro-step validabili
4. **Esecuzione** — Implementa, modalità unsupervised con checkpoint
5. **Verifica** — Test passano, build funziona

**Definition of Done**:

- Tutti gli step completati
- Test passano
- Build senza errori
- Pronto per review

### checkpoint-task (Checkpoint)

Salvataggio del progresso. Commit delle modifiche.

**Quando usarlo**:

- Dopo review approvata
- A fine giornata (checkpoint intermedio)
- Prima di passare ad altra task

**Doc Impact gate (morbido)**: ogni checkpoint su code task processa la sezione `## Doc Impact` del task file. Per ogni voce non marcata, scelta utente: capture inline / crea D-task / skip. Dettagli: [Task Management §Doc Impact gate](./task-management.md).

### Pattern di Iterazione

```
# Lane parallele (ogni lane nel suo worktree)
Lane l1:  spawn-lane → run → checkpoint → merge-lane → spawn-lane (next) → ...
Lane l2:  spawn-lane → run → checkpoint → merge-lane → spawn-lane (next) → ...

# Task nella lane
spawn-lane → run → checkpoint → merge-lane

# Checkpoint intermedio (fine giornata)
run → checkpoint → (pausa) → run → checkpoint → merge-lane

# Task spot (direttamente su main, senza lane)
start → run → checkpoint
```

---

## Naming Convention

| Elemento       | Pattern               | Esempio (illustrativo)      |
| -------------- | --------------------- | --------------------------- |
| Worktree lane  | `{project}-{lane}`    | `{project}-l1-core`         |
| Branch lane    | `feat/{lane}`         | `feat/l1-core`              |
| Task ID        | `T{N}`                | `T319`                      |

### Note

- Il prefisso `{project}-` riflette il nome del progetto (monorepo) — ogni progetto usa il proprio nome
- Worktree e branch prendono il nome della lane, non della task
- I nomi delle lane sono definiti nel grafo di `docs/tasks.md` (es. `l1-core`, `l2-api`, `l3-ui`)
- Task prefix `T` hardcoded (ID incrementali); task documentali usano `D{N}` con counter separato

---

## Config Centralizzata

I worktree condividono una configurazione comune posizionata a livello superiore.

```
/code/
├── .{project}-config/     # Config condivisa (nome dipende dal progetto)
│   ├── .env               # API keys
│   └── dev.properties     # Settings dev
├── {project}/             # Main
├── {project}-l1/          # Lane l1
└── {project}-l2/          # Lane l2
```

> Il codice applicativo deve leggere dalla config condivisa e poi applicare eventuali override locali. Il nome della cartella config (es. `.myproject-config/`) è specifico di ogni progetto.

---

## Legend Progress/Priority

Marcatori standard per tracking nelle task table.

### Prog (colonna emoji-only)

| Emoji | Significato |
| ----- | ----------- |
| 🔵 | Non iniziata |
| 🟡 | In corso |
| ✔️ | Completata |

### Pri (colonna emoji-only)

| Emoji | Significato |
| ----- | ----------- |
| 🔥 | Priorità alta |
| ⚡ | Priorità media |
| 🔹 | Priorità bassa |

---

## Esempio Task Table

Formato standard per `docs/tasks.md` (Task max 100 caratteri).

| ID   | Pri | Prog | Task (max 100)                                                                                       |
| ---- | --- | ---- | ---------------------------------------------------------------------------------------------------- |
| T319 | 🔥 | ✔️   | Task completata              |
| T321 | ⚡ | 🟡   | Task in corso                |
| T322 | ⚡ | 🔵   | Task non iniziata            |
