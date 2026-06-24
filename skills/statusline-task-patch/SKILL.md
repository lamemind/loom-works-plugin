---
name: statusline-task-patch
description: Inject the loom-works active-task widget (📌 current-task symlink) into the user's global Claude Code statusLine script. Idempotent, marker-based, lane-aware. Reversible via statusline-task-unpatch.
allowed-tools: Bash(*), Read, Edit, AskUserQuestion
---

Aggiunge alla **statusline globale** un widget `📌 Tnn-slug` che mostra la task attiva risolvendo il symlink `current-task.md` del progetto corrente (lane-aware, perché legge `workspace.project_dir`).

Il widget è **self-contained inline** (non dipende da `${CLAUDE_PLUGIN_ROOT}`, che NON espande nel contesto statusLine) e delimitato da **sentinel markers** → patch idempotente, unpatch deterministico.

## 0. Risolvi il target

```bash
TARGET=$(${CLAUDE_PLUGIN_ROOT}/scripts/statusline/resolve-target.sh) && echo "target: $TARGET"
```

- **exit 2/3** (nessuna statusLine, o command inline senza file `.sh`): NON inventare. Riporta all'utente che non c'è uno script statusline da patchare e fermati (oppure offri di crearne uno minimale solo se l'utente lo chiede). Stop.
- **ok**: prosegui.

## 1. Clean slate (rende la patch idempotente)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/statusline/strip.sh "$TARGET"
```

Rimuove un'eventuale versione precedente del widget (no-op se assente). Ora reinserisci da zero.

## 2. Leggi e comprendi lo script

`Read "$TARGET"`. Identifica due cose:

| Cosa | Come | Default tipico |
| --- | --- | --- |
| **Var JSON** | la variabile che cattura stdin (`x=$(cat)` / `$(</dev/stdin)`) | `data` |
| **Var output** | la variabile con la stringa finale stampata da `echo`/`printf` in fondo | `parts` |

## 3. Inserisci il blocco

Blocco canonico (single source of truth):

```bash
cat ${CLAUDE_PLUGIN_ROOT}/scripts/statusline/task-widget.block.sh
```

Inseriscilo con `Edit` **dopo** la cattura del JSON e **prima** dell'assemblaggio dell'output finale. Adatta SOLO se il target differisce dai default:

- se la var JSON non è `data` → sostituisci `"$data"` nel blocco con la var giusta.
- folder docs: il blocco prova `runtime/` e `docs/`. Se `${user_config.doc_folder_name}` è diverso da entrambi, aggiungi `"$LW_proj/${user_config.doc_folder_name}/current-task.md"` come primo candidato nel loop.
- **non toccare** i marker `# >>> ... >>>` / `# <<< ... <<<`.

## 4. Wire nell'output

Aggiungi una **riga dedicata** (mai append a una riga host esistente) subito prima della stampa finale, che prepende il widget alla var output con separatore condizionale:

```bash
parts="${LW_task:+$LW_task | }$parts"   # loom-works:task-widget:wire
```

Sostituisci `parts` con la var output reale. La riga DEVE terminare col commento `# loom-works:task-widget:wire` (è il contratto per l'unpatch).

## 5. Test (obbligatorio)

```bash
SL_DIR=$(mktemp -d); mkdir -p "$SL_DIR/runtime/tasks"
echo x > "$SL_DIR/runtime/tasks/T99-smoke.md"
ln -s "$SL_DIR/runtime/tasks/T99-smoke.md" "$SL_DIR/runtime/current-task.md"
echo "=== CON task ===";  printf '%s' '{"model":{"display_name":"X"},"workspace":{"project_dir":"'"$SL_DIR"'"},"context_window":{"context_window_size":200000,"used_percentage":10}}' | bash "$TARGET" | grep -o '📌 [^ ]*' || echo "NO 📌 (FAIL)"
echo "=== SENZA task ==="; printf '%s' '{"model":{"display_name":"X"},"workspace":{"project_dir":"/nonexistent"},"context_window":{"context_window_size":200000,"used_percentage":10}}' | bash "$TARGET" | grep -q '📌' && echo "📌 presente (FAIL)" || echo "ok: niente 📌"
rm -rf "$SL_DIR"
```

Atteso: CON task → `📌 T99-smoke`; SENZA → niente 📌, riga valida.

## 6. Report

Riporta in forma compatta: target patchato, esito test, una riga d'esempio. Ricorda: rimovibile con `/loom-works:statusline-task-unpatch`. Nessun restart necessario.

## Note

- **Globale**: lo script serve TUTTE le sessioni/progetti. In progetti senza symlink il widget degrada vuoto. Corretto.
- **Idempotente**: re-invocare = strip + reinsert → nessuna duplicazione.
- **Lane-aware**: in worktree lane `workspace.project_dir` = root lane → mostra la task della lane.
