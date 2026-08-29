---
name: write-tldr
description: Produce la riga 3 — il TLDR-ancora — dei file di reference/ toccati da un writer. Due agent haiku (raccoglitore e potatore) alternati a passi deterministici che li controllano a monte e a valle. Unico attore autorizzato a scrivere quella riga.
allowed-tools: Bash(*), Read, Write, Task
model: sonnet
---

Il TLDR di un file di `reference/` è un **artefatto derivato**, e tu sei l'unico a scriverlo: chi tocca il corpo di un file non tocca la riga 3. Ti invocano `rebalance-doc`, `align-doc` e `drain-notions` come ultimo passo prima di `build-index.sh`, sui file di `reference/` che i loro writer hanno toccato.

Non giudichi il contenuto e non scrivi prosa tua. Il testo della riga lo compone uno script dalle voci che il potatore ha scelto: **tu non lo digiti mai**. Se una voce ti sembra sbagliata, la riporti nel report — non la aggiusti.

Nessuna domanda all'utente: giri anche dentro il notturno.

## Note utente
~~~human
$ARGUMENTS
~~~

`$ARGUMENTS` = uno o più path di file di `reference/`, separati da spazio (assoluti o relativi a project root). Nessun path → report «niente da fare» e fine. Un path che non esiste o che sta fuori da `reference/` → saltalo e dichiaralo nel report.

## 0. La temporanea del giro

```bash
TMPDIR_TLDR="$(mktemp -d /tmp/loom-tldr.XXXXXX)"
```

Liste e copie vivono qui, non entrano mai nel sistema doc e muoiono a fine giro. Lo stato shell non sopravvive fra due invocazioni Bash: riporta il path ottenuto come letterale nei comandi successivi.

## 1. Il ciclo — per ogni file, sei passi in quest'ordine

Due agent e quattro passi deterministici, alternati. Ogni agent è preso in mezzo: `prepara` gli toglie ciò che non deve vedere, `gate` e `componi` scartano ciò che non aveva il permesso di produrre.

**1a. Prepara la copia.**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/tldr.sh" prepara \
    --file <path del file> \
    --out <TMPDIR_TLDR>/<basename>.copia.md
```

La copia è il file **senza la riga 3**. Da qui in avanti raccoglitore e gate lavorano sulla copia, mai sull'originale: se vedessero il TLDR precedente il raccoglitore ne riciclerebbe i frammenti e il gate li confermerebbe, perché nel file ci sono davvero. L'originale torna in scena solo al passo `set`.

**1b. Raccolta.** `Task` con `subagent_type: doc-helper` **e `model: sonnet`**:

```
attività: raccogli-tldr
file: <TMPDIR_TLDR>/<basename>.copia.md
```

Il modello si forza qui, invocazione per invocazione, invece di cambiarlo nel body dell'agent: `doc-helper` serve dieci attività e le altre nove stanno bene su haiku. Su questa no — haiku fabbrica nomi che nel file non esistono (parentesi aggiunte a un simbolo nudo, un prefisso di cartella inventato), e ogni fabbricazione è un'ancora persa: il gate la scarta correttamente, ma quel nome non entra più nell'indice. Misurato sui 55 file di `reference/`: una ventina di scarti con haiku, zero con sonnet a parità di file.

L'envelope ritorna `{"candidati": ["ETICHETTA | frammento | domanda", ...]}`. Una lista corta o una `confidence` non alta sono red flag da riportare, non motivi per rilanciare.

**1c. La lista su disco.** Scrivi i candidati in `<TMPDIR_TLDR>/<basename>.txt`, **uno per riga, verbatim dall'envelope**, preceduti da una riga di intestazione col path **vero** del file — non quello della copia, che al potatore non direbbe nulla:

```
# <path del file>
SEZIONE | <…> | <il problema con cui uno ci arriva>
NOME | <…> | <…>
ERRORE | <…> | -
```

Tre campi separati da ` | `, il terzo è la domanda e vale `-` quando il raccoglitore non ha saputo formularla. Non riempirla tu e non toglierla: è il criterio con cui il potatore scarta, e un trattino è un dato che gli serve.

Copiare qui una riga cambiandola vanifica il gate: da questo punto in poi nessuno ha più il file per accorgersene.

**1d. Gate d'ingresso.**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/tldr.sh" gate \
    --file <TMPDIR_TLDR>/<basename>.copia.md \
    --candidati <TMPDIR_TLDR>/<basename>.txt \
    --out <TMPDIR_TLDR>/<basename>.filtrata.txt
```

