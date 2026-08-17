---
name: capture-doc
description: Capture ad-hoc doc notions outside of a task. Chain of doc-router (verdict), doc-writer (patch), doc-verifier (collaudo), then commit.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `{docs_root}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

Cattura **estemporanea** di una nozione documentale (fuori dal ciclo task). Leggi il contesto conversazionale corrente + eventuale hint dell'utente, spawna `doc-router` che **giudica** dove va, `doc-writer` che **applica la patch**, `doc-verifier` che la **collauda**; poi committa.

Input utente:
~~~human
$ARGUMENTS
~~~

## Una sola domanda ammessa, e non è sulla patch

Puoi chiedere **cosa** catturare quando il contesto è ambiguo (step 2). Non chiedi mai **se tenere** ciò che è stato scritto: quello lo misura `doc-verifier` contro il contratto, allo step 5.

Il loop di review che stava qui — stage come approvazione, restore come rifiuto, e lo stage-su-ok come punto di ripristino — è stato **rimosso**. Era l'unico collaudo della skill, e poggiava su una patch lasciata nell'indice in attesa di un giudizio: lo stage git è uno per *worktree*, non per sessione, quindi quella patch veniva raccolta dal `git add -A` di qualunque altra sessione che committasse nel frattempo.

Da cui, per l'intera esecuzione:

- **Guardia in ingresso.** Se `git diff --cached --quiet` esce non-zero l'indice è già popolato da qualcun altro: **fermati e dillo**. Il commit ha una pathspec esplicita, e con un indice sporco porterebbe via lavoro non tuo.
- **Mai staged fino al commit.** La patch vive solo nel working tree, il collaudo legge `git diff` non-staged, e il commit è una catena unica: `git add -- <path...> && git commit -m "..." -- <path...>`.

## Scope

Questa skill è l'ingresso **estemporaneo**: una nozione che nasce fuori dal ciclo task e va collocata subito. Le due vie task-bound sono altre e non passano di qui — `create-task` e `run-task` appendono a `## Doc Impact`, e il checkpoint porta quelle voci in `{docs_root}/inbox/` scrivendole da sé, senza spawnare nessuno. Una nozione già in inbox la colloca `drain-doc`, non questa skill.

Nessun worktree: i subagent lavorano in-place, sul working tree condiviso con la sessione chiamante.

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

Docs root: {project_root}/{docs_root}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo, ha la parola finale su convenzioni e soglie.
Criteri di selezione: ${CLAUDE_PLUGIN_ROOT}/docs/doc-criteria.md — i criteri dipendenti sono il tuo mestiere.
Prefisso ID: CAP

Ritorna solo il registro.
```

**Due spawn, sempre — anche su una nozione sola.** Chi scrive ha un attaccamento al proprio output, quindi un verdetto di scarto è credibile solo se lo dà chi non l'ha scritta. Una scorciatoia sul caso singolo renderebbe condizionale il prompt del writer, che è tagliato per non giudicare mai.

### 4. Spawn `doc-writer` — la patch

Al writer passano **solo le rotte `online` e `offline`**, raggruppate per file target — un writer per gruppo, mai due sullo stesso file: si sovrascrivono a vicenda. Il subagent **applica** le patch al working tree e ritorna il contratto `APPLIED:` — lista file con marker `NEW`/`MOD` + `INDEX_REBUILD_NEEDED`.

**La regola è una whitelist di due verdetti, non un'esclusione.** Gli altri cinque — `→ codice`, `→ fonte viva`, `già scritto`, `noto`, `drop` — non passano di qui: il loro verdetto è già nel registro e li riporti tu allo step 5. Scritta in negativo («passano tutte tranne quelle senza target») la regola manderebbe al writer proprio `già scritto`, che **porta un target pieno** ma è evidenza e non destinazione: un'invocazione intera per non scrivere niente. Una whitelist fallisce chiusa e si nota subito; un'esclusione per proprietà del target fallisce aperta, e un verdetto nuovo del router cade nel ramo sbagliato senza che niente lo segnali.

Zero rotte in whitelist significa **nessun writer**: riporta i verdetti e fermati, invece di rilanciare il router con istruzioni più aggressive.

```
Rotte da applicare — verdetto e target sono già decisi e vincolanti, non rivalutarli:

<le voci del registro per questo target: NOTION / VERDICT / TARGET / TLDR / POINTER / WRITE>

Contesto:
<estratto rilevante della conversazione, 10-30 righe max>

Docs root: {project_root}/{docs_root}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo, ha la parola finale su convenzioni e soglie.
Formule TLDR: ${CLAUDE_PLUGIN_ROOT}/docs/tldr-formats.md

