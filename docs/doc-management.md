# Gestione Documentazione

Contratto delle convenzioni doc: **cosa** è doc e **dove** va. *Come* si scrive non sta qui: alla chat lo dà l'output style.

## Il paradigma: la doc è l'as-is di prod

Il codice cambia da più fonti — le task, i merge altrui, i commit spot — e un commit non è un rilascio. **La doc descrive prod.** Le nozioni emerse restano della task finché la feature non è materializzata, riesaminate a ogni checkpoint; la chiusura le congela nell'inbox della task, dove restano indicizzate. La cronaca sta in git, l'intenzione nel task file, il cantiere nella task folder, lo sviluppo non rilasciato negli inbox di branch.

## I quattro layer

Regola unica: **la doc possiede solo il complemento di ciò che la fonte nativa del suo layer risponde da sé.** Duplicare è un puntare mancato.

- **online** — la **mappa** e la **carta**: dove passano i confini, quali regole vincolano il lavoro futuro. Si legge *prima* di sapere cosa chiedere. Caricata via `@-import` in `CLAUDE.md`.
- **offline** — il **perché** e l'**estraneo**: ciò che resta vero quando il codice cambia, e ciò che il codice non possiede. In `{docs_root}/reference/`, si apre quando hai già la domanda.
- **codice** — il manuale di ciò che possiedi. Non si duplica: **si punta**, con `file + simbolo` (mai `file:riga`, muore alla prima riga inserita sopra).
- **fonte viva** — inventario sempre fresco: un MCP su DB, `--help` di un CLI, uno schema servito, la suite di test. Non si copia: **si interroga**. Si punta col comando **più la forma della domanda giusta**.

Nei primi due la doc **è** la verità. Negli altri due la verità sta altrove, e copiarla dentro una fonte morta ha **valore negativo**: la copia compete con l'originale e vince, perché è più economica da leggere — il lettore prende la risposta vecchia.

**Quattro verdetti**, uno per nozione: `online` · `offline` · `→ codice` · `→ fonte viva`. I due rimandi hanno forma diversa e non sono intercambiabili.

## La base di un path

Un path in doc dichiara la propria base con la grafia. Dal token nudo chi legge non può sapere da dove l'autore lo intendesse, e provare entrambe le basi darebbe per buono un riferimento rotto che trova un omonimo dall'altra parte.

- **`🏠/<path>`** parte da project root, e solo da lì, anche quando risale sopra la root: un riferimento a un progetto fratello (il corpus di gruppo) si scrive `🏠/../<fratello>/…`. Si risolve solo da project root, senza ripiego sulla cartella del file.
- **`./…` e `../…` senza marcatore** partono dalla cartella del file che li cita, mai da project root. È la forma dei link markdown, l'unica che un editor risolve: un `../<fratello>/…` scritto pensando alla root risulta appeso anche quando il file esiste.
- **Un path nudo con almeno una barra** (`{docs_root}/reference/x.md`) si prova dalla cartella del file e poi da project root. Il marcatore è additivo: i path nudi restano validi.

La grafia è una convenzione di scrittura: nessuno script verifica i riferimenti di una pagina.

## L'inbox — il punto d'arrivo

`{docs_root}/inbox/` tiene le nozioni che le task hanno prodotto. Non è un quinto verdetto: è il **punto d'arrivo** di una nozione, che resta lì, indicizzata in `INDEX.md`. Nessun processo la sposta nei quattro layer. Tre nature, dichiarate dal marker in riga 3 del file (`nozioni` · `derivazione` · `sweep`); il formato e il vocabolario dei token sono degli script (`scripts/docs/inbox.sh`), mai di un prompt. Il checkpoint produce solo `nozioni`: le altre due nature restano leggibili per i file già scritti, e nessuna skill le esegue.

- **`drainable` dice che il file descrive un rilascio chiuso.** Senza il token l'owner è la task che scrive il file: il corpo si appende, si riscrive e si pota a ogni checkpoint (`inbox-format.md`). La chiusura della task accende il token e il file **si congela**: da lì l'unica scrittura è il marker, che `pull-repos` riscrive quando sblocca un inbox di branch. Il nome del token resta perché lo leggono gli script, il deck e ogni inbox già scritto.
- **Una task, un inbox**: il primo trasloco lo crea, e da lì è l'unica sede delle nozioni di quella task. Un file per trasloco moltiplicherebbe i file senza moltiplicare il contenuto.
- **Accumulo libero**: nessun cap sul numero di file inbox, nessuna soglia che blocchi. Sul singolo file il checkpoint conta le nozioni e stampa un avviso sopra `LW_DOC_INBOX_NOZIONI` (`lib-doc.sh`), senza tagliare né splittare.
- **Due stati, due semantiche.** Un file **drainable** descrive un rilascio: se contraddice `reference/`, **vince l'inbox**. Un file **non-drainable** descrive lavoro in corso, che il checkpoint successivo può smentire: è **inconsistenza, non precedenza** — a disposizione, non garantito, e si legge insieme alla task che lo scrive. `build-index.sh` li tiene in due sezioni distinte.
- **`branch:<nome>`** qualifica *per chi* la nozione è vera: la precedenza vale solo per chi lavora su quel branch, per chi sta su prod non conta niente. Non congela il file per la task che ne è owner.
- La ridondanza in inbox è ammessa: «è già scritto altrove» è un criterio dipendente, e non lo applica nessuno.

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

Tutti gli altri — *eco*, *sorpresa*, *sopravvive al refactor* (dipendono dal codice) · *inventario*, *calco* (dalla fonte viva) · *già scritto*, *online o offline*, *quale file* (dalla doc) — sono **dipendenti**, e nessun passo li applica. Pretenderli al checkpoint rimetterebbe la lettura dell'intera doc dentro ogni checkpoint. Ne segue che un inbox può contenere doppioni ed echi di ciò che `reference/` dice già.

## Chi scrive la doc

- nozione emersa in una task → vive nella sede che il task file dichiara (`## Doc Impact`, poi l'inbox della task dal primo trasloco), **riesaminata** a ogni checkpoint (`checkpoint-task`), congelata alla chiusura
- `reference/` e le pagine online → **nessuna skill le scrive**: si scrivono e si correggono a mano. Niente segnala una pagina che descrive pezzi che il codice non ha più

L'unica soglia vive in uno **script**, mai in un prompt: l'avviso sul numero di nozioni di un inbox (`LW_DOC_INBOX_NOZIONI`).

**La doc segue il rilascio.** Codice + task file nel checkpoint. Nuovo file in `reference/` o in `inbox/` → rigenera l'indice con `scripts/docs/build-index.sh`; un file di `reference/` senza TLDR in riga 3 entra col solo titolo.
