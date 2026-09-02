# Il file inbox — formato e scrittura

Contratto per chi **scrive dentro** un file inbox di natura `nozioni`: la struttura del file, le tre operazioni ammesse sul corpo, e la riga che segna il confine oltre il quale il file non si tocca più.

Non riguarda `derivazione` e `sweep`, che nascono e muoiono senza che nessuno ne riapra il corpo.

## Un inbox per task, WIP finché la task è aperta

Il file lo crea `checkpoint-task` al primo trasloco, con `inbox.sh new`. Da lì in avanti è **l'unica sede delle nozioni di quella task**: `## Doc Impact` nel task file resta con la sola riga puntatore, e chi cattura una nozione nuova (`preflight-task`, `run-task`, il modello in chat) la scrive qui.

Finché la task è aperta l'owner è la task, non il sistema documentale: nessun altro attore legge il file come fonte, nessuna coda automatica lo prende. **Modificarlo è come modificare il task file.**

Alla chiusura della task `checkpoint-task` accende `drainable` nel marker, e in quell'istante la proprietà passa al sistema documentale: da lì il corpo è congelato.

## Struttura del file

```markdown
# T138 — modello inbox v2                                  ← riga 1, titolo
                                                           ← riga 2, vuota
> **INBOX**: nozioni · indexed · drainable · branch:feat/x  ← riga 3, marker
> **TLDR**: perimetro della task, non elenco delle voci     ← riga 4, opzionale
                                                           ← riga 5, vuota
- **n1** — testo della nozione, per esteso, su UNA riga
- **n2** — testo della nozione, per esteso, su UNA riga
  - router → reference/x.md — evidenza                     ← sub-bullet: del drain
```

- **Riga 1 e riga 3 sono posizionali.** Un marker che scivola in riga 4 rende il file malformato e `inbox.sh parse` esce 2: ogni consumer lo scarta, silenziosamente per chi legge la coda.
- **La riga 4 si scrive una volta sola**, alla creazione, e non si riscrive mai più. Descrive il **perimetro** della task — il cerchio, non l'area: un TLDR che enumera le voci presenti invecchia a ogni append, uno che traccia il confine del lavoro resta vero finché la task è quella. Formule: `tldr-formats.md`.
- **Una nozione è una riga sola.** Nessun hard-wrap, nessuna riga vuota in mezzo: il parser chiude la nozione alla prima riga che non è né una nozione né un suo sub-bullet.
- **I sub-bullet indentati sono il registro del drain** (`router →`, `router ✖️`, `writer ✔️`, `writer ✖️`). Li scrive `inbox.sh registro`, mai una mano: su un file WIP non ce ne sono ancora.

## Le tre operazioni sul corpo

Si eseguono con `Edit` sul file, direttamente. Non esiste una primitiva: gli scrittori sono cinque e devono anche **rileggere** ciò che è già scritto per rimetterlo in discussione, che è lavoro di conversazione, non di script.

**Appendere.** Nuova riga in coda, id = `max(nN) + 1` letto nel file. Gli id sono **stabili**: si assegnano alla nascita della voce e non si riusano.

```markdown
- **n7** — <il fatto per esteso: cosa, perché, e le condizioni in cui vale>. Ancora: <comando, simbolo o path>.
```

**Riscrivere.** Sostituisci il testo dopo `— `, **l'id resta quello**. È l'operazione del riesame quando il codice ha cambiato il fatto senza smentirlo.

**Eliminare.** Togli la riga intera, coi suoi eventuali sub-bullet. **Non si rinumera**: i buchi sono ammessi e attesi (`n1, n2, n4, n7`), il contatore resta `max+1`. Rinumerare romperebbe l'aggancio del registro del drain, che indirizza i verdetti per id.

## Quando il file non si tocca più

**`drainable` nel marker = congelato.** Il file appartiene al sistema documentale: `drain-notions` può averlo già in lavorazione, e le uniche scritture ammesse sono le sue — il registro e il marker. Un append qui produce una nozione che nessun router ha giudicato dentro un file che il drain crede di conoscere.

Il divieto è **una regola, non un controllo**: nessuno script lo rifiuta. Chi scrive legge la riga 3 prima di scrivere.

**`branch:<nome>` non congela**, e vale solo per il drain: la task che possiede il file continua a scriverlo e a potarlo come qualsiasi altra. I due token sono gate distinti — `branch:` dice *per chi* la nozione è vera, `drainable` dice *da quando* la doc può assorbirla.

## Cosa si scrive, e come

Valgono i criteri di `doc-management.md`: qui la ridondanza **fra** voci è ammessa, la cronaca dentro la voce no.

Il fatto va scritto **per esteso** — il perché e le condizioni in cui vale — mai compresso in un aforisma. Chi lo smaltisce è il drain, mesi dopo, senza in memoria la conversazione che l'ha prodotto: da una frase ellittica non può ricostruirlo, e la butta.

- ✅ `- **n3** — **Bash ≥ 5.2 interpreta & nella replacement di ${var//pat/repl} come il match intero**, non come sé stesso: una sostituzione scritta per 5.1 diventa un no-op silenzioso. Ancora: bash 5.2 release notes, ${var//pat/repl}.`
- ❌ `- **n3** — Gotcha su bash e la sostituzione. Ancora: bash.`

## Il conteggio

Le nozioni si contano con `inbox.sh parse`, mai con una regex propria:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" parse --file <path> --format tsv | grep -c $'^NOZIONE\t'
```

La soglia di avviso vive in `lib-doc.sh` (`LW_DOC_INBOX_NOZIONI`), insieme alle altre soglie del sistema doc. Sopra soglia il checkpoint stampa una riga e prosegue: non taglia, non splitta, non solleva altro lavoro.
