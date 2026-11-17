# L'analisi del perimetro — il metodo

Metodo per chi **scrive** la sezione `## Analisi del perimetro` di un mandato o di un'epica: `prepare-mandate` la scrive da zero, e chi la riscrive quando un membro l'ha smentita usa lo stesso metodo. Forma della tabella, colonne e domini: `mandate-format.md` §`## Analisi del perimetro`.

L'analisi ha due metà, e servono entrambe:

- la **metà meccanica** viene da `mandate.py tree`, che legge i campi dichiarati dei membri: le dipendenze di `## Dependencies` e del grafo di `tasks.md`, e i path in comune nei `## Materiale`;
- la **metà del modello** trova le collisioni che nessun campo dichiara, per esempio due task spot che toccano lo stesso codice senza scriverlo nel `## Materiale`. Su quelle `tree` tace, e una regia lancerebbe le due task in parallelo.

## L'ingresso

- **la testa** — l'id del perimetro, mandato o epica. Il suo task file deve esistere su disco: `tree` senza esce 1 (`ERROR: task file di T<n> non trovato`). Non serve che sia committato.
- **i membri** — per un mandato la lista che si sta scrivendo, che può non essere ancora quella su disco; per un'epica le figlie, da `resolve-task.sh <epica> --members`.
- **la tabella vecchia**, quando la sezione esiste già (§La rianalisi).

## La metà meccanica — da `mandate.py tree`

```bash
"PY" -B -I "${CLAUDE_PLUGIN_ROOT}/scripts/regia/mandate.py" tree <testa> --children <membri…>
```

`PY` è il primo fra `python3` e `python` che risponde con Python 3. Le righe che servono:

| Riga | Cosa dà all'analisi |
|---|---|
| `TASK\|<id>\|…\|next=…\|blocked=…\|…` | `next=chiusa` → membro chiuso, fuori dalla tabella. `blocked=` → le dipendenze aperte del membro, dentro e fuori dal perimetro |
| `DEPS\|<id>\|T52 🟢 (deps) · T40 ✔ (grafo)` | il verso di ogni dipendenza, e da dove viene |
| `CONFLICT\|<a>\|<b>\|dipendenza` | una riga `dipende`, fonte `dichiarata` |
| `CONFLICT\|<a>\|<b>\|materiale: <path>, …` | una riga `collide`, fonte `materiale` |

`tree` stampa una riga `CONFLICT` solo fra due membri ancora aperti: una task chiusa non riparte, e un suo conflitto non ferma nessuno.

**Regole di trascrizione:**

- **Ogni riga `CONFLICT` diventa una riga della tabella, e nessuna riga `dichiarata` o `materiale` esiste senza la sua `CONFLICT`.** È la proprietà che rende la metà meccanica verificabile con un confronto, alla partenza della regia: le stesse righe si ricalcolano dai file.
- **`dipendenza`** → il verso viene da `DEPS`: `A → B` se le `DEPS` di A nominano B. Se si nominano a vicenda, due righe. `Su cosa` è la prosa della voce di `## Dependencies` di A che nomina B, accorciata; per una freccia che viene solo dal grafo, «grafo di `tasks.md`».
- **`materiale: <path>`** → `A · B`, coi membri nell'ordine della lista. `Su cosa` porta i path fra backtick. Se uno dei due dichiara il path come 📖 fonte, cioè lo legge e basta, `Su cosa` lo dice — la riga resta, perché `tree` la calcola e il confronto la conta.
- **Una dipendenza verso una task chiusa** non entra in tabella.
- **Una dipendenza aperta verso una task fuori dal perimetro** — un id in `blocked=` che non è fra i membri — non entra in tabella: si mostra alla conferma, con l'offerta di aggiungere la task ai membri. In un'epica l'offerta non c'è, perché le figlie le decide il `Parent Task` della figlia: alla conferma si dice che per seguirla insieme serve un mandato.

Ne discende una conseguenza per chi confronta: quando un membro chiude, le sue righe restano scritte nella tabella e `tree` smette di stamparle. Una riga il cui membro è ✔️ non è una divergenza.

## La metà del modello — le collisioni non dichiarate