Applica le patch direttamente (Write/Edit), incluso l'eventuale patch a CLAUDE.md; non committare, non rigenerare l'indice, non stagiare niente. Ritorna il contratto APPLIED: (marker NEW/MOD per ogni file) + INDEX_REBUILD_NEEDED.
```

Un `APPLIED:` vuoto col razionale è un esito previsto — il contesto era insufficiente per scrivere qualcosa di vero. Non c'è niente da annullare: riportalo e chiudi.

### 5. Guardiani, poi collaudo

Prima gli script, che non hanno opinioni:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh"       # solo se INDEX_REBUILD_NEEDED: yes
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/check-doc-links.sh"
```

**Exit 2 è un verdetto, non un comando fallito**: su `build-index.sh` l'indice è scritto ma i TLDR elencati su stderr sono oltre il cap, su `check-doc-links.sh` ci sono riferimenti appesi. Non riparare niente qui — gli esiti si passano al collaudo, che decide.

Poi `Task` con `subagent_type: doc-verifier`:

```
Patch da collaudare — cattura estemporanea.

File toccati (dal contratto APPLIED: del writer):
<la lista coi marker NEW / MOD / DEL>

Registro delle rotte che hanno ordinato questa patch:
<le voci del registro di doc-router>

Docs root: {project_root}/{docs_root}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo.

Esiti dei guardiani (fatti deterministici, non ricontarli):
- build-index.sh: exit <n> <+ i TLDR oltre cap che ha elencato, se ce ne sono>
- check-doc-links.sh: exit <n>, riferimenti appesi: <la lista, o «nessuno»>

La patch non è staged: leggila con `git diff` sul working tree.
Ritorna solo il referto.
```

- **`LABEL: accodato` non boccia**: un file che dopo la patch supera la soglia di split, o scende sotto il pavimento, è topologia che la patch ha *rivelato*, non causato. Lo raccoglie `lint-doc` alla prossima misura, perché la misura è lo stato.
- **`OUTCOME: rollback` annulla la patch**, per file secondo il marker: `MOD` → `git checkout -- <file>` · `NEW` → `rm -- <file>` · `DEL` → `git checkout -- <file>`. Poi **rigenera l'indice**: il rebuild ha già scritto la voce di un file che adesso non esiste più. Niente commit, e il motivo — la `RULE:` della violazione — va nel report.

### 6. Committa

Solo su `pass`. Catena unica con pathspec esplicita:

```bash
git add -- <path...> && git commit -m "docs(capture): <di cosa parla la nozione>" -m "<corpo>" -- <path...>
```

La pathspec sono tutti i file di `APPLIED:`, più `{docs_root}/reference/INDEX.md` se il rebuild l'ha toccato. Il **corpo** porta le rotte fuori whitelist col motivo — i `drop`, i due puntatori, i `già scritto` col file che già lo dice, i `noto` con la ragione — più il blocco `DISCARDED:` del writer: sono nozioni che non atterrano da nessuna parte, e il messaggio di commit è dove quel verdetto resta greppabile.

**Non pusha.** Il push è una decisione del chiamante.

Poi il ping TTS:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "doc captured"
```

### 7. Report finale

**Non stampare il diff in chat** — un file reference `NEW` è 200+ righe e brucia contesto; è già ispezionabile, meglio, nel pannello git. Stampa la **lista file** dal contratto `APPLIED:` col marker, lo SHA del commit, e le rotte fuori whitelist col motivo.

Una lista applicata vuota è un esito legittimo — con dei `drop` pieni, con dei `già scritto` che dicono che la nozione era già in doc, o con dei `noto` che dicono che è un fatto generale della materia. Non rilanciare nessuno dei subagent per far scrivere comunque qualcosa.

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici.

## Note

- **Apply-first**: il writer non ritorna una proposta come testo — scrive i file. Una proposta vivrebbe solo nel suo contesto, invisibile a chi deve misurarla; una patch applicata è un diff reale, ed è su quello che il collaudo lavora.
- Per capture **in** una task, appendi a `## Doc Impact` (`create-task` / `run-task`), non questa skill.
- Il doc-writer opera su **tutta la doc** (online `{docs_root}/project/`, offline `{docs_root}/reference/`) e applica **anche una patch a `CLAUDE.md`** quando serve (es. aggiunta `@-import` per un nuovo file online). Quel file compare come `MOD CLAUDE.md` nel contratto `APPLIED:` → entra nella pathspec del commit, o torna indietro col rollback, come il resto.
