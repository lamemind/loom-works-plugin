# Il perimetro orchestrabile — formato del task file e lettore dei membri

Contratto per chi **scrive e legge** il task file di un perimetro orchestrabile, nelle sue due forme, epica e lista custom: le sezioni di una lista custom, la regola che vieta le copie di stato, e il lettore unico dei membri. L'analisi del perimetro orchestrabile e l'ordine del giro non stanno nel task file: stanno nel piano, `orchestration-schedule.md` nella sua task folder (`orchestration-schedule-format.md`). `schedule.md` è il nome di prima del piano: chi legge il piano cerca prima il nome nuovo, poi quello, e `prepare-perimeter` lo rinomina quando ci passa.

## Epica e lista custom

Un perimetro orchestrabile vive sempre in un task file, in una di due forme:

- **epica** (`Size: Epic`) — i membri sono le **figlie**, le task che dichiarano `**Parent Task**: T<id>`. La parentela la scrive la figlia, e il campo è uno solo: una task ha un padre solo.
- **lista custom** (`Size: Custom`) — i membri sono **elencati nel file della lista custom**, e possono venire da epiche diverse o non avere un padre. La parentela non cambia: nessun task file dei membri si tocca, una task può stare in più liste custom, e l'epica di dominio resta intatta. `Size: Mandate` è il nome di prima di `Size: Custom` e vale uguale, senza scadenza: lo riscrive `prepare-perimeter` quando passa sul file.

Le due forme differiscono solo nel punto da cui si leggono i membri, e il lettore è uno solo (§Il lettore dei membri).

Una lista custom non ha lavoro eseguibile proprio, come un'epica: `run-task` dichiara che è una lista custom e si ferma, il recap lo fa `recap-status-epic`, e il checkpoint `checkpoint-perimeter`, che riallinea il file del perimetro orchestrabile a ciò che i membri hanno scritto.

## Struttura del task file

L'header è quello del task template, con `Size: Custom`. Dopo `## Description` viene una sezione propria, `## Membri`:

```markdown
# Task: Lista custom: convention e orchestrator insieme

- **ID**: T230
- **Size**: Custom
- **Parent Task**:
- **Folder**: ./.26-11-20-convention-e-orchestrator
- **Progress**: 🔵 Todo

## Description

Perché questa lista custom esiste e cosa vuole ottenere.

## Membri

- T52 (lettore unico delle convention)
- T61 (gate del deck sulle convention)
- T64 (orchestrator headless)

## Materiale
*📖 fonte · 🔬 analisi · 📤 prodotto · 🎬 stato dell'orchestrator · 💎 da non eliminare, accanto al glifo di ruolo (📤💎); 📁/ = task folder. Solo materiale di alto rilievo, non l'inventario della folder.*

- 🔬 `📁/orchestration-schedule.md` — eseguire il giro: analisi del perimetro e piano dello script
- 🎬 `.claude/loom/orchestrator/T230.md` — seguire il giro dell'orchestrator: fatti del perimetro, proposte in sospeso, delega (fuori da git)
```

`## Materiale` non è una sezione propria della lista custom: è quella del task template, e in un perimetro orchestrabile porta la voce del piano e la voce 🎬 (§La voce 🎬). La task folder di un perimetro orchestrabile c'è sempre, perché ci sta il piano.

### `## Membri`

- **Una riga per membro**, a colonna zero, che comincia con `- `. Vale il **primo `T<numero>`** della riga, il resto è la maniglia: `- T52 (maniglia)`, `- **T52** — maniglia` e ``- `T52` maniglia`` leggono tutte `T52`. È la stessa tolleranza del campo `**Parent Task**`.
- Righe indentate, righe senza id, righe dentro un blocco ```` ``` ```` e testo fuori dalla lista non contano: sono prosa.
- La sezione finisce al prossimo heading `#` o `##`. Un `###` la divide in gruppi senza chiuderla.
- L'ordine è quello del file. Un id ripetuto conta una volta, alla prima riga; la lista custom che elenca sé stessa non conta.
- **Niente checkbox e niente stato.** Il `checkpoint-task` di un membro spunta solo la checkbox del suo `Parent Task`: una checkbox per membro nella lista custom non ha custode e resta indietro alla prima chiusura. La checkbox per figlia nell'Acceptance di un'epica resta, perché lì il custode c'è.
- **Un'epica o una lista custom fra i membri resta una riga sola.** Il lettore non la sostituisce coi suoi membri: chi consuma la tratta come un perimetro orchestrabile da seguire a parte. Così nessun ciclo fra liste custom può nascere dal lettore. Il prezzo: «tutte le figlie di T40 più due orfane» si scrive elencando le figlie una per una, e una figlia nata dopo non entra da sola.

### L'ordine e l'analisi stanno nel piano

L'ordine che vale **solo per questo giro** («in questo giro prima le convention») e l'analisi delle relazioni fra i membri — chi dipende da chi, chi tocca gli stessi file — stanno in `orchestration-schedule.md`, nella task folder del perimetro orchestrabile: la prosa per chi legge, un blocco JSON per lo script che esegue il giro (`orchestration-schedule-format.md`). Il suo task file non le ripete: una seconda copia resterebbe indietro alla prima modifica del piano.

Le dipendenze vere non stanno nemmeno nel piano: stanno in `## Dependencies` dei membri e nel grafo di `tasks.md`, perché valgono per ogni perimetro orchestrabile che contiene quei membri. Una dipendenza vera scritta solo nel piano resta invisibile a chi lavora sulla task fuori dal perimetro orchestrabile. Il piano la ripete per lo script, e `orchestration_schedule.py verify` controlla che la ripeta.

