---
name: set-task-folder
description: Attach a dot-prefixed task folder to an existing task.
allowed-tools: Bash(*), Read, Edit, Glob
model: haiku
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `${DOCS_ROOT}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

> **NOTA**: lo script `set-task-folder.sh` popola **da sé** il campo `**Folder**:` nel task file e fa `git add` di folder + task file. La skill non deve editare il task file a mano.

Aggiunge retroattivamente una task folder a una task esistente.

Input utente:
~~~human
$ARGUMENTS
~~~

## Parsing argomenti

Da `$ARGUMENTS` estrai:
- **taskId**: pattern `T\d+` o `D\d+` (opzionale — omesso, lo risolve la cascata)
- **`--slug <slug>`**: override slug per naming canonical (opzionale). Default: task slug dal filename.

## Flusso

### 1. Risolvi task file

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId}
```

Cascata `arg → $LOOM_TASK → symlink`. Exit non-zero = nessun binding: chiedi il task ID.

`Read` di `TASK_FILE`. Estrai il campo `**Folder**:` corrente — se già popolato, avvisa l'utente e chiedi conferma prima di sovrascrivere.

### 2. Crea (o riusa) la folder canonical

Naming canonico `.YY-MM-DD-slug` **in project root** (mai sotto `${DOCS_ROOT}/tasks/`: il nome dotted è solo il nome, il parent è la root):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/set-task-folder.sh ${TASK_ID} [--slug <slug>]
```

Passa il `TASK_ID` **risolto** allo step 1, non l'arg grezzo: senza, lo script rifà la cascata per conto suo e una fonte diversa gli farebbe scrivere il campo `**Folder**:` in un altro task file.

Lo script:
- Calcola `DATE=$(date +%y-%m-%d)`
- Compone `FOLDER_NAME=".${DATE}-${slug}"`
- **Permissivo**: se la folder canonica esiste già la riusa, altrimenti la crea (mkdir in project root)
- Aggiorna riga `- **Folder**:` nel task file col path root-relative `./${FOLDER_NAME}`
- Fa `git add` di folder + task file (commit deferito al caller)
- Stampa `FOLDER_NAME=...` come ultima riga

### 3. Feedback

```
✅ Task folder impostata per ${taskId}
   Folder: ${folder_name}/
   Task file aggiornato: ${DOCS_ROOT}/tasks/${taskId}-*.md
```

## Note

- **CWD invariato**: non fare mai `cd` nella folder. CWD resta project root (dove sta CLAUDE.md).
- **Idempotenza**: rieseguire la skill sullo stesso task nello stesso giorno riusa la folder canonica esistente (no errore). Slug diverso o giorno diverso → nuova folder.
- **Git**: la folder nasce vuota; git la traccia solo quando contiene file. Lo `git add` in repo mode è un no-op finché la folder resta vuota.
</content>
</invoke>
