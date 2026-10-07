---
name: dagny-tasks
description: Manage tasks in the Dagny DAG-oriented task tracker via MCP tools. Use when creating, updating, or querying tasks, statuses, transitions, or dependencies.
argument-hint: "[list|create|update|status] [description]"
---

# Dagny Task Management

Dagny is a DAG-oriented task tracker with MCP tools for managing projects,
tasks, statuses, and dependencies.

## Authentication

MCP tools require OAuth authentication. The user identity is derived from
the JWT session automatically — no `user_id` parameter is needed. If the
MCP connection shows "requires authentication", use the Authenticate option
to complete the OAuth flow.

## MCP Tools

| Tool | Purpose |
|------|---------|
| `mcp__dagny__whoami` | Get the authenticated user's ID, username, and email |
| `mcp__dagny__list_projects` | List projects accessible to the authenticated user |
| `mcp__dagny__create_project` | Create a new project |
| `mcp__dagny__get_task` | Get full task details including GitHub links. Accepts `task_id` (UUID) or `short_id` (integer) |
| `mcp__dagny__list_tasks` | List tasks with filters and field selection (see below) |
| `mcp__dagny__search_tasks` | Text search on task titles/descriptions, returns lightweight results |
| `mcp__dagny__create_task` | Create a task (with optional deps, tags, status, assignee, value, repo) |
| `mcp__dagny__update_task` | Update task fields (title, description, status, deps, tags, estimate, value, assignee, collaborators) |
| `mcp__dagny__list_statuses` | List statuses configured for a project |
| `mcp__dagny__list_transitions` | List allowed status transitions for a project |
| `mcp__dagny__get_priority_tasks` | Get highest-priority unblocked tasks, sorted by effective value |
| `mcp__dagny__push_task_to_github` | Create a GitHub issue from a task and link them |
| `mcp__dagny__list_project_repos` | List GitHub repos linked to a project |
| `mcp__dagny__add_project_repo` | Link a GitHub repo to a project and check the Dagny App is installed on it (project admins). Relay `action_required` to the user when the App is missing |
| `mcp__dagny__set_repo_import_policy` | Set what a project mirrors unasked from a linked repo: `all`, `manual`, or `blockers` (project admins) |
| `mcp__dagny__import_github_issues` | Import issues from a linked repo as tasks, with their blockers unless `include_blockers` is false; per-item outcomes, and `action_required` to relay when a repo's App token could not be obtained |
| `mcp__dagny__refresh_task_github` | Refresh a task from its linked issue or pull request and return the report (conflicts, dependencies, imported blockers, truncation) |
| `mcp__dagny__list_task_prs` | List pull requests linked to a task with review state. Requires `project_id`, and the task must belong to that project |
| `mcp__dagny__get_task_history` | Get event history for a task from the event log. Accepts `task_id` (UUID) or `short_id` (integer) |
| `mcp__dagny__list_linear_teams` | List the project's Linear workspaces and linked teams with keys and import policies. Relay `action_required` to the user when no workspace is connected: connecting takes a browser |
| `mcp__dagny__link_linear_team` | Link a Linear team by key, from those Linear grants Dagny that the user's own Linear account can read, optionally setting its import policy (project admins). Relay `action_required` when the user must first connect their own Linear account: connecting takes a browser |
| `mcp__dagny__set_linear_team_import_policy` | Set a linked team's import policy: `all` (every new issue becomes a task) or `manual` (only issues imported on request) (project admins) |
| `mcp__dagny__list_linear_issues` | One page of a linked team's open issues, most recently updated first, each with a `disposition`: `new` (importing builds a task from Linear), `linksExisting` (importing links the task already mirroring the GitHub issue in `githubRef`), `viaGitHub` (importing mirrors `githubRef` from GitHub first), or `imported`; a query shaped like `ENG-12` finds that issue, any other matches titles; pass `nextCursor` back as `cursor` |
| `mcp__dagny__import_linear_issues` | Import Linear issues by identifier; per-item outcomes (imported, linked to the existing mirror of its GitHub issue, imported through GitHub, `teamNotLinked`, `notFound`, …), and `action_required` to relay when the workspace must be reconnected. An issue of a team the user's own Linear account cannot read is `notFound` |
| `mcp__dagny__push_task_to_linear` | Create a Linear issue from a task in a linked team (by `team_key`) and link them; it starts in the state the team's status map gives the task's status, carries the task's GitHub issues, and mirrors its blockers and dependents already on Linear as blocks relations. Refused for a task already on Linear or whose GitHub issue already has a Linear issue; relay `action_required` when the workspace must be reconnected |
| `mcp__dagny__list_labels` | List a project's labels: subsystems (authored) and objectives (derived from objective nodes), with their definitions |
| `mcp__dagny__create_subsystem` | Create a subsystem label from a color, name, description, exclusions, and example task titles; the short code is derived from the name when left out (maintainers) |
| `mcp__dagny__update_subsystem` | Update a subsystem's code, color, name, description, exclusions, or examples; omitted arguments keep their values (maintainers) |
| `mcp__dagny__set_label_pin` | Pin a label on (`member: true`) or off (`member: false`) for a task, overriding the model's inference. Accepts `task_id` or `short_id` |
| `mcp__dagny__clear_label_pin` | Remove a task's pin so the label follows the model's inference again. Accepts `task_id` or `short_id` |
| `mcp__dagny__classification_coverage` | How well a scheme's taxonomy fits the project: counts, tags and repositories over-represented in the gap bucket, and the bucket ranked by the model's "other" probability; use it to draft missing subsystems |
| `mcp__dagny__run_classification` | Classify the project's tasks now, whatever the automatic-run settings say; answers how many tasks were queued (maintainers) |
| `mcp__dagny__list_notes` | The user's own notes on a `day`, in one project or, without `project_id`, in every project |
| `mcp__dagny__create_note` | Create one of the user's notes in a project on a `day`. A `#N` in the body references task N. A new note is a `todo` visible to the whole project unless `visibility: "private"` is given; `copied_from_id` carries one of the user's notes forward to the new day |
| `mcp__dagny__update_note` | Change one of the user's notes: its `day`, `state` (`todo`, `in_progress`, `done`, `friction`), `visibility` (`private`, `project_public`), or `body`, or `dismissed`. Omitted arguments keep their values |
| `mcp__dagny__delete_note` | Delete one of the user's notes |
| `mcp__dagny__list_task_notes` | The notes that reference a task: the user's own, and the project-public notes of other members. Accepts `task_id` or `short_id` |
| `mcp__dagny__list_team_notes` | A project's notes on the days `from` to `to`, inclusive: the user's own, and the project-public notes of other members |
| `mcp__dagny__search_notes` | Search the user's own notes for text, newest first, in one project or every project; `limit` defaults to 50, at most 200 |
| `mcp__dagny__list_note_days` | The days `from` to `to` on which the user has notes, with counts, in one project or every project |

