---
name: start-task
description: Activate a task for checkpoint tracking and planning analysis.
allowed-tools: Bash(*), Read
model: haiku
---

Attiva una task con approccio "checkpoint di progresso".

raw=`$ARGUMENTS`

## Parsing argomenti

Da `raw` estrai:
- **DETACH**: `1` se `raw` contiene una delle parole `detach`, `detached`, `--detach` (case-insensitive); altrimenti `0`
- **taskFilter**: `raw` con il token detach rimosso, trimmed

Modalità detached: la task viene attivata SENZA creare il symlink `${user_config.doc_folder_name}/current-task.md`. Serve quando vuoi più task in parallelo nello stesso worktree (sessioni Claude separate, ognuna con il proprio task ID esplicito). Vedi `docs/task-management.md` §Detached.

## Flusso

1. **Identifica task**
   1. Se taskFilter è vuoto, leggi `${user_config.doc_folder_name}/tasks.md` e prendi la prima task incompleta (status non "✔️ Done")
   2. Se taskFilter è un ID (es. T01, T319), usa quello
   3. Se è testo, cerca nella tabella Tasks Overview di `${user_config.doc_folder_name}/tasks.md`

2. **Esegui script**
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/task/start-task.sh --mode "${user_config.project_mode}" --docs-root "${user_config.doc_folder_name}" ${DETACH:+--detach} ${TASK_ID}
   ```
   (passa `--detach` solo se DETACH=1)

   Lo script:
   - Trova il file task in `${user_config.doc_folder_name}/tasks/`
   - Ottiene SHA corrente
   - Aggiorna Progress a 🟡 0% (nel file task)
   - Aggiorna Last tracked commit (nel file task)
   - Aggiorna `${user_config.doc_folder_name}/tasks.md`: Progress 🟡 In Progress nella Tasks Overview + emoji nel grafo lane
   - Crea symlink `${user_config.doc_folder_name}/current-task.md` (skippato in detached)

3. **Presenta task**
   1. Leggi il file task appena attivato
   2. **Calcola stato preflight** dalla sezione `## Decisions` del task file:
      - **✅ fatto · ${data} · ${N} decisioni** — esiste ≥1 blocco `### Preflight` con ≥1 bullet `**D{N}**`. `${data}` = data del blocco `### Preflight` più recente; `${N}` = totale bullet `**D{N}**` su tutti i blocchi Preflight.
      - **➖ non necessario · ${data}** — esiste ≥1 blocco `### Preflight` ma zero bullet `**D{N}**` (marker "nessuna ambiguità" lasciato da preflight-task).
      - **⚠️ da fare** — nessun blocco `### Preflight` (o sezione `## Decisions` assente).
   3. Estrai e mostra (formato compatto, identico a run-task):
      ```
      📋 ${taskId} — ${titolo}
      📐 Size: ${size} | ⚡ ${priority}
      📝 ${prima riga della Description, troncata a ~100 char}
      📦 ${numero deliverables} deliverables
      🛫 Preflight: ${stato preflight}
      📁 Folder: ${campo Folder se popolato, altrimenti ometti riga}
      🟡 Tracked from: ${SHA}
      🔗 Mode: ${linked|detached}

      ▶️  Usa /loom-works:run-task ${taskId se detached, altrimenti vuoto} per eseguire,
         /loom-works:checkpoint-task ${taskId se detached, altrimenti vuoto} per checkpoint.
      ```
   4. Se preflight è **⚠️ da fare**, aggiungi sotto il footer la riga:
      `   🛫 Preflight non eseguita → valuta /loom-works:preflight-task ${taskId se detached, altrimenti vuoto} prima di run-task.`

## Note

- **tasks.md update**: lo script aggiorna direttamente `${user_config.doc_folder_name}/tasks.md`. Eventuali divergenze tra branch vengono riconciliate da `reconcile-tasks` in `merge-lane`.
- **Checkpoint approach**: SHA tracking per diff analysis
- **Working tree può essere sporco**: Normale durante sviluppo
- **Detached mode**: niente symlink, task ID va passato esplicitamente a run-task e checkpoint-task. Esempio: `/loom-works:start-task T102 detach`. Più task detached possono coesistere nello stesso worktree (sessioni separate). In detached, checkpoint-task NON usa l'analisi diff: l'agente deriva i deliverables completati dal contesto della conversazione e fa staging selettivo.
