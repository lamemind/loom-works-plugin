---
name: statusline-task-unpatch
description: Remove the loom-works active-task widget (📌) from the user's global Claude Code statusLine script. Deterministic, marker-based, idempotent. Inverse of statusline-task-patch.
allowed-tools: Bash(*), Read
---

Rimuove dalla **statusline globale** il widget task `📌` iniettato da `statusline-task-patch`. Deterministico via sentinel markers, idempotente (no-op se assente).

## 1. Risolvi il target

```bash
TARGET=$(${CLAUDE_PLUGIN_ROOT}/scripts/statusline/resolve-target.sh) && echo "target: $TARGET"
```

Se fallisce (exit 2/3): nessuno script statusline → niente da rimuovere. Riporta e fermati.

## 2. Strip

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/statusline/strip.sh "$TARGET"
```

Rimuove blocco marcato (`# >>> ... >>>` → `# <<< ... <<<`) + la wire line (`# loom-works:task-widget:wire`). L'output dice se ha rimosso qualcosa o se non c'era nulla.

## 3. Verifica

```bash
grep -c 'loom-works:task-widget' "$TARGET" || true   # atteso: 0
printf '%s' '{"model":{"display_name":"X"},"context_window":{"context_window_size":200000,"used_percentage":10}}' | bash "$TARGET" | grep -q '📌' && echo "📌 ancora presente (FAIL)" || echo "ok: widget rimosso, statusline valida"
```

## 4. Report

Conferma rimozione + esito test. Ricorda: ri-aggiungibile con `/loom-works:statusline-task-patch`.

## Note

- **Idempotente**: se il widget non c'è, lo script lo dice senza modificare nulla.
- **Sicuro**: `strip.sh` rifiuta di editare se trova begin marker senza end marker (file corrotto) → nessun troncamento.
