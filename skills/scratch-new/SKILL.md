---
name: scratch-new
description: Create a new scratch folder in project root using the .YY-MM-DD-slug convention.
allowed-tools: Bash(*), Read, Write
model: haiku
---

Crea uno scratch: cartella di lavoro per attività complesse, in project root, con pattern `.YY-MM-DD-{slug}`.

Input utente:
~~~human
$ARGUMENTS
~~~

## Concetto

Vedi `${CLAUDE_PLUGIN_ROOT}/docs/task-management.md` §Task Folder per la spec completa. In sintesi: scratch = cartella umana visibile/sincronizzata, lifecycle libero, zero metadata. Folder dedicata per attività estemporanee fuori dal ciclo task.

## Esecuzione

### 1. Estrai slug

Lo slug è l'unico argomento. Pulisci e valida:
- Trim whitespace
- Lowercase
- Spazi → `-`
- Solo `[a-z0-9-]`, niente double-dash
- Non vuoto

Se non valido o assente → chiedi all'utente uno slug kebab-case e ripeti.

### 2. Run script

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/scratch/scratch-new.sh <slug>
```

Lo script:
- Calcola `DATE=$(date +%y-%m-%d)` → `YY-MM-DD`
- Compone path `<project_root>/.${DATE}-${slug}/`
- Fail se la folder esiste già (collisione stesso giorno + stesso slug)
- `mkdir` della folder (vuota)
- Stampa il path creato

### 3. Report

- Path scratch creato (relativo a project root)
- Promemoria: la folder è vuota, l'utente ci mette dentro il materiale di lavoro

## Note

- Una sola skill in famiglia scratch. Rinomina/archivia/elimina si fanno a mano (è solo una folder)
- Lo scratch è AI-pattern minimale: nessun frontmatter, nessun registry, nessun index file
- Se l'utente passa più parole come argomento, joinale in kebab-case (es: `scratch-new prod db clone` → slug `prod-db-clone`)
