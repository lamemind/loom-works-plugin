# Gestione Documentazione

Contratto delle convenzioni doc. Razionale, esempi e i test per esteso: `${CLAUDE_PLUGIN_ROOT}/docs/doc-criteria.md` — aprilo quando un verdetto non è ovvio.

## I quattro layer

Regola unica: **la doc possiede solo il complemento di ciò che la fonte nativa del suo layer risponde da sé.** Duplicare è un puntare mancato.

- **online** — la **mappa** e la **carta**: dove passano i confini, quali regole vincolano il lavoro futuro. Si legge *prima* di sapere cosa chiedere. Caricata via `@-import` in `CLAUDE.md`.
- **offline** — il **perché** e l'**estraneo**: ciò che resta vero quando il codice cambia, e ciò che il codice non possiede. In `{docs_root}/reference/`, si apre quando hai già la domanda.
- **codice** — il manuale di ciò che possiedi. Non si duplica: **si punta**, con `file + simbolo` (mai `file:riga`, muore alla prima riga inserita sopra).
- **fonte viva** — inventario sempre fresco: un MCP su DB, `--help` di un CLI, uno schema servito, la suite di test. Non si copia: **si interroga**. Si punta col comando **più la forma della domanda giusta**.

Nei primi due la doc **è** la verità. Negli altri due la verità sta altrove, e copiarla dentro una fonte morta ha **valore negativo**: la copia compete con l'originale e vince, perché è più economica da leggere — il lettore prende la risposta vecchia.

**Quattro verdetti**, uno per nozione: `online` · `offline` · `→ codice` · `→ fonte viva`. I due rimandi hanno forma diversa e non sono intercambiabili.

## Cronaca — cosa non va in doc

Nove parole per il materiale che ha un custode legittimo altrove:

- **cronaca** — la sequenza degli eventi, il prima/dopo → git, Progress Log
- **intenzione** — cosa si voleva ottenere → task file
- **ipotesi** — previsione fatta prima di lavorare → task file (`Doc Impact`)
- **cantiere** — materiale grezzo, dump, protocolli → task folder
- **scarto** — provato e buttato, motivazione non stabile → task folder
- **eco** — la doc che ripete il sorgente → si cancella, resta il puntatore
- **inventario** — elenchi, conteggi, colonne, campi, flag → codice o fonte viva
- **calco** — copia di una fonte che continua a muoversi → fonte viva
- **cornice** — preambolo che situa il documento invece di consegnarlo: negazione preventiva, auto-referenza, giustificazione del meccanismo → si cancella

Due coppie sono la stessa nozione a due stadi di maturazione, non due sinonimi: **scarto → sentenza** e **ipotesi → referto**. Confonderle fa entrare in doc materiale che non ha finito di muoversi.

## Offline — sette tipologie, sette confini

Ogni tipologia ha un confine proprio: applicarne uno solo lascia entrare tutto il resto.

- **referto** — risultato d'indagine, misure, benchmark. *Confine*: il numero e la conclusione; il protocollo è cantiere.
- **sentenza** — scelta con motivazione **definitiva**, alternative bocciate. *Confine*: definitiva; se può riaprirsi è scarto. Non driftà mai.
- **trappola** — ciò che sorprende chi legge il codice con competenza. *Confine*: deve **violare un'aspettativa ragionevole**; se la conferma, è eco.
- **manuale dell'estraneo** — sistemi che non possiedi; il manuale di ciò che possiedi **è il codice**. *Confine*: solo ciò che **hai scoperto tu** e la doc ufficiale non dice, dice male o dice falso. La doc ufficiale è a sua volta una fonte: si punta.
- **invariante** — la regola che nessun singolo file afferma. *Confine*: alla doc il perché, a un **test** il controllo.
- **snodo** — di una procedura, i punti di decisione e il perché dell'ordine. *Confine*: i passi meccanici sono uno **script**, quindi layer codice. Procedura scriptabile non ancora scritta → il verdetto è "scrivila", non "documentala".
- **complemento della fonte viva** — che esiste, come si accede, quali domande fargli, cosa non risponde. *Confine*: mai l'inventario; la forma della query sì, il risultato mai.

