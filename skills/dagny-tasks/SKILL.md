---
name: dagny-tasks
description: Manage tasks in the Dagny DAG-oriented task tracker via MCP tools. Use when creating, updating, or querying tasks, statuses, transitions, or dependencies.
argument-hint: "[list|create|update|status] [description]"
---

# Dagny Task Management

Dagny is a DAG-oriented task tracker with MCP tools for managing projects,
tasks, statuses, and dependencies.

## Authentication

The tools act as the Dagny user whose credential the MCP connection
carries; no tool takes a `user_id` argument. The credential is one of
these:

- The access token of a sign-in through the browser (OAuth). If the MCP
  connection shows "requires authentication", use the Authenticate option
  to complete the OAuth flow.
- A personal access token, sent as the header `Authorization: Bearer
  <token>`, for an agent that cannot sign in through a browser.

A change or reset of the user's password revokes all of the user's
personal access tokens at once. A client that signed in through the
browser keeps working until its access token expires, at most an hour
later, and must then sign in again.

## MCP Tools

| Tool | Purpose |
|------|---------|
| `mcp__dagny__whoami` | Get the authenticated user's ID, username, and email |
| `mcp__dagny__list_projects` | List projects accessible to the authenticated user |
| `mcp__dagny__create_project` | Create a new project |
| `mcp__dagny__get_task` | Get full task details including GitHub links. Accepts `task_id` (UUID) or `short_id` (integer) |
| `mcp__dagny__list_tasks` | List tasks with filters and field selection (see below) |
| `mcp__dagny__search_tasks` | One page of tasks matching a text, short id, or GitHub issue number, as lightweight results with each task's status; open tasks only unless `include_closed` is true (see below) |
| `mcp__dagny__create_task` | Create a task from `project_id` and `title`, and optionally `description`, `status_id`, `estimate`, `value`, `tags`, `depends_on`, `assignee_id`, and `repo_id`, a linked GitHub repository to open the task's issue in (see create_task with a repo below) |
| `mcp__dagny__update_task` | Change a task's or objective's `title`, `description`, `status_id`, `estimate`, `value`, `assignee_id`, or `objective_state`, and its tags, dependencies, and collaborators (see Updating Tasks below). Takes `project_id` and `task_id`, not `short_id` |
| `mcp__dagny__list_statuses` | List statuses configured for a project |
| `mcp__dagny__list_transitions` | List allowed status transitions for a project |
| `mcp__dagny__get_priority_tasks` | Get highest-priority unblocked tasks, sorted by effective value |
| `mcp__dagny__push_task_to_github` | Create a GitHub issue from a task and link them |
| `mcp__dagny__list_project_repos` | List GitHub repos linked to a project |
| `mcp__dagny__add_project_repo` | Link a GitHub repo to a project and check the Dagny App is installed on it (project admins). Relay `action_required` to the user when the App is missing |
| `mcp__dagny__set_repo_import_policy` | Set what a project mirrors unasked from a linked repo: `all`, `manual`, or `blockers` (project admins) |
| `mcp__dagny__import_github_issues` | Import issues from a linked repo as tasks, with their blockers unless `include_blockers` is false; per-item outcomes, and `action_required` to relay when a repo's App token could not be obtained |
| `mcp__dagny__list_github_issues` | The open issues of a linked repo, or of every linked repo when `repo_id` is left out, each with `mirrored`: whether the project already mirrors it. `only_new` keeps the unmirrored issues that are not pull requests; `limit` (1 to 200, default 200) and `offset` take a window, and `total` counts the issues before the window. A repo that cannot be read is named under `unreadable_repos`; relay `action_required` |
| `mcp__dagny__import_all_github_issues` | Import the open issues of a linked repo (`repo_id`) that the project does not yet mirror, pull requests left out, with their blockers unless `include_blockers` is false. Answers a `status`: `nothing_new`, `unreadable`, or `imported` with `requested`, `remaining`, and each issue's result in `outcomes`; call again while `remaining` is above zero. `remaining` leaves out the issues in `requested`, so read `outcomes` even when it is zero. An issue whose import failed is still not mirrored, so a later call can choose it again; when the same issues keep failing, import the others with `import_github_issues`. Relay `action_required` when a repo cannot be read |
| `mcp__dagny__refresh_task_github` | Refresh a task from its linked issue or pull request, GitHub being the source of truth, and return the report (see refresh_task_github below) |
| `mcp__dagny__list_task_prs` | List pull requests linked to a task with review state. Requires `project_id`, and the task must belong to that project |
| `mcp__dagny__get_task_history` | Get event history for a task from the event log. Accepts `task_id` (UUID) or `short_id` (integer) |
| `mcp__dagny__list_linear_teams` | List the project's Linear workspaces and linked teams. Each team gives its `teamId`, `key`, `importPolicy`, and `reviewSubIssues`. Relay `action_required` to the user when no workspace is connected: connecting takes a browser |
| `mcp__dagny__link_linear_team` | Link a Linear team, by `team_key` or `team_id` (see Linear teams below), from those Linear grants Dagny that the user's own Linear account can read, optionally setting its import policy (project admins). Relay `action_required` when the user must first connect their own Linear account: connecting takes a browser |
| `mcp__dagny__set_linear_team_import_policy` | Set the import policy of a linked team, named by `team_key` or `team_id`: `all` (every new issue becomes a task) or `manual` (only issues imported on request) (project admins) |
| `mcp__dagny__set_linear_team_review_sub_issues` | Turn on (`enabled: true`) or off (`enabled: false`) the creation of a Linear sub-issue for each review task, in a linked team named by `team_key` or `team_id` (project admins). A review task is the task Dagny keeps for one reviewer of a pull request; its sub-issue is made under the team's Linear issue that the pull request resolves. Turning the switch on creates no sub-issue in that call. Answers `team_key`, `team_id`, and `review_sub_issues` |
| `mcp__dagny__list_linear_issues` | One page of the open issues of a linked team, named by `team_key` or `team_id`, most recently updated first, each with a `disposition`: `new` (importing builds a task from Linear), `linksExisting` (importing links the task already mirroring the GitHub issue in `githubRef`), `viaGitHub` (importing mirrors `githubRef` from GitHub first), or `imported`; a query shaped like `ENG-12` finds that issue, any other matches titles; pass `nextCursor` back as `cursor` |
| `mcp__dagny__import_linear_issues` | Import Linear issues by identifier; per-item outcomes (imported, linked to the existing mirror of its GitHub issue, imported through GitHub, `teamNotLinked`, `notFound`, …), and `action_required` to relay when the workspace must be reconnected. An issue of a team the user's own Linear account cannot read is `notFound`. An issue whose outcome is `unavailable` was not imported this time, and its `message` says why; import it again later |
| `mcp__dagny__push_task_to_linear` | Create a Linear issue from a task in a linked team (by `team_key` or `team_id`) and link them; it starts in the state the team's status map gives the task's status, carries the task's GitHub issues, and mirrors its blockers and dependents already on Linear as blocks relations. Refused for a task already on Linear or whose GitHub issue already has a Linear issue; relay `action_required` when the workspace must be reconnected |
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

