# Gestione Documentazione

Contratto delle convenzioni doc: **cosa** è doc e **dove** va. *Come* si scrive è `writing-patterns.md`, che vale ovunque e non si ripete qui. Razionale, esempi e i criteri che richiedono di aprire una fonte: `${CLAUDE_PLUGIN_ROOT}/docs/doc-criteria.md` — aprilo quando un verdetto non è ovvio.

## I quattro layer

Regola unica: **la doc possiede solo il complemento di ciò che la fonte nativa del suo layer risponde da sé.** Duplicare è un puntare mancato.

- **online** — la **mappa** e la **carta**: dove passano i confini, quali regole vincolano il lavoro futuro. Si legge *prima* di sapere cosa chiedere. Caricata via `@-import` in `CLAUDE.md`.
- **offline** — il **perché** e l'**estraneo**: ciò che resta vero quando il codice cambia, e ciò che il codice non possiede. In `{docs_root}/reference/`, si apre quando hai già la domanda.
- **codice** — il manuale di ciò che possiedi. Non si duplica: **si punta**, con `file + simbolo` (mai `file:riga`, muore alla prima riga inserita sopra).
- **fonte viva** — inventario sempre fresco: un MCP su DB, `--help` di un CLI, uno schema servito, la suite di test. Non si copia: **si interroga**. Si punta col comando **più la forma della domanda giusta**.

Nei primi due la doc **è** la verità. Negli altri due la verità sta altrove, e copiarla dentro una fonte morta ha **valore negativo**: la copia compete con l'originale e vince, perché è più economica da leggere — il lettore prende la risposta vecchia.

**Quattro verdetti**, uno per nozione: `online` · `offline` · `→ codice` · `→ fonte viva`. I due rimandi hanno forma diversa e non sono intercambiabili.

## Il terzo layer — inbox

`{docs_root}/inbox/` tiene le nozioni **vere ma non ancora collocate**: un file per checkpoint, col TLDR sulla riga 3, indicizzato nell'INDEX come tutto il resto. Non è un quinto verdetto — è uno **stato di transizione** verso i quattro.

- **indicizzata** — senza TLDR resta fuori dall'INDEX, e un file inbox non indicizzato non ha ragione di esistere.
- **temporanea per contratto** — nasce per sparire. Un file inbox fermo da mesi è un fallimento del sistema, non uno stato stabile.
- **ha precedenza sul drift** — se contraddice un file di `reference/`, **vince l'inbox**: è più recente e nasce dal codice appena scritto. La regola non è scritta qui né dentro i file inbox — la cabla `build-index.sh` in testa alla sezione, così sparisce da sola quando l'inbox si svuota.

**La ridondanza in inbox è ammessa**: «è già scritto altrove» è un criterio dipendente (§Imbuto), e pretenderlo alla transizione rimetterebbe la lettura dell'intera doc dentro il checkpoint — il costo che l'inbox esiste per togliere.

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

Due coppie sono la stessa nozione a due stadi di maturazione: **scarto → sentenza** e **ipotesi → referto**. Confonderle fa entrare in doc materiale che non ha finito di muoversi.

Offline è poliedrico e ha **sette tipologie, ognuna col proprio confine** — referto · sentenza · trappola · manuale dell'estraneo · invariante · snodo · complemento della fonte viva. Servono a chi **colloca**, non a chi cattura: per esteso in `doc-criteria.md` §Le sette tipologie offline.

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

**I test non si pagano tutti nello stesso momento**, e il discriminante è da cosa dipende il verdetto.

- **indipendenti** — si rispondono guardando la nozione e chi l'ha scritta, senza aprire niente. Sono i soli che si applicano alla **transizione in inbox**: *sopravvive alla task* (fra sei mesi, senza sapere che è esistita la task che l'ha generata, la frase ha ancora senso?) · *costo di scoperta* (quanto è costato scoprirlo la prima volta? lo sa chi ha appena lavorato) · le nove parole riconoscibili dal testo — cronaca, intenzione, ipotesi, cantiere, scarto, cornice · il TLDR, che è forma.
- **dipendenti** — il verdetto sta fuori dalla frase: *eco*, *sorpresa* e *sopravvive al refactor* dipendono dal **codice** · *inventario* e *calco* dalla **fonte viva** · *fonte unica*, *online o offline*, *quale file* e le soglie del target dipendono dalla **doc**. Si pagano allo **smaltimento**, che apre quelle fonti una volta per batch invece di una per nozione.

