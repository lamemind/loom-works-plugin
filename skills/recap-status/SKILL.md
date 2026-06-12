---
name: recap-status
description: Project status overview — cross-check doc↔git/fs, flag inconsistencies, propose next step.
allowed-tools: Bash(*), Read, Glob
model: opus
---

Panoramica dello stato corrente del progetto per riorientarsi all'inizio di una sessione o dopo un context-switch. **Read-only**: non scrive né modifica nessun file.

## Fase 1 — Raccolta dati

**1a. Stato git/fs** — esegui:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/recap-git-status.sh --docs-root "${user_config.doc_folder_name}"
```

**1b. Doc** — leggi in parallelo dove possibile:
- `${user_config.doc_folder_name}/tasks.md` → Tasks Overview + Execution Plan
- L'output script dice `active: <path>` o `none` per current-task
  - Se attivo: leggi il task file puntato (path relativo alla repo root)
- Glob `${user_config.doc_folder_name}/tasks/*.md` → leggi tutti i file task che non hanno `Progress: ✔️` nella loro intestazione (al più 8-10 task — non serve leggere i completati se ce ne sono molti)

## Fase 2 — Verifica incrociata

Confronta stato *dichiarato* nei doc vs stato *reale* da git/fs. Segnala esplicitamente:

- **Progress stale**: `🟡 0%` (o bassa %) ma commit recenti mostrano lavoro su quella task
- **Da chiudere**: tutti gli AC/deliverable `[x]` ma Progress < 100%
- **Gap deliverable**: file dichiarato nel Deliverables Checklist assente su fs (usa Bash `test -f` o Glob se utile)
- **Symlink stale**: `current-task.md` punta a task con `Progress: ✔️`
- **Lavoro non tracciato**: task `🔵 Todo` ma cartella Folder già popolata o commit rilevanti già presenti

## Fase 3 — Sintesi adattiva

Output in **layout visivo facilitatore**: emoji, tabelle, grassetti, ASCII block. Tono: colloquiale, diretto — non un report formale.

Blocchi disponibili — **seleziona e adatta** in base al progetto reale. Non tutti sono sempre presenti; non usare template fissi.

| Blocco | Quando includerlo |
|--------|-------------------|
| **Identità** | se stack deducibile da CLAUDE.md o README |
| **Stato git** | sempre — branch, HEAD commit, worktree/lane, lavorazioni uncommitted |
| **Task attiva** | se symlink presente — focus sullo stato REALE (confronto AC/deliverable vs git) |
| **Tabella task** | sempre —  ID / Stato / Titolo / preflight. Aggiungi Pri / Size dove aggiungono valore |
| **Fondamenta consolidate** | su progetti maturi (≥5 task done) — cosa è già a terra, raggruppato per area |
| **⚠️ Incongruenze** | se ce ne sono — sezione separata, evidenziata |
| **Gap / residui** | se task attiva ha lavoro non chiuso — checklist prima di completare |
| **Filo conduttore** | se ci sono deps implicite tra task — priorità nascosta, cross-deps concettuali |

**Non fare un dump di tasks.md.** Il valore è il giudizio interpretativo: cosa è davvero completo, cosa è bloccato, cosa va chiuso prima, cosa si può fare ora. Ma includi sempre titolo task (ID nudo non parlante).

## Fase 4 — Chiusura operativa

- Proponi il **next step naturale**: chiudere task X, partire con Y, committare modifiche pending, riconciliare doc stale
- **Chiudi con una domanda diretta** all'utente su cosa aprire/fare — tono colloquiale, coerente col progetto
- **No `AskUserQuestion`** — domanda inline in markdown
