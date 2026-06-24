# >>> loom-works:task-widget >>>
# Active loom-works task (current-task.md symlink) → status bar. Lane-aware, self-contained.
# Managed by /loom-works:statusline-task-patch · remove via /loom-works:statusline-task-unpatch
LW_proj=$(printf '%s' "$data" | jq -r '.workspace.project_dir // .workspace.current_dir // .cwd // empty')
LW_task=""
for LW_cand in "$LW_proj/runtime/current-task.md" "$LW_proj/docs/current-task.md"; do
    if [ -L "$LW_cand" ]; then
        LW_task=$'\033[36m''📌 '"$(basename "$(readlink "$LW_cand")" .md)"$'\033[0m'
        break
    fi
done
# <<< loom-works:task-widget <<<