### Argument names

Every tool refuses a call that gives an argument name that its input
schema does not declare, and the `filter` argument of `list_tasks`
refuses an unknown key in the same way. A refused call changes nothing.
The error names each unknown name, and the declared name that differs
from it only in case or underscores, when there is one. Use the argument
names exactly as this skill and the tool schemas give them.

Five tools accept `short_id` in place of `task_id`: `get_task`,
`get_task_history`, `set_label_pin`, `clear_label_pin`, and
`list_task_notes`. Every other tool that names a task takes `task_id`,
the task's UUID, which `get_task` and `search_tasks` answer.

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
  | `includeTaskIds` | `string[]` or `null` | `null` | Start from these task UUIDs alone, whatever the other fields say (see below) |
  | `includeBlockers` | `bool` | `false` | Augment results with transitive upstream blockers |
  | `includeBlocked` | `bool` | `false` | Augment results with transitive downstream dependents |
  | `includeBridges` | `bool` | `false` | Also return the finished tasks (closed tasks and retired objectives) that lie on a dependency path between two returned tasks, as context |
  | `subsystems` | `string[]` or `null` | `null` | Include only tasks in at least one of these subsystem labels, by label UUID |
  | `objectives` | `string[]` or `null` | `null` | Include only tasks in at least one of these objective labels, by label UUID |
  | `kinds` | `string[]` or `null` | `null` | `task`, `objective`, or both; `null` returns both |
  | `includeUnconnected` | `bool` | `true` | `false` leaves out the tasks that block no task and that no task blocks |
  | `text` | `string` or `null` | `null` | A full-text query over titles and descriptions, in web-search syntax: words (all must match), `"quoted phrases"`, `-excluded` words, and `or` |

  In `assigneeIds`, `repoIds`, and `tags`, an element may be
  `__dagny:absent__`, which matches tasks with no assignee, no linked repo,
  or no tags, respectively. In `subsystems` and `objectives`, `__dagny:other__` selects
  the gap bucket (tasks the scheme was asked about whose work no label of
  it names), and `__dagny:absent__` selects tasks with no label of the
  scheme.

  With a non-empty `includeTaskIds`, the results start from those tasks
  alone, and they are returned whatever the other fields say,
  `includeUnconnected` included. An empty list sets no constraint.

  `includeBlockers` and `includeBlocked` walk the dependencies within the
  project, through closed tasks too. A task that the walk reaches is
  returned when it is open, or when `statusIds` allows its status; with
  `statusIds` null, closed tasks are returned as well. With a non-empty
  `includeTaskIds`, a reached task must also match the other fields. With
  `statusIds` set to the open statuses, the walk adds no closed task, but
  the tasks that `includeTaskIds` names and `includeBridges` adds are
  returned whatever their status.

