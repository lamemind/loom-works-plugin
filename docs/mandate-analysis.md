# L'analisi del perimetro e il piano — il metodo

Metodo per chi **scrive** `schedule.md`, il piano di un perimetro: `prepare-mandate` lo scrive prima del giro, da zero o rifacendo un piano che c'è già, e l'orchestrator lo riscrive durante il giro quando entra un membro o scopre una collisione. Forma del file, campi del blocco JSON e controlli di `verify`: `schedule-format.md`.

Il lavoro ha due tempi. Prima le **relazioni** fra i membri — chi dipende da chi, chi tocca gli stessi file —, che vanno nella prosa con la loro fonte. Poi le **decisioni** che ne discendono, che vanno nel blocco JSON: lo script del flusso legge solo il blocco, e una relazione che non diventa un campo per lo script non esiste.

Le relazioni hanno due metà, e servono entrambe:

- la **metà meccanica** viene da `mandate.py tree`, che legge i campi dichiarati dei membri: le dipendenze di `## Dependencies` e del grafo di `tasks.md`, e i path in comune nei `## Materiale`. Di `## Dependencies` conta il primo id di ogni voce a colonna zero, e una voce che comincia con «Nessuna» non dichiara niente anche se poi nomina una task («Nessuna. Non parte insieme a T211»): un vincolo «non insieme» è una collisione, e lo trova la metà del modello;
- la **metà del modello** trova le collisioni che nessun campo dichiara, per esempio due task spot che toccano lo stesso codice senza scriverlo nel `## Materiale`. Su quelle `tree` tace, e senza una risorsa nel piano lo script lancerebbe le due task in parallelo.

## L'ingresso

