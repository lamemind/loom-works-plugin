---
name: capture-doc
description: Capture ad-hoc doc notions outside of a task. Invokes doc-writer subagent inline.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion
model: sonnet
---

Cattura **estemporanea** di una nozione documentale (fuori dal ciclo task). Leggi il contesto conversazionale corrente + eventuale hint dell'utente, invoca `doc-writer` che **applica la patch** al working tree; poi rivedi il diff e **accetti** (stage) o **rifiuti** (restore).

Flusso **apply-first**: il doc-writer non ritorna più una proposta come testo (invisibile in chat) — scrive direttamente i file. La modifica diventa un diff reale, ispezionabile nel pannello git. Stage = approvazione, restore = rifiuto.

Input utente:
~~~human
$ARGUMENTS
~~~

**YOLO**: se `$ARGUMENTS` contiene il token `yolo` (case-insensitive), salta la review e tiene la patch applicata. Strippa il token prima di passare il resto al subagent.

## Scope

Questa skill è **path 3** (estemporaneo) del triple-capture di loom-works:
1. Task-bound capture: `create-task`, `run-task` → `## Doc Impact` nel task file
2. Task-bound processing: `checkpoint-task` Doc Impact gate → invoca **questa skill** inline (opzione [1]) oppure `doc-task` (opzione [2])
3. **Estemporaneo (questa skill)**: fuori dal ciclo task, review immediata

Nessun worktree, nessun commit automatico. La patch accettata resta **staged** (non committed); quella rifiutata è restorata via git.

**Invocazione da checkpoint-task gate**: il caller passa la voce Doc Impact come hint in `$ARGUMENTS` e il contesto conversazionale corrente. I file accettati restano staged → il commit doc separato del checkpoint (step 7) li raccoglie, atomico col checkpoint.

## Prerequisiti

Progetto inizializzato con `docs/reference/INDEX.md`. La verifica è implicita: il subagent `doc-writer` in step 1 legge `INDEX.md` e, se manca, segnala di lanciare `/loom-works:init`. Non anticipare il check con un `test -f`.

## Flusso

### 1. Estrai nozione

Analizza:
- Il **contesto conversazionale immediatamente precedente** (gli ultimi scambi dell'utente e tue risposte)
- L'**input** `$ARGUMENTS` se presente (può essere una frase libera, un hint, o `"come appena discusso"`)

Estrai **una o più nozioni candidate**. Per ciascuna formula:
- **Nozione**: 1-2 frasi concrete (cosa va documentato, perché)
- **Ancora primaria**: trigger concreto (tag, keyword, comando, pattern). Se non la vedi chiara, lascia vuota — il doc-writer la proporrà.

Se NON emerge nulla di significativo → comunicalo e fermati (non invocare il subagent).

### 2. Conferma con l'utente (opzionale ma raccomandata)

Se hai dubbi su quale nozione catturare (il contesto è ambiguo o troppo vasto), prima esegui il ping TTS:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su nozione da catturare"
```
Poi usa `AskUserQuestion` per far scegliere. Se è evidente, procedi senza domande.

### 3. Invoca doc-writer (applica la patch)

Usa `Task` con `subagent_type: doc-writer`. Il subagent **applica** le patch al working tree (niente proposta testuale) e ritorna il contratto `APPLIED:` — lista file con marker `NEW`/`MOD` + `INDEX_REBUILD_NEEDED`.

```
Nozione da documentare:
- **Nozione**: <testo>
- **Ancora primaria**: <testo o vuota>

Contesto:
<estratto rilevante della conversazione, 10-30 righe max>

Docs root: <PROJECT_ROOT>/${user_config.doc_folder_name}

Applica le patch direttamente (Write/Edit), incluso l'eventuale patch a CLAUDE.md; non committare, non rigenerare l'indice. Leggi ${user_config.doc_folder_name}/reference/INDEX.md, scegli target (EXTEND file esistente o NEW). Ritorna il contratto APPLIED: (marker NEW/MOD per ogni file) + INDEX_REBUILD_NEEDED.
```

**YOLO**: stesso invito, ma **salta gli step 4** (niente review): la patch resta applicata. Vai dritto a step 5.

### 4. Review dal diff → ok / edit / skip

**Non stampare il diff in chat** — un file reference NEW è 200+ righe e brucia contesto; è già ispezionabile, meglio, nel pannello git di VS Code. Stampa solo la **lista file** dal contratto `APPLIED:`, col marker:

```
Patch applicata (rivedi il diff nel pannello git):
- MOD docs/reference/foo.md
- NEW docs/reference/bar.md
```

Poi il ping TTS e `AskUserQuestion` con opzioni `ok` / `edit` / `skip`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su patch doc da tenere o scartare"
```

Gestione della scelta (path assoluti, `cwd` = project root):

- **ok** → **stage** i file: `git add -- <file>...`. Lo stage è insieme *approvazione* e *punto di ripristino*: un rifiuto successivo su un file condiviso torna a questo stato, non a HEAD. Vai a step 5.
- **skip** → **restore** (annulla la patch, working tree pulito), per ogni file secondo il marker:
  - `MOD` → `git restore -- <file>`
  - `NEW` (untracked, `git restore` non lo recupera) → `rm -- <file>`
  
  Nessuna modifica persiste. **Salta step 5** (niente rebuild INDEX su patch scartata). Vai a step 6.
- **edit** → restore (come skip) + **rilancia lo step 3** col feedback dell'utente, su base pulita. Poi torna a step 4.

**no-repo** (nessun git): niente stage né restore. La patch resta applicata; il gate degrada a **informativo** — stampa la lista file + avviso «no-repo: patch applicata, nessun rollback automatico», **nessuna** `AskUserQuestion` ok/skip (non c'è reversibilità da offrire). Rileva con `git rev-parse --is-inside-work-tree 2>/dev/null` prima di offrire il gate.

### 5. Rigenera INDEX se serve

Solo su patch **accettata** (ok) e se il contratto `APPLIED:` porta `INDEX_REBUILD_NEEDED: yes` (o sai che ha toccato `${user_config.doc_folder_name}/reference/`):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "${user_config.doc_folder_name}"
```

Poi il ping TTS:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "doc catturata"
```

Se `INDEX.md` è stato rigenerato, mettilo in stage anch'esso: `git add -- ${user_config.doc_folder_name}/reference/INDEX.md`.

### 6. Report finale

Lista sintetica dei file accettati (staged) / scartati (restored) e se l'INDEX è stato rigenerato. Stop.

**Non committare**: la patch accettata resta **staged** (non committed). Il commit è dell'utente in standalone, del `checkpoint-task` quando questa skill è invocata dal gate.

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici.

## Note

- Il subagent lavora **in-place**: nessun worktree, nessun branch. Se il progetto è `no-repo`, funziona uguale (il gate degrada a informativo, vedi step 4).
- Per capture **in** una task, usa `create-task` / `run-task` (path 1), non questa skill.
- Il doc-writer opera su **tutta la doc** (online `docs/project/`, `docs/meta/`, offline `docs/reference/`) e applica **anche una patch a `CLAUDE.md`** quando serve (es. aggiunta `@-import` per un nuovo file online). Quel file compare come `MOD CLAUDE.md` nel contratto `APPLIED:` → segue la stessa sorte del resto: staged su ok, restorato su skip.
- **Apply-first**: la review dell'utente è sul diff reale (working tree), non su un testo di ritorno del subagent. Stage = approvazione, restore = rifiuto. Lo stage-su-ok è anche il *punto di ripristino* che protegge le patch approvate da un rifiuto successivo su file condiviso.
