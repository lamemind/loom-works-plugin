# loom-works

A Claude Code plugin that brings lane-based task management with a coupled documentation lifecycle to your projects.

## What it does

loom-works organizes work into **tasks** and **lanes**:

- **Tasks** — atomic units of work tracked in `docs/tasks.md` with git-anchored progress
- **Lanes** — persistent git worktrees (`feat/{lane}`) hosting sequences of related tasks, eliminating repeated setup overhead
- **Doc lifecycle** — tasks emit documentation fragments that are captured, indexed, and embedded as CLAUDE.md context

## Install

```
/plugin install loom-works@lamemind
```

Or add directly to your project's `.claude/settings.json`:

```json
{
  "pluginConfigs": {
    "loom-works@lamemind": {}
  }
}
```

Then bootstrap the project structure:

```
/loom-works:init
```

## Skills

| Skill | Description |
|-------|-------------|
| `/loom-works:init` | Bootstrap loom-works structure on the current project |
| `/loom-works:create-task` | Create a new task with automation-ready metadata |
| `/loom-works:start-task` | Activate a task for checkpoint tracking |
| `/loom-works:run-task` | Execute a task (adaptive S/M/L workflow) |
| `/loom-works:checkpoint-task` | Checkpoint progress: analyze changes, commit, update tasks.md |
| `/loom-works:preflight-task` | Freeze design decisions before execution |
| `/loom-works:spawn-lane` | Create a persistent git worktree lane |
| `/loom-works:merge-lane` | Merge lane into main, keep worktree |
| `/loom-works:drop-lane` | Destroy a lane without merging |
| `/loom-works:recap-status` | Project status overview with doc↔git cross-check |
| `/loom-works:list-worktrees` | List worktrees with branch, dirty count and active task |
| `/loom-works:reindex` | Regenerate the reference INDEX.md from file TLDRs |
| `/loom-works:capture-doc` | Capture ad-hoc doc notions outside of tasks |
| `/loom-works:doc-task` | Create a documentary task (D{N} prefix) |
| `/loom-works:run-doc` | Multi-round workflow for documentary tasks |
| `/loom-works:discover` | Doc bootstrap for a project with zero existing docs |
| `/loom-works:tutor` | Interactive topic tutor with comprehension checkpoints |
| `/loom-works:scratch-new` | Create a scratch folder for ad-hoc investigations |
| `/loom-works:set-task-folder` | Attach a task folder to an existing task |
| `/loom-works:reconcile-tasks` | Reconcile git conflicts in tasks.md during lane merge |

## Configuration

All options are optional. Set in your project's `.claude/settings.json`:

```json
{
  "pluginConfigs": {
    "loom-works@lamemind": {
      "options": {
        "doc_folder_name": "docs",
        "project_mode": "repo",
        "on_lane_spawned_hook": ""
      }
    }
  }
}
```

| Option | Default | Description |
|--------|---------|-------------|
| `doc_folder_name` | `docs` | Folder for tasks.md, tasks/, reference/, current-task.md |
| `project_mode` | auto-detect | `repo` or `no-repo` — auto-detected via `git rev-parse` if empty |
| `on_lane_spawned_hook` | (empty) | Path relative to project root, executed once after `spawn-lane` |

## TTS support

loom-works emits optional audio feedback via `scripts/utils/say.sh`. Requires macOS `say` or a compatible TTS backend. Degrades silently when unavailable.

## License

[MIT](LICENSE)
