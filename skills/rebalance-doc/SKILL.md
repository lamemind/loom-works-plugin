---
name: rebalance-doc
description: La topologia della doc — le tre operazioni cross-file che nessun attore del drain può fare: SPLIT dei file sopra soglia, riesame MERGE? dei troppo piccoli, REGROUP delle cartelle. Sequenziale in quest'ordine, sui flag di doc-metrics; la skill decide e applica, l'helper haiku analizza e verifica la non-perdita. Presidiata, gira a richiesta.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Usa il valore ovunque sotto compaia `{docs_root}`.

La topologia è tua: split, merge di file e regroup sono operazioni **cross-file**, e nessun attore del drain le può fare — il router punta un file, il writer ne tocca uno. **Lo script dà i flag (chi guardare, mai cosa fare); tu decidi e applichi.** Il contenuto si muove **verbatim**, senza riscritture: titoli e TLDR dei file nati da uno split li scrivi tu, il resto si sposta com'è. L'helper haiku fa le analisi (trigger di ricerca, mappa dei TLDR) e la **verifica di non-perdita** — l'unico controllo esterno rimasto, che vale di più proprio perché chi decide è anche chi applica.

Non stai nel notturno e giri presidiata: in dubbio su un taglio o una fusione, chiedi.

## 0. Guardia e misura

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-guard.sh" worktree --docs-root "{docs_root}"
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-metrics.sh" --docs-root "{docs_root}"
```

Guardia exit 2 → STOP con l'elenco. Dalla misura raccogli i flag: `SPLIT` sui file, `MERGE?` sui file, `REGROUP` sulle cartelle. Nessun flag → report «topologia in equilibrio» e fine.

**L'ordine delle fasi è vincolante: ① split → ② merge → ③ regroup.** Gli split cambiano i conteggi di tutto il resto — un merge deciso prima dello split misura file che non esisteranno più, e una partizione dimensionata su file che stanno per essere spezzati nasce stale.

## ① Split — per ogni file flaggato `SPLIT`

1. **Analisi di fondo** — `Task` con `subagent_type: doc-helper`, attività `proponi-taglio`, `file: <path>`. La proposta ritorna gruppi di sezioni con trigger di ricerca distinti.
2. **La decisione è tua**: il taglio è **per perimetro di ricerca** — due trigger distinti, due file — mai per byte. La proposta dell'helper è materiale, non un ordine.
3. **Applica verbatim**: le sezioni si spostano com'erano nel file nuovo (naming col prefisso del file d'origine: `loom-deck-spawn.md` genera fratelli `loom-deck-*`, mai nomi che perdono il prefisso — l'ancora vive anche fuori dalla doc, nei task file e nei commit). Titolo e TLDR-ancora del file nuovo li scrivi tu, riga 3, formula ancora.
4. **Verifica di non-perdita** — `Task` `doc-helper`, attività `verifica-non-perdita`: `originale` = il file com'era (da `git show HEAD:<path>`), `parti` = i frammenti. `completo: false` → reintegra il `mancante` prima di andare avanti.
5. **Riferimenti**: `"${CLAUDE_PLUGIN_ROOT}/scripts/docs/check-doc-links.sh" --docs-root "{docs_root}"` — ogni `DANGLING`/`NOSECTION` prodotto dal taglio si rimappa sul frammento giusto, a mano.
6. `build-index.sh --docs-root "{docs_root}"`, poi commit del solo split:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
   lw_git_add_n_commit "docs(rebalance): split <file> → <frammenti>" <i file coinvolti> "{docs_root}/reference/INDEX.md"
   ```

## ② Merge — per ogni file flaggato `MERGE?`

**Il flag è un riesame, non un ordine.** Cerca un **fratello dello stesso perimetro di ricerca**: se non c'è, il file resta — un file piccolo che sta da solo per una ragione non si fonde, e lo dichiari nel report. Se c'è:

1. Fondi A dentro B **verbatim** (una sezione nuova o una fusione di sezioni affini; per ricuciture di prosa usa `doc-helper` attività `fondi-paragrafo`).
2. `verifica-non-perdita` sull'originale A contro B risultante.
3. `git rm` di A; `check-doc-links` → rimappa i riferimenti ad A verso B; `build-index`; commit del solo merge.

## ③ Regroup — per ogni cartella flaggata `REGROUP`

1. **Analisi di fondo** — `Task` `doc-helper`, attività `mappa-tldr` con le voci `{file, tldr}` della cartella (i TLDR, **mai i corpi**).
2. **La partizione la decidi tu**, sulla mappa: le categorie sono **perimetri di ricerca**, non temi · nessuna categoria «varie» — chi non appartiene resta in root, che è il default e non il residuo · zoom disomogeneo ammesso — una cartella da un file solo accanto a un file sciolto è un esito corretto.
3. **Applica**: `git mv` senza rinominare i file (lo spostamento cambia il path, mai il nome), riscrittura dei riferimenti che `check-doc-links` segnala, `build-index`, commit.

## Chiusura

```bash
lw_git_push
```

Report per fase: cosa flaggato, cosa applicato, cosa lasciato com'era e perché (il `MERGE?` respinto è un esito, non un'omissione), esiti delle verifiche di non-perdita, riferimenti rimappati.
