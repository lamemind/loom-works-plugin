# Criteri di selezione doc

Estensione di `doc-management.md`, che resta la norma. Questo file **non è iniettato**: si apre da path quando un verdetto non è ovvio.

Il taglio fra i due non è per argomento ma per **quando si paga il verdetto**. La norma porta i criteri **indipendenti**, che si applicano guardando la sola nozione e devono essere in contesto al checkpoint senza aprire niente. Qui stanno i **dipendenti** — quelli il cui verdetto richiede di aprire il codice, una fonte viva o il resto della doc — più il razionale dei numeri e la meccanica della manutenzione. Li paga chi **colloca** (`doc-router`, `doc-auditor`, `drain-doc`) e chi **collauda** (`doc-verifier`, che misura una patch contro il contratto e per farlo apre la doc), non chi cattura.

I due test indipendenti che vivevano qui — *sopravvive alla task* e *costo di scoperta* — sono saliti in `doc-management.md` §Imbuto di selezione, con le nove parole. Non ne resta una copia: due fonti dello stesso test sono la prima a driftare.

## I criteri dipendenti

Nell'ordine dell'imbuto. Ognuno cattura qualcosa che gli altri lasciano passare.

### Sopravvive al refactor — durabilità

> Un refactor che non cambia il comportamento invalida questa frase?

Cattura il **code-echo**: meccanica, conteggi, firme, flusso di controllo, stringhe renderizzate.

Il criterio non è il livello di dettaglio ma il **costo di manutenzione**: una frase invalidata da un refactor è una frase che pagherai per aggiornare, per sempre, e che `align-doc` continuerà a segnalare come drift. Il conto del drift è proporzionale a quanto la doc è accoppiata al codice.

- ❌ «il record porta `sessionId` più quattro campi opzionali» — un campo in più la falsifica
- ❌ «`MODE_FLAG` è un pattern flag opzionale, non un `if` che duplica `IN_TAB_CMD`» — un rename la falsifica
- ✅ «VTE conta EAW con ambiguous=1 e ignora VS16» — nessun refactor del nostro codice la tocca

Punto cieco: una frase può superarlo ed essere comunque inutile («il progetto usa TypeScript»). Per quello servono il costo di scoperta (indipendente, sta nella norma) e la sorpresa.

### Sorpresa — violazione di aspettativa

> Chi legge il codice con competenza ci arriva da solo, o si sorprende?

Una frase che **conferma** un'assunzione ragionevole è peso morto: il lettore l'aveva già. Una frase che la **contraddice** è la doc di massimo valore, perché è l'unica che intercetta un errore prima che venga commesso.

- ✅ «il `thinking` è persistito VUOTO, resta solo la `signature`» — chiunque assume il contrario e ci sbatte
- ✅ «`key.delete` è ANCHE Backspace» — due sequenze diverse collassano sullo stesso nome
- ❌ «`RES_FLAG` è il gemello di `SID_FLAG`» — è esattamente ciò che ti aspetti dopo aver visto l'altro

Costo di scoperta e sorpresa non selezionano lo stesso insieme: una misura può essere costosa da scoprire e per niente sorprendente; una trappola può sorprendere e costare cinque minuti. Entrambe passano. Cadono però in classi diverse — il costo lo sa chi ha appena lavorato, la sorpresa richiede di rileggere il codice con occhi competenti — ed è la ragione per cui l'una si applica al checkpoint e l'altra allo smaltimento.

Corollario: i file di gotcha hanno la densità di valore più alta per carattere perché sono fatti **solo** di sorpresa. Non sono un'eccezione al criterio di zoom — sono il caso in cui il criterio dice «scendi in profondità».

---

Da qui in poi la nozione **è** doc: non si taglia più, si colloca.

### Prima mezz'ora — online o offline

> Senza questa frase, chi arriva sul progetto prende una decisione sbagliata **prima di sapere che esiste una domanda da fare**?

Sì → online. No → offline.

