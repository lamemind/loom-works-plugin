# Il mandato — formato del task file e lettore dei membri

Contratto per chi **scrive e legge** il task file di un perimetro di lavoro: le sezioni di un mandato, la regola che vieta le copie di stato, e il lettore unico dei membri.

## Epica e mandato

Un perimetro di lavoro vive sempre in un task file, in una di due forme:

- **epica** (`Size: Epic`) — i membri sono le **figlie**, le task che dichiarano `**Parent Task**: T<id>`. La parentela la scrive la figlia, e il campo è uno solo: una task ha un padre solo.
- **mandato** (`Size: Mandate`) — i membri sono **elencati nel file del mandato**, e possono venire da epiche diverse o non avere un padre. La parentela non cambia: nessun task file dei membri si tocca, una task può stare in più mandati, e l'epica di dominio resta intatta.

Le due forme differiscono solo nel punto da cui si leggono i membri, e il lettore è uno solo (§Il lettore dei membri).

Un mandato non ha lavoro eseguibile proprio, come un'epica: `run-task` dichiara che è un mandato e si ferma, il recap lo fa `recap-status-epic`, e il checkpoint `checkpoint-mandate`, che riallinea il file del perimetro a ciò che i membri hanno scritto.

## Struttura del task file

L'header è quello del task template, con `Size: Mandate`. Dopo `## Description` vengono tre sezioni proprie, in quest'ordine:

```markdown
# Task: Mandato: convention e regia insieme

- **ID**: T230
- **Size**: Mandate
- **Parent Task**:
- **Folder**:
- **Progress**: 🔵 Todo

## Description

Perché questo perimetro esiste e cosa vuole ottenere.

## Membri

- T52 (lettore unico delle convention)
- T61 (gate del deck sulle convention)
- T64 (regia headless)

## Preferenze d'ordine

- In questo giro prima le convention: T52 e T61 prima di T64.

## Analisi del perimetro

| Coppia | Relazione | Su cosa | Fonte |
|---|---|---|---|
| T61 → T52 | dipende | il gate legge il formato scritto da T52 | dichiarata |
| T52 · T64 | collide | `scripts/utils/lib.sh` | materiale |
| T61 · T64 | collide | entrambe riscrivono il poll del deck | modello |

## Materiale
*📖 fonte · 🔬 analisi · 📤 prodotto · 🎬 stato della regia; 📁/ = task folder. Solo materiale di alto rilievo, non l'inventario della folder.*

- 🎬 `.claude/loom/regia/T230.md` — seguire il giro della regia: conversazioni, fatti del perimetro, proposte in sospeso (fuori da git)
```

`## Materiale` non è una sezione propria del mandato: è quella del task template, e in un perimetro porta la voce 🎬 (§La voce 🎬).

### `## Membri`

- **Una riga per membro**, a colonna zero, che comincia con `- `. Vale il **primo `T<numero>`** della riga, il resto è la maniglia: `- T52 (maniglia)`, `- **T52** — maniglia` e ``- `T52` maniglia`` leggono tutte `T52`. È la stessa tolleranza del campo `**Parent Task**`.
- Righe indentate, righe senza id, righe dentro un blocco ```` ``` ```` e testo fuori dalla lista non contano: sono prosa.
- La sezione finisce al prossimo heading `#` o `##`. Un `###` la divide in gruppi senza chiuderla.
- L'ordine è quello del file. Un id ripetuto conta una volta, alla prima riga; il mandato che elenca sé stesso non conta.
- **Niente checkbox e niente stato.** Il `checkpoint-task` di un membro spunta solo la checkbox del suo `Parent Task`: una checkbox per membro nel mandato non ha custode e resta indietro alla prima chiusura. La checkbox per figlia nell'Acceptance di un'epica resta, perché lì il custode c'è.
- **Un'epica o un mandato fra i membri resta una riga sola.** Il lettore non lo sostituisce coi suoi membri: chi consuma lo tratta come un perimetro da orchestrare a parte. Così nessun ciclo fra mandati può nascere dal lettore. Il prezzo: «tutte le figlie di T40 più due orfane» si scrive elencando le figlie una per una, e una figlia nata dopo non entra da sola.

### `## Preferenze d'ordine`

L'ordine che vale **solo per questo perimetro** («in questo giro prima le convention»), in prosa o in lista. Facoltativa.

Le dipendenze vere non stanno qui: stanno in `## Dependencies` dei membri e nel grafo di `tasks.md`, perché valgono per ogni perimetro che contiene quei membri. Una dipendenza vera scritta solo nel mandato resta invisibile a chi lavora sulla task fuori dal mandato.

### `## Analisi del perimetro`