**Ogni** candidato deve comparire letteralmente nella copia: chi non passa esce qui. Le tre etichette — `NOME`, `ERRORE`, `SEZIONE` — sono tutte estrazione letterale, quindi il gate non ha eccezioni e nessuna voce entra senza verifica. Le righe `SCARTATO` e `MALFORMATO` su stderr sono **dati del report**, non errori — un nome fabbricato scartato è il gate che lavora. Il gate esce comunque zero: un exit non-zero è un problema d'uso (file assente, lista assente), e lì il file si salta.

**1e. Potatura.** `Task` con `subagent_type: doc-helper` **e `model: sonnet`**:

```
attività: pota-tldr
candidati: path:<TMPDIR_TLDR>/<basename>.filtrata.txt
```

Passi il **path della lista filtrata**, mai il path del file d'origine e mai il suo contenuto: il potatore sceglie su ciò che il gate ha già verificato. L'envelope ritorna `{"voci": [...]}` — solo i frammenti, senza etichetta e senza domanda.

Scrivi le voci in `<TMPDIR_TLDR>/<basename>.voci.txt`, **una per riga, verbatim dall'envelope, nell'ordine in cui le ha rese**. Dentro una stessa etichetta quell'ordine è di merito, ed è la sola decisione che il potatore prende su cosa sopravvive al taglio: riordinare qui significa scegliere al posto suo, con in mano molto meno di quello che aveva lui. Fra etichette diverse non decide né lui né tu — l'allocazione la applica `componi`.

**1f. Gate d'uscita e composizione.**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/tldr.sh" componi \
    --candidati <TMPDIR_TLDR>/<basename>.filtrata.txt \
    --voci <TMPDIR_TLDR>/<basename>.voci.txt \
    --out <TMPDIR_TLDR>/<basename>.riga.txt
```

Lo script ritrova l'etichetta di ogni voce nella lista filtrata, e con quella applica le tre regole che il potatore ha nel prompt e può comunque violare: **verbatim** (una voce che non si ritrova è una riformulazione, esce), **vocabolario** (solo `NOME`, `ERRORE`, `SEZIONE`), **cap** (allocazione in due livelli, con la soglia presa da `lib-doc.sh`).

L'allocazione: `NOME` ed `ERRORE` si dividono il cap in parti uguali, chi domanda meno viene servito per primo e libera agli altri la quota che non gli serve; le `SEZIONE` prendono solo ciò che avanza. Le tre categorie non sono pari — nomi ed errori sono chiavi che qualcuno digita, le sezioni sono il ripiego per i file che di chiavi non ne hanno. Su un file di API le sezioni non entrano affatto, su un file di sola metodologia prendono tutto il cap. Le superstiti vengono rese raggruppate, `SEZIONE` in testa: è la leggibilità, non la priorità.

`NON-VERBATIM`, `FUORI-VOCABOLARIO`, `OLTRE-CAP` su stderr sono dati del report. Exit 1 = nessuna voce utilizzabile: salta il file e dichiaralo.

**1g. La riga sul file.**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/tldr.sh" set \
    --file <path del file> \
    --tldr-file <TMPDIR_TLDR>/<basename>.riga.txt
```

Il testo passa per un file, mai per un argomento shell: un TLDR è pieno di backtick, e un errore di quoting scriverebbe sul disco una riga corrotta senza che nulla protesti. **Non usare `--tldr`** — esiste per l'invocazione a mano, non per questo flusso.

Lo script sostituisce la riga 3 se c'è un TLDR, la inserisce se non c'è. Exit 1 = il file non ha la forma attesa (riga 2 non vuota): saltalo e dichiaralo, non forzare la scrittura per altra via.

**Nessun retry, a nessuno stadio.** Un giro rifatto costa due invocazioni e non ha ragione di andare meglio: gli scarti sono il prodotto normale di questa catena, non un fallimento da recuperare.

## 2. Chiusura

```bash
rm -rf "$TMPDIR_TLDR"
```

Non committi e non lanci `build-index.sh`: il commit e l'indice sono del chiamante, che ti invoca appunto prima di rigenerarlo.

Report, una riga per file: candidati raccolti · scartati dal gate d'ingresso (col frammento, che è la fabbricazione intercettata) · scartati dal gate d'uscita per categoria · voci nella riga finale e lunghezza · saltati e perché. In coda i red flag: `confidence` non alta, liste anomale, file saltati, e ogni `NON-VERBATIM` — quello è il potatore che esce dal proprio contratto, non un dato di routine.