Online serve a chi **non sa ancora cosa cercare**; offline a chi **ha già la domanda**. Una nozione preziosissima ma che cerchi solo quando ti serve non ha titolo per stare online — e l'online si paga a ogni sessione, per sempre, moltiplicato per tutte le sessioni future.

Controprova: se riesci a formulare la query che porterebbe qualcuno ad aprire il file, quella query è un'ancora, e il posto è offline.

### Fonte unica — dov'è scritto anche altrove

> Qual è l'unica fonte di questo fatto? Se ce ne sono due, quale muore?

Vale fra file, e vale **dentro** un file fra TLDR e corpo: un TLDR che riassume il corpo è un secondo documento da leggere, non un indirizzo.

Vale anche fra doc e **task file**: un task file che porta il modello normativo è una seconda fonte del contratto. Finché la task è in corso è materiale di lavoro; quando il contratto esiste, la sezione diventa un puntatore.

### Reperibilità — cosa digita chi cerca

> Formula la query con cui qualcuno arriverebbe qui. Se non ci riesci, chi la scrive?

Doc irreperibile = doc inesistente, con l'aggravante che la paghi in manutenzione e in drift.

È questo test che decide **dove passa il taglio** di uno split: un file va spezzato quando contiene due trigger di ricerca distinti. La soglia in char è un proxy — utile perché misurabile, ma non dice dove tagliare.

### Rilevabilità del drift — chi se ne accorge quando diventa falsa

> Esiste un modo di accorgersi che questa frase è diventata falsa, che non sia rileggerla accanto al codice?

Tre classi, **tre rimedi diversi**:

- **indriftabile** — un perché, un'alternativa scartata, un vincolo esterno. Non può diventare falsa. La doc più economica che esista.
- **verificabile da una macchina** — un'invariante. Il rimedio non è cancellare né riscrivere: è **asserirla in un test** e far puntare la doc al test. Alla prosa resta il perché.
- **verificabile solo da un umano che confronta** — bomba a orologeria: vera oggi, falsa fra un mese, nessun segnale. Da minimizzare per costruzione.

Cattura il residuo che il test sul refactor lascia passare: una frase può essere **vera doc** e diventare comunque falsa in silenzio. Caso reale: «questo modulo è la contabilità **unica** della larghezza» era durevole e di perimetro — giusta da scrivere — e l'ha resa falsa una seconda implementazione comparsa in un altro file. Il rimedio non era tagliarla, era renderla verificabile.

**Un'invariante che merita di essere documentata merita quasi sempre di essere asserita.**

## Le sette tipologie offline

Offline si gonfia perché è poliedrico: ogni tipologia ha un confine proprio, e applicarne uno solo lascia entrare tutto il resto.

### referto — risultato d'indagine

Misure, benchmark, esito di uno spike.

*Confine*: il **numero e la conclusione**. Il protocollo dell'esperimento è **cantiere** e resta nella task folder.

- ✅ «57 MB di JSONL sono 10,4 MB di testo; in RAM 1-9 ms, con `grep` 26 ms»
- ❌ la sequenza di comandi con cui è stato cronometrato

### sentenza — scelta con motivazione definitiva

Alternative valutate e bocciate, con il motivo che chiude la questione.

*Confine*: **definitiva**. Una folder contiene anche alternative bocciate con motivazione provvisoria, poi riprese: quelle sono **scarto**, non sentenza. Una sentenza non driftà mai — una bocciatura resta bocciata.

- ✅ «`GLib.KeyFile` scartato: mismatch di `length` su UTF-8 con emoji multibyte»
- ❌ «per ora usiamo X, valutiamo Y più avanti»

### trappola — ciò che sorprende

Il gotcha: dove ti incastri anche leggendo bene il codice.

*Confine*: deve **violare un'aspettativa ragionevole**. Se conferma ciò che il lettore già assumeva, è **eco**. Vale sia sul mondo esterno sia sul proprio codice.

### manuale dell'estraneo — sistemi che non possiedi

Broker, terminale, libreria di sistema, API di terzi.