### list_tasks Parameters

For large projects, use these parameters to reduce context consumption:

- **`filter`**: A `TaskFilter` JSON object with inclusion-based semantics.
  All fields are optional; omitted fields impose no constraint.

  | Field | Type | Default | Description |
  |-------|------|---------|-------------|
  | `statusIds` | `string[]` or `null` | `null` | Include only tasks with these status UUIDs |
  | `assigneeIds` | `string[]` or `null` | `null` | Include only tasks assigned to these user UUIDs |
  | `repoIds` | `string[]` or `null` | `null` | Include only tasks linked to these GitHub repo UUIDs |
  | `tags` | `string[]` or `null` | `null` | Include only tasks with at least one of these tags |
  | `hasPR` | `bool` or `null` | `null` | If true, only tasks with a linked PR; if false, only tasks without |
  | `includePRTasks` | `bool` | `true` | Include tasks tagged `pr` |
  | `includeTaskIds` | `string[]` or `null` | `null` | Include these specific task UUIDs (intersected with other filters) |
  | `includeBlockers` | `bool` | `false` | Augment results with transitive upstream blockers |
  | `includeBlocked` | `bool` | `false` | Augment results with transitive downstream dependents |

  When `includeBlockers` or `includeBlocked` is true, closed tasks are excluded
  from the walk — completed blockers are considered resolved.

- **`fields`**: Comma-separated list of fields to include. Only `task_id` and
  `short_id` are always returned. Options: `title`, `description`, `status`,
  `tags`, `estimate`, `value`, `effectiveValue`, `depends_on`, `assigneeId`, `prSummaries`.
  Example: `fields=title,status,deps` for a lightweight graph overview.
- **`limit`** / **`offset`**: Pagination. Use `limit=20` to cap results.

