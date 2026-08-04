# Criteri di selezione doc

Estensione di `doc-management.md`, che resta la norma. Argomenta le due domande che la norma pone e non spiega: **perché una nozione è doc** (gli otto test) e **che forma prende quando lo è** (le sette tipologie offline).

## Gli otto test

Nell'ordine dell'imbuto, dal filtro più economico: i primi costano un'occhiata, gli ultimi richiedono di guardare fuori dalla frase. Ognuno cattura qualcosa che gli altri lasciano passare.

### Sopravvive alla task — nozione o cronaca

> Fra sei mesi, senza sapere che è esistita la task che l'ha generata, questa frase ha ancora senso?

Da applicare **nel momento in cui scrivi**, che è quando sei meno capace di applicarlo: durante una task il prima/dopo è la cosa più saliente che hai in testa, ed è la prima a evaporare.

- ❌ «`caretWindow` sostituisce `tailCut` (RIMOSSO)» — nomina un simbolo che non esiste, ha senso solo per chi ricorda lo stato precedente
- ❌ «l'append-only era una scelta, non un limite della libreria» — risponde a una domanda che solo quella task si è posta
- ✅ «le frecce arrivano regolari; il limite vero è che `Home`/`End` non sono esposte» — stessa nozione, riscritta come stato attuale

### Sopravvive al refactor — durabilità

> Un refactor che non cambia il comportamento invalida questa frase?

Cattura il **code-echo**: meccanica, conteggi, firme, flusso di controllo, stringhe renderizzate.

Il criterio non è il livello di dettaglio ma il **costo di manutenzione**: una frase invalidata da un refactor è una frase che pagherai per aggiornare, per sempre, e che `align-doc` continuerà a segnalare come drift. Il conto del drift è proporzionale a quanto la doc è accoppiata al codice.

- ❌ «il record porta `sessionId` più quattro campi opzionali» — un campo in più la falsifica
- ❌ «`MODE_FLAG` è un pattern flag opzionale, non un `if` che duplica `IN_TAB_CMD`» — un rename la falsifica
- ✅ «VTE conta EAW con ambiguous=1 e ignora VS16» — nessun refactor del nostro codice la tocca

Punto cieco: una frase può superarlo ed essere comunque inutile («il progetto usa TypeScript»). Per quello servono i due test seguenti.

### Costo di scoperta — valore, misurato al contrario

> Quanto è costato scoprirlo la prima volta?

Valore di una nozione ≈ **costo di scoperta evitato × letture future**. Documentare ciò che si scopre in due minuti leggendo il sorgente rende quasi zero, per quanto sia vero e durevole.

- ✅ «full-text sui corpi in RAM: 1-9 ms contro 26 ms di `grep`» — costa un benchmark, e la conclusione è controintuitiva
- ❌ «il comando accetta tre flag» — costa dieci secondi di `--help`

### Sorpresa — violazione di aspettativa

> Chi legge il codice con competenza ci arriva da solo, o si sorprende?

Una frase che **conferma** un'assunzione ragionevole è peso morto: il lettore l'aveva già. Una frase che la **contraddice** è la doc di massimo valore, perché è l'unica che intercetta un errore prima che venga commesso.

- ✅ «il `thinking` è persistito VUOTO, resta solo la `signature`» — chiunque assume il contrario e ci sbatte
- ✅ «`key.delete` è ANCHE Backspace» — due sequenze diverse collassano sullo stesso nome
- ❌ «`RES_FLAG` è il gemello di `SID_FLAG`» — è esattamente ciò che ti aspetti dopo aver visto l'altro

Costo di scoperta e sorpresa non selezionano lo stesso insieme: una misura può essere costosa da scoprire e per niente sorprendente; una trappola può sorprendere e costare cinque minuti. Entrambe passano.

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

## Nota per l'auditor

Un verdetto di scarto è un **verdetto**, non un'omissione: va dichiarato. Il posto durevole è il corpo del messaggio di commit dell'integrazione, greppabile con `git log --grep`, coerente col principio che la cronaca sta in git e non nella doc.

```
docs: integra nozioni — perimetro X

Integrate:
- <nozione> → <file>

Scartate:
- «<nozione>» → eco, il sorgente lo dice (percorso/file.ts → simbolo)
```