*Confine*, il più violato: solo ciò che **hai scoperto tu** e la doc ufficiale non dice, dice male, o dice **falso**. La doc ufficiale è a sua volta una fonte: si punta, non si ricopia.

- ✅ «il terminale non ha targeting per-finestra: `--tab` va sempre alla finestra attiva»
- ❌ l'elenco dei flag del terminale

Il taglio che regge tutta la tipologia: **il manuale di ciò che possiedi è il codice**. Scrivi manuale solo di ciò che non possiedi — perché sul tuo codice risponde il sorgente, sempre aggiornato e sempre disponibile, mentre su un sistema esterno non risponde nessuno che tu controlli: o l'hai scritto, o è perso.

### invariante — la regola che nessun file dice da solo

La proprietà distribuita che dedurresti solo leggendo cinque file.

*Confine*: alla doc il **perché**, a un **test** il controllo (vedi §Rilevabilità del drift).

- ✅ «il taglio lo fa il chiamante, la funzione di misura non si ripara da sola»
- ✅ «un budget calcolato è un tetto, mai un pavimento»

### snodo — i punti di decisione di una procedura

*Confine*: i passi meccanici sono uno **script**, quindi layer codice. Se la procedura è scriptabile e non è ancora uno script, il verdetto non è «documentala» ma «scrivila».

Resta doc ciò che lo script non porta: **perché** l'ordine è quello, e cosa si decide a ogni bivio.

- ✅ «rigenerare l'artefatto **dopo** il publish: chi invoca il path canonico esegue la cache, non il sorgente, quindi rigenerarlo prima produce lavoro che il primo run successivo butta via»
- ❌ i sei comandi in sequenza

### complemento della fonte viva

Per un layer interrogabile: che la fonte esiste, come si accede, **quali domande fargli**, cosa non risponde, e le trappole di costo.

*Confine*: **mai l'inventario**. La forma della query sì, il risultato della query mai.

- ✅ «per lo stato di un ordine leggi `orders` join `fills`, non `order_events`»
- ✅ «quella tabella ha centinaia di milioni di righe: mai un `select *`»
- ❌ l'elenco di tabelle, colonne, tipi, foreign key

**Layer interrogabile ≠ RAG.** RAG recupera da un corpus indicizzato: lavora su uno *snapshot*, quindi driftà come la doc, con in più una reindicizzazione da mantenere. La proprietà che serve qui è **freschezza per costruzione** — una chiamata a strumento risponde dallo stato attuale, quindi non può essere falsa. Chiamarlo RAG porta a costruire una pipeline di indicizzazione dove bastava una chiamata.

## Le due coppie che sembrano sinonimi

Stessa nozione, due stadi di maturazione. Confonderle fa entrare in doc materiale che non ha finito di muoversi.

- **scarto → sentenza** — l'alternativa bocciata, prima e dopo che la motivazione si è stabilizzata. Finché può riaprirsi resta nella task folder.
- **ipotesi → referto** — la nozione, prima e dopo l'esecuzione. Una voce `## Doc Impact` è scritta a `create-task`, cioè **prima di lavorare**: sembra affidabile perché ha già il formato giusto (nozione + ancora), ma è una previsione. Si **verifica** contro il risultato, non si integra alla lettera.

## Le cinque soglie — perché quel numero

La norma porta i numeri, che sono ciò che serve per applicarli. Qui il perché, che serve per **cambiarli**.

