# Gestione Documentazione

Contratto delle convenzioni doc: **cosa** è doc e **dove** va. *Come* si scrive non sta qui: alla chat lo dà l'output style, agli agent il contratto editoriale inline nel loro body.

## Il paradigma: la doc è l'as-is di prod

Il codice cambia da più fonti — le task, i merge altrui, i commit spot — e un commit non è un rilascio. **La doc descrive prod.** Le nozioni emerse restano della task finché la feature non è materializzata, riesaminate a ogni checkpoint; la chiusura le rende drenabili; il drain le colloca. La cronaca sta in git, l'intenzione nel task file, il cantiere nella task folder, lo sviluppo non rilasciato negli inbox di branch.

## I quattro layer

Regola unica: **la doc possiede solo il complemento di ciò che la fonte nativa del suo layer risponde da sé.** Duplicare è un puntare mancato.

- **online** — la **mappa** e la **carta**: dove passano i confini, quali regole vincolano il lavoro futuro. Si legge *prima* di sapere cosa chiedere. Caricata via `@-import` in `CLAUDE.md`.
- **offline** — il **perché** e l'**estraneo**: ciò che resta vero quando il codice cambia, e ciò che il codice non possiede. In `{docs_root}/reference/`, si apre quando hai già la domanda.
- **codice** — il manuale di ciò che possiedi. Non si duplica: **si punta**, con `file + simbolo` (mai `file:riga`, muore alla prima riga inserita sopra).
- **fonte viva** — inventario sempre fresco: un MCP su DB, `--help` di un CLI, uno schema servito, la suite di test. Non si copia: **si interroga**. Si punta col comando **più la forma della domanda giusta**.

Nei primi due la doc **è** la verità. Negli altri due la verità sta altrove, e copiarla dentro una fonte morta ha **valore negativo**: la copia compete con l'originale e vince, perché è più economica da leggere — il lettore prende la risposta vecchia.

**Quattro verdetti**, uno per nozione: `online` · `offline` · `→ codice` · `→ fonte viva`. I due rimandi hanno forma diversa e non sono intercambiabili.

## L'inbox — stato di transizione

`{docs_root}/inbox/` tiene i file in attesa di smaltimento. Non è un quinto verdetto: è uno **stato di transizione** verso i quattro. Tre nature, dichiarate dal marker in riga 3 del file (`nozioni` · `derivazione` · `sweep`); il formato e il vocabolario dei token sono degli script (`scripts/docs/inbox.sh`), mai di un prompt.

- **`drainable` è un passaggio di proprietà.** Senza il token l'owner è la task che scrive il file: nessun consumer lo prende, quindi non c'è consistenza da proteggere e il corpo si appende, si riscrive e si pota a ogni checkpoint (`inbox-format.md`). Col token il file passa al sistema documentale e **si congela**: da lì le uniche scritture sono il marker (`pull-repos`) e il registro del drain.
- **Una task, un inbox**: il primo trasloco lo crea, e da lì è l'unica sede delle nozioni di quella task. Un file per trasloco moltiplicherebbe i file senza moltiplicare il contenuto, e il costo del drain scala col numero di file.
- **Accumulo libero**: nessun cap sulla coda, nessuna soglia che blocchi. Sul singolo file il checkpoint conta le nozioni e stampa un avviso sopra `LW_DOC_INBOX_NOZIONI` (`lib-doc.sh`), senza tagliare né splittare.
- **Due stati, due semantiche.** Un file **drainable** descrive un rilascio che la doc consolidata non ha ancora assorbito: se contraddice `reference/`, **vince l'inbox**. Un file **non-drainable** descrive lavoro in corso, che il checkpoint successivo può smentire: è **inconsistenza, non precedenza** — a disposizione, non garantito, e si legge insieme alla task che lo scrive. `build-index.sh` li tiene in due sezioni distinte.
- **`branch:<nome>`** qualifica *per chi* la nozione è vera: la precedenza vale solo per chi lavora su quel branch, per chi sta su prod non conta niente. Non congela il file per la task che ne è owner.
- **Esente da split e merge**: un file inbox aggrega un trasloco e nasce per morire al drain.
- La ridondanza in inbox è ammessa: «è già scritto altrove» è un criterio dipendente e si paga allo smaltimento, non alla transizione.

## Cosa non va in doc

Nove parole per il materiale che ha un custode legittimo altrove:

- **cronaca** — la sequenza degli eventi, il prima/dopo → git, Progress Log
- **intenzione** — cosa si voleva ottenere → task file
- **ipotesi** — previsione fatta prima di lavorare → task file (`Doc Impact`)
- **cantiere** — materiale grezzo, dump, protocolli → task folder
- **scarto** — provato e buttato, motivazione non stabile → task folder
- **eco** — la doc che ripete il sorgente → si cancella, resta il puntatore
- **inventario** — elenchi, conteggi, colonne, campi, flag → codice o fonte viva
- **calco** — copia di una fonte che continua a muoversi → fonte viva
- **cornice** — preambolo che situa il documento invece di consegnarlo → si cancella

Due coppie sono la stessa nozione a due stadi di maturazione: **scarto → sentenza** e **ipotesi → referto**. Confonderle fa entrare in doc materiale che non ha finito di muoversi.

## Imbuto — i criteri indipendenti

Si rispondono guardando la sola nozione, senza aprire niente, e sono i soli che si applicano **al riesame e al trasloco**:

```
sopravvive alla task?          no → non scriverla
costata scoprirla?             no → taglia, il codice basta
le nove parole                 riconoscibili dal testo
```

Tutti gli altri — *eco*, *sorpresa*, *sopravvive al refactor* (dipendono dal codice) · *inventario*, *calco* (dalla fonte viva) · *già scritto*, *online o offline*, *quale file*, *noto* (dalla doc e dalla competenza di progetto) — sono **dipendenti**: li paga il drain, aprendo quelle fonti una volta per file inbox invece che una per nozione. Pretenderli prima rimetterebbe la lettura dell'intera doc dentro il checkpoint.

`noto` si misura contro la competenza **di progetto** (`{docs_root}/reference/assumed-knowledge.md`, §Project assumed knowledge), mai contro quella di chi lancia.

## Chi scrive la doc

**La doc non si scrive a mano**: ogni scrittura passa da una skill.

- nozione emersa in una task → vive nella sede che il task file dichiara (`## Doc Impact`, poi l'inbox della task dal primo trasloco), **riesaminata** a ogni checkpoint (`checkpoint-task`)
- file inbox `nozioni` drainable → `drain-notions` (router → writer → validator, registro nel file)
- file inbox `derivazione` → `derive-notions` (dal diff a un file `nozioni` nuovo)
- file inbox `sweep` → `align-doc` (estrazione + stesura, su branch `doc/sweep-<slug>` con PR)
- topologia (split · merge · regroup) → `rebalance-doc`, sui flag di `doc-metrics.sh`

Le soglie vivono negli **script**, mai nei prompt: chi decide legge i flag dall'output. Nessun man-in-the-loop nei flussi non presidiati; l'unico presidio dello sweep è la review della PR.

**La doc segue il rilascio.** Atomicità richiesta: inbox + doc derivata nello stesso commit di drain; codice + task file nel checkpoint. Nuovo file in `reference/` o in `inbox/` → rigenera l'indice con `scripts/docs/build-index.sh`.
