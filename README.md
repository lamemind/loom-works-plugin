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
| `/loom-works:recap-status` | Recap dispatcher: resolves the active task and routes to one of the three below |
| `/loom-works:recap-status-project` | Whole-project recap with doc↔git cross-check — no next-step proposal |
| `/loom-works:recap-status-task` | Single-task recap: open DLV/AC, material produced, one named next step |
| `/loom-works:recap-status-epic` | Umbrella-task recap: children with DLV/AC figures, deps, two-level entry point |
| `/loom-works:list-worktrees` | List worktrees with branch, dirty count and active task |
| `/loom-works:reindex` | Regenerate the reference INDEX.md from file TLDRs |
| `/loom-works:capture-doc` | Capture ad-hoc doc notions outside of tasks |
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
        "on_lane_spawned_hook": ""
      }
    }
  }
}
```

| Option | Default | Description |
|--------|---------|-------------|
| `on_lane_spawned_hook` | (empty) | Path relative to project root, executed once after `spawn-lane` |

### Docs folder — not a user option

The folder holding `tasks.md`, `tasks/`, `reference/` and `current-task.md` is **per-project**, so it lives in the project file `.claude/loom-works.json` under `docsRoot` (default `docs`), not in `userConfig`. User options are global across every project: a project keeping its docs in `runtime/` cannot be described by one.

```json
{ "id": "my-project", "docsRoot": "runtime" }
```

Read it with `scripts/utils/docs-root.sh` (`--abs` for an absolute path); scripts resolve it themselves via `lw_docs_root` in `scripts/utils/lib.sh`.

## TTS support

loom-works emits optional audio feedback via `scripts/utils/say.sh`. Requires macOS `say` or a compatible TTS backend. Degrades silently when unavailable.

## License

[MIT](LICENSE)
