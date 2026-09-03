---
name: pull-repos
description: Pull del cappello e dei submodule (registro = .gitmodules, nessuna lista a mano) — sblocca gli inbox branch: trovati su main (la presenza È la prova del merge) e crea una derivazione di align per ogni merge altrui senza doc prenotata. Non presidiata.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Usa il valore ovunque sotto compaia `{docs_root}`.

Porti dentro il lavoro altrui e ne fai discendere il lavoro documentale: **sblocchi** gli inbox di branch che il merge ha portato su main, e **crei una derivazione** per ogni merge che nessun inbox aveva prenotato. Nessuna domanda all'utente: giri anche in `nightly-doc`.

## 1. Pull — il registro è `.gitmodules`

```bash
prima=$(git rev-parse HEAD)
git pull --ff-only 2>&1 || echo "RED FLAG: pull non fast-forward sul cappello"
git config -f .gitmodules --get-regexp path | awk '{print $2}'
```

Per ogni submodule elencato (nessuna lista scritta a mano: un registro parallelo drifta al primo add):

```bash
git -C <submodule> pull --ff-only 2>&1 || echo "RED FLAG: <submodule>"
```

Poi i commit di merge nuovi del cappello: `git log --merges --format='%h %s' ${prima}..HEAD`.

## 2. Sblocco — la presenza su main È la prova del merge

Il drain gira **solo su main**: un inbox creato su un branch vive lì e nessun drain lo raggiunge. Trovarlo adesso nel working tree significa che il merge è avvenuto — nessun confronto di liste di branch, nessuna domanda su chi ha mergiato. Funziona identico che il merge arrivi dal remoto o l'abbia fatto `merge-lane` in locale.

Per ogni file di `{docs_root}/inbox/` il cui marker porta `branch:` (colonna BRANCH di `doc-metrics --inbox` non vuota):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" marker --file <path> --unset branch --set drainable
```

Tocca la sola riga 3, mai le nozioni — è l'invariante che la primitiva rende strutturale. Exit 1 (malformato) → red flag nel report, file saltato.

## 3. Lavoro altrui senza doc prenotata

Per ogni commit di merge del passo 1: `b` = il branch mergiato (dal messaggio del merge). Se **nessuno** dei file sbloccati al passo 2 portava `branch:<b>`, quel lavoro non ha doc in arrivo — creane l'ordine:

```bash
printf '%s\n' "Riallinea la doc al merge di <b>: confronta le pagine dei perimetri toccati col codice arrivato." | \
  "${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" new --docs-root "{docs_root}" \
    --slug align-merge-<b-slugificato> --natura derivazione --drainable \
    --ancora "range:${prima}..HEAD" --ancora "path:<i path toccati dal merge>"
```

## 4. Chiusura

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "{docs_root}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
lw_git_add_n_commit "docs(pull): <N> inbox sbloccati, <M> derivazioni create" \
    "{docs_root}/inbox/" "{docs_root}/reference/INDEX.md"
lw_git_push
```

Niente da committare (zero sblocchi, zero derivazioni) → nessun commit. Report: repo pullati (e quali in red flag), inbox sbloccati, derivazioni create per quali merge. A consumare le derivazioni è `derive-notions` — non invocarlo tu.
