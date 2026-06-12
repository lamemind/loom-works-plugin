---
name: spawn-lane
description: Create a git worktree for a lane (single-project or multi-project).
allowed-tools: Bash(*), Read, AskUserQuestion
model: sonnet
---

Crea il worktree per una lane. Idempotente: se il worktree esiste già mostra il path e si ferma.

Supporta:
- **Single-project** (nessun repo): worktree `{project}-{lane}` dall'intero progetto
- **Multi-project** (repo specificati): worktree `{repo}-{lane}` per ogni sub-repo indicato

Input utente:
~~~human
$ARGUMENTS
~~~

## Parsing input

Da `$ARGUMENTS` estrai:
- **lane** (obbligatorio): nome della lane (es. `l1`, `feat-auth`, `hotfix-login`)
- **repos** (opzionale): lista di nomi sub-repo separati da spazio (es. `ms-buyer ms-seller`)
  - Assenti → single-project mode
  - Presenti → multi-project mode

Se `$ARGUMENTS` è vuoto:
1. Leggi `${user_config.doc_folder_name}/tasks.md` → Execution Plan
2. Mostra le lane nel grafo con `AskUserQuestion`. Opzioni:
   - Lane definite nel grafo (con prima task non-✔️)
   - Opzione libera "Nuova lane ad-hoc (inserisci nome)"
3. Se sceglie lane dal grafo → usa quel nome
4. Per multi-project: chiedi i repo da includere

## Precondizioni

```bash
# Verifica working tree pulito nel PROJECT_ROOT
git status --porcelain
```

Se ci sono modifiche non committate, avvisa l'utente (non blocca, ma il worktree partirà dall'HEAD committato).

## Esecuzione

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/spawn-lane.sh \
    --docs-root "${user_config.doc_folder_name}" \
    --lane-hook "${user_config.on_lane_spawned_hook}" \
    "${lane}" ${repos}
```

Cattura l'output. Se exit 0, mostra:
```
Lane:   ${lane}
Mode:   single-project  (oppure: multi-project [${repos}])
Paths:  (dalla riga "cd ... && claude" dello script)

Prossimo passo:
  cd <worktree-path> && claude
  Poi: /loom-works:start-task <task-id>
```

Se exit 1 (errore), mostra il messaggio di errore e non procedere.

## Note

- Esegui dal worktree base (il repo con docs/tasks.md, branch main)
- Il nome lane identifica il worktree — usalo coerente tra spawn e merge
- Dopo spawn: apri una sessione Claude nel worktree lane, poi `/loom-works:start-task`
- `merge-lane` auto-rileva i worktrees `*-{lane}` → non serve ripetere i repo a merge
- Worktrees sibling preservati dopo merge (default). `merge-lane --cleanup` per rimuovere.
- **Profilo terminale Ptyxis**: se il progetto ha un profilo Ptyxis, lo script duplica automaticamente il profilo per il worktree (label `[lane]`, cd → worktree). Best-effort, noop su macchine senza Ptyxis.
- **Hook on-lane-spawned**: se `user_config.on_lane_spawned_hook` è valorizzato, `spawn-lane` esegue quello script come ultimo step, **una sola volta**, sulla lane parent root `{project}-{lane}` (`$1` = CWD = lane root). Silent noop se la variabile è vuota o il file è assente/non-eseguibile. In caso di failure: warning evidente con comando di retry, ma spawn-lane prosegue. Env nell'hook: `LOOM_LANE`, `LOOM_WORKTREE`, `LOOM_PROJECT_ROOT`.
