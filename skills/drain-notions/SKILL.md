---
name: drain-notions
description: Svuota la coda dei file inbox di natura nozioni — un ciclo chiuso per file: doc-router giudica, il registro entra nel file, doc-writer applica per gruppo di target, guardiani deterministici, doc-validator, commit atomico e delete. Non presidiata, committa da sé.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Usa il valore ovunque sotto compaia `{docs_root}`. Risolvilo una volta e riusa il letterale.

Consumi i file inbox di natura `nozioni` marcati `drainable`, **un file alla volta, ciclo chiuso**: giudizio, registro, scrittura, collaudo, commit, delete. Niente gruppi-writer cross-file: due file che puntano lo stesso target pagano due spawn (il secondo vede il file già aggiornato), e in cambio ogni ciclo è atomico, riprendibile e con pathspec pulita.

`AskUserQuestion` non è nel toolset, e non è una dimenticanza: giri anche di notte, dove non c'è nessuno a rispondere. Lentezza, abort, consumo anomalo di token sono **red flag da notificare nel report**, mai costi da assorbire in silenzio.

## Note utente
~~~human
$ARGUMENTS
~~~

Un path di file inbox in `$ARGUMENTS` → la coda è quel solo file. Altrimenti la coda intera.

## Costanti

- `LIMITE_AGGIUSTAMENTI = 2` — giri del ciclo validator→writer per file. Esaurito, **si committa comunque**: l'elaborazione non si perde, l'imperfezione residua si dichiara nel messaggio di commit.

## 0. Guardia d'ingresso

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-guard.sh" worktree --docs-root "{docs_root}"
```

- exit 0 → prosegui
- exit 2 → **STOP con notifica**: l'elenco stampato è lavoro non committato di qualcun altro (o di un drain morto a metà) dentro il perimetro doc. Un red flag, non un caso da degradare: un writer che applica patch sopra modifiche non committate altrui le porta nel proprio commit.
- exit 1 → non è un repo git: STOP.

Nessun lock: un run morto a metà lascia il tree sporco e il run successivo si ferma qui — è la guardia stessa il presidio del caso concorrente.

## 1. La coda

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-metrics.sh" --docs-root "{docs_root}" --inbox --natura nozioni --drainable
```

Ordine per `created` crescente — non riordinare. Una riga `malformato` non compare qui (esclusa dal filtro): se la vedi nella coda piena, segnalala nel report e non toccare il file. Coda vuota → report «niente da drenare» e fine.

## 2. Il ciclo — per ogni file, nell'ordine della coda

**2a. Guardia, di nuovo.** Stessa invocazione dello step 0, **prima di ogni file**: il confine fra due file è un punto a tree pulito, e la guardia lì prende lo sporco esterno sopraggiunto mentre il drain lavorava. Sporco → STOP con notifica; i file già smaltiti sono committati, la ripresa è gratis.

**2b. Stato del file.**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" parse --file <path> --format text
```

- **aperte = 0** → il file è il residuo di un run morto dopo l'ultimo flag e prima del commit: salta il giudizio, vai dritto a **2f**.
- le aperte **con** `router → <target>` sono rotte già emesse da un run morto fra router e writer: vanno **dritte al writer** (2d), mai ri-giudicate — un secondo `→` sullo stesso id lascerebbe due rotte nel record storico.
- le aperte **nude** vanno al router (2c).

**2c. Giudizio — un solo spawn di `doc-router`.** `Task` con `subagent_type: doc-router` e prompt:

```
inbox: <path del file>
docs_root: {docs_root}
assumed_knowledge: {docs_root}/reference/assumed-knowledge.md
```

L'envelope `{"verdetti": [...]}` è vincolante. Scrivilo nel registro del file — l'agent è read-only, su disco scrive l'orchestratore:

```bash
echo '<envelope JSON>' | "${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" registro --file <path> --attore router
```

Exit 1 = envelope malformato (id assente, motivo mancante): red flag nel report, salta il file. Lo script è tutto-o-niente: il file non è stato toccato.

**2d. Scrittura — un `doc-writer` per gruppo di target.** Raggruppa le rotte (le nuove del 2c + quelle già in rotta del 2b) per `target`. Per ogni gruppo, `Task` con `subagent_type: doc-writer`, modo scrittura:

```
Modo scrittura.

target: {docs_root}/<target del gruppo>
assumed_knowledge: {docs_root}/reference/assumed-knowledge.md

nozioni:
- id: <nN>
  settore: <dal verdetto>
  grado: <dal verdetto>
  evidenza: <dal verdetto>
  testo: <il testo INTEGRALE della nozione, dal file inbox>
```

Poi registra gli esiti nel file:

```bash
echo '<envelope esiti JSON>' | "${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" registro --file <path> --attore writer
```

**2e. Collaudo — il determinabile prima del modello.**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "{docs_root}"
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/check-doc-links.sh" --docs-root "{docs_root}"
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-metrics.sh" --docs-root "{docs_root}"
```

Exit 2 non è un comando fallito: è un finding (indice scritto con TLDR oltre cap, riferimenti appesi, flag di misura). Raccogli gli output, poi `Task` con `subagent_type: doc-validator`:

```
perimetro: <i file doc toccati dai writer di questo ciclo>
registro: <path del file inbox>
guardiani: <esiti testuali dei tre check, compattati>
assumed_knowledge: {docs_root}/reference/assumed-knowledge.md
```

Se `aggiustamenti` non è vuoto: per al più `LIMITE_AGGIUSTAMENTI` giri, passa gli aggiustamenti a `doc-writer` in **modo aggiustamento** (un Task per file toccato), rilancia i guardiani, rilancia il validator. Esaurito il limite con aggiustamenti ancora aperti: **si committa comunque** — l'imperfezione residua entra come riga dichiarata nel messaggio di commit. Le `note` del validator non bloccano mai: riportale e prosegui.

**2f. Uscita del file — due commit, atomici.**

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
lw_git_add_n_commit "docs(drain): <basename> — <N> nozioni collocate[, residuo: <violazione dichiarata>]" \
    <path del file inbox> <i file doc toccati> "{docs_root}/reference/INDEX.md"
git rm -q <path del file inbox>
git commit -qm "docs(drain): <basename> smaltito — registro in cronologia nel commit precedente" -- <path del file inbox>
```

Il primo commit porta il file inbox **completo** — registro incluso — più la doc derivata: è l'indirizzo storico del lavoro (parent del commit che elimina). Il secondo elimina il file. Poi passa al file successivo (da 2a).

## 3. Chiusura

```bash
lw_git_push
```

Report finale: file smaltiti (con conteggio nozioni collocate/scartate per file) · file saltati e perché (malformati, envelope rifiutato, guardia scattata) · imperfezioni residue committate · red flag (lentezza, token anomali, abort). La misura è lo stato: nessun registro fuori dai file inbox, nessun bookkeeping da riconciliare — un run morto a metà si rilancia e riparte da dove lo stato dice.
