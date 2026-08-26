---
name: statusline-task
description: Manage the loom-works active-task widget (📌 $LOOM_TASK → current-task symlink) in the user's global Claude Code statusLine script. Default mode patches it in; token `unpatch` removes it. Idempotent, marker-based, lane-aware.
allowed-tools: Bash(*), Read, Edit, AskUserQuestion
---

Gestisce sulla **statusline globale** il widget `📌 Tnn` che mostra la task attiva con cascata `$LOOM_TASK → symlink current-task.md`: se la sessione ha `LOOM_TASK` settata (binding per-sessione, es. spawn `deck-run`) vince quella; altrimenti fallback al symlink `current-task.md` del progetto corrente (lane-aware, perché legge `workspace.project_dir`).

Il widget è **self-contained inline** (non dipende da `${CLAUDE_PLUGIN_ROOT}`, che NON espande nel contesto statusLine) e delimitato da **sentinel markers** → patch idempotente, unpatch deterministico.

## Modo

Due modi, stesso file, stessi marker:

- **patch** (default) — inietta il widget.
- **unpatch** — lo rimuove. Attivo se le Note utente contengono il token `unpatch` (o una richiesta esplicita di rimozione).

## 0. Risolvi il target (entrambi i modi)

```bash
TARGET=$(${CLAUDE_PLUGIN_ROOT}/scripts/statusline/resolve-target.sh) && echo "target: $TARGET"
```

- **exit 2/3** (nessuna statusLine, o command inline senza file `.sh`): NON inventare. In patch riporta che non c'è uno script statusline da patchare e fermati (oppure offri di crearne uno minimale solo se l'utente lo chiede). In unpatch: niente da rimuovere, riporta e fermati.
- **ok**: prosegui col modo scelto.

---

## Modo patch

### 1. Clean slate (rende la patch idempotente)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/statusline/strip.sh "$TARGET"
```

Rimuove un'eventuale versione precedente del widget (no-op se assente). Ora reinserisci da zero.

### 2. Leggi e comprendi lo script

`Read "$TARGET"`. Identifica due cose:

| Cosa | Come | Default tipico |
| --- | --- | --- |
| **Var JSON** | la variabile che cattura stdin (`x=$(cat)` / `$(</dev/stdin)`) | `data` |
| **Var output** | la variabile con la stringa finale stampata da `echo`/`printf` in fondo | `parts` |

### 3. Inserisci il blocco

Blocco canonico (single source of truth):

```bash
cat ${CLAUDE_PLUGIN_ROOT}/scripts/statusline/task-widget.block.sh
```

Inseriscilo con `Edit` **dopo** la cattura del JSON e **prima** dell'assemblaggio dell'output finale. Adatta SOLO se il target differisce dai default:

- se la var JSON non è `data` → sostituisci `"$data"` nel blocco con la var giusta.
- folder docs: il blocco prova `runtime/` e `docs/`. Se la docs-root del progetto è diversa da entrambe — leggila con `"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"` — aggiungi `"$LW_proj/{docs_root}/current-task.md"` come primo candidato nel loop.
- **non toccare** i marker `# >>> ... >>>` / `# <<< ... <<<`.

### 4. Wire nell'output

Aggiungi una **riga dedicata** (mai append a una riga host esistente) subito prima della stampa finale, che prepende il widget alla var output con separatore condizionale:

```bash
parts="${LW_task:+$LW_task | }$parts"   # loom-works:task-widget:wire
```

Sostituisci `parts` con la var output reale. La riga DEVE terminare col commento `# loom-works:task-widget:wire` (è il contratto per l'unpatch).

### 5. Test (obbligatorio)

```bash
SL_DIR=$(mktemp -d); mkdir -p "$SL_DIR/runtime/tasks"
echo x > "$SL_DIR/runtime/tasks/T99-smoke.md"
ln -s "$SL_DIR/runtime/tasks/T99-smoke.md" "$SL_DIR/runtime/current-task.md"
SL_JSON='{"model":{"display_name":"X"},"workspace":{"project_dir":"'"$SL_DIR"'"},"context_window":{"context_window_size":200000,"used_percentage":10}}'
echo "=== symlink (no env) ==="; env -u LOOM_TASK bash "$TARGET" <<<"$SL_JSON" | grep -o '📌 [^ ]*' || echo "NO 📌 (FAIL)"
echo "=== env → slug intero (ID risolto al filename) ==="; LOOM_TASK=T99 bash "$TARGET" <<<"$SL_JSON" | grep -o '📌 [^ ]*' || echo "NO 📌 (FAIL)"
echo "=== env → fallback ID grezzo (file assente) ==="; LOOM_TASK=T42 bash "$TARGET" <<<"$SL_JSON" | grep -o '📌 [^ ]*' || echo "NO 📌 (FAIL)"
echo "=== SENZA task ==="; printf '%s' '{"model":{"display_name":"X"},"workspace":{"project_dir":"/nonexistent"},"context_window":{"context_window_size":200000,"used_percentage":10}}' | env -u LOOM_TASK bash "$TARGET" | grep -q '📌' && echo "📌 presente (FAIL)" || echo "ok: niente 📌"
rm -rf "$SL_DIR"
```

Atteso: symlink → `📌 T99-smoke`; env con file → `📌 T99-smoke` (ID risolto allo slug); env senza file → `📌 T42` (fallback grezzo); SENZA → niente 📌, riga valida.

### 6. Report

Riporta in forma compatta: target patchato, esito test, una riga d'esempio. Ricorda: rimovibile con `/loom-works:statusline-task unpatch`. Nessun restart necessario.

---

## Modo unpatch

### 1. Strip

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/statusline/strip.sh "$TARGET"
```

Rimuove blocco marcato (`# >>> ... >>>` → `# <<< ... <<<`) + la wire line (`# loom-works:task-widget:wire`). L'output dice se ha rimosso qualcosa o se non c'era nulla.

### 2. Verifica

```bash
grep -c 'loom-works:task-widget' "$TARGET" || true   # atteso: 0
printf '%s' '{"model":{"display_name":"X"},"context_window":{"context_window_size":200000,"used_percentage":10}}' | bash "$TARGET" | grep -q '📌' && echo "📌 ancora presente (FAIL)" || echo "ok: widget rimosso, statusline valida"
```

### 3. Report

Conferma rimozione + esito test. Ricorda: ri-aggiungibile con `/loom-works:statusline-task`.

---

## Note

- **Globale**: lo script serve TUTTE le sessioni/progetti. In progetti senza symlink il widget degrada vuoto. Corretto.
- **Idempotente**: patch re-invocata = strip + reinsert → nessuna duplicazione; unpatch su widget assente = no-op dichiarato.
- **Lane-aware**: in worktree lane `workspace.project_dir` = root lane → mostra la task della lane.
- **Sicuro**: `strip.sh` rifiuta di editare se trova begin marker senza end marker (file corrotto) → nessun troncamento.
