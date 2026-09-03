---
name: nightly-doc
description: Il giro notturno del sistema doc — composizione dei pezzi, zero logica propria: derivazione dai commit spot delle 24h, pull-repos, derive-notions, drain-notions, align-doc (gli sweep, ognuno sul suo branch con PR), report. Replicabile a mano lanciando le skill nello stesso ordine.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task, Skill
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Usa il valore ovunque sotto compaia `{docs_root}`.

Componi i flussi del sistema doc, nell'ordine sotto e senza aggiungere logica: tutto ciò che sai fare lo fanno le skill che invochi, e il giro completo si replica lanciandole a mano nello stesso ordine. Nessuna domanda all'utente.

## 0. I commit spot delle ultime 24 ore

```bash
git log --since "24 hours ago" --no-merges --format='%h %s' | grep -vE 'T[0-9]+'
```

I commit **senza riferimento a task** sono lavoro che nessun task file documenta. Se ce ne sono, crea una derivazione:

```bash
printf '%s\n' "Riallinea la doc ai commit spot delle ultime 24 ore: confronta le pagine dei perimetri toccati col codice arrivato." | \
  "${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" new --docs-root "{docs_root}" \
    --slug align-spot-<data-iso-del-giro> --natura derivazione --drainable \
    --ancora "range:<sha del commit spot più vecchio>~1..HEAD"
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
lw_git_add_n_commit "docs(nightly-doc): derivazione sui commit spot" <INBOX_PATH>
```

## 1–4. La composizione

Invoca le quattro skill, in quest'ordine, ognuna fino in fondo prima della successiva:

1. `/loom-works:pull-repos` — porta dentro il lavoro altrui: sblocca gli inbox `branch:` arrivati su main, crea le derivazioni per i merge senza doc prenotata.
2. `/loom-works:derive-notions` — le derivazioni (comprese quelle appena create) producono file `nozioni`.
3. `/loom-works:drain-notions` — questo stesso giro colloca i file `nozioni`, quelli appena prodotti compresi.
4. `/loom-works:align-doc` — gli sweep: ognuno sul suo branch `doc/sweep-<slug>`, ognuno una PR da leggere. Niente atterra su main.

Una skill che STOPpa sulla guardia del working tree ferma il giro lì: le successive troverebbero lo stesso sporco. Riporta cosa è stato fatto fino al punto di stop.

## 5. Report

Un blocco solo, leggibile al mattino: cosa drenato (file e nozioni) · derivazioni create e consumate · inbox sbloccati · PR aperte dagli sweep · cosa escluso e perché (malformati, guardie, branch in volo) · red flag (lentezza, token anomali, pull falliti).
