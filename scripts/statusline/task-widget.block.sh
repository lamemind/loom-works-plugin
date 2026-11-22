# >>> loom-works:task-widget >>>
# Active loom-works task → status bar. Source: $LOOM_TASK (session binding) only; without it, no 📌.
# Self-contained. Managed by /loom-works:statusline-task (patch default · unpatch token)
LW_proj=$(printf '%s' "$data" | jq -r '.workspace.project_dir // .workspace.current_dir // .cwd // empty')
LW_task=""
LW_file=""
LW_name=""
if [ -n "${LOOM_TASK:-}" ]; then
    # risolvi l'ID (Txx) al filename completo (Txx-slug); fallback all'ID grezzo
    for LW_td in "$LW_proj/runtime/tasks" "$LW_proj/docs/tasks"; do
        LW_file=$(ls "$LW_td/${LOOM_TASK}"-*.md 2>/dev/null | head -1)
        [ -n "$LW_file" ] && break
    done
    LW_name="${LW_file:+$(basename "$LW_file" .md)}"
    LW_name="${LW_name:-$LOOM_TASK}"
fi
if [ -n "$LW_name" ]; then
    # Pallino di stato dal campo Progress del task file: è testo libero (`🟡 85%`), quindi
    # si prende il primo token e si mostra solo se è un glifo del ciclo di vita, altrimenti niente
    LW_prog=""
    [ -f "$LW_file" ] && LW_prog=$(sed -n '/^- \*\*Progress\*\*:/{s/^- \*\*Progress\*\*:[[:space:]]*\([^[:space:]]*\).*/\1/p;q}' "$LW_file")
    case "$LW_prog" in
        🔵|🟢|🟡|✔️|🔒) ;;
        *) LW_prog="" ;;
    esac
    LW_task=$'\033[36m''📌 '"${LW_prog:+$LW_prog }$LW_name"$'\033[0m'
fi
# <<< loom-works:task-widget <<<
