---
name: derive-notions
description: Consuma i file inbox di natura derivazione — legge l'ordine e il diff che l'ancora range indica, estrae i fatti di disallineamento (la doc dice X, il codice fa Y) e produce un file inbox di natura nozioni; la derivazione muore nello stesso commit. Non presidiata.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Usa il valore ovunque sotto compaia `{docs_root}`.

Consumi i file inbox di natura `derivazione`: ognuno è un **ordine di analisi in prosa** con l'ancora di un diff. Il tuo prodotto non è doc — è un file inbox di natura `nozioni` nuovo, che il flusso standard (`drain-notions`) collocherà. **Rifornisci la coda, non la chiudi**: è la differenza col drain, ed è il fatto che chi ti lancia di notte deve sapere.

Nessuna domanda all'utente: giri anche nel notturno.

## Note utente
~~~human
$ARGUMENTS
~~~

Una derivazione nominata in `$ARGUMENTS` → la coda è quel solo file, e lo step 1 non si esegue.

**Come si nomina.** Basta il nome, non il path: la cartella la sai già. Accetta il path completo, il basename con o senza `.md`, e il match è case-insensitive contro i file di `{docs_root}/inbox/`. Più di un file che matcha → elenca i candidati e fermati; nessuno → dillo, e non ripiegare sulla coda intera.

**Un file nominato si consuma anche senza `drainable`.** Quel token governa la **coda automatica** — chi il notturno può prendere da sé — non il permesso di consumare: nominare un file È la decisione che il token dichiarerebbe. Non aggiungere il token e non committare niente per «sbloccarlo». Resta escluso il solo `branch:`, che congela il file per chiunque.

## 0. Guardia d'ingresso

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-guard.sh" worktree --docs-root "{docs_root}"
```

Exit 2 → STOP con notifica (l'elenco è il red flag) · exit 1 → non è un repo git, STOP.

## 1. La coda

**Salta questo step se `$ARGUMENTS` nomina una derivazione**: la coda è già quel file. Questa misura costruisce la coda **automatica**, e il suo filtro `--drainable` scarterebbe un file parcheggiato che qualcuno ha nominato apposta — chiudendo il giro con «coda vuota» invece che con un errore, cioè nel modo che non lascia traccia.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-metrics.sh" --docs-root "{docs_root}" --inbox --natura derivazione --drainable
```

Ordine `created` crescente. Coda vuota → report e fine.

## 2. Il ciclo — per ogni derivazione

**2a. Guardia**, di nuovo, prima di ogni file (stessa invocazione dello step 0): ogni ciclo chiude con un commit, quindi il confine è un punto pulito e lo sporco che trova è esterno.

**2b. Leggi ordine e ancore.**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" parse --file <path> --format text
```

La prosa del file è l'ordine; le righe `ANCORA` portano i dati esatti — `range:` (il diff, obbligatorio) e `path:` (il perimetro, opzionale, ripetibile). **`range` assente = red flag, salta il file**: senza un diff non c'è niente da derivare, e il caso è uno `sweep` scritto con la natura sbagliata — dillo nel report, la correzione è di chi l'ha scritto.

**2c. Il materiale.**

```bash
git diff <range> -- <path...>     # il perimetro delle ancore path:, o tutto se assenti
```

Un range non risolvibile (commit garbage-collected, branch sparito) è un red flag: salta e riporta.

**2d. Estrai i disallineamenti.** Individua le pagine doc del perimetro (dall'INDEX e dai path toccati dal diff), poi spawn di `doc-helper` in parallelo — un `Task` con `subagent_type: doc-helper` per pagina o gruppo affine, attività `estrai-disallineamenti`:

```
attività: estrai-disallineamenti
diff: <path di un file temporaneo col diff, se grande; inline se piccolo>
pagine: <lista dei path doc del gruppo>
```

Raccogli i `fatti` di tutti gli helper. Un fatto = «la doc dice X, la fonte fa Y» con la sede. Componi da ogni fatto una **nozione per esteso**: il fatto, il perché, le condizioni in cui vale — chi la leggerà non ha in memoria né il diff né questa conversazione. Zero fatti → la derivazione muore senza produrre niente (2e, senza file nuovo): l'ordine era già assorbito.

**2e. Commit atomico: nasce il file `nozioni`, muore la derivazione.**

```bash
printf '%s\n' "<nozione 1>" "<nozione 2>" | \
  "${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" new --docs-root "{docs_root}" \
    --slug <tema-dal-titolo-della-derivazione> --natura nozioni \
    --titolo "<tema>" --tldr "<perimetro>" --indexed --drainable
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "{docs_root}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
git rm -q <path della derivazione>
lw_git_add_n_commit "docs(derive): <basename derivazione> → <basename nozioni> (<N> nozioni)" \
    <INBOX_PATH stampato da new> <path della derivazione> "{docs_root}/reference/INDEX.md"
```

Senza `--cappello`: il file nasce da un diff, non da una task — la sua provenienza è **questo commit atomico**, che uccide la derivazione e dà vita alle nozioni insieme. Con zero fatti il commit porta il solo `git rm` della derivazione, con un messaggio che dichiara l'ordine assorbito.

## 3. Chiusura

```bash
lw_git_push
```

Report: derivazioni consumate (→ quale file nozioni, quante nozioni), saltate e perché (`range` assente o morto), red flag. Le nozioni prodotte le colloca `drain-notions` — non invocarlo tu: la composizione dei flussi è del giro notturno o dell'utente.
