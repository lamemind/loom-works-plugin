# >>> loom-works:task-widget >>>
# Active loom-works task → status bar. Cascade: $LOOM_TASK (session binding) → current-task.md symlink.
# Lane-aware, self-contained. Managed by /loom-works:statusline-task (patch default · unpatch token)
LW_proj=$(printf '%s' "$data" | jq -r '.workspace.project_dir // .workspace.current_dir // .cwd // empty')
LW_task=""
LW_file=""
LW_name=""
if [ -n "${LOOM_TASK:-}" ]; then
    # env vince: risolvi l'ID (Txx) al filename completo (Txx-slug), come il symlink; fallback all'ID grezzo
    for LW_td in "$LW_proj/runtime/tasks" "$LW_proj/docs/tasks"; do
        LW_file=$(ls "$LW_td/${LOOM_TASK}"-*.md 2>/dev/null | head -1)
        [ -n "$LW_file" ] && break
    done
    LW_name="${LW_file:+$(basename "$LW_file" .md)}"
    LW_name="${LW_name:-$LOOM_TASK}"
else
    for LW_cand in "$LW_proj/runtime/current-task.md" "$LW_proj/docs/current-task.md"; do
        if [ -L "$LW_cand" ]; then
            LW_file="$LW_cand"
            LW_name=$(basename "$(readlink "$LW_cand")" .md)
            break
        fi
    done
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