### Rimandi fra repo in `## Dependencies`

Di ogni voce di `## Dependencies` a colonna zero conta il primo riferimento a una task, e il resto è prosa. Una task di un altro repo si scrive **attaccata al nome del repo**, `<repo>·T<n>`: è la forma del grafo di un cappello, e non si confonde con la prosa.

```markdown
## Dependencies

- factory·T41 (formato del registro): serve il suo DLV2
- T07 (lettore dei membri)
```

- **Il rimando non è una dipendenza del progetto.** Il parser di `perimeter.py tree` salta `<repo>·T<n>` e anche la forma con lo spazio, `<parola> · T<n>`, e stampa `XREF|<membro>|<rimando>` per ogni voce saltata. L'orchestrator non aspetta un rimando: l'ordine fra due repo lo segue chi lavora sui due.
- **Una voce che comincia con un rimando non dichiara nessuna dipendenza**, anche se poi cita un id del progetto: `- factory·T41, lo stesso lavoro di T07 qui` non dà T07. Una dipendenza locale va in una voce sua.
- **Senza separatore il rimando non si riconosce.** `- factory T41` resta una dipendenza del progetto su T41: se il progetto ha un suo T41, l'orchestrator aspetta la task sbagliata, e nessuna riga lo avvisa.
- **La forma con lo spazio può nascondere una dipendenza locale.** Una voce come `- parser · T41` è saltata come rimando anche quando T41 è una task del progetto: la riga `XREF` lo mostra a chi conferma il piano, e la correzione è riscrivere la voce con l'id in testa.

### La voce 🎬

Il glifo 🎬, **stato dell'orchestrator**, marca in `## Materiale` di un perimetro orchestrabile — lista custom o epica — la voce che punta al file in cui l'orchestrator tiene la sua memoria del giro: `.claude/loom/orchestrator/T<id>.md`, sotto la project root, ignorato da git. Il file porta fatti del perimetro, proposte in sospeso, rami fermi e delega, e `checkpoint-perimeter` ne porta i fatti nella prosa del perimetro orchestrabile. I passi e le conversazioni del giro stanno nel flusso dello script, accanto (`flow-format.md`).

- La scrive `prepare-perimeter`, una volta sola; l'orchestrator non scrive nei task file.
- È un puntatore per chi legge il task file. L'orchestrator e `checkpoint-perimeter` ricavano il path dall'id del perimetro orchestrabile, quindi un perimetro orchestrabile senza la voce viene seguito lo stesso.
- Il file può non esserci ancora: nasce al primo lancio dell'orchestrator.

### Acceptance e Deliverables

Facoltativi: il formato non prescrive né `## Acceptance Criteria` né `## Deliverables Checklist`. Una lista custom non ha lavoro proprio, e la sua chiusura è la sua Prog in `tasks.md`, non una derivazione dai membri.

## Nessuna copia di stato o di cifre

**Il file di un perimetro orchestrabile — lista custom o epica — non copia niente che vive altrove:**

- niente colonna di stato dei membri: la Prog sta in `tasks.md`;
- niente cifre ricopiate da un membro (DLV spuntati, misure, conteggi): si scrive il puntatore al membro che le produce.

Una copia scritta a mano resta indietro alla prima modifica, chiunque sia il proprietario. Su un progetto reale, dopo un orchestrator, quattro dei sei disallineamenti del cappello erano copie: lo stato delle figlie, lo stato di una task collegata, una cifra ricopiata da una figlia, un componente chiuso non segnato nello schema.

Il piano non è una copia: descrive relazioni fra membri e decisioni d'ordine, non il loro stato, e `verify` lo ricontrolla contro i file.

## Il lettore dei membri

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh <id> --members
```

Dopo le tre righe della risoluzione (`TASK_ID`, `TASK_FILE`, `TASK_SRC`) stampa la fonte, il conteggio e una riga per membro. Le righe dei membri non sono %q-quotate: sono per un lettore, non per `eval`.

```
TASK_MEMBERS_SRC=list
TASK_MEMBERS_COUNT=2
TASK_MEMBER=T52 /abs/path/runtime/tasks/T52-slug.md
TASK_MEMBER_MISSING=T58
TASK_MEMBER=T61 /abs/path/runtime/tasks/T61-slug.md
```

- **`TASK_MEMBERS_SRC=list`** quando l'header porta `- **Size**: Custom`: i membri vengono da `## Membri`, nell'ordine del file.
- **`TASK_MEMBERS_SRC=parent`** su ogni altra task: i membri sono le figlie, in ordine numerico, con la stessa regola di `--children` (`T7` non matcha `T74`).
- **`TASK_MEMBER_MISSING=<id>`** — un membro dichiarato senza task file. Non entra nel conteggio e non ferma il lettore, exit 0: una task chiusa e purgata da `clean-tasks` è un caso normale, e chi consuma decide cosa farne.
- Una lista custom senza `## Membri`, o con la sezione vuota, dà `TASK_MEMBERS_COUNT=0` ed exit 0. Il lettore **non ripiega sulle figlie**: i membri di una lista custom sono la sua lista, e una task che la nomina in `Parent Task` non ne diventa membro.

`--children` resta com'era: le figlie da `Parent Task`, anche su una lista custom. Il calcolo vive in `lw_task_members` (`scripts/utils/lib.sh`); uno script che sourca `lib.sh` chiama la funzione, non il wrapper.