La riga «costosa o sorprendente» ne mescola due: il costo di scoperta è indipendente, la sorpresa è una domanda sul codice e aspetta.

## Forma

- **Solo as-is**: presente indicativo, stato corrente. Niente date, task, PR inline.
- **Sostituisci, non appendere**: riscrivi la sezione toccata, non stratificare versioni. È così che un TLDR diventa un secondo documento.
- **Coordinate non opache**: ogni id porta una maniglia verbo+oggetto — `D07 (unificare docs-root)`, mai `D07` nudo.
- **Token-efficiente**: liste `- chiave: valore` invece di tabelle · niente separatori `---` · gerarchia per indentazione, non per heading annidati · header ogni 2-3 righe = rumore.
- I pattern di scrittura (claim in grassetto d'apertura, un'idea per blocco, nessun livello che ri-afferma) sono in `writing-patterns.md` e valgono qui senza essere ricopiati.

## Soglie

Numeri, non giudizi a runtime: due verifiche sullo stesso file devono dare lo stesso esito.

- **Split**: file ≥ **15.000 char**. Il taglio è **per perimetro** — due trigger di ricerca distinti = due file — mai per byte; ogni frammento nasce col proprio TLDR-ancora.
- **Merge**: file ≤ **3.000 char** → va **riesaminato**, non fuso d'ufficio: sopravvive se il suo perimetro di ricerca è distinto.
- **Regroup**: cartella ≥ **60.000 char** di figli diretti → i suoi file vanno in sottocartelle. Trigger **ricorsivo**, quindi la profondità emerge invece di essere decisa.
- **TLDR**: cap **600 char**, violazione **bloccante** — `build-index.sh` esce non-zero. Il TLDR finisce nell'INDEX, che è online: un TLDR prolisso si paga come se il file intero fosse online.
- **Inbox**: **8 file** → oltre, lo smaltimento non è più opzionale. La metrica è il **conteggio**, non i char: ogni file costa fino a 600 char di TLDR online a ogni sessione. Provvisorio, da tarare sull'esercizio.

Perché ogni numero è quello e non un altro: `doc-criteria.md` §Le cinque soglie.

## Chi scrive la doc

**La doc non si scrive a mano**: ogni scrittura passa da una skill, che porta con sé forma, soglie e le due formule del TLDR (`${CLAUDE_PLUGIN_ROOT}/docs/tldr-formats.md`).

- nozione ad hoc, fuori da una task → `capture-doc`
- voce `## Doc Impact` → il checkpoint, che la porta in inbox
- nozione in inbox → `drain-doc`, che la colloca
- doc esistente che mente o viola → `align-doc` · `lint-doc`

## Manutenzione

Tre skill, distinte da cosa fanno alla doc — `align-doc` **misura** contro la fonte nativa del layer (i **drift**) · `lint-doc` **misura** contro questo contratto (le violazioni) · `drain-doc` **colloca**, svuotando l'inbox e pagando i criteri dipendenti una volta per batch. Le due che misurano giudicano con `doc-auditor` read-only, `drain-doc` con `doc-router`; tutte applicano con `doc-writer` e chiudono uguale — guardiani deterministici, `doc-verifier` sul diff, commit. Le misure vengono da `scripts/docs/doc-metrics.sh`, mai da un giudizio a runtime. Perimetri, ordine delle fasi e regole del regroup: `doc-criteria.md` §Manutenzione.

**Nessun man-in-the-loop.** Le quattro skill di scrittura non chiedono di approvare una patch e non lasciano niente staged: il collaudo è `doc-verifier`, che etichetta ogni violazione `rollback` (l'ha causata questa patch) o `accodato` (l'ha solo rivelata — topologia, e la raccoglie la misura successiva).

**Tre operazioni topologiche**, due verticali e una orizzontale: **split** (un file oltre soglia diventa N) · **merge** (N file sotto il pavimento tornano uno) · **regroup** (N file in una sottocartella). Il regroup è la terza fase di `lint-doc`, in coda e **mai prima**: una categorizzazione dimensionata su file che stanno per essere spezzati nasce stale.

**Doc segue codice, stesso commit.** Nuovo file in `reference/` o in `inbox/` → rigenera l'indice con `scripts/docs/build-index.sh`.

## Origine D-task

Le task documentali (`D{N}`) nascono **solo on-demand**, via `/loom-works:doc-task`: nessun automatismo le genera. Soglia per aprirne una, e contratto parent-child: `doc-criteria.md` §Origine D-task.
