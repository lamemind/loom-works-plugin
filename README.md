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
| `/loom-works:checkpoint-mandate` | Checkpoint of a scope (epic or mandate): realign its task file to what the members did and found since the last progress entry — blockers, related tasks, open decisions, scope analysis re-checked, status copies removed; commits only the scope file and tasks.md, no doc phase, no questions. `checkpoint-task` hands epics and mandates over to it |
| `/loom-works:preflight-task` | Freeze design decisions before execution |
| `/loom-works:spawn-task` | Ask the project's running deck to open a task conversation (preflight, run with scope, recap, checkpoint) — one spawn per call, no questions |
| `/loom-works:close-session` | Ask the project's running deck to close a live conversation that `spawn-task` opened — the `claude` process ends, the tab closes, the transcript stays resumable; one session per call, no questions |
| `/loom-works:orchestrate-mandate` | Direct a scope semi-automatically — one id, an epic or a mandate (`Size: Mandate`): checks the written scope analysis at launch, recap, live sessions, session monitor; launches preflight, run and checkpoint of the members and the scope checkpoint at the end as headless turns with `loom-deck-headless`, no tab (a tab only when the user asks for one for a step), proposes answers and sends them only on the user's go-ahead (or by itself under a delegation the user declares) — never writes to the repos |
| `/loom-works:prepare-mandate` | Build a direction scope before it starts: create a mandate (`Size: Mandate`) from task ids or a description, add or remove its members, or write the scope analysis into an epic — dependencies and collisions between members, mechanical half from `mandate.py tree` plus a model half; the user confirms before every commit, member task files are never touched |
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

Everything under `scripts/` is bash and needs nothing beyond a POSIX shell, `git` and `jq` — with one exception, Python with the standard library only. One skill, the regia, also needs a command from the deck package.

| Dependency | Required by | Without it |
|---|---|---|
| `python3` (or `python` on Windows) | `scripts/regia/watch_sessions.py`, `scripts/regia/sessions.py` — the monitor that follows the live sessions of a project, and `list`/`tail` on them | No monitor for the regia of an epic. Whoever launches it reports the missing interpreter. |
| `loom-deck-headless` (npm `@lamemind/loom-deck`) | `orchestrate-mandate` — opens and continues the members' conversations without a tab | The regia stops at launch: `mandate.py gate` prints `HEADLESS=assente` and closes the gate. |

## TTS support

loom-works emits optional audio feedback via `scripts/utils/say.sh`. Requires macOS `say` or a compatible TTS backend. Degrades silently when unavailable.

## License

[MIT](LICENSE)
