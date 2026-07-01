---
name: set-task-folder
description: Attach a dot-prefixed task folder to an existing task.
allowed-tools: Bash(*), Read, Edit, Glob
model: haiku
---

> **NOTA**: lo script `set-task-folder.sh` popola **da sé** il campo `**Folder**:` nel task file e fa `git add` di folder + task file. La skill non deve editare il task file a mano.

Aggiunge retroattivamente una task folder a una task esistente.

Input utente:
~~~human
$ARGUMENTS
~~~

## Parsing argomenti

Da `$ARGUMENTS` estrai:
- **taskId**: pattern `T\d+` (obbligatorio)
- **`--slug <slug>`**: override slug per naming canonical (opzionale). Default: task slug dal filename.

Se taskId assente → leggi symlink `${user_config.doc_folder_name}/current-task.md` per ricavarlo. Se anche symlink assente → errore, chiedi task ID.

## Flusso

### 1. Risolvi task file

```bash
ls ${user_config.doc_folder_name}/tasks/${taskId}-*.md
```

Leggi il file task. Estrai:
- task slug (dal filename: `T02-my-slug.md` → slug = `my-slug`)
- campo `**Folder**:` corrente

Se campo Folder già popolato → avvisa l'utente e chiedi conferma prima di sovrascrivere.

### 2. Crea (o riusa) la folder canonical

Naming canonico `.YY-MM-DD-slug` **in project root** (mai sotto `${user_config.doc_folder_name}/tasks/`: il nome dotted è solo il nome, il parent è la root):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/set-task-folder.sh ${taskId} [--slug <slug>] --docs-root "${user_config.doc_folder_name}"
```

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
   Task file aggiornato: ${user_config.doc_folder_name}/tasks/${taskId}-*.md
```

## Note

- **CWD invariato**: non fare mai `cd` nella folder. CWD resta project root (dove sta CLAUDE.md).
- **Idempotenza**: rieseguire la skill sullo stesso task nello stesso giorno riusa la folder canonica esistente (no errore). Slug diverso o giorno diverso → nuova folder.
- **Git**: la folder nasce vuota; git la traccia solo quando contiene file. Lo `git add` in repo mode è un no-op finché la folder resta vuota.
</content>
</invoke>