## Imbuto di selezione

Dal filtro più economico. I primi tre decidono **se**, gli ultimi quattro **dove** e **come tenerla viva**.

```
sopravvive alla task?          no → non scriverla
sopravvive al refactor?        no → → codice
costosa o sorprendente?        no → taglia, il codice basta
   (è doc: da qui si colloca, non si taglia più)
serve prima della domanda?     sì → online    no → offline
è già scritto altrove?         sì → una fonte muore
con che query la trovo?        → il file e il punto di taglio
come si accorge che è falsa?   → invariante: asseriscila in un test
```

## Forma

- **Solo as-is**: presente indicativo, stato corrente. Niente date, task, PR inline.
- **Sostituisci, non appendere**: riscrivi la sezione toccata, non stratificare versioni. È così che un TLDR diventa un secondo documento.
- **Coordinate non opache**: ogni id porta una maniglia verbo+oggetto — `D07 (unificare docs-root)`, mai `D07` nudo.
- **Token-efficiente**: liste `- chiave: valore` invece di tabelle · H2 da una riga → `**Titolo.** testo` · niente separatori `---` · gerarchia per indentazione, non per heading annidati · header ogni 2-3 righe = rumore.

## Soglie

Numeri, non giudizi a runtime: due verifiche sullo stesso file devono dare lo stesso esito.

- **Split**: file ≥ **15.000 char** → va splittato. Il taglio è **per perimetro** (lo decide la reperibilità: due trigger di ricerca distinti = due file), mai per byte; ogni frammento nasce col proprio TLDR-ancora.
- **TLDR**: cap **600 char**, violazione **bloccante** — `build-index.sh` esce non-zero oltre soglia. Il TLDR finisce nell'INDEX, che è online: un TLDR prolisso si paga come se il file intero fosse online.

## Formato file offline

Il TLDR sta **esattamente sulla riga 3**, o il file resta fuori dall'indice:

```markdown
# Titolo

> **TLDR**: <ancora primaria>

Contenuto dettagliato...
```

**Il TLDR è un'ancora, non un riassunto**: deve far decidere *se aprire* il file, non risparmiare l'apertura. Trigger concreti separati da `·` — comando, flag, tag, pattern, messaggio d'errore, frase con cui uno cercherebbe la cosa.

- ✅ `deck-run --resume · sidecar session-tasks.jsonl · "bindare una task a una sessione"`
- ❌ `Descrive il funzionamento del deck e le sue interazioni con le sessioni.`

## Manutenzione

Due skill gemelle, distinte dalla fonte di verità contro cui misurano:

- `align-doc` — misura contro la **fonte nativa del layer** (il sorgente, oppure la query viva) → i **drift**. Un drift è peggio di una lacuna: chi si fida agisce su una realtà inesistente e nessun segnale glielo dice.
- `lint-doc` — misura contro **questo contratto** → le violazioni (soglie, TLDR-riassunto, layer sbagliato, cronaca persistita). Non apre mai i sorgenti.

Entrambe girano su `doc-auditor` read-only, N perimetri in parallelo; applica `doc-writer`. Le misure vengono da `scripts/docs/doc-metrics.sh`, mai da un giudizio a runtime.

**Doc segue codice, stesso commit.** Nuovo file in `reference/` → rigenera l'indice con `scripts/docs/build-index.sh` (opzioni: `--help`).

## Origine D-task

Le task documentali (`D{N}`) nascono via `/loom-works:doc-task` — spot, nessun parent — oppure dal gate al checkpoint di una code task con `## Doc Impact` non vuoto, e allora il D-file porta `**Parent Task**: T{N}` e il parent ha `- [ ] D{N} (<maniglia>) chiusa` in Acceptance. Task e lane: [Task Management](./task-management.md).
