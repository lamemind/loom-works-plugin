# Gestione Documentazione

## Online / Offline

Doc progetto = due livelli:

- **Online**: caricata contesto Claude Code ogni sessione, orientamento/overview. Referenziata `CLAUDE.md` via `@-import`.
- **Offline**: `docs/reference/`, dettagliata, on-demand. `docs/reference/INDEX.md` elenca file con TLDR.

### Doc del plugin

Doc utente plugin (questo file + `task-management.md`) auto-inietta via hook SessionStart, no `@-import`. Meccanismo: `../INTEGRATION.md` §5.4. Doc progetto utente segue convenzione standard: online → `CLAUDE.md`, offline → `INDEX.md`.

Questo file = filosofia generale. Implementazione = responsabilità progetto. `/loom-works:init` propone scaffold minimale (`docs/tasks.md`, `docs/reference/INDEX.md`, dirs).

## Formato file offline

Header standard `docs/reference/` per generazione indice:

```markdown
# Titolo

> **TLDR**: Descrizione breve (1-2 frasi). Estratta per l'indice.

Contenuto dettagliato...
```

Ancora primaria TLDR = trigger concreto (tag, comando, pattern, keyword) che decide apertura. Descrizione astratta = ancora inefficace. Riforma TLDR: `../INTEGRATION.md` §4.6.

## Generazione indice

`build-index.sh` genera `docs/reference/INDEX.md` da TLDR dei `.md`. Path canonico cross-install:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh
```

Già integrato (`[x]` in `../INTEGRATION.md` §2.3). Parametri: `--dir`, `--output`, `--exclude` (comma), `--title`.

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