---
name: reconcile-tasks
description: Reconcile git conflicts in tasks.md during merge-lane (single-project only).
allowed-tools: Read, Edit, Bash(*)
model: sonnet
---

Riconcilia conflitti git nel worktree specificato usando operational transformation.
**Single-project only** — in multi-project tasks.md non viene branchato, non ci sono conflitti.
Invocato da `/loom-works:merge-lane` in caso di conflitto (exit 2).

Input:
~~~human
$ARGUMENTS
~~~

`$ARGUMENTS` = path assoluto del worktree con conflitti (merge in corso, MERGE_HEAD presente).

## Flusso

### 1. Estrai contesto OT

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/reconcile-tasks-context.sh \
    --docs-root "${user_config.doc_folder_name}" \
    ${conflict_dir}
```

Leggi tutto l'output. Lo script produce:
- Lista file in conflitto classificati: `[tasks]` o `[other]`
- Per ogni file tasks: base (merge-base), diff A (HEAD), diff B (MERGE_HEAD), commit messages
- Per altri file: solo lista

### 2. Riconcilia tasks.md

Per ogni file marcato `[tasks]`:
1. Leggi base, i due diff e i commit messages
2. Applica **entrambe** le serie di operazioni al file base (regole OT sotto)
3. Scrivi il file riconciliato COMPLETO con Edit tool: `${conflict_dir}/${file}`
4. `git -C ${conflict_dir} add ${file}`

Per ogni file marcato `[other]`:
- `git -C ${conflict_dir} checkout --theirs ${file}`
- `git -C ${conflict_dir} add ${file}`

### 3. Commit

```bash
git -C ${conflict_dir} commit --no-edit
```

---

## Regole OT per tasks.md

Hai il file base e due set di operazioni (diff A da HEAD, diff B da MERGE_HEAD).

### Operazioni indipendenti
Se diff A modifica T250 e diff B modifica T255 → applica entrambe, nessun conflitto.

### Conflitto sullo stesso task ID
**Precedenza stati** (il più avanzato vince):
`✔️ Done > 🟡 In Progress > 🔵 Todo > vuoto`

**Emoji additive**: 🚀📋 sono additive — mantieni se presenti in almeno un diff.

### Tasks Overview (tabella `| ID | Pri | K | Prog | Task |`)
- Applica modifiche colonna Prog da entrambi i diff
- Task aggiunte in un diff → aggiungi
- Task rimosse in un diff → rispetta la rimozione

### Execution Plan (grafo lane nel blocco ```)
- Applica modifiche emoji (✔️, 🟡) da entrambi i diff
- Preserva struttura frecce e nomi lane
- Task rimosse dalla tabella → rimuovi anche dal grafo

### Sezione LANES (`<!-- LANES:START/END -->`)
- Applica modifiche additive da entrambi i diff
- In conflitto reale: preferisci HEAD (diff A = main autoritativo)

### Sezioni non pertinenti
- Modificate da un solo diff → applica quel diff
- Modificate da entrambi → merge additivo (aggiungi contenuto da entrambi)
- Conflitto reale → preferisci HEAD

### Output
Scrivi il file riconciliato **COMPLETO** con Edit tool. NON produrre diff parziali.
