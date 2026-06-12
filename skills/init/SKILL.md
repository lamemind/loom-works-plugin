---
name: init
description: Minimal bootstrap of the loom-works structure on the current project.
allowed-tools: Bash(*), Read, Write, Edit, AskUserQuestion
model: sonnet
---

Inizializza un progetto vergine (o verifica/ripara un progetto esistente) creando la struttura minima che le altre skill loom-works si aspettano.

Input utente:
~~~human
$ARGUMENTS
~~~

## Cosa crea

Solo se **assenti** (idempotente):
- `${user_config.doc_folder_name}/tasks.md` — dal template `tasks-skeleton.md` (Tasks Overview + Execution Plan)
- `${user_config.doc_folder_name}/reference/INDEX.md` — dal template `reference-index-skeleton.md`
- `${user_config.doc_folder_name}/tasks/` — directory per i file task
- `${user_config.doc_folder_name}/reference/` — directory per doc offline
- `.claude/loom-works.initialized` — file sentinel (la dir `.claude/` è creata lazy se assente), segnala che init è passato

**CLAUDE.md**: init **propone** (non forza) l'aggiunta degli `@-import` base — vedi step 3. **Non tocca**: file git, config, dipendenze.

## Esecuzione

### 0. Mostra configurazione docs root

Prima di eseguire, mostra all'utente il valore che sarà usato:

```
📁 Docs folder: ${user_config.doc_folder_name}
   (default "docs" se non configurato — cambiabile in Claude Code › Plugin settings › loom-works)
```

Se `${user_config.doc_folder_name}` risulta vuoto o non risolto, usa il fallback `docs` e avvisa l'utente.

### 1. Run script

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/init/init.sh --docs-root "${user_config.doc_folder_name}"
```

Se l'input contiene `--force`, passa il flag (rigenera `tasks.md` e `INDEX.md` anche se presenti — distruttivo, chiedi conferma prima).

### 2. Integrazione CLAUDE.md

`CLAUDE.md` è il punto di ingresso: se non referenzia `tasks.md` e `reference/INDEX.md`, le skill task-level e il doc-writer partono ciechi. Propone (non forza):

**Formato riga @-import** (sia `@-import` che ancora cliccabile MD, sulla stessa riga):

```markdown
- @${user_config.doc_folder_name}/tasks.md [Tasks](${user_config.doc_folder_name}/tasks.md)
- @${user_config.doc_folder_name}/current-task.md [Current Task](${user_config.doc_folder_name}/current-task.md)
- @${user_config.doc_folder_name}/reference/INDEX.md [Reference Index](${user_config.doc_folder_name}/reference/INDEX.md)
```

Caso A — **`CLAUDE.md` assente**:
- Usa `AskUserQuestion` → "Creo `CLAUDE.md` con skeleton minimo (@-import a tasks.md, current-task.md, reference/INDEX.md)?"
- Su **yes** → `Write` di uno skeleton con heading progetto placeholder + blocco `@-import` sopra.
- Su **no** → stampa lo snippet, l'utente lo aggiunge a mano.

Caso B — **`CLAUDE.md` presente ma manca almeno uno tra `@{doc_folder_name}/tasks.md` e `@{doc_folder_name}/reference/INDEX.md`**:
- Usa `AskUserQuestion` mostrando quali righe mancano → "Aggiungo le righe mancanti in fondo a `CLAUDE.md`?"
- Su **yes** → `Edit` append delle sole righe mancanti (nel formato sopra, `@-import` + ancora MD cliccabile).
- Su **no** → stampa lo snippet, l'utente lo aggiunge a mano.

Caso C — **`CLAUDE.md` presente e già completo**: nessuna domanda, log "CLAUDE.md already wired".

### 3. Report

Riepiloga cosa ha fatto lo script (file/dir creati vs skippati) e cosa è successo a `CLAUDE.md` (creato / righe aggiunte / già completo / snippet stampato da copiare).

## Note

- Lo script è sicuro da rilanciare: salta file già presenti
- Config vera vive in plugin settings.json (project level), non nel sentinel — il file `.claude/loom-works.initialized` è solo anchor per project root detection in `lib.sh`
- Nessuna rilevazione interattiva di `project_mode` per ora: la detection è automatica via `lib.sh` quando serve