- **la testa** — l'id del perimetro, mandato o epica. Il suo task file deve esistere su disco, col campo `**Folder**`: `tree` senza file esce 1 (`ERROR: task file di T<n> non trovato`), e `verify` senza folder non trova il piano. Non serve che sia committato.
- **i membri** — quelli del lettore unico, `resolve-task.sh <testa> --members`: per un mandato la lista di `## Membri` già scritta sul disco, per un'epica le figlie. `verify` confronta il piano con quella lettura, quindi la lista va scritta nel task file prima del controllo.
- **le parole dell'utente** per questo giro: un ordine, un membro che segue lui, un perimetro di DLV (§Le preferenze dell'utente).
- **il piano vecchio**, quando c'è; oppure, in un perimetro preparato prima del piano, le sezioni `## Analisi del perimetro` e `## Preferenze d'ordine` del suo task file (§La rianalisi).

## La metà meccanica — da `mandate.py tree`

```bash
"PY" -B -I "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/mandate.py" tree <testa> --children <membri…>
```

`PY` è il primo fra `python3` e `python` che risponde con Python 3. Le righe che servono:

| Riga | Cosa dà all'analisi |
|---|---|
| `TASK\|<id>\|…\|next=…\|blocked=…\|…` | `next=chiusa` → membro chiuso. `blocked=` → le dipendenze aperte del membro, dentro e fuori dal perimetro |
| `DEPS\|<id>\|T52 🟢 (deps) · T40 ✔ (grafo)` | il verso di ogni dipendenza, e da dove viene |
| `CONFLICT\|<a>\|<b>\|dipendenza` | una dipendenza fra due membri aperti |
| `CONFLICT\|<a>\|<b>\|materiale: <path>, …` | un path in comune fra due membri aperti, che almeno uno dei due scrive |

`tree` stampa una riga `CONFLICT` solo fra due membri ancora aperti: una task chiusa non riparte, e un suo conflitto non ferma nessuno.

**Ogni riga `CONFLICT` diventa una riga di prosa e un campo del blocco.** È la proprietà che `verify` controlla: ricalcola le stesse righe dai file e stampa un `DIFF` per ognuna che il blocco non copre.

- **`dipendenza`** → il verso viene da `DEPS`: A dipende da B se le `DEPS` di A nominano B. La prosa: `- T61 dipende da T52: <la voce di ## Dependencies di T61, accorciata> (## Dependencies di T61)`, o `(grafo di tasks.md)` per una freccia che viene solo dal grafo. Il blocco: `"dopo": ["T52"]` in T61. Se la voce nomina dei DLV precisi di B («serve il DLV2 di T52»), il `dopo` è `"T52:2"`, e B prende `"dlv": "2"`: il suo primo ciclo fa solo quei DLV, e A parte prima della fine di B.
- **Due membri che si dichiarano a vicenda** sono un ciclo, e nessun piano lo scioglie: `verify` vuole i due `dopo`, e lo script terrebbe fermi tutti e due. La prosa lo scrive, e alla conferma è un difetto dei due task file da correggere prima del giro.
- **`materiale: <path>`** → la prosa: ``- T52 e T64 scrivono `scripts/utils/lib.sh` (## Materiale dei due)``; se uno dei due dichiara il path come 📖 fonte, la riga lo dice. Il blocco: una risorsa in comune, col nome del path, nei due membri. Un `dopo` fra i due già scritto, per una dipendenza o una preferenza, basta da solo: due membri in fila non girano mai insieme.
- **Una dipendenza verso una task chiusa** non scrive niente.
- **Una dipendenza aperta verso una task fuori dal perimetro** — un id in `blocked=` che non è fra i membri — scrive una riga di prosa, `- T61 aspetta T70, fuori dal perimetro (## Dependencies di T61)`, e niente nel blocco: lo script la legge da `tree` e ferma il membro finché T70 non chiude. Se la voce nomina dei DLV di T70, il `dopo` può portare `"T70:2"`, e il membro parte quando quei DLV sono spuntati. Alla conferma si offre di aggiungere T70 ai membri; in un'epica l'offerta non c'è, perché le figlie le decide il `Parent Task` della figlia, e si dice che per seguirla insieme serve un mandato.

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

**Cosa entra nel piano**: una collisione solo quando l'oggetto è concreto — un file, un simbolo, un comportamento che tutti e due nominano. «Potrebbero interferire» non è una collisione. Se la metà meccanica dice già la stessa cosa per quella coppia — lo stesso path, o una dipendenza dichiarata — non si ripete.

- **Una collisione** → la prosa: `- T61 e T70 riscrivono il poll del deck: nessun campo lo dichiara`. Il blocco: una risorsa in comune, col nome dell'oggetto (`"poll del deck"`, o il path del file).
- **Una dipendenza non dichiarata** — A legge ciò che B scrive, e A non dichiara B → la prosa: `- T61 legge il formato che scrive T52: dipendenza non dichiarata`. Il blocco: `"dopo": ["T52"]` in T61, subito, perché lo script legge l'ordine solo dal piano. La dipendenza vera appartiene a `## Dependencies` di T61, che chi scrive il piano non tocca: alla conferma si chiede a chi lavora su T61 di dichiararla.

## Le risorse del ciclo di lavoro

Oltre ai file, un ciclo di lavoro occupa ciò che il suo run fa fuori dal codice. Si leggono dai DLV e dalla Description dei membri aperti, e prendono un nome fisso, perché la risorsa vale solo se due membri la scrivono uguale:

| Risorsa | Quando un membro la prende | Perché due cicli non la condividono |
|---|---|---|
| `publish-plugin` | un DLV pubblica il plugin (`publish-plugin.sh`, un bump) | il publish committa tutto il working tree del plugin: un rilascio porterebbe fuori il lavoro a metà dell'altro run |
| `release-deck` | un DLV rilascia il deck (publish npm, tag) | stessa ragione, sul repo del deck |
| `build-deck` | un DLV builda o collauda il deck (`npm test`, gate pty) | i gate pty avviano il deck dalla build: una build dell'altro run cambia il codice sotto un collaudo in corso |

Una riga di prosa in `## Ordine` dice perché ogni risorsa c'è: `- T52 e T64 pubblicano il plugin: risorsa publish-plugin`. Un nome fuori da questa tabella è ammesso — un comportamento, un servizio condiviso — se due membri lo scrivono uguale.

## Le preferenze dell'utente

Le preferenze d'ordine valgono **solo per questo giro** e le dice l'utente. Ognuna diventa una riga di prosa in `## Ordine`, con le sue parole nella sostanza, e un campo del blocco:

| L'utente dice | Il blocco |
|---|---|
| «prima T52, poi T64» | `"dopo": ["T52"]` in T64 |
| «T255 per ultima» | `"dopo": ["*"]` in T255 |
| «T245 la seguo io» | `"umano": true` in T245 |
| «di T21 in questo giro solo il DLV2» | `"dlv": "2"` in T21 |
| «T64 parte dal run, senza preflight» | `"passo": "run"` in T64 — solo su una S o una M: `run-task` rifiuta il run su una L senza preflight, e `verify` lo ferma |
| «T21 riparte dal checkpoint» | `"passo": "checkpoint"` in T21 |

**L'ordine dei membri nel blocco** è la preferenza a parità di condizioni: fra due membri pronti lo script lancia prima quello che sblocca più membri, poi il primo nel blocco. Senza parole dell'utente vale l'ordine del lettore.

**Una dipendenza vera non è una preferenza.** Se l'utente dice «T61 ha bisogno del formato di T52», la dipendenza va in `## Dependencies` di T61: entra nel `dopo` come una dipendenza non dichiarata (§La metà del modello), e la conferma lo dice.

## Il file scritto

````markdown
# Piano di T<testa> — <tema>

## Analisi del perimetro

- <una relazione per riga, con la fonte fra parentesi>

## Ordine

- <una preferenza o una risorsa per riga, col perché>

## Piano

```json
{"perimetro": "T<testa>", "membri": [ … ]}
```
````

- **La prosa dell'analisi**, in quest'ordine: le dipendenze dichiarate, i path in comune, le collisioni del modello, le dipendenze aperte fuori dal perimetro; dentro ogni gruppo, per posizione nella lista del primo membro nominato. Nessuna relazione → una riga sola: `Nessuna relazione fra i membri aperti.`
- **`## Ordine`** c'è solo se c'è una preferenza o una risorsa da spiegare.
- **Il blocco** porta una voce per ogni membro del lettore, nell'ordine scelto: i membri chiusi, i membri epica o mandato e i `TASK_MEMBER_MISSING` compresi, con il solo `id`. `verify` li conta, e lo script non lancia niente su di loro.
- **Niente sha, niente data, niente Prog, niente cifre**: il piano descrive relazioni e decisioni, non lo stato dei membri.
- **Si riscrive intero** a ogni rianalisi.

Scritto il file, il controllo:

```bash
"PY" -B -I "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/schedule.py" verify <testa> --bozza
```

`VERIFY=ok` → il piano copre ogni relazione meccanica. Un `ERRORE` è un blocco scritto male; un `DIFF` è una relazione che non è diventata un campo: si corregge il piano e si rilancia, prima di mostrarlo a nessuno. Un `AVVISO` su un `passo` vuol dire che i file lo hanno già superato: il campo si toglie.

## La rianalisi

Quando un piano c'è già, il piano si rifà **intero**, col vecchio in ingresso:

- le relazioni meccaniche si ricalcolano da `tree`: quelle vecchie non contano;
- ogni collisione del modello vecchia viene **confermata** (stesso testo), **riscritta** (testo nuovo, con la ragione) o **tolta** (con la ragione: membro chiuso, membro tolto, il task file non nomina più quel file). Nessuna sparisce in silenzio;
- le preferenze dell'utente restano, salvo che l'utente le cambi o che nominino un membro tolto;
- un `dlv` resta se i suoi DLV sono ancora aperti; un `passo` resta se `verify --bozza` non lo dà superato;
- le coppie nuove, quelle di un membro aggiunto, passano dalla metà del modello da zero.

**Un perimetro preparato prima del piano** porta nel task file la tabella `## Analisi del perimetro` e, in un mandato, `## Preferenze d'ordine`. Le righe con fonte `modello` della tabella sono le collisioni del modello vecchie da confermare, riscrivere o togliere; quelle `dichiarata` e `materiale` si ricalcolano; ogni voce delle preferenze diventa una preferenza. Le due sezioni escono dal task file nello stesso commit che scrive il piano: due copie resterebbero disallineate alla prima modifica.

Alla conferma la differenza si mostra riga per riga, sulla prosa e sul blocco:

```
= T52 e T64 scrivono `scripts/utils/lib.sh` (## Materiale dei due)
+ T61 e T70 riscrivono il poll del deck: nessun campo lo dichiara
- T52 e T58 scrivono `docs/tasks.md` — T58 tolta dai membri
~ T61 e T64 scrivono `src/hooks.ts` — T64 non nomina più `src/sessions.ts`
~ T64 dopo=T52 → dopo=T52,T61 · risorse=publish-plugin → publish-plugin,poll del deck
```

## I punti ciechi

Si dicono alla conferma, mai nel piano:

- i membri aperti che non nominano nessun file: una loro collisione resta invisibile anche dopo l'analisi;
- i membri epica o mandato: le collisioni dei loro membri non sono analizzate qui.
