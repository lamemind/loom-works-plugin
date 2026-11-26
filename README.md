# loom-works

A Claude Code plugin that brings task management with a coupled documentation lifecycle to your projects.

## What it does

loom-works organizes work into **tasks**:

- **Tasks** — atomic units of work tracked in `docs/tasks.md` with git-anchored progress, run in the project's own worktree (on main, or on a branch the task file declares)
- **Doc lifecycle** — tasks emit documentation fragments that are captured, indexed, and embedded as CLAUDE.md context

## Install

The plugin is published in the `lamemind` marketplace ([`lamemind/claude-marketplace`](https://github.com/lamemind/claude-marketplace)):

```
/plugin marketplace add lamemind/claude-marketplace
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
| `/loom-works:run-task` | Execute a task's deliverables — scoped per DLV, one commit each |
| `/loom-works:checkpoint-task` | Checkpoint progress: commit the files you name, update tasks.md |
| `/loom-works:checkpoint-perimeter` | Checkpoint of an orchestrable perimeter (epic or custom list): realign its task file to what the members did and found since the last progress entry — blockers, related tasks, open decisions, perimeter analysis re-checked, status copies removed; commits only the perimeter file and tasks.md, no doc phase, no questions. `checkpoint-task` hands epics and custom lists over to it |
| `/loom-works:preflight-task` | Freeze design decisions before execution |
| `/loom-works:spawn-task` | Ask the project's running deck to open a task conversation (preflight, run with scope, recap, checkpoint) — one spawn per call, no questions |
| `/loom-works:close-session` | Ask the project's running deck to close a live conversation that `spawn-task` opened — the `claude` process ends, the tab closes, the transcript stays resumable; one session per call, no questions |
| `/loom-works:orchestrate-perimeter` | Direct an orchestrable perimeter semi-automatically — one id, an epic or a custom list (`Size: Custom`): checks the perimeter's plan (`orchestration-schedule.md`) at launch, then starts the flow script (`flow.py`) detached, which opens and closes preflight, run and checkpoint of the members as headless turns following the plan, asks for the checkpoint after a clean run and launches the perimeter checkpoint at the end; the orchestrator waits with a background Bash and wakes only for a judgement — questions, findings, unclassified outcomes, a plan that no longer holds, the context threshold, the cache keep-alive —, proposes answers and sends them only on the user's go-ahead (or by itself under a delegation the user declares), rewrites and commits the plan on a collision; never writes to task files |
| `/loom-works:drive-task` | Move one task forward by one step from the conversation that asks for it — launches a headless preflight (no tab) with the context the conversation built with the user, waits for the turn to end, brings the preflight's questions into the chat and sends the answers, on the user's go-ahead or by itself under a delegation (`con delega`); keeps who drives the step in `.claude/loom/drive/`, ignored by git |
| `/loom-works:prepare-perimeter` | Build an orchestrable perimeter before it starts: create a custom list (`Size: Custom`) from task ids or a description, add or remove its members, or prepare an epic — and write its plan, `orchestration-schedule.md` in the perimeter's task folder: dependencies and collisions between members (mechanical half from `perimeter.py tree` plus a model half) and the order the flow script follows; the user confirms before every commit, member task files are never touched |
| `/loom-works:recap-status` | Recap dispatcher: resolves the active task and routes to one of the two below; with no task resolved it answers «nessuna task» |
| `/loom-works:recap-status-task` | Single-task recap: open DLV/AC, material produced, one named next step |
| `/loom-works:recap-status-epic` | Umbrella-task recap: children with DLV/AC figures, deps, two-level entry point |
| `/loom-works:pull-repos` | Pull umbrella + submodules, unlock `branch:` inboxes found on main |
| `/loom-works:statusline-task` | Manage the 📌 active-task widget in the global statusline (default patch, token `unpatch`) |
| `/loom-works:scratch-new` | Create a scratch folder for ad-hoc investigations |
| `/loom-works:set-task-folder` | Attach a task folder to an existing task |

## Configuration

The plugin declares no user options (`userConfig`). Every setting is per-project and lives in the project file `.claude/loom-works.json`.

### Docs folder — not a user option

The folder holding `tasks.md`, `tasks/` and `reference/` is **per-project**, so it lives in the project file `.claude/loom-works.json` under `docsRoot` (default `docs`), not in `userConfig`. User options are global across every project: a project keeping its docs in `runtime/` cannot be described by one.

```json
{ "id": "my-project", "docsRoot": "runtime" }
```

Read it with `scripts/utils/docs-root.sh` (`--abs` for an absolute path); scripts resolve it themselves via `lw_docs_root` in `scripts/utils/lib.sh`.

### Task fields and lifecycle hooks — per project

The same file can declare two optional blocks: `taskFields`, extra fields that `create-task` asks for and writes into the task file header, and `hooks`, project skills invoked by `run-task` and `checkpoint-task` when a deliverable closes (`deliverableDone`) and when the task closes (`taskDone`).

```json
{
  "taskFields": [{ "key": "User Story", "pattern": "^[A-Z]+-\\d+$", "inherit": true }],
  "hooks": { "deliverableDone": ["jira-sync"], "taskDone": ["jira-sync"] }
}
```

Skills read the blocks with `scripts/config/project-config.sh`. Contract — reserved keys, hook arguments, how a hook skill must behave unattended: `docs/taskfields-hooks-format.md`.

## Runtime dependencies

Everything under `scripts/` is bash and needs nothing beyond a POSIX shell, `git` and `jq` — with one exception, Python with the standard library only. Two skills, the orchestrator and `drive-task`, also need a command from the deck package.

| Dependency | Required by | Without it |
|---|---|---|
| `python3` (or `python` on Windows) | `scripts/orchestrator/flow.py` — the flow script of an orchestrator, with the scanners of `watch_sessions.py` that follow the live sessions of a project; `scripts/orchestrator/orchestration_schedule.py` — the orchestrable perimeter's plan; `scripts/orchestrator/sessions.py` — `list`/`tail` on the live sessions; `scripts/orchestrator/drive_state.py` — the entry checks of `drive-task` | No orchestrator, no `prepare-perimeter`, no `drive-task`. Whoever launches them reports the missing interpreter. |
| `loom-deck-headless` (npm `@lamemind/loom-deck`) | `orchestrate-perimeter` — opens and continues the members' conversations without a tab | The orchestrator stops at launch: `perimeter.py gate` prints `HEADLESS=assente` and closes the gate. |
| `loom-deck-headless` ≥ 0.99.0, with `open --context` | `drive-task` — opens the step with the conversation's context in its user notes | `drive-task` stops at launch: `drive_state.py check` prints `HEADLESS_CONTEXT=no` (or `HEADLESS=assente`). |

## TTS support

loom-works emits optional audio feedback via `scripts/utils/say.sh`. Requires macOS `say` or a compatible TTS backend. Degrades silently when unavailable.

## License

[MIT](LICENSE)
