# Gestione Documentazione

Contratto unico delle convenzioni doc. Vive **plugin-side** in `${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md`: non esiste una copia per-progetto e non esiste override. Chi scrive doc lo **legge** a quel path — le skill lo passano ai subagent, che nascono con contesto pulito e non ereditano l'iniezione di sessione.

## Online / Offline

Doc progetto = due livelli:

- **Online**: caricata nel contesto a **ogni** sessione via `@-import` in `CLAUDE.md`. Orientamento, perimetro, as-is.
- **Offline**: `{docs_root}/reference/`, dettaglio on-demand. `reference/INDEX.md` la elenca coi TLDR.

Doc utente del plugin (questo file + `task-management.md`) si auto-inietta a SessionStart, senza `@-import`.

**Il costo online è un vincolo di progettazione, non un dettaglio.** Gli `@-import` si pagano a ogni sessione prima che il modello legga una riga di codice. E il TLDR di un file offline finisce dentro l'INDEX, che è online: un TLDR prolisso si paga come se il file intero fosse online.

## Principi editoriali

Doc = fotografia dello stato attuale, non diario dei cambiamenti.

- **Solo as-is**: scrivi al presente lo stato corrente. No cronologia, no changelog, no "prima/dopo", no date/task/PR inline. La storia vive in git.
- **Motivazioni → solo offline**: il *perché* di una scelta (trade-off, alternative scartate, contesto) sta in `reference/`. Online tiene il *cosa/come* del perimetro.
- **Compatta: sostituisci, non appendere**: a ogni modifica riscrivi as-is la sezione toccata, non stratificare versioni successive.
- **Coordinate non opache**: ogni id scritto su file porta una maniglia verbo+oggetto — `D07 (unificare docs-root)`, mai `D07` nudo. Un numero non si risolve a memoria a settimane di distanza.

## Soglie

Numeri, non giudizi a runtime: due verifiche sullo stesso file devono dare lo stesso esito.

- **Split**: file ≥ **15.000 char** → va splittato. Il taglio è **per perimetro**, mai per byte — e ogni frammento nasce col proprio TLDR-ancora, altrimenti lo split disperde l'unica ancora esistente e peggiora la reperibilità invece di migliorarla.
- **TLDR**: cap **600 char**. `build-index.sh` avvisa a stderr oltre soglia.

## Formato file offline

Header standard per la generazione dell'indice. Il TLDR sta **esattamente sulla riga 3**:

```markdown
# Titolo

> **TLDR**: <ancora primaria>

Contenuto dettagliato...
```

**Il TLDR è un'ancora, non un riassunto**: deve far decidere *se aprire* il file, non risparmiare l'apertura. Trigger concreti separati da `·` — comando, flag, tag, pattern, keyword, messaggio d'errore, frase con cui uno cercherebbe la cosa. Se riassume il contenuto diventa un secondo documento da leggere, e l'indice smette di essere un indice.

- ✅ `deck-run --resume · sidecar session-tasks.jsonl · "bindare una task a una sessione"`
- ❌ `Descrive il funzionamento del deck e le sue interazioni con le sessioni.`

## Generazione indice

`build-index.sh` rigenera `reference/INDEX.md` dai TLDR. Path cross-install:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh
```

Emette **liste**, non tabelle. Un file senza TLDR sulla riga 3 resta fuori dall'indice (warning a stderr). Parametri: `--dir`, `--output`, `--exclude` (comma), `--title`.

## Manutenzione

Due skill gemelle, distinte dalla **fonte di verità** contro cui misurano la doc:

- `align-doc` — misura contro il **codice** → trova i **drift** (la doc dice X, il sorgente fa Y). Un drift è peggio di una lacuna: la doc offline esiste per *sostituire* la lettura del codice, quindi chi si fida agisce su una realtà inesistente e nessun segnale glielo dice.
- `lint-doc` — misura contro **questo contratto** → trova le violazioni (file sopra soglia, TLDR-riassunto, residui storici, costo online). Non apre mai i sorgenti.

Entrambe girano su `doc-auditor` **read-only** — non scrive, quindi N perimetri si ispezionano in parallelo sulla stessa working copy — e producono un registro con verdetti proposti. Applica `doc-writer`, solo sulle voci che l'utente approva. Le misure numeriche (char per file, char TLDR, footprint per-sessione incluse le entry hook) vengono da `scripts/docs/doc-metrics.sh`, non da un giudizio a runtime.

## Freshness

**Doc segue codice, stesso commit.** Nuovo perimetro (servizio, comando, export pubblico) → file online se serve orientamento, offline se serve dettaglio consultabile. Nuovo file in `reference/` → rigenera l'indice.

## Origine D-task

Le task documentali (`D{N}`) nascono da due path:

- **Spot** via `/loom-works:doc-task` — esigenza documentale identificata dall'utente. Nessun parent.
- **Gate al checkpoint** di una code task con `## Doc Impact` non vuoto. Opzione `[2]` del gate (vedi [Task Management §Doc Impact gate](./task-management.md)). Il D-file porta `**Parent Task**: T{N}`, il parent ha `- [ ] D{N} (<maniglia>) chiusa` in Acceptance. Back-link bidirezionale gestito da `checkpoint-task`.

Task e lane: vedi [Task Management](./task-management.md).

## Markdown token-efficiente

Tabelle markdown = peggior formato token/info, e una cella lunga sfonda la larghezza del terminale. Prosa strutturata con bullet = miglior compromesso.

- Tabelle → liste `- chiave: valore`
- H2 con 1 riga → `**Titolo.** Testo inline`
- H3 etichetta → bullet `- **Label:** contenuto`
- No separatori `---`, usa albero bullet
- Gerarchie → indentazione bullet, no heading multipli
- Sezioni brevi → uniscile; header ogni 2-3 righe = rumore
