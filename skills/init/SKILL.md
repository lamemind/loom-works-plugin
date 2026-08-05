---
name: init
description: Minimal bootstrap of the loom-works structure on the current project.
allowed-tools: Bash(*), Read, Write, Edit, AskUserQuestion
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `${DOCS_ROOT}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

Inizializza un progetto vergine (o verifica/ripara un progetto esistente) creando la struttura minima che le altre skill loom-works si aspettano.

Input utente:
~~~human
$ARGUMENTS
~~~

## Cosa crea

Solo se **assenti** (idempotente):
- `${DOCS_ROOT}/tasks.md` — dal template `tasks-skeleton.md` (Tasks Overview + Execution Plan)
- `${DOCS_ROOT}/reference/INDEX.md` — dal template `reference-index-skeleton.md`
- `${DOCS_ROOT}/tasks/` — directory per i file task
- `${DOCS_ROOT}/reference/` — directory per doc offline
- `.claude/loom-works.json` — config progetto (identità + surface), creata nello **step 1b** (bootstrap interattivo). È anche il marker di project-root per `lib.sh`

**CLAUDE.md**: init **propone** (non forza) l'aggiunta degli `@-import` base — vedi step 3. **Non tocca**: file git, config, dipendenze.

## Esecuzione

### 0. Mostra configurazione docs root

Prima di eseguire, mostra all'utente il valore che sarà usato:

```
📁 Docs folder: ${DOCS_ROOT}
   (default "docs" — per cambiarla: campo "docsRoot" in .claude/loom-works.json)
```

Il fallback lo garantisce già `docs-root.sh`: se il file config manca o non ha `docsRoot`, stampa `docs`. Un output vuoto è quindi un guasto dello script, non una configurazione assente — segnalalo invece di tirare a indovinare.

### 1. Run script

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/init/init.sh
```

Se l'input contiene `--force`, passa il flag (rigenera `tasks.md` e `INDEX.md` anche se presenti — distruttivo, chiedi conferma prima).

### 1b. Config progetto (`.claude/loom-works.json`) + registrazione dconf

Identità del progetto per l'ecosistema loom (compass/deck). Modello: `project-config-architecture.md`. Il file `.claude/loom-works.json` è la **source of truth config** (portabile, committabile); il registry dconf `/org/lamemind/loom/` è il **runtime** (macchina-locale). La `label` (`{emoji} {name}`) e gli UUID profilo sono **derivati**, mai nel file.

Controlla `<project-root>/.claude/loom-works.json`.