- **Split, 15.000 char.** È un proxy: dice *che* un file va tagliato, non *dove*. Il taglio lo decide la reperibilità — due trigger di ricerca distinti = due file. **Le riduzioni precedono il taglio**: se eco e cronaca si tolgono dopo, i frammenti nascono dimensionati su peso che stava per sparire, e quello grosso nasce già a ridosso della soglia.
- **Merge, 3.000 char.** Non è un ordine di fusione, è un trigger di **riesame**. Ogni file costa un TLDR nell'INDEX, che è online: sotto quella soglia l'indicizzazione si mangia un quinto del contenuto. Il pavimento esiste perché senza, lo split è a senso unico — e un file che si svuota non ha nessuno che se ne accorga.
- **Regroup, 60.000 char.** Preso in prestito da `doc-partition.sh --max-char`, dove misura quanta doc legge **un** auditor. Riusare quel numero tiene coerenti per costruzione la topologia e il fan-out che la percorre: una cartella sotto la soglia è un perimetro che un agente tiene in testa tutto insieme. È l'analogia giusta, non una prova — va tarata sull'esercizio.
- **TLDR, 600 char.** Bloccante perché il TLDR finisce nell'INDEX, che è online: un TLDR prolisso si paga a ogni sessione come se il file intero lo fosse. È l'unica soglia che uno script fa rispettare (`build-index.sh` esce 2).
- **Inbox, 8 file.** Conteggio e non char, perché dev'essere leggibile a colpo d'occhio in un header («3/8») senza aprire niente. Al ritmo di flusso misurato il tetto cade a cadenza settimanale — la stessa a cui l'azione notturna drenerebbe da sé. Provvisorio come il regroup.

## Manutenzione

`align-doc` e `lint-doc` **misurano** doc già collocata, contro fonti di verità diverse: la fonte nativa del layer la prima, questo contratto la seconda. `drain-doc` non misura — **colloca**, ed è per questo che è una terza skill e non una modalità delle altre.

**Le fasi di `lint-doc` sono ordinate e l'ordine è vincolante**: `clean` → `split` → `regroup`. Le riduzioni prima del taglio (vedi §Le cinque soglie), e la categorizzazione per ultima — dimensionata su file che stanno per essere spezzati nascerebbe stale, e un file che dopo lo split diventa tre può cambiare cartella di appartenenza.

Il regroup sposta file senza rinominarli: `loom-deck-spawn.md` → `loom-deck/loom-deck-spawn.md`, mai `loom-deck/spawn.md`. La ripetizione costa poco; togliere il prefisso rompe un'ancora che vive anche fuori dalla doc — nei `SKILL.md`, nei task file, nei messaggi di commit, cioè in perimetri che `check-doc-links.sh` non scandisce.

Tre regole della partizione, ognuna contro un modo tipico di sbagliarla:

- **Le categorie sono perimetri di ricerca, non temi.** Una tassonomia elegante ma ortogonale a come si cerca è *peggio* della root piatta: aggiunge navigazione senza aggiungere reperibilità.
- **Nessuna categoria «varie».** Chi non appartiene a nessun raggruppamento resta in root — la root è la categoria di default, non il residuo.
- **Zoom disomogeneo ammesso.** Una cartella da cinque file accanto a un file sciolto è l'esito corretto: la densità dei domini non è uniforme, e forzare la simmetria è ciò che genera il contenitore-avanzi.

Corollario controintuitivo: **meglio una cartella con un solo file che una da dieci**. Una cartella non è un premio alla numerosità, è un confine di ricerca; se un dominio ne merita uno, lo merita anche da solo.

## Origine D-task

Soglia per aprire una `D{N}`: il lavoro dev'essere **multi-chunk**, cioè partizionabile in scope che `run-doc` esegue a giri con un `doc-writer` fresco per chunk. Una nozione singola resta `capture-doc`, che è one-shot — aprire una D per essa paga il ciclo (task file, planning, checkpoint per giro) per un lavoro che non lo ammortizza.

Col `parent=T{N}` passato a mano il D-file porta `**Parent Task**: T{N}`, e il parent va corredato di `- [ ] D{N} (<maniglia>) chiusa` in Acceptance: alla chiusura della D il suo checkpoint flagga indietro la checkbox.

## Nota per l'auditor

Un verdetto di scarto è un **verdetto**, non un'omissione: va dichiarato. Il posto durevole è il corpo del messaggio di commit dell'integrazione, greppabile con `git log --grep`, coerente col principio che la cronaca sta in git e non nella doc.

```
docs: integra nozioni — perimetro X

Integrate:
- <nozione> → <file>

Scartate:
- «<nozione>» → eco, il sorgente lo dice (percorso/file.ts → simbolo)
```
