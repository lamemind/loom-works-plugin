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

Esegue i **deliverable** di una task, uno alla volta. Può essere lanciato più volte, su perimetri diversi.

**Fasi**:

1. **Gate `Epic`** — un cappello non si esegue: dichiara le figlie e ferma
2. **Perimetro** — `task-deliverables.sh` numera i DLV 1-based e risolve `--scope "1,3-5"`; nudo = tutti gli aperti. Errore secco su indice fuori range, spec malformata, perimetro vuoto, DLV già `[x]` nominato
3. **Gate preflight** — nessun dubbio architetturale aperto: `L` pretende `## Decisions`, `S`/`M` lo pretendono quando il dubbio emerge. Nessuna domanda inline
4. **Rito** — `Size` decide quanta validazione e pianificazione precedono il codice (`S` nessuna · `M` leggera · `L` profonda + piano top-down)
5. **Promozione 🟡** — `promote-wip.sh`, tre posti insieme e commit dedicato, solo da 🔵 o 🟢
6. **Ciclo per-DLV** — lavora, spunta `[x]`, committa `run(Txx): DLVn <maniglia>` con pathspec esplicita, pusha

**Definition of Done** (per deliverable, non per task):

- Il DLV è chiuso davvero: test passano, build senza errori
- Spunta `[x]` e commit leggero — codice + spunta, niente `Prog`, niente inbox
- Un DLV che non si chiude non si spunta: fermata dichiarata, quelli dopo restano intatti

### checkpoint-task (Checkpoint)

Salvataggio del progresso. Commit delle modifiche.

**Quando usarlo**:

- Dopo review approvata
- A fine giornata (checkpoint intermedio)
- Prima di passare ad altra task

**Doc Impact**: le voci restano vive nella sede che il task file dichiara e ogni checkpoint le **riesamina** coi soli criteri indipendenti — riscrive o elimina, nessun marker. Il primo trasloco le porta nell'inbox della task, lasciando al loro posto `→ inbox <file> · storia: <sha>`; da lì la sede è quel file, finché la chiusura non lo congela con `drainable`. Nessuna scelta utente, nessuno spawn. Dettagli: [Task Management §Doc Impact](./task-management.md).

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
- Task prefix `T` hardcoded, counter unico (ID incrementali)

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
| 🟢 | Preflight fatto (design congelato, zero codice) |
| 🟡 | In corso |
| ✔️ | Completata |

Il ciclo di vita è `🔵 → 🟢 → 🟡 → ✔️`. Il verde lo scrive `preflight-task`, e solo su una task `🔵`: da qualunque altro stato la cella resta intatta, perché la skill è ri-eseguibile e rifare il preflight su una task chiusa non deve riaprirla.

`🔒` (bloccata da cross-deps) resta **esclusivo del grafo Execution Plan** e non compare mai in tabella.

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
| T322 | ⚡ | 🟢   | Task col preflight fatto     |
| T323 | ⚡ | 🔵   | Task non iniziata            |