**Se ASSENTE → bootstrap interattivo.** `id` e `name` = basename della project root (mostralo). Raccogli il resto via `AskUserQuestion`, una domanda per volta; **prima di ciascuna** esegui il ping TTS (vedi §Convenzione TTS in altre skill):
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic>"
```
1. **owner** — metadato organizzativo (a chi appartiene il progetto). Non entra nella label né nei titoli di tab: nessun consumer lo legge, resta come classificazione. Opzioni: `LOCAL`, `LAMEMIND`, `COFACE`, `SHADOW`, `BBETTER` + Other (custom).
2. **emoji** — emoji del **cappello** (progetto). Proponi 3-4 default comuni + Other (l'utente incolla l'emoji che vuole).
3. **surfaces tracked** — multi-select (`multiSelect: true`): SOLO `claude`, `deck` (surface rigide, con match finestra + stato). Default suggerito: entrambe.
4. **launch** — surface custom (bottoni "apri app @project-root"). Chiedi se l'utente ne vuole aggiungere; proponi come default comuni `codium` (`codium .`) e, per progetti Java, `idea` (`idea .`). Per ogni voce raccogli: **emoji** della voce, **label** leggibile, **command** shell (girato con cwd=project root; può contenere una subdir come target, es. `idea ud-maven-parent`, o flag arbitrari). Nessuna voce = `launch: []`.
5. **defaultSurface** — quale surface apre il click sul **nome** del progetto nella riga compass (focus-or-launch). Opzioni: `terminal` (default suggerito, shell @project-root), `claude`, `deck`. Offri solo le tracked che l'utente ha appena abilitato al punto 3. Se sceglie `terminal`, **ometti il campo** dal file: è già il fallback, scriverlo aggiunge rumore.
6. **permissionMode** — con quale permission mode parte una sessione della surface `claude` spawnata dal deck. Chiedilo **solo se** `claude` è fra le tracked abilitate al punto 3. Opzioni da offrire: `manual` (default suggerito — ogni azione chiede conferma), `acceptEdits` (accetta le modifiche a file senza chiedere), `auto`, `plan` (parte in planning, non esegue). Gli altri due valori del CLI — `dontAsk` e `bypassPermissions` — **non vanno proposti in lista**: restano raggiungibili via Other, perché `bypassPermissions` disattiva i controlli e non deve essere una scelta a un click. Se sceglie `manual`, **ometti il campo** (stessa regola di `defaultSurface`: è già il fallback).

Poi scrivi il file con `Write` — `surfaces` = solo i tracked selezionati (bool), `launch` = array delle voci custom raccolte (label opzionale, fallback = command), `defaultSurface` solo se ≠ `terminal`, `permissionMode` solo se ≠ `manual`:
```json
{
  "id": "<basename>",
  "emoji": "<scelto>",
  "owner": "<scelto>",
  "name": "<basename>",
  "surfaces": { "claude": true, "deck": true },
  "launch": [
    { "emoji": "📝", "label": "codium", "command": "codium ." }
  ],
  "defaultSurface": "claude",
  "permissionMode": "auto"
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
- @${DOCS_ROOT}/tasks.md [Tasks](${DOCS_ROOT}/tasks.md)
- @${DOCS_ROOT}/reference/INDEX.md [Reference Index](${DOCS_ROOT}/reference/INDEX.md)
```

**`current-task.md` non va @-importato**, mai — nemmeno "per comodità". La task attiva la scrive in contesto **solo** l'hook `SessionStart` (`inject-task.sh`), che risolve la cascata `$LOOM_TASK → symlink`. Un `@-import` la farebbe entrare in parallelo per conto proprio: in una sessione con `$LOOM_TASK` il modello si troverebbe **due** task attive divergenti, l'iniettata e quella (stale) a cui punta il symlink del worktree. Il symlink resta una primitiva di *risoluzione*, non un canale di *iniezione*.

Caso A — **`CLAUDE.md` assente**:
- Usa `AskUserQuestion` → "Creo `CLAUDE.md` con skeleton minimo (@-import a tasks.md e reference/INDEX.md)?"
- Su **yes** → `Write` di uno skeleton con heading progetto placeholder + blocco `@-import` sopra.
- Su **no** → stampa lo snippet, l'utente lo aggiunge a mano.

Caso B — **`CLAUDE.md` presente ma manca almeno uno tra `@${DOCS_ROOT}/tasks.md` e `@${DOCS_ROOT}/reference/INDEX.md`**:
- Usa `AskUserQuestion` mostrando quali righe mancano → "Aggiungo le righe mancanti in fondo a `CLAUDE.md`?"
- Su **yes** → `Edit` append delle sole righe mancanti (nel formato sopra, `@-import` + ancora MD cliccabile).
- Su **no** → stampa lo snippet, l'utente lo aggiunge a mano.

Caso C — **`CLAUDE.md` presente e già completo**: nessuna domanda, log "CLAUDE.md already wired".

### 3. Report

Riepiloga cosa ha fatto lo script (file/dir creati vs skippati), lo stato di `CLAUDE.md` (creato / righe aggiunte / già completo / snippet stampato da copiare) e la **config progetto** (`.claude/loom-works.json` creato interattivamente o già presente; esito di `register`/`materialize`: registrato in dconf, profili adottati/generati, oppure noop se dconf/Ptyxis assenti).

## Note

- Lo script è sicuro da rilanciare: salta file già presenti
- Le preferenze cross-project (`on_lane_spawned_hook`…) vivono in plugin settings.json; tutto ciò che è **per-progetto** — identità, surface e **docs-root** (`docsRoot`) — vive in `.claude/loom-works.json`, file **obbligatorio** e unico marker di project-root per `lib.sh`. Il discriminante è la portata, non il tipo di dato: un userConfig vale per ogni progetto insieme, quindi non può descriverne uno. Nessun fallback: il vecchio sentinel `.claude/loom-works.initialized` non vale più e va rimosso.
