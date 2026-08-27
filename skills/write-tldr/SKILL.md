---
name: write-tldr
description: Produce la riga 3 — il TLDR-ancora — dei file di reference/ toccati da un writer. Tre stadi per file: raccoglitore haiku, gate deterministico a grep, potatore haiku che può solo copiare verbatim o scartare. Unico attore autorizzato a scrivere quella riga.
allowed-tools: Bash(*), Read, Write, Task
model: sonnet
---

Il TLDR di un file di `reference/` è un **artefatto derivato**, e tu sei l'unico a scriverlo: chi tocca il corpo di un file non tocca la riga 3. Ti invocano `rebalance-doc`, `align-doc` e `drain-notions` come ultimo passo prima di `build-index.sh`, sui file di `reference/` che i loro writer hanno toccato.

Non giudichi il contenuto e non scrivi prosa tua: **componi**, unendo con ` · ` frammenti che altri hanno prodotto e che tu non hai il permesso di riformulare. Se una voce ti sembra sbagliata, la riporti nel report — non la aggiusti.

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

Le liste di candidati vivono qui, non entrano mai nel sistema doc e muoiono a fine giro. Lo stato shell non sopravvive fra due invocazioni Bash: riporta il path ottenuto come letterale nei comandi successivi.

## 1. Il ciclo — per ogni file, i tre stadi in quest'ordine

**1a. Raccolta.** `Task` con `subagent_type: doc-helper`:

```
attività: raccogli-tldr
file: <path del file>
```

L'envelope ritorna `{"candidati": ["ETICHETTA | frammento", ...]}`. Una lista corta o una `confidence` non alta sono red flag da riportare, non motivi per rilanciare.

**1b. La lista su disco.** Scrivi i candidati in `<TMPDIR_TLDR>/<basename>.txt`, **uno per riga, verbatim dall'envelope**, preceduti da una riga di intestazione col path del file:

```
# <path del file>
ORIENTAMENTO | <…>
NOME | <…>
```

Copiare qui una riga cambiandola vanifica il gate: da questo punto in poi nessuno ha più il file per accorgersene.

**1c. Gate.**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/tldr.sh" gate \
    --file <path del file> \
    --candidati <TMPDIR_TLDR>/<basename>.txt \
    --out <TMPDIR_TLDR>/<basename>.filtrata.txt
```

Ogni candidato `NOME` o `ERRORE` deve comparire letteralmente nel file: chi non passa esce qui. Le righe `SCARTATO` e `MALFORMATO` su stderr sono **dati del report**, non errori — un nome fabbricato scartato è il gate che lavora. Il gate esce comunque zero: un exit non-zero è un problema d'uso (file assente, lista assente), e lì il file si salta.

**1d. Potatura.** `Task` con `subagent_type: doc-helper`:

```
attività: pota-tldr
candidati: path:<TMPDIR_TLDR>/<basename>.filtrata.txt
```

Passi il **path della lista filtrata**, mai il path del file d'origine e mai il suo contenuto: il potatore sceglie su ciò che il gate ha già verificato. L'envelope ritorna `{"voci": [...]}`, già nell'ordine di resa.

**1e. La riga.** Unisci le `voci` con ` · ` — separatore incluso negli spazi, nient'altro: nessuna parola aggiunta, nessuna tolta, nessun rimescolamento dell'ordine ricevuto.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/tldr.sh" set --file <path del file> --tldr "<le voci unite>"
```

Lo script sostituisce la riga 3 se c'è un TLDR, la inserisce se non c'è. Exit 1 = il file non ha la forma attesa (riga 2 non vuota): saltalo e dichiaralo, non forzare la scrittura per altra via.

**Nessun retry, a nessuno stadio.** Se l'uscita è più lunga del cap se ne accorge `build-index.sh`, che esce 2 e nomina il file: quello è un red flag per il tuo chiamante, non un giro da rifare qui. La riga resta com'è.

## 2. Chiusura

```bash
rm -rf "$TMPDIR_TLDR"
```

Non committi e non lanci `build-index.sh`: il commit e l'indice sono del chiamante, che ti invoca appunto prima di rigenerarlo.

Report, una riga per file: candidati raccolti · scartati dal gate (con il frammento, che è la fabbricazione intercettata) · voci nel TLDR finale · saltati e perché. In coda i red flag: `confidence` non alta, liste anomale, file saltati.
