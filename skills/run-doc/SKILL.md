---
name: run-doc
description: Multi-round workflow for documentary tasks (D{N} prefix). Spawns a doc-writer subagent per chunk.
allowed-tools: Bash(*), Read, Edit, Glob, Grep, Task, AskUserQuestion
model: sonnet
---

Workflow adattivo per task documentali. Complementa `run-task` (che resta code-only).

Input utente:
~~~human
$ARGUMENTS
~~~

## Scope

Questa skill orchestra un ciclo **a giri** su una task di tipo doc (prefix `D`):

1. Pianifica la partizione in **chunks** (primo giro)
2. Per ogni chunk, spawna `doc-writer` come subagent (tool `Task`)
3. Parsa il ritorno `done|blocked`, aggiorna `## Execution`, checkpoint
4. Continua fino a completamento, blocco o break-point utente

Architettura **option B** (DESIGN §6): la main session non fa lavoro editoriale — orchestra. Il subagent nasce fresco per ogni chunk (contesto sempre pulito per la lettura codice + patch doc). `/clear` non è per-chunk: è intervento utente raro, coperto da cold-restart via task file.

## Prerequisiti

- Task file deve esistere in `${user_config.doc_folder_name}/tasks/D{N}-*.md` con il template doc-task
- Progetto inizializzato (`${user_config.doc_folder_name}/reference/INDEX.md` presente); altrimenti il primo subagent doc-writer segnala di lanciare `/loom-works:init`

## 0. Risolvi la task

Con questa precedenza:
1. Se le Note utente contengono un ID (es. `D03`), risolvilo via `Glob ${user_config.doc_folder_name}/tasks/${id}-*.md`
2. Altrimenti leggi il symlink `${user_config.doc_folder_name}/current-task.md`

Verifica che la task sia di **tipo doc** (prefix `D`). Se è code (prefix `T`), reindirizza l'utente a `/loom-works:run-task` e fermati.

Stampa riassunto compatto PRIMA di qualsiasi altra azione:

```
📝 ${taskId} — ${titolo}
📍 Progress: ${progress}
📂 Target: ${n_target_items} aree
🎯 Deliverables: ${n_deliverables}
```

## 1. Determina lo stato del workflow

Leggi `## Execution` del task file. Due casi:

- **Primo giro**: sezione vuota o senza sottosezioni `### Chunk N`. Vai a §2 Planning.
- **Giri successivi**: chunks già presenti. Vai a §3 Loop.

## 2. Planning (solo primo giro)

### 2.1 Analisi

Leggi dal task file:
- `## Description`, `## Target`, `## Acceptance Criteria`, `## Deliverables Checklist`, `## Fonti`

Leggi per overview del landscape (no deep read — quello lo fa il subagent per chunk):
- `CLAUDE.md` del progetto
- `${user_config.doc_folder_name}/reference/INDEX.md`
- `${user_config.doc_folder_name}/meta/doc-management.md` se presente (convenzioni)

Scorri le Fonti per farti un'idea del volume.

### 2.2 Proposta partizione

Scomponi il lavoro in **chunks**. Ogni chunk deve:
- Avere uno **scope concreto** (N file sorgente / una directory / un dominio / un pezzo di diff)
- Essere dimensionato per un singolo giro di doc-writer (euristica: ≤10 file sorgente da leggere, ≤3 file doc da toccare)
- Essere indipendente o esplicitamente sequenziale

Proponi la partizione all'utente via `AskUserQuestion` chiusa:
- Se esistono varianti sensate: 2-3 opzioni con trade-off (granularità, ordine, raggruppamento)
- Se la partizione è ovvia: conferma binaria (ok / rivedi)

**Non procedere senza ok utente**. La partizione è una decisione strutturale.

### 2.3 Scrivi chunks nel task file

Dopo ok utente, popola `## Execution`:

```markdown
## Execution

### Chunk 1 — <scope>
**Status**: pending
**Round**: -

### Chunk 2 — <scope>
**Status**: pending
**Round**: -

<...N chunks...>

### Rounds

### Resume context
<1-3 righe di contesto editoriale iniziale: eventuali decisioni già emerse dal planning, stile noto, convenzioni da rispettare>
```

### 2.4 Checkpoint

Invoca `/loom-works:checkpoint-task` per committare il planning (in repo-mode). Poi procedi a §3.

## 3. Loop

### 3.1 Pick chunk

Il prossimo chunk con `Status: pending`. Se non ce ne sono, vai a §4 Finalizzazione.

Se tutti i restanti sono `blocked`, fermati a §4 con stato bloccato.

### 3.2 Spawn doc-writer come subagent

Invoca il tool `Task` con `subagent_type: doc-writer` e prompt self-contained:

