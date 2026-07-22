# Gestione Documentazione

## Online / Offline

Doc progetto = due livelli:

- **Online**: caricata contesto Claude Code ogni sessione, orientamento/overview. Referenziata `CLAUDE.md` via `@-import`.
- **Offline**: `docs/reference/`, dettagliata, on-demand. `docs/reference/INDEX.md` elenca file con TLDR.

### Doc del plugin

Doc utente plugin (questo file + `task-management.md`) auto-inietta via hook SessionStart, no `@-import`. Doc progetto utente segue convenzione standard: online → `CLAUDE.md`, offline → `INDEX.md`.

Questo file = filosofia generale. Implementazione = responsabilità progetto. `/loom-works:init` propone scaffold minimale (`docs/tasks.md`, `docs/reference/INDEX.md`, dirs).

## Principi editoriali

Doc = fotografia dello stato attuale, non diario dei cambiamenti.

- **Solo as-is**: scrivi al presente lo stato corrente. No cronologia, no changelog, no "prima/dopo", no date/task/PR inline. La storia vive in git.
- **Motivazioni → solo offline**: il *perché* di una scelta (trade-off, alternative scartate, contesto) sta in `docs/reference/`. Online descrive *cosa* è e *come* funziona il perimetro, mai *perché* è stato scelto.
- **Compatta: sostituisci, non appendere**: a ogni modifica riscrivi as-is la sezione toccata, non stratificare versioni successive. Chiudendo una task (es. refactor) documenta solo l'esito + motivazioni generali, non cosa è cambiato.

## Formato file offline

Header standard `docs/reference/` per generazione indice:

```markdown
# Titolo

> **TLDR**: Descrizione breve (1-2 frasi). Estratta per l'indice.

Contenuto dettagliato...
```

Ancora primaria TLDR = trigger concreto (tag, comando, pattern, keyword) che decide apertura. Descrizione astratta = ancora inefficace.

## Generazione indice

`build-index.sh` genera `docs/reference/INDEX.md` da TLDR dei `.md`. Path canonico cross-install:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh
```

Già integrato negli script del plugin. Parametri: `--dir`, `--output`, `--exclude` (comma), `--title`.

## Freshness

- Nuovo endpoint/tool → reference in `docs/reference/operations/`
- Nuova utility/export → file online (orientamento) + offline (reference)
- Nuovo servizio/job → file online descrive perimetro
- Nuovo file reference → run `build-index.sh`

**Principio**: doc segue codice. Aggiungi export → aggiorna doc stesso commit.

## Origine D-task

Le task documentali (`D{N}`) nascono da due path:

- **Spot** via `/loom-works:doc-task` — l'utente identifica un'esigenza documentale e crea una task dedicata. Nessun parent.
- **Gate al checkpoint** di una code task con `## Doc Impact` non vuoto. Opzione `[2]` del gate (vedi [Task Management §Doc Impact gate](./task-management.md)). Il D-file porta `**Parent Task**: T{N}`, il parent ha `- [ ] D{N} chiusa` in Acceptance. Back-link bidirezionale gestito da `checkpoint-task`.

Task e lane: vedi [Task Management](./task-management.md).

## Markdown token-efficiente

Tabelle markdown = peggior formato token/info. Prosa strutturata con bullet = miglior compromesso.

- Tabelle → liste `- chiave: valore`
- H2 con 1 riga → `**Titolo.** Testo inline`
- H3 etichetta → bullet `- **Label:** contenuto`
- No separatori `---`, usa albero bullet
- Gerarchie → indentazione bullet, no heading multipli
- Sezioni brevi → uniscile; header ogni 2-3 righe = rumore

Refs: **LLMLingua** (MSR), paper **PromptAgent**, "prompt compression", note Anthropic context efficiency.