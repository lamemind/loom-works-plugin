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

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `{docs_root}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

Inizializza un progetto vergine (o verifica/ripara un progetto esistente) creando la struttura minima che le altre skill loom-works si aspettano.

Input utente:
~~~human
$ARGUMENTS
~~~

## Cosa crea

Solo se **assenti** (idempotente):
- `{docs_root}/tasks.md` — dal template `tasks-skeleton.md` (Tasks Overview + Execution Plan)
- `{docs_root}/reference/INDEX.md` — dal template `reference-index-skeleton.md`
- `{docs_root}/tasks/` — directory per i file task
- `{docs_root}/reference/` — directory per doc offline
- `{docs_root}/inbox/` — directory per le nozioni non ancora collocate, che il checkpoint riempie e `drain-notions` svuota. Nasce vuota e non si versiona: nessun `.gitkeep`, e ogni lettore ne tollera l'assenza
- `.claude/loom-works.json` — config progetto (identità + surface), creata nello **step 1b** (bootstrap interattivo). È anche il marker di project-root per `lib.sh`. Unico file che init tocca anche quando esiste già: su un progetto registrato lo step 1b ripropone i campi non identitari coi valori attuali, per far crescere un file scritto prima che un campo esistesse
- `.claude/settings.json` — solo la regola `Read(~/.claude/plugins/cache/…/**)`, aggiunta in coda alle esistenti senza toccare il resto del file. Serve agli agent doc, che aprono i propri contratti dalla cache del plugin: senza, la `Read` cade sotto approvazione e l'agent **prosegue senza contratto** invece di fermarsi. Il path è sul segmento stabile, mai sulla versione — una regola concessa a mano da un «non chiedere più» nasce version-pinned e muore al primo bump

**CLAUDE.md**: init **propone** (non forza) due blocchi — gli `@-import` base e la sezione `User assumed knowledge` — vedi step 2. **Non tocca**: file git, config, dipendenze.

## Esecuzione

### 0. Mostra configurazione docs root

Prima di eseguire, mostra all'utente il valore che sarà usato:

```
📁 Docs folder: {docs_root}
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

**Deroga dichiarata a `output-styles/regole-output.md` §Domande all'utente.** Quella sezione prescrive «una chiamata per domanda»; qui non vale, e vale solo qui. I campi di questo step sono un blocco anagrafico omogeneo — chi è il progetto e come si apre — e chiederli uno per chiamata costringe l'utente a sei context-switch su un argomento solo, cioè l'affaticamento che quella regola esiste per ridurre. Le chiamate sotto sono **tre**, tagliate per oggetto.

**Nessun ping TTS in questo step**: niente `say_auto` prima delle chiamate né prima della domanda aperta finale. L'utente ha lanciato `init` lui e sta guardando lo schermo. Costo accettato: la domanda finale chiude il turno, quindi compass segnala `done` invece di `ask`.

Controlla `{project_root}/.claude/loom-works.json`:

- **ASSENTE** → esegui Ask 1, Ask 2, Ask 3 e la domanda aperta. `id` e `name` = basename della project root (mostralo).
- **PRESENTE** → salta **Ask 1** (l'identità non si tocca: `id`, `name`, `owner`, `emoji` restano quelli del file) ed esegui **Ask 2, Ask 3 e la domanda aperta**, mettendo il valore attuale del file come **prima opzione di ogni domanda, marcata `(attuale)`**. Serve ad allineare un progetto registrato prima che un campo esistesse: `register.sh` e il refresh propagano nel registry **solo ciò che il file contiene**, quindi un file incompleto resta incompleto per sempre se `init` non torna a chiedere. Alla scrittura **preserva ogni campo non chiesto** (`docsRoot`, `order`, e qualunque altro presente): riscrivere il file da zero perderebbe la docs-root del progetto.

**Ask 1 — identità** (una chiamata, due domande):

1. **owner** — metadato organizzativo (a chi appartiene il progetto). Non entra nella label né nei titoli di tab: nessun consumer lo legge, resta come classificazione. Opzioni: `LOCAL`, `LAMEMIND`, `COFACE`, `SHADOW`, `BBETTER` + Other (custom).
2. **emoji** — emoji del **cappello** (progetto). Proponi 3-4 default comuni + Other (l'utente incolla l'emoji che vuole).

**Ask 2 — surface e regime** (una chiamata, tre domande):

1. **surfaces tracked** — multi-select (`multiSelect: true`): SOLO `claude`, `deck` (surface rigide, con match finestra + stato). Default suggerito: entrambe.
2. **defaultSurface** — quale surface apre il click sul **nome** del progetto nella riga compass (focus-or-launch). Offri **le tre opzioni piene**: `terminal` (default suggerito, shell @project-root), `claude`, `deck` — senza restringerle sulle surface della domanda accanto, che nella stessa schermata non è ancora stata risposta. Una scelta incoerente (`deck` con `deck` non abilitato) si scrive **com'è**: `cfg_validate` rifiuta i valori fuori dominio, mai le incoerenze incrociate, e il consumer degrada a `terminal`.
3. **permissionMode** — con quale permission mode parte una sessione `claude` spawnata dal deck. **Si chiede sempre**, anche se `claude` non finisce fra le tracked: è una preferenza su *come* si lancia quella surface, valida se e quando viene abilitata, e condizionarla alla domanda accanto la renderebbe non ponibile nella stessa schermata. Opzioni: `manual` (default suggerito — ogni azione chiede conferma), `acceptEdits` (accetta le modifiche a file senza chiedere), `auto`, `plan` (parte in planning, non esegue). Gli altri due valori del CLI — `dontAsk` e `bypassPermissions` — **non vanno proposti in lista**: restano raggiungibili via Other, perché `bypassPermissions` disattiva i controlli e non deve essere una scelta a un click.

**Ask 3 — launch preconfezionati** (una chiamata, tre domande sì/no). Ogni sì produce una voce `launch` con emoji, label e comando già fissati qui — niente da digitare:

| Label | Emoji | Command |
|---|---|---|
| Vs Code | 📝 | `codium .` |
| IntelliJ | ☕ | `idea .` |
| File Manager | 📁 | `xdg-open .` |

`xdg-open .` apre il file manager registrato dal sistema, così la voce non è legata a un desktop specifico.

**Domanda aperta — launch custom** (scritta in chat, **non** col tool). Non è aggregabile per costruzione: dominio aperto, numero di voci ignoto in anticipo, e per ciascuna tre campi di testo libero che il tool non ha una forma per raccogliere. Scrivi in chat le tre variabili di una voce — **emoji**, **label** leggibile, **command** shell (girato con cwd = project root; può portare una subdir come target, es. `idea ud-maven-parent`, o flag arbitrari) — più due o tre esempi liberi (una connessione `ssh`, un tail di log remoto, un altro editor), poi chiedi se ne vuole aggiungere. Nessuna voce = solo quelle di Ask 3, o `launch: []` se anche quelle sono tutte no.

**Se lo schema di `AskUserQuestion` non accetta un gruppo intero**, spezza quel gruppo tenendo insieme i campi indipendenti e rimandando a una chiamata successiva quelli che dipendono da una risposta della stessa schermata (`defaultSurface` e `permissionMode` dipendono da `surfaces`). Il criterio di taglio è la dipendenza, mai l'ordine in cui i campi compaiono qui.

Poi scrivi il file con `Write`. **Tutti i campi si scrivono sempre**, anche quando il valore coincide col fallback del consumer (`defaultSurface: terminal`, `permissionMode: manual`): l'omissione cancella la differenza fra «qualcuno ha scelto» e «nessuno ha mai deciso», e senza il campo scritto non c'è modo di sapere quali domande siano già state poste. Il significato dell'assenza non cambia — per ogni consumer un campo assente vale il fallback.

```json
{
  "id": "<basename>",
  "emoji": "<scelto>",
  "owner": "<scelto>",
  "name": "<basename>",
  "surfaces": { "claude": true, "deck": true },
  "launch": [
    { "emoji": "📝", "label": "Vs Code", "command": "codium ." }
  ],
  "defaultSurface": "claude",
  "permissionMode": "auto"
}
```

**In entrambi i casi**, registra e materializza (idempotente; noop silenzioso su macchine senza dconf/Ptyxis):
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/config/register.sh
${CLAUDE_PLUGIN_ROOT}/scripts/config/materialize-profiles.sh "<id>"
```
- `register.sh` (cwd) scrive identità + surface nel registry dconf.
- `materialize-profiles.sh <id>` adotta i profili Ptyxis esistenti del progetto (o genera il profilo `claude` se manca) e scrive i binding UUID. La surface `deck`, se non ha già un profilo, viene skippata con log (il lancio del deck è loom-deck-specifico).

### 2. Integrazione CLAUDE.md

`CLAUDE.md` è il punto di ingresso, e init ci **propone** (non forza) due blocchi indipendenti: gli `@-import` della doc e la sezione `User assumed knowledge`. Il file può esistere già — il plugin si installa anche su un progetto maturo — con uno dei due blocchi, entrambi o nessuno: **ogni blocco si valuta per conto proprio, e ciò che c'è non si riscrive.**

**Blocco 1 — `@-import` della doc.** Senza queste righe le skill task-level e il doc-writer partono ciechi, perché non sanno dove stiano `{docs_root}/tasks.md` e `{docs_root}/reference/INDEX.md`. Ogni riga porta insieme l'`@-import` e l'ancora MD cliccabile:

```markdown
- @{docs_root}/tasks.md [Tasks]({docs_root}/tasks.md)
- @{docs_root}/reference/INDEX.md [Reference Index]({docs_root}/reference/INDEX.md)
```

**`current-task.md` non va @-importato**, mai — nemmeno "per comodità". La task attiva la scrive in contesto **solo** l'hook `SessionStart` (`inject-task.sh`), che risolve la cascata `$LOOM_TASK → symlink`. Un `@-import` la farebbe entrare in parallelo per conto proprio: in una sessione con `$LOOM_TASK` il modello si troverebbe **due** task attive divergenti, l'iniettata e quella (stale) a cui punta il symlink del worktree. Il symlink resta una primitiva di *risoluzione*, non un canale di *iniezione*.

**Blocco 2 — `User assumed knowledge`.** Dichiara, settore per settore, quanto l'utente ne sa, sulla scala `K0` (non possiede né vocabolario né implicazioni) → `K3` (possiede entrambi). È il pavimento su cui una risposta decide se un termine va glossato o resta nudo, e `CLAUDE.md` è l'unico posto dove la dichiarazione vale in permanenza — inline in chat si dichiara solo un override di conversazione.

```markdown
## User assumed knowledge

- rocket science: K0
- loom-works plugin: K0
```

Le due voci sono **placeholder di forma**: mostrano la grafia `settore: grado` su una materia accademica e su un contesto progettuale, cioè le due classi di settore. Non descrivono nessuno — segnalalo nel report e invita a sostituirle, o restano lì a dichiarare per sempre un'ignoranza di rocket science che l'utente non ha mai affermato.

**Rilevazione, un blocco per volta:**

- **blocco 1** → le due righe `@{docs_root}/…` dentro `CLAUDE.md`.
- **blocco 2** → l'heading `User assumed knowledge`, cercato in `CLAUDE.md` **e nei file che `CLAUDE.md` @-importa**: la sezione è lecita anche in un file importato, e cercarla solo nel file principale ne produrrebbe una seconda copia.

Caso A — **`CLAUDE.md` assente**:
- Usa `AskUserQuestion` → "Creo `CLAUDE.md` con skeleton minimo (@-import a {docs_root}/tasks.md e {docs_root}/reference/INDEX.md + sezione User assumed knowledge)?"
- Su **yes** → `Write` di uno skeleton: heading progetto placeholder, blocco `@-import` sopra, sezione `## User assumed knowledge` sotto.
- Su **no** → stampa i due snippet, l'utente li aggiunge a mano.

Caso B — **`CLAUDE.md` presente ma manca almeno una parte** — una delle due righe `@-import`, la sezione `User assumed knowledge`, o entrambe:
- Usa `AskUserQuestion` elencando cosa manca → "Aggiungo le parti mancanti in fondo a `CLAUDE.md`?"
- Su **yes** → `Edit` append delle sole parti mancanti, nel formato sopra. Le righe già presenti non si toccano, e una sezione `User assumed knowledge` già popolata non si integra con le voci placeholder.
- Su **no** → stampa gli snippet mancanti, l'utente li aggiunge a mano.

Caso C — **`CLAUDE.md` presente e già completo** su entrambi i blocchi: nessuna domanda, log "CLAUDE.md already wired".

### 3. Report

Riepiloga cosa ha fatto lo script (file/dir creati vs skippati), lo stato di `CLAUDE.md` **per blocco** (`@-import`: creato / righe aggiunte / già completo / snippet stampato da copiare — `User assumed knowledge`: idem), e la **config progetto** (`.claude/loom-works.json` creato interattivamente o aggiornato, coi campi cambiati rispetto al file precedente; esito di `register`/`materialize`: registrato in dconf, profili adottati/generati, oppure noop se dconf/Ptyxis assenti).

## Note

- Lo script è sicuro da rilanciare: salta file già presenti
- Le preferenze cross-project (`on_lane_spawned_hook`…) vivono in plugin settings.json; tutto ciò che è **per-progetto** — identità, surface e **docs-root** (`docsRoot`) — vive in `.claude/loom-works.json`, file **obbligatorio** e unico marker di project-root per `lib.sh`. Il discriminante è la portata, non il tipo di dato: un userConfig vale per ogni progetto insieme, quindi non può descriverne uno. Nessun fallback: il vecchio sentinel `.claude/loom-works.initialized` non vale più e va rimosso.