Le relazioni fra coppie di membri sull'intero perimetro. Ha **lo stesso nome e la stessa forma in un'epica**, così chi la cerca la cerca con un nome solo.

| Colonna | Dominio |
|---|---|
| `Coppia` | `T61 → T52` per una dipendenza (la prima dipende dalla seconda) · `T52 · T64` per una collisione |
| `Relazione` | `dipende` · `collide` |
| `Su cosa` | il dato, il file o il comportamento su cui la relazione morde |
| `Fonte` | `dichiarata` · `materiale` · `modello` |

- **`dichiarata`** — una dipendenza che un membro dichiara in `## Dependencies` o che il grafo di `tasks.md` porta: le righe `DEPS` di `scripts/regia/mandate.py tree`.
- **`materiale`** — due membri aperti che nominano path sovrapposti in `## Materiale`, e almeno uno dei due non come 📖 fonte: le righe `CONFLICT` di `mandate.py tree`. Due letture dello stesso file non si scontrano, e una voce 🎬 non conta: punta allo stato della regia, che nessun membro scrive.
- **`modello`** — una collisione che nessun campo dichiara, trovata leggendo i DLV dei membri.

Le righe `dichiarata` e `materiale` si ricalcolano dai file, quindi un confronto meccanico le verifica contro lo stato attuale: `scripts/regia/mandate.py verify`. Le righe `modello` vengono da una lettura, e si riesaminano quando un membro cambia. La sezione non porta sha né data: il commit da cui l'analisi vale si ricava dalla storia, ed è il più recente fra l'ultimo che ha cambiato le righe della sezione e l'ultimo `### Avanzamento` del perimetro.

Il metodo con cui la sezione si scrive e si riscrive — trascrizione delle righe di `tree`, lettura dei membri, rianalisi — è `mandate-analysis.md`.

### La voce 🎬

Il glifo 🎬, **stato della regia**, marca in `## Materiale` di un perimetro — mandato o epica — la voce che punta al file in cui la regia tiene il suo giro: `.claude/loom/regia/T<id>.md`, sotto la project root, ignorato da git. Il file porta conversazioni, fatti del perimetro e proposte in sospeso, e `checkpoint-mandate` ne porta i fatti nella prosa del perimetro.

- La scrive `prepare-mandate`, una volta sola; la regia non scrive nei task file.
- È un puntatore per chi legge il task file. La regia e `checkpoint-mandate` ricavano il path dall'id del perimetro, quindi un perimetro senza la voce viene seguito lo stesso.
- Il file può non esserci ancora: nasce al primo lancio della regia.

### Acceptance e Deliverables

Facoltativi: il formato non prescrive né `## Acceptance Criteria` né `## Deliverables Checklist`. Un mandato non ha lavoro proprio, e la sua chiusura è la sua Prog in `tasks.md`, non una derivazione dai membri.

## Nessuna copia di stato o di cifre

**Il file di un perimetro — mandato o epica — non copia niente che vive altrove:**

- niente colonna di stato dei membri: la Prog sta in `tasks.md`;
- niente cifre ricopiate da un membro (DLV spuntati, misure, conteggi): si scrive il puntatore al membro che le produce.

Una copia scritta a mano resta indietro alla prima modifica, chiunque sia il proprietario. Su un progetto reale, dopo una regia, quattro dei sei disallineamenti del cappello erano copie: lo stato delle figlie, lo stato di una task collegata, una cifra ricopiata da una figlia, un componente chiuso non segnato nello schema.

L'analisi del perimetro non è una copia: descrive relazioni fra membri, non il loro stato, e dichiara la fonte da cui si ricontrolla.

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

- **`TASK_MEMBERS_SRC=list`** quando l'header porta `- **Size**: Mandate`: i membri vengono da `## Membri`, nell'ordine del file.
- **`TASK_MEMBERS_SRC=parent`** su ogni altra task: i membri sono le figlie, in ordine numerico, con la stessa regola di `--children` (`T7` non matcha `T74`).
- **`TASK_MEMBER_MISSING=<id>`** — un membro dichiarato senza task file. Non entra nel conteggio e non ferma il lettore, exit 0: una task chiusa e purgata da `clean-tasks` è un caso normale, e chi consuma decide cosa farne.
- Un mandato senza `## Membri`, o con la sezione vuota, dà `TASK_MEMBERS_COUNT=0` ed exit 0. Il lettore **non ripiega sulle figlie**: i membri di un mandato sono la sua lista, e una task che nomina il mandato in `Parent Task` non ne diventa membro.

`--children` resta com'era: le figlie da `Parent Task`, anche su un mandato. Il calcolo vive in `lw_task_members` (`scripts/utils/lib.sh`); uno script che sourca `lib.sh` chiama la funzione, non il wrapper.
