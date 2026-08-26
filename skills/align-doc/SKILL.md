---
name: align-doc
description: Esegue i file inbox di natura sweep — ordini di riscrittura della doc in prosa. Due stadi su un branch doc/sweep-<slug> con PR: doc-extractor (fable) legge il perimetro codice e scrive un referto in temporanea, doc-writer riscrive un bersaglio alla volta dal referto. Nessun router davanti, nessun validator dietro: la sicurezza è il branch, il presidio è la review della PR.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Usa il valore ovunque sotto compaia `{docs_root}`.

Esegui gli **sweep**: ordini di riscrittura della doc scritti in prosa da un umano, unico produttore di questa natura. Catena corta e senza giudici — leggi l'ordine, estrai, riscrivi, apri una PR. Nessun router davanti (non collochi niente di nuovo: riscrivi ciò che è già collocato) e nessun validator dietro (una doc driftata non offre un metro, e un giudice puntiglioso su una riscrittura di massa produce rumore). **La sicurezza è git**: su main non atterra niente finché qualcuno non mergia. Che il risultato sia perfetto non è un'attesa — su un perimetro grande è scontato che non lo sia, e la PR è dove lo si constata.

Nessuna domanda all'utente: giri anche nel notturno, e il presidio umano è asincrono — la review della PR.

## Note utente
~~~human
$ARGUMENTS
~~~

Un path di sweep in `$ARGUMENTS` → la coda è quel solo file.

## 0. Guardia d'ingresso

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-guard.sh" worktree --docs-root "{docs_root}"
```

Exit 2 → STOP con notifica · exit 1 → non è un repo git, STOP.

## 1. La coda

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-metrics.sh" --docs-root "{docs_root}" --inbox --natura sweep --drainable
```

Ordine `created` crescente. Coda vuota → report e fine.

## 2. Il ciclo — per ogni sweep

**2a. Il branch è lo stato.** `slug` = basename del file senza estensione, `branch` = `doc/sweep-<slug>`.

```bash
git branch --list "doc/sweep-<slug>"; git ls-remote --heads origin "doc/sweep-<slug>" 2>/dev/null
```

Branch esistente (locale o remoto) = **sweep in volo**, la PR è aperta: salta il file. È ciò che permette a un notturno di girare due sere di fila senza ripartire da capo. Poi la guardia, di nuovo (stessa invocazione dello step 0).

**2b. Leggi l'ordine.**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" parse --file <path> --format text
```

La prosa è l'ordine, integrale. Le ancore sono **indicazioni, non perimetri** — facoltative, mai verificate a valle:

- `codice:` — dove guardare. Assente o `niente` → nessuna estrazione: riscrittura di sola prosa, che riformula i fatti del target senza introdurne.
- `doc:` — dove scrivere. Assente → i bersagli si ricavano dalla prosa, via INDEX quando l'ordine nomina un componente.
- `modo:` — `integra` (default: assorbi la doc preesistente) | `riscrivi` (rasala e riparti dal referto).
- `online: si` — solo con questa riga la doc @-importata da `CLAUDE.md` entra nei bersagli; la **lista** degli @-import resta comunque fuori (topologia, mestiere di `rebalance-doc`).

**2c. Sul branch.**

```bash
git checkout -b "doc/sweep-<slug>"
```

Da qui in poi main non si tocca, fino al `checkout main` finale.

**2d. Stadio 1 — estrazione.** Solo se `codice:` indica qualcosa:

```bash
TMPDIR_SWEEP="$(mktemp -d /tmp/loom-sweep-<slug>.XXXXXX)"
```

Partiziona il perimetro codice in **componenti** (una lettura per componente, non una gigante). Per ogni componente, `Task` con `subagent_type: doc-extractor`:

```
perimetro: <i path del componente>
ordine: <la prosa dello sweep, integrale>
out: <TMPDIR_SWEEP>/<componente>.md
```

Il referto è prolisso per progetto e **non entra mai nel sistema doc**: vive nella temporanea, non si committa, muore a fine giro. Una `confidence: bassa` nel ritorno è un red flag da riportare nella PR.

**2e. Dalla prosa ai file — il pezzo che nessun agent copre.** Ricava i **bersagli**: da `doc:` quando c'è, dall'ordine e dall'INDEX quando nomina un componente. Lista esplicita di file, dichiarata nel report e nel corpo della PR.

**2f. Stadio 2 — stesura.** Un `Task` con `subagent_type: doc-writer` **per bersaglio**, modo sweep:

```
Modo sweep.

target: <path del bersaglio>
ordine: <la prosa dello sweep, integrale>
referto: <path del referto pertinente in TMPDIR_SWEEP, o vuoto>
modo: <integra | riscrivi>
assumed_knowledge: {docs_root}/reference/assumed-knowledge.md
```

Lo sweep **non cambia il numero dei file**: il writer non esce dal file che riceve. Un bersaglio che finisce sopra la soglia di split ci resta — lo raccoglie `rebalance-doc` al giro dopo.

**2g. Guardiani e chiusura del branch.**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "{docs_root}"
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/check-doc-links.sh" --docs-root "{docs_root}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
git rm -q <path del file sweep>
lw_git_add_n_commit "docs(sweep): <slug> — <N> bersagli riscritti" \
    <i bersagli> "{docs_root}/reference/INDEX.md" <path del file sweep>
rm -rf "$TMPDIR_SWEEP"
```

Il file sweep muore **nello stesso commit** della patch: mergiare la PR lo fa sparire da main; chiudere la PR e cancellare il branch lo rimette in coda, con l'ordine da riscrivere meglio.

```bash
git push -u origin "doc/sweep-<slug>" && \
gh pr create --title "docs(sweep): <slug>" --body "<ordine integrale + lista bersagli + esiti guardiani + red flag>" || \
echo "senza remote/gh: branch locale doc/sweep-<slug>, merge a mano"
git checkout main
```

Senza remote il giro degrada al solo branch, mergiato a mano — dillo nel report.

## 3. Chiusura

Report: sweep eseguiti (branch e PR), saltati perché in volo, bersagli per sweep, red flag (confidence bassa, guardiani rossi — che non bloccano: finiscono nel corpo della PR, dove il diff si legge).
