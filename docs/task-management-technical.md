# Task Management - Dettagli Tecnici

---

Per l'overview del sistema (struttura, grafo dipendenze, comandi principali) vedi [Task Management](./task-management.md).

---

## Esempi Comandi

### Ciclo di una task

```bash
# Crea la task
/loom-works:create-task T319 "Setup database models"

# Congela le decisioni di design (obbligatorio a Size L)
/loom-works:preflight-task T319

# Esegue i deliverable, poi il checkpoint
/loom-works:run-task T319
/loom-works:checkpoint-task T319
```

---

## Workflow Interno Task - Dettagli

### run-task (Esecutore)

Esegue i **deliverable** di una task, uno alla volta. Può essere lanciato più volte, su perimetri eseguibili diversi.

**Fasi**:

1. **Gate `Epic` / `Custom`** — un cappello o una lista custom non si esegue: dichiara i membri (`resolve-task.sh --members`) e ferma
2. **Perimetro eseguibile** — `task-deliverables.sh` numera i DLV 1-based e risolve `--scope "1,3-5"`; nudo = tutti gli aperti. Errore secco su indice fuori range, spec malformata, perimetro eseguibile vuoto, DLV già `[x]` nominato
3. **Gate preflight** — nessun dubbio architetturale aperto: `L` pretende `## Decisions`, `S`/`M` lo pretendono quando il dubbio emerge. Nessuna domanda inline. Un blocco `### Preflight` con l'heading `— premessa decaduta` non vale come preflight fatto, a nessun Size: il preflight si è fermato davanti a una premessa smentita dalla misura senza porre domande, e i DLV poggiano su un meccanismo che la misura ha già smentito
4. **Rito** — `Size` decide quanta validazione e pianificazione precedono il codice (`S` nessuna · `M` leggera · `L` profonda + piano top-down)
5. **Promozione 🟡** — `promote-wip.sh`, tre posti insieme e commit dedicato, solo da 🔵 o 🟢
6. **Ciclo per-DLV** — lavora, spunta `[x]`, committa `run(Txx): DLVn <maniglia>` con pathspec esplicita, pusha, poi invoca in ordine le skill di `hooks.deliverableDone` del progetto (`project-config.sh hooks deliverableDone --task --dlv --sha` compone gli argomenti); un hook fallito è un avviso e una segnalazione, mai una fermata

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

**Epica e lista custom**: su `Size: Epic` o `Size: Custom` non esegue il proprio flusso e passa a `checkpoint-perimeter`, che riallinea il file del perimetro orchestrabile a ciò che i membri hanno scritto, aggiorna la Prog e committa il solo file del perimetro orchestrabile con `tasks.md`. Nessuna fase doc: un perimetro orchestrabile non rilascia niente.

**Hook di progetto**: dopo il push della fase codice invoca le skill di `hooks.deliverableDone` per ogni DLV che il checkpoint spunta da sé; nel giro che chiude la task, dopo il push finale, quelle di `hooks.taskDone`. Un hook fallito è un avviso e una segnalazione, mai una fermata.

**Doc Impact**: le voci restano vive nella sede che il task file dichiara e ogni checkpoint le **riesamina** coi soli criteri indipendenti — riscrive o elimina, nessun marker. Il primo trasloco le porta nell'inbox della task, lasciando al loro posto `→ inbox <file> · storia: <sha>`; da lì la sede è quel file, finché la chiusura non lo congela con `drainable`. Nessuna scelta utente, nessuno spawn. Dettagli: [Task Management §Doc Impact](./task-management.md).

### Pattern di Iterazione

```
# Task
create → preflight → run → checkpoint

# Checkpoint intermedio (fine giornata)
run → checkpoint → (pausa) → run → checkpoint
```

---

## Naming Convention

| Elemento | Pattern | Esempio (illustrativo) |
| -------- | ------- | ---------------------- |
| Task ID  | `T{N}`  | `T319`                 |

Task prefix `T` hardcoded, counter unico (ID incrementali).

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
