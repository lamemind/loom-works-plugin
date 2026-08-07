---
name: capture-doc
description: Capture ad-hoc doc notions outside of a task. Spawns doc-router for the verdict, then doc-writer for the patch.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `${DOCS_ROOT}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

Cattura **estemporanea** di una nozione documentale (fuori dal ciclo task). Leggi il contesto conversazionale corrente + eventuale hint dell'utente, spawna `doc-router` che **giudica** dove va, poi `doc-writer` che **applica la patch** al working tree; infine rivedi il diff e **accetti** (stage) o **rifiuti** (restore).

Flusso **apply-first**: il writer non ritorna una proposta come testo (invisibile in chat) — scrive direttamente i file. La modifica diventa un diff reale, ispezionabile nel pannello git. Stage = approvazione, restore = rifiuto.

Input utente:
~~~human
$ARGUMENTS
~~~

**YOLO**: se `$ARGUMENTS` contiene il token `yolo` (case-insensitive), salta la review e **auto-accetta**: la patch resta applicata e viene stagiata senza chiedere niente. Strippa il token prima di passare il resto al subagent.

## Scope

Questa skill è l'ingresso **estemporaneo**: una nozione che nasce fuori dal ciclo task e va collocata subito, con review immediata. Le due vie task-bound sono altre e non passano di qui — `create-task` e `run-task` appendono a `## Doc Impact`, e il checkpoint porta quelle voci in `{docs_root}/inbox/` scrivendole da sé, senza spawnare nessuno.

Nessun worktree, nessun commit automatico. La patch accettata resta **staged** (non committed); quella rifiutata è restorata via git.

## Prerequisiti

Progetto inizializzato con `{docs_root}/reference/INDEX.md`. La verifica è implicita: il `doc-router` (step 3) legge `INDEX.md` e, se manca, lo dichiara in `NOTE:` — allora lancia `/loom-works:init`. Non anticipare il check con un `test -f`.

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

### 3. Spawn `doc-router` — il verdetto

Usa `Task` con `subagent_type: doc-router`. Read-only: apre codice, fonti vive e resto della doc per pagare i criteri dipendenti, e ritorna un **registro di rotte** (verdetto, target, evidenza).

```
Nozioni non collocate:
- <nozione 1> — ancora: <ancora o vuota>
- <nozione 2> — ancora: …

Contesto:
<estratto rilevante della conversazione, 10-30 righe max>

Docs root: <PROJECT_ROOT>/${DOCS_ROOT}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo, ha la parola finale su convenzioni e soglie.
Criteri di selezione: ${CLAUDE_PLUGIN_ROOT}/docs/doc-criteria.md — i criteri dipendenti sono il tuo mestiere.
Prefisso ID: CAP

Ritorna solo il registro.
```

**Due spawn, sempre — anche su una nozione sola.** Chi scrive ha un attaccamento al proprio output, quindi un verdetto di scarto è credibile solo se lo dà chi non l'ha scritta. Una scorciatoia sul caso singolo renderebbe condizionale il prompt del writer, che è tagliato per non giudicare mai.

### 4. Spawn `doc-writer` — la patch

Raggruppa le rotte **per file target** e invoca un `doc-writer` per gruppo (mai due writer sullo stesso file: si sovrascrivono a vicenda). Il subagent **applica** le patch al working tree e ritorna il contratto `APPLIED:` — lista file con marker `NEW`/`MOD` + `INDEX_REBUILD_NEEDED`.

Le rotte `drop` **non passano di qui**: non hanno target, e il verdetto è già nel registro — le riporti tu allo step 5. Un registro di soli `drop` significa **nessun writer**: riporta i verdetti e fermati, invece di rilanciare il router con istruzioni più aggressive.

```
Rotte da applicare — verdetto e target sono già decisi e vincolanti, non rivalutarli:

<le voci del registro per questo target: NOTION / VERDICT / TARGET / TLDR / POINTER / WRITE>

Contesto:
<estratto rilevante della conversazione, 10-30 righe max>

Docs root: <PROJECT_ROOT>/${DOCS_ROOT}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo, ha la parola finale su convenzioni e soglie.
Formule TLDR: ${CLAUDE_PLUGIN_ROOT}/docs/tldr-formats.md

Applica le patch direttamente (Write/Edit), incluso l'eventuale patch a CLAUDE.md; non committare, non rigenerare l'indice. Ritorna il contratto APPLIED: (marker NEW/MOD per ogni file) + INDEX_REBUILD_NEEDED.
```

