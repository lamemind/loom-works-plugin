---
name: feedback
description: Capture the current conversation as a feedback payload and drop it into loom-works for later analysis.
allowed-tools: Bash(*)
model: haiku
---

Cattura la conversazione corrente e la deposita in **loom-works**, dove viene analizzata a mente fresca. Si usa quando l'output dell'IA è incapibile, fuorviante o comunque sbagliato *nella forma*.

Annotazione utente:
~~~human
$ARGUMENTS
~~~

## Confine — impacchetta, NON diagnostica

Questa skill gira **dentro** la conversazione difettosa: l'IA che la esegue è la stessa che ha prodotto l'output brutto. Auto-analizzarsi qui produce razionalizzazione, non diagnosi.

Quindi: **raccogli e spedisci, punto.**

- ❌ non spiegare cosa è andato storto
- ❌ non giustificarti, non scusarti, non riformulare l'output incriminato
- ❌ non proporre fix alla doctrine
- ✅ esegui lo script, riporta il codice-maniglia

La diagnosi avviene in loom-works (`/feedback-review`), con la doctrine sotto mano.

## Esecuzione

### 1. Annotazione

`$ARGUMENTS` è **free-text puro**: nessuna sintassi, nessun tag, nessun dominio di valori. Passalo verbatim, senza riscriverlo, riassumerlo o "migliorarlo".

Se è vuoto, chiedi una riga all'utente — è l'unico caso in cui questa skill fa una domanda.

### 2. Cattura

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/feedback/capture-feedback.sh" "<annotazione verbatim>"
```

Lo script:

- identifica la sessione corrente da `$CLAUDE_CODE_SESSION_ID` e ne localizza il `.jsonl` sotto `~/.claude/projects/`
- risolve la dir di loom-works: `$LOOM_WORKS_DIR` → `dconf read /org/lamemind/loom/projects/loom-works/dir` → errore parlante
- crea `<loom>/<docsRoot>/feedbacks/FB-YYYYMMDDHHMMSS/` con `transcript.jsonl` (copia integrale) + `meta.json`
- stampa il codice-maniglia e il path

### 3. Report

Due righe, niente altro:

```
📮 FB-20260726104233 depositato in loom-works
   Incolla il codice in loom per riaprire il caso: /feedback-review FB-20260726104233
```

Se lo script fallisce, riporta l'errore così com'è — non tentare workaround (scrivere il payload a mano, indovinare il path di loom).

## Note

- **Copia integrale, non puntatore**: la conversazione continua dopo la cattura, quindi un riferimento vivo punterebbe a un file che cambia. Serve lo snapshot dell'istante in cui il difetto si è manifestato.
- Del progetto sender viaggia **solo il path** della project root: loom lo legge se serve contesto. Nessuna copia della doc.
- Il sender **non** deve essere loom-registered; solo loom-works lo è (è il collettore).
- Il difetto sta di norma in **coda** al transcript — l'annotazione si scrive subito dopo l'output incriminato.