- **`fields`**: Comma-separated list of fields to include. Only `task_id` and
  `short_id` are always returned. Options: `title`, `description`, `status`,
  `tags`, `estimate`, `value`, `effectiveValue`, `depends_on`, `assigneeId`,
  `prSummaries`, and `labels` (the effective labels per scheme and the
  classification summary).
  Example: `fields=title,status,deps` for a lightweight graph overview.
- **`limit`** / **`offset`**: Pagination. Use `limit=20` to cap results.

**Recommended pattern for large projects**: Start with
`list_tasks(project_id=<project-uuid>, filter={"statusIds": [<open-status-uuids>]}, fields="title,status,deps")`
to get the graph shape, then use `get_task` on specific tasks for full details.

**To exclude closed statuses**: call `list_statuses` first, collect the UUIDs of
non-closed statuses, then pass them as `filter.statusIds`.

### search_tasks

Finds tasks without loading the full list. The `query` matches a task's
short id (`42` or `#42`), the number of its linked GitHub issue or pull
request, its title, or its description, ranked in that order; a title that
starts with the query ranks before one that only contains it.

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `query` | `string` | required | The text to match |
| `include_closed` | `bool` | `false` | Match tasks in closed statuses too; they come after every open match |
| `limit` | `int` | `10` | Tasks per page: a positive integer, at most 100 |
| `offset` | `int` | `0` | Matches to skip, for later pages: a non-negative integer |

The result is one page:

```json
{"tasks": [
   {"task_id": "…", "short_id": 12, "title": "…", "statusId": "…",
    "statusName": "In Progress", "statusIsClosed": false},
   {"task_id": "…", "short_id": 3, "title": "…", "objectiveState": "active"}
 ],
 "hasMore": true}
```

- A task gives its `statusId`, `statusName`, and `statusIsClosed`. The two
  last are `null` for a status the project does not list.
- An objective gives `objectiveState` in place of the status fields.
- When `hasMore` is true, call again with `offset` increased by the number
  of tasks returned to get the next page.

To look for prior work, such as a completed task or a Wontfix decision,
pass `include_closed: true`.

### create_task with a repo

With `repo_id`, `create_task` also opens an issue for the new task in
that linked GitHub repository, and links the two.

- When the task is created but GitHub creates no issue, the answer names
  the task and says "GitHub issue not created", with the reason.
- When Dagny cannot confirm whether GitHub created the issue, the answer
  names the task and says so. Look at the repository's issues before you
  push the task with `push_task_to_github`: a push would create a second
  issue if the first exists.

### Note days

A note tool takes each day as `YYYY-MM-DD`. A tool that stores a day
(`create_note`, `update_note`) also takes `utc_offset_minutes`, the user's
offset from UTC on that day (for example `-420` for UTC-7); it defaults
to 0. The tools that list notes or days (`list_notes`, `list_team_notes`,
`list_note_days`) accept `utc_offset_minutes` too, and it has no effect
on them.

### Linear teams