**Cosa legge**: il task file di ogni membro aperto, **per intero** — Description, Deliverables, `## Materiale`, Decisions, Implementation Notes. Non legge i membri chiusi, che non ripartono, né i membri di un membro epica o mandato: quello è un perimetro a sé, e il lettore non lo espande.

**Il procedimento:**

1. **L'impronta di ogni membro aperto**: i file e le cartelle che nomina in qualunque punto del task file, non solo nel `## Materiale`; i simboli che nomina (funzioni, script, skill, sezioni di un documento, campi di configurazione); i comportamenti che dichiara di riscrivere («il poll del deck», «il commit del checkpoint»).
2. **Il confronto per coppia.** Lo stesso file, o una cartella che contiene il file dell'altro → collisione su quel file. Un simbolo nominato da un membro e un path nominato dall'altro → si cerca il simbolo nel repo per sapere in quale file vive:

   ```bash
   git grep -l -F --recurse-submodules -- '<simbolo>'
   ```

   Se il file trovato è il path dell'altro membro, la collisione è su quel file. Due simboli diversi si cercano allo stesso modo, per vedere se cadono nello stesso file.
3. **Lo stesso comportamento** riscritto da tutti e due, detto in prosa → collisione sul comportamento.

La ricerca nel repo si fa **solo sui path e sui simboli che due membri nominano**. Il codice non si esplora per i membri che non nominano file: la ricerca resta proporzionata al perimetro, e il prezzo è un punto cieco dichiarato (sotto).

**Lo stesso file basta, anche su righe lontane.** Due sessioni nello stesso worktree che toccano lo stesso file si rubano le modifiche al commit: la pathspec del commit prende il file intero, e chi committa per primo porta con sé il lavoro a metà dell'altra.

**Cosa entra in tabella**: una riga `A · B | collide | <su cosa> | modello` solo quando

- l'oggetto è concreto: un file, un simbolo, un comportamento che tutti e due nominano. «Potrebbero interferire» non è una riga;
- la metà meccanica non dice già la stessa cosa per quella coppia: lo stesso path in una riga `materiale`, o una dipendenza già dichiarata.

**Una dipendenza non dichiarata** — A legge ciò che B scrive, e A non dichiara B — entra come `collide`, con il verso detto in `Su cosa`: «T61 legge il formato che scrive T52, dipendenza non dichiarata». La dipendenza vera appartiene a `## Dependencies` di A, che l'analisi non scrive: alla conferma si dice a chi lavora su A di dichiararla.

**I punti ciechi**, detti alla conferma e mai scritti in tabella:

- i membri aperti che non nominano nessun file: una loro collisione resta invisibile anche dopo l'analisi;
- i membri epica o mandato: le collisioni dei loro membri non sono analizzate qui.

## La sezione scritta

- **Ordine delle righe**: prima `dichiarata`, poi `materiale`, poi `modello`; dentro ogni fonte, per posizione nella lista del primo membro della coppia.
- **Nessuna relazione** → la sezione porta una riga sola: `Nessuna relazione fra i membri aperti.`
- **Niente sha, niente data, niente Prog**: la sezione descrive relazioni fra membri, non il loro stato.
- **Si sostituisce intera** a ogni riscrittura.

## La rianalisi

Quando la sezione esiste già, l'analisi si rifà **intera**, con la tabella vecchia in ingresso:

- le righe `dichiarata` e `materiale` si ricalcolano da `tree`: quelle vecchie non contano;
- ogni riga `modello` vecchia viene **confermata** (stesso testo), **riscritta** (testo nuovo, con la ragione) o **tolta** (con la ragione: membro chiuso, membro tolto, il task file non nomina più quel file). Nessuna sparisce in silenzio;
- le coppie nuove, quelle di un membro aggiunto, passano dalla metà del modello da zero.

Alla conferma la differenza si mostra riga per riga:

```
= T52 · T64 | collide | `scripts/utils/lib.sh` | materiale
+ T61 · T70 | collide | entrambe riscrivono il poll del deck | modello
- T52 · T58 | collide | `docs/tasks.md` | modello — T58 tolta dai membri
~ T61 · T64 | collide | `src/hooks.ts` | modello — T64 non nomina più `src/sessions.ts`
```
