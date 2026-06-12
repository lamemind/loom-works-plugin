---
name: set-task-folder
description: Attach a dot-prefixed task folder to an existing task.
allowed-tools: Bash(*), Read, Edit, Glob
model: haiku
---

> **NOTA**: lo script `set-task-folder.sh` (modalità canonical) ora popola **da sé** il campo `**Folder**:` nel task file e fa `git add` di folder + task file. Lo step 4 sotto vale solo per modalità `--existing`.

Aggiunge retroattivamente una task folder a una task esistente.

Input utente:
~~~human
$ARGUMENTS
~~~

## Parsing argomenti

Da `$ARGUMENTS` estrai:
- **taskId**: pattern `T\d+` (obbligatorio)
- **`--existing <path>`**: path relativo di una folder pre-esistente in project root (opzionale). Se presente → nessun mkdir, solo popola campo Folder.
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

### 2. Modalità --existing

Se `--existing <path>` fornito:
- Verifica che la folder esista in project root: `ls -d "${PROJECT_ROOT}/${path}"`
- Se non esiste → errore con path mostrato
- Popola campo Folder nel task file con il path fornito (senza mkdir)
- Skip step 3

### 3. Modalità canonical (default)

Crea folder con naming canonico `.YY-MM-DD-slug`:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/set-task-folder.sh ${taskId} [--slug <slug>] --docs-root "${user_config.doc_folder_name}"
```

Lo script:
- Calcola `DATE=$(date +%y-%m-%d)`
- Compone `FOLDER_NAME=".${DATE}-${slug}"`
- Chiama `${CLAUDE_PLUGIN_ROOT}/scripts/utils/folder-create.sh` per mkdir
- Aggiorna riga `- **Folder**:` nel task file
- Fa `git add` di folder + task file (commit deferito al caller)
- Stampa `FOLDER_NAME=...` come ultima riga

### 4. Aggiorna campo Folder (solo modalità `--existing`)

In canonical mode skip — già fatto dallo script.

Per `--existing <path>`: usa Edit per scrivere la riga:
```
- **Folder**: <path>
```

### 5. Feedback

```
✅ Task folder impostata per ${taskId}
   Folder: ${folder_name}/
   Task file aggiornato: ${user_config.doc_folder_name}/tasks/${taskId}-*.md
```

## Note

- **CWD invariato**: non fare mai `cd` nella folder. CWD resta project root (dove sta CLAUDE.md).
- **Idempotenza**: se folder canonico già esiste (stessa data + stesso slug), `folder-create.sh` fallisce con errore. L'utente deve usare `--existing` o aspettare giorno diverso.
- **Git**: la folder nasce vuota; git la traccia solo quando contiene file. Lo `git add` in repo mode è un no-op finché la folder resta vuota.