**YOLO**: **salta lo step 5** (niente review) eseguendone da te il ramo **ok**: `git add -- <file>...` su tutti i file del contratto `APPLIED:`, poi step 6. Lo stage non è un dettaglio saltabile — chi invoca in yolo committa con `--no-add`, quindi un file applicato ma non staged non entra in nessun commit e la cattura si perde in silenzio.

### 5. Review dal diff → ok / edit / skip

**Non stampare il diff in chat** — un file reference NEW è 200+ righe e brucia contesto; è già ispezionabile, meglio, nel pannello git di VS Code. Stampa solo la **lista file** dal contratto `APPLIED:`, col marker:

```
Patch applicata (rivedi il diff nel pannello git):
- MOD docs/reference/foo.md
- NEW docs/reference/bar.md
```

Stampa anche i **`drop` del registro** e l'eventuale blocco `DISCARDED:` del writer: sono nozioni che non atterrano da nessuna parte, e il motivo è un verdetto. Taciuto, diventa una cattura che sembra riuscita a metà senza che si sappia perché. Una lista applicata vuota con dei `drop` pieni è un esito legittimo — non rilanciare nessuno dei due subagent per farla scrivere comunque.

Poi il ping TTS e `AskUserQuestion` con opzioni `ok` / `edit` / `skip`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su patch doc da tenere o scartare"
```

Gestione della scelta (path assoluti, `cwd` = project root):

- **ok** → **stage** i file: `git add -- <file>...`. Lo stage è insieme *approvazione* e *punto di ripristino*: un rifiuto successivo su un file condiviso torna a questo stato, non a HEAD. Vai a step 6.
- **skip** → **restore** (annulla la patch, working tree pulito), per ogni file secondo il marker:
  - `MOD` → `git restore -- <file>`
  - `NEW` (untracked, `git restore` non lo recupera) → `rm -- <file>`
  
  Nessuna modifica persiste. **Salta step 6** (niente rebuild INDEX su patch scartata). Vai a step 7.
- **edit** → restore (come skip) + **rilancia dallo step 3** col feedback dell'utente, su base pulita. Si riparte dal router, non dal writer: un feedback sul dove la nozione è atterrata è una correzione del verdetto, e il writer non ha il mandato per cambiarlo.

### 6. Rigenera INDEX se serve

Solo su patch **accettata** (ok) e se il contratto `APPLIED:` porta `INDEX_REBUILD_NEEDED: yes` (o sai che ha toccato `${DOCS_ROOT}/reference/`):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh"
```

**Exit 2** = indice scritto, ma i TLDR elencati su stderr sono oltre il cap: violazione **bloccante** del contratto, non un comando fallito. Non annulla la cattura; se il TLDR fuori cap è quello che hai appena scritto, riscrivilo come ancora prima di chiudere.

Poi il ping TTS:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "doc captured"
```

Se `INDEX.md` è stato rigenerato, mettilo in stage anch'esso: `git add -- ${DOCS_ROOT}/reference/INDEX.md`.

### 7. Report finale

Lista sintetica dei file accettati (staged) / scartati (restored), i `drop` del registro col motivo, e se l'INDEX è stato rigenerato. Stop.

**Non committare**: la patch accettata resta **staged** (non committed). Il commit è dell'utente.

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici.

## Note

- I subagent lavorano **in-place**: nessun worktree, nessun branch. Il gate di review poggia su git (stage su ok, restore su skip), che il modello dà per presente.
- Per capture **in** una task, appendi a `## Doc Impact` (`create-task` / `run-task`), non questa skill.
- Il doc-writer opera su **tutta la doc** (online `{docs_root}/project/`, offline `{docs_root}/reference/`) e applica **anche una patch a `CLAUDE.md`** quando serve (es. aggiunta `@-import` per un nuovo file online). Quel file compare come `MOD CLAUDE.md` nel contratto `APPLIED:` → segue la stessa sorte del resto: staged su ok, restorato su skip.
- **Apply-first**: la review dell'utente è sul diff reale (working tree), non su un testo di ritorno del subagent. Stage = approvazione, restore = rifiuto. Lo stage-su-ok è anche il *punto di ripristino* che protegge le patch approvate da un rifiuto successivo su file condiviso.