A tool that acts on one Linear team takes the team as `team_key`, such
as `ENG`, or as `team_id`. Give exactly one of the two. Two of the
project's Linear workspaces can each have a team with the same key; then
`team_key` is refused, and the error names each team's workspace id and
team id. Give that `team_id` instead. For a team that the project already
links, `list_linear_teams` answers it as `teamId`.

### refresh_task_github

The tool refreshes a task through its issue link, or through its pull
request link when the task has no issue link.

- Through an issue, the refresh takes the task's text, status, assignee,
  dependencies, and tags from the issue, and imports the issue's blockers
  over the project's linked repositories. It also updates the review
  tasks of the issue's open pull requests.
- Through a pull request, the refresh imports no dependencies, and a
  review task takes only its status from it. It updates the pull
  request's review tasks when the pull request is open and the task is
  not a review task.

A review task is the task Dagny keeps for one reviewer of a pull
request. An update of the review tasks makes them follow GitHub:

- While GitHub lists the reviewer as requested, the review task is open
  and records no verdict.
- When GitHub no longer lists the reviewer, and the reviewer's latest
  approval or request for changes stands, the review task records that
  verdict and is closed.

A project can lack the status that such a change needs, and the task's
status then stays as it was. Read the task before you say that a review
task was opened or closed.

The report says what the refresh did. Among its fields are
`fieldsWritten`, `depsAdded`, `depsRemoved`, `tagsAdded`, `tagsRemoved`,
`prsAdded`, `prsRemoved`, `prSummaries`, `reviewTasksCreated`,
`reviewTasksReopened`, `reviewTasksVerdictRecorded`, and `tasksImported`.
`truncated` is true when the import of blockers stopped at the import
limit; refresh again to continue it. `resyncJobId` names the re-sync job
that is taking the tasks that the call made mirror an issue, or is
`null`.

### get_task_history

Returns the full event log for a task, ordered by time. Each entry contains:
- `id`: event UUID
- `initiatedById`: user UUID that triggered the event
- `eventTime`: ISO 8601 timestamp
- `action`: raw JSON of the event (e.g., `{"createNode": {...}}`, `{"setTitle": {...}}`, `{"setStatus": {...}}`)

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

### Updating Tasks

`update_task` writes every field that a call gives, or, when it refuses
the call, none of them. A call that gives no field to change answers
"Nothing to change".

- **Dependencies**: prefer `add_depends_on` and `remove_depends_on`. They
  add and remove the named dependencies, and keep the task's other
  dependencies. `depends_on` replaces the whole list. Give
  `depends_on_was`, the list that you read, with it: the call is then
  refused if the list changed since, and the refusal names the current
  list. `depends_on` cannot be combined with `add_depends_on` or
  `remove_depends_on`.
- A dependency on the task itself, or one that would close a cycle of
  dependencies, is refused. The answer names the tasks of the cycle by
  short id, and a task of a project that you are not a member of as "a
  task of another project". Leave that dependency out.
- **Tags**: prefer `add_tags` and `remove_tags`, which keep the task's
  other tags. `tags` replaces the whole set, so it removes a tag that
  another writer added since you read the task. It cannot be combined
  with `add_tags` or `remove_tags`. `add_tags` cannot hold an empty tag.
- **Objectives**: `objective_state` sets the state of an objective:
  `active`, `paused`, or `retired`. An objective has no status and no
  estimate.

### Task Assignment

`assignee_id` sets a task's primary assignee, and `null` unassigns it.
For collaborators, prefer `add_collaborators` and `remove_collaborators`,
which keep the task's other collaborators. `collaborator_ids` replaces
the whole set, and cannot be combined with them. These arguments take
user UUIDs. Every user that `assignee_id`, `collaborator_ids`, or
`add_collaborators` names must be a member of the project;
`remove_collaborators` can name any user. `whoami` answers your own
`user_id`.

## Best Practices

- Use descriptive task titles (imperative mood, concise).
- Add descriptions with enough context for future sessions.
- Tag tasks by area: `server`, `client`, `github`, `mcp`, `deploy`, `security`, etc.
- Set `value` on goal-level tasks to drive priority propagation.
- Build out the task graph before starting work — plan first, then execute.
- Always set tasks to "In Review" after implementation, not "Complete".
- Use `get_task` with `short_id` to look up GitHub issue numbers before creating PRs.
- Push tasks to GitHub (`push_task_to_github`) before creating branches so `Fixes #N` works.