**Recommended pattern for large projects**: Start with
`list_tasks(filter={"statusIds": [<open-status-uuids>]}, fields="title,status,deps")`
to get the graph shape, then use `get_task` on specific tasks for full details.

**To exclude closed statuses**: call `list_statuses` first, collect the UUIDs of
non-closed statuses, then pass them as `filter.statusIds`.

### search_tasks

Lightweight text search across task titles and descriptions. Returns only
`task_id`, `short_id`, `title`, and `statusId`. Use this to find specific
tasks without loading the full list.

### Note days

A note tool takes each day as `YYYY-MM-DD`. A tool that stores a day
(`create_note`, `update_note`) also takes `utc_offset_minutes`, the user's
offset from UTC on that day (for example `-420` for UTC-7); it defaults
to 0.

### get_task_history

Returns the full event log for a task, ordered by time. Each entry contains:
- `id`: event UUID
- `initiatedById`: user UUID that triggered the event
- `eventTime`: ISO 8601 timestamp
- `action`: raw JSON of the event (e.g., `{"createTask": {...}}`, `{"setTitle": {...}}`, `{"setStatus": {...}}`)

Useful for auditing when and how task data was changed.

## Task References

Tasks have both a UUID (`task_id`) and a project-scoped short integer ID
(`short_id`). Use `get_task` with `short_id` for human-friendly lookups
(e.g., "tell me about task #97"). The `get_task` response includes GitHub
link information (issue numbers, repo owner/name) needed for PR references.

## PR-Based Development Workflow

All feature work and bug fixes follow this workflow:

1. **Get the task**: Use `get_task` to get full details including the GitHub issue number.
2. **Create a branch**: `git checkout -b feat/<name>` or `fix/<name>` from the default branch.
3. **Implement**: Make changes, build, test.
4. **Commit**: Reference the GitHub issue with `Fixes #N` in the commit message.
5. **Push and create PR**: Push the branch, create a PR with `gh pr create`.
6. **Update task status**: Transition to "In Review" after the PR is created.
7. **Switch back to default branch**: Continue with the next task.

### PR Conventions

- PR title: concise description of the change (under 70 chars)
- PR body: `## Summary` (bullets), `Fixes #N`, `## Test plan` (checklist)
- The `Fixes #N` keyword links the PR to the GitHub issue; merging closes both the issue and the corresponding Dagny task via webhook

### Status Transitions

Transition tasks through statuses as work proceeds. The typical flow is:

```
Created -> In Progress -> In Review -> Complete
```

Use `list_statuses` to get status UUIDs and `list_transitions` to see which
transitions are allowed from the current status.

- **Starting work**: transition to "In Progress"
- **PR created**: transition to "In Review"
- **User verified**: only the user marks tasks "Complete" after verification

## Workflow Details

### Finding IDs

1. Call `list_projects` to find the project.
2. Use `list_statuses` to get status UUIDs for the project.

### Creating Tasks with Dependencies

Create tasks in dependency order — independent tasks first, then tasks that
depend on them:

1. Create independent tasks (no `depends_on`).
2. Capture the returned task IDs.
3. Create dependent tasks with `depends_on` referencing the earlier IDs.
4. Tasks that can be created in parallel (no mutual deps) should use
   parallel tool calls.

### Priority-Driven Workflow

Use `get_priority_tasks` to find what to work on next. By default, it
returns only tasks in the project's default (Created) status — tasks that
haven't been started yet. Pass `status_ids` to include other statuses.

Tasks with higher `value` propagate priority to their dependencies via
`effectiveValue`, so leaf tasks that block high-value goals sort first.

### Updating Dependencies

When calling `update_task` with `depends_on`, provide the **complete** list
of dependency task IDs — it replaces the existing list, not appends to it.

### Task Assignment

Tasks support `assignee_id` (primary assignee) and `collaboratorIds`
(additional collaborators). Use project member UUIDs for these fields.

## Best Practices

- Use descriptive task titles (imperative mood, concise).
- Add descriptions with enough context for future sessions.
- Tag tasks by area: `server`, `client`, `github`, `mcp`, `deploy`, `security`, etc.
- Set `value` on goal-level tasks to drive priority propagation.
- Build out the task graph before starting work — plan first, then execute.
- Always set tasks to "In Review" after implementation, not "Complete".
- Use `get_task` with `short_id` to look up GitHub issue numbers before creating PRs.
- Push tasks to GitHub (`push_task_to_github`) before creating branches so `Fixes #N` works.
