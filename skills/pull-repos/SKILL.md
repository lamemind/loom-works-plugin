---
name: pull-repos
description: Pull del cappello e dei submodule (registro = .gitmodules, nessuna lista a mano) — sblocca gli inbox branch: trovati su main (la presenza È la prova del merge). Non presidiata.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Usa il valore ovunque sotto compaia `{docs_root}`.

Porti dentro il lavoro altrui e **sblocchi** gli inbox di branch che il merge ha portato su main. Nessuna domanda all'utente.

## 1. Pull — il registro è `.gitmodules`

```bash
git pull --ff-only 2>&1 || echo "RED FLAG: pull non fast-forward sul cappello"
git config -f .gitmodules --get-regexp path | awk '{print $2}'
```

Per ogni submodule elencato (nessuna lista scritta a mano: un registro parallelo drifta al primo add):

```bash
git -C <submodule> pull --ff-only 2>&1 || echo "RED FLAG: <submodule>"
```

## 2. Sblocco — la presenza su main È la prova del merge

Un inbox creato su un branch porta `branch:<nome>`: l'indice lo dà valido solo per chi lavora su quel branch, e il file non diventa `drainable`. Trovarlo adesso nel working tree di main significa che il merge è avvenuto — nessun confronto di liste di branch, nessuna domanda su chi ha mergiato. Funziona identico che il merge arrivi dal remoto o l'abbia fatto `merge-lane` in locale.

Per ogni file di `{docs_root}/inbox/` il cui marker porta `branch:` (colonna BRANCH di `doc-metrics --inbox` non vuota):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" marker --file <path> --unset branch --set drainable
```

Tocca la sola riga 3, mai le nozioni — è l'invariante che la primitiva rende strutturale. Exit 1 (malformato) → red flag nel report, file saltato.

## 3. Chiusura

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "{docs_root}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
lw_git_add_n_commit "docs(pull): <N> inbox sbloccati" \
    "{docs_root}/inbox/" "{docs_root}/reference/INDEX.md"
lw_git_push
```

Niente da committare (zero sblocchi) → nessun commit. Report: repo pullati (e quali in red flag), inbox sbloccati.
