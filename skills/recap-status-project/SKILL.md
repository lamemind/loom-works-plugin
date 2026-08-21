---
name: recap-status-project
description: Recap del progetto intero — quadro di cosa è aperto, in che stato, quali fili sono vivi, con cross-check doc↔git/fs. Nessuna proposta di cosa fare adesso.
allowed-tools: Bash(*), Read, Glob
model: opus
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `{docs_root}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

## Note utente
~~~human
$ARGUMENTS
~~~

Panoramica dello stato corrente del **progetto intero**, per riorientarsi all'inizio di una sessione o dopo un context-switch. **Read-only**: non scrive né modifica nessun file.

Normalmente ci arrivi da `recap-status` quando nessuna task è attiva. Invocata a mano produce il quadro intero **anche** con una task attiva in contesto: chi la nomina sta chiedendo lo zoom largo, e la task attiva diventa una riga fra le altre.

## Grado di competenza — `K1` sul progetto

Chi chiede un recap dichiara, con l'atto stesso, di non avere la bussola della situazione. Scrivi quindi a **`K1`** su un perimetro dichiarato:

- **cosa** — il progetto intero: le sue task, le sue epiche, il suo stato
- **dove** — tutto il dominio del progetto (qui *cosa* e *dove* coincidono, perché lo zoom è già il più largo)

`K1` significa: termini comuni nudi, termini specialistici glossati alla prima occorrenza, implicazioni sempre esplicitate, nessuna ancora al mondo di tutti i giorni. La scala `K0`-`K3` non la ridefinisci — vive nell'output style; qui dichiari solo a che grado leggerla dentro il perimetro.

**Fuori dal perimetro vale il grado dichiarato normalmente**: un recap di progetto non abbassa `java`, `sql` o qualunque altra materia — il vuoto che un recap presume riguarda lo stato di un lavoro, non il possesso di un vocabolario.

**Un `[Kx]` inline vince secco** sul settore che nomina: è la dichiarazione cosciente di quanto l'utente ricorda adesso, e correggerla significherebbe non credergli. I settori che l'override non nomina restano a `K1` dentro il perimetro.

**Le coordinate opache restano opache a ogni grado.** `T113`, `D14`, `#4782` non sono termini da imparare, sono indirizzi: ogni citazione porta la sua maniglia verbo+oggetto — `T113 (partizione di recap-status)`, mai `T113` nudo.

## Fase 1 — Raccolta dati

**1a. Stato git/fs** — esegui:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/recap-git-status.sh
```

**1b. Doc** — leggi in parallelo dove possibile:
- `{docs_root}/tasks.md` → Tasks Overview + Execution Plan
- L'output script dice `active: <path>` o `none` per current-task
  - Se attivo: leggi il task file puntato (path relativo alla repo root)
- Glob `{docs_root}/tasks/*.md` → leggi tutti i file task che non hanno `Progress: ✔️` nella loro intestazione (al più 8-10 task — non serve leggere i completati se ce ne sono molti)

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
| **Epiche aperte** | se ci sono task `Size: Epic` non chiuse — cappello + figlie aperte, raggruppate |
| **Fondamenta consolidate** | su progetti maturi (≥5 task done) — cosa è già a terra, raggruppato per area |
| **⚠️ Incongruenze** | se ce ne sono — sezione separata, evidenziata |
| **Gap / residui** | se una task ha lavoro non chiuso — checklist prima di completare |
| **Filo conduttore** | se ci sono deps implicite tra task — priorità nascosta, cross-deps concettuali |

**Non fare un dump di tasks.md.** Il valore è il giudizio interpretativo: cosa è davvero completo, cosa è bloccato, cosa va chiuso prima, cosa si può fare ora. Ma includi sempre titolo task (ID nudo non parlante).

## Fase 4 — Chiusura: la domanda, non la proposta

**Non proporre una singola cosa da fare adesso.** A questo zoom convivono task orfane ed epiche, cioè unità di lavoro non commensurabili fra loro: nominarne una fingerebbe un ordinamento che il progetto non possiede. Vale anche per le forme travestite — un elenco di fili «ordinato per convenienza» è una proposta con un'altra faccia, e reintroduce l'ordinamento dalla porta di servizio.

Chiudi invece con una **domanda diretta** all'utente su quale filo tirare, inline in markdown, tono colloquiale e coerente col progetto. **No `AskUserQuestion`.**

La risposta operativa arriva al giro dopo: quando il filo scelto diventa la task attiva, scatta `recap-status-task` o `recap-status-epic`, ed è lì che la proposta nomina un movimento preciso.
