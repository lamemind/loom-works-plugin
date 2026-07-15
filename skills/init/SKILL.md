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
- `.claude/loom-works.json` — config progetto (identità + surface), creata nello **step 1b** (bootstrap interattivo). È anche il marker di project-root per `lib.sh`

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

### 1b. Config progetto (`.claude/loom-works.json`) + registrazione dconf

Identità del progetto per l'ecosistema loom (compass/deck). Modello: `project-config-architecture.md`. Il file `.claude/loom-works.json` è la **source of truth config** (portabile, committabile); il registry dconf `/org/lamemind/loom/` è il **runtime** (macchina-locale). La `label` (`{emoji} {owner} {name}`) e gli UUID profilo sono **derivati**, mai nel file.

Controlla `<project-root>/.claude/loom-works.json`.

**Se ASSENTE → bootstrap interattivo.** `id` e `name` = basename della project root (mostralo). Raccogli il resto via `AskUserQuestion`, una domanda per volta; **prima di ciascuna** esegui il ping TTS (vedi §Convenzione TTS in altre skill):
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic>"
```
1. **owner** — prefisso label. Opzioni: `LOCAL`, `LAMEMIND`, `COFACE`, `SHADOW`, `BBETTER` + Other (custom).
2. **emoji** — emoji del **cappello** (progetto). Proponi 3-4 default comuni + Other (l'utente incolla l'emoji che vuole).
3. **surfaces tracked** — multi-select (`multiSelect: true`): SOLO `claude`, `deck` (surface rigide, con match finestra + stato). Default suggerito: entrambe.
4. **launch** — surface custom (bottoni "apri app @project-root"). Chiedi se l'utente ne vuole aggiungere; proponi come default comuni `codium` (`codium .`) e, per progetti Java, `idea` (`idea .`). Per ogni voce raccogli: **emoji** della voce, **label** leggibile, **command** shell (girato con cwd=project root; può contenere una subdir come target, es. `idea ud-maven-parent`, o flag arbitrari). Nessuna voce = `launch: []`.

Poi scrivi il file con `Write` — `surfaces` = solo i tracked selezionati (bool), `launch` = array delle voci custom raccolte (label opzionale, fallback = command):
```json
{
  "id": "<basename>",
  "emoji": "<scelto>",
  "owner": "<scelto>",
  "name": "<basename>",
  "surfaces": { "claude": true, "deck": true },
  "launch": [
    { "emoji": "📝", "label": "codium", "command": "codium ." }
  ]
}
```

**Se PRESENTE:** salta il bootstrap (non sovrascrivere — è committato).

**In entrambi i casi**, registra e materializza (idempotente; noop silenzioso su macchine senza dconf/Ptyxis):
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/config/register.sh
${CLAUDE_PLUGIN_ROOT}/scripts/config/materialize-profiles.sh "<id>"
```
- `register.sh` (cwd) scrive identità + surface nel registry dconf.
- `materialize-profiles.sh <id>` adotta i profili Ptyxis esistenti del progetto (o genera il profilo `claude` se manca) e scrive i binding UUID. La surface `deck`, se non ha già un profilo, viene skippata con log (il lancio del deck è loom-deck-specifico).

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

Riepiloga cosa ha fatto lo script (file/dir creati vs skippati), lo stato di `CLAUDE.md` (creato / righe aggiunte / già completo / snippet stampato da copiare) e la **config progetto** (`.claude/loom-works.json` creato interattivamente o già presente; esito di `register`/`materialize`: registrato in dconf, profili adottati/generati, oppure noop se dconf/Ptyxis assenti).

## Note

- Lo script è sicuro da rilanciare: salta file già presenti
- Le preferenze cross-project (`project_mode`, `doc_folder_name`…) vivono in plugin settings.json; l'**identità per-progetto** vive in `.claude/loom-works.json` — file **obbligatorio**, unico marker di project-root per `lib.sh`. Nessun fallback: il vecchio sentinel `.claude/loom-works.initialized` non vale più e va rimosso.
- Nessuna rilevazione interattiva di `project_mode` per ora: la detection è automatica via `lib.sh` quando serve
