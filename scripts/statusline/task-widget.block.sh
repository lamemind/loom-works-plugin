# >>> loom-works:task-widget >>>
# Active loom-works task → status bar. Cascade: $LOOM_TASK (session binding) → current-task.md symlink.
# Lane-aware, self-contained. Managed by /loom-works:statusline-task-patch · remove via /loom-works:statusline-task-unpatch
LW_proj=$(printf '%s' "$data" | jq -r '.workspace.project_dir // .workspace.current_dir // .cwd // empty')
LW_task=""
if [ -n "${LOOM_TASK:-}" ]; then
    # env vince: risolvi l'ID (Txx) al filename completo (Txx-slug), come il symlink; fallback all'ID grezzo
    LW_tf=""
    for LW_td in "$LW_proj/runtime/tasks" "$LW_proj/docs/tasks"; do
        LW_tf=$(ls "$LW_td/${LOOM_TASK}"-*.md 2>/dev/null | head -1)
        [ -n "$LW_tf" ] && break
    done
    LW_id="${LW_tf:+$(basename "$LW_tf" .md)}"
    LW_task=$'\033[36m''📌 '"${LW_id:-$LOOM_TASK}"$'\033[0m'
else
    for LW_cand in "$LW_proj/runtime/current-task.md" "$LW_proj/docs/current-task.md"; do
        if [ -L "$LW_cand" ]; then
            LW_task=$'\033[36m''📌 '"$(basename "$(readlink "$LW_cand")" .md)"$'\033[0m'
            break
        fi
    done
fi
# <<< loom-works:task-widget <<<