```
Sei invocato come subagent da /loom-works:run-doc.

## Task documentale
${taskId} — ${titolo del task}

## Chunk corrente
${numero e scope del chunk, copiato dalla sottosezione}

## Target del task
${contenuto della sezione ## Target del task file, integrale}

## Fonti rilevanti
${sottoinsieme di ## Fonti pertinenti a questo chunk; se non sai filtrare, passale tutte}

## Resume context
${contenuto della sezione ### Resume context, integrale}

## Contratto di ritorno
Opera in mode `apply`. Usa AskUserQuestion su ogni ambiguità strutturale (non tornare con domande al livello di ritorno). Non committare.

Il tuo ultimo messaggio DEVE essere formattato così:

STATUS: done | blocked
SUMMARY: <1-2 righe descrittive per il round log>
PATCHES: <lista file toccati, uno per riga>
BLOCK_REASON: <presente solo se STATUS=blocked>

Docs root: ${PROJECT_ROOT}/${user_config.doc_folder_name}
```

### 3.3 Parse ritorno

Dal messaggio finale del subagent estrai:
- `STATUS` (done o blocked)
- `SUMMARY`
- `PATCHES` (lista file)
- `BLOCK_REASON` (se blocked)

Se il formato manca o è corrotto, tratta come `blocked` con `BLOCK_REASON: formato ritorno non parsabile`.

### 3.4 Update Execution

Nel task file:

- Aggiorna la sottosezione del chunk:
  - `**Status**`: `done` o `blocked`
  - `**Round**`: append round corrente (`r1`, `r2`, ...)
  - Se `blocked`:
    - Aggiungi `**Block reason**: ${BLOCK_REASON}`
    - Aggiungi `**Unblock action**: TBD utente` (o suggerimento se evidente)
  - Aggiungi eventuali note editoriali che emergono da PATCHES (es. "esteso common-package.md sezione Logging")

- Append a `### Rounds`: `- **r${N}** (${data_oggi}): ${SUMMARY}` (se blocked: `- **r${N}** (${data}): chunk ${n} blocked — ${motivo sintetico}`)

- Aggiorna `### Resume context` se dal SUMMARY emergono decisioni cross-chunk significative (stile adottato, convenzione scelta, file esteso piuttosto che creato nuovo). Mantieni 2-5 righe.

### 3.5 Rigenera INDEX se serve

Se nei PATCHES compaiono file in `${user_config.doc_folder_name}/reference/`, rigenera l'indice offline:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "${user_config.doc_folder_name}"
```

### 3.6 Checkpoint

Invoca `/loom-works:checkpoint-task` per committare il progresso del giro.

### 3.7 Decidi continuazione

- Se chunk corrente `blocked`: fermati e rimanda all'utente (intervento richiesto)
- Se chunk `done` e ci sono altri `pending`:
  - Default: loop immediato al prossimo chunk
  - Ogni 3 giri consecutivi, inserisci un **break-point** via `AskUserQuestion`: `continua / ferma / rivedi partizione`
- Se tutti done: vai a §4

## 4. Finalizzazione

### Caso completamento pulito
Tutti i chunks `done`:
- Verifica `## Deliverables Checklist`: spunta quelli prodotti. Se ne restano di non coperti, elencali come follow-up.
- Aggiorna il metadata `- **Progress**:` a `✔️ Done`.
- Aggiorna `### Resume context` con un "outcome" sintetico (1-2 righe).
- Esegui il ping TTS:
  ```bash
  source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "doc $(say_id ${taskId}) completata"
  ```
- Suggerisci all'utente di lanciare `/loom-works:checkpoint-task` per il commit finale.

### Caso con blocks residui
Uno o più chunks `blocked`:
- Elenca blocchi con relativi `Block reason` e `Unblock action` richieste
- Suggerisci: replan (rilancia `run-doc` dopo modifica Target/Fonti), discussione utente, o creazione di task-doc separata per sbloccare un dominio
- **Non marcare la task come done**.

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici.

## Note operative

- **`/clear` non serve per-chunk**: ogni subagent nasce fresco, la main session cresce lento (solo task file read + Agent summary per iterazione). Se l'utente sente pressione di contesto dopo molti giri, può interrompere e rilanciare `/loom-works:run-doc` — il task file supporta cold-restart via `### Rounds` e `### Resume context`.
- **Checkpoint per giro**: commit frequenti. In progetto `no-repo`, checkpoint-task degrada a noop silenzioso (nessun commit).
- **Non modificare doc direttamente**: tutto il lavoro editoriale passa dal subagent. Questa skill **orchestra**, non scrive doc.
- **Progress del task file**: a primo giro, aggiorna `- **Progress**:` da `🔵 Todo` a `🟡 In Progress` (coerente con `start-task`, se non già fatto).
