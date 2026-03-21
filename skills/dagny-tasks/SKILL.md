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
| `mcp__dagny__list_task_prs` | List pull requests linked to a task with review state |

### list_tasks Parameters

For large projects, use these parameters to reduce context consumption:

- **`fields`**: Comma-separated list of fields to include. Only `task_id` and
  `short_id` are always returned. Options: `title`, `description`, `status`,
  `tags`, `estimate`, `value`, `effectiveValue`, `depends_on`, `assigneeId`, `hasPR`.
  Example: `fields=title,status,deps` for a lightweight graph overview.
- **`limit`** / **`offset`**: Pagination. Use `limit=20` to cap results.
- **`status_id`**: Filter to a single status UUID.
- **`exclude_closed`**: Omit tasks in closed statuses (default false).
- **`tags`**: Comma-separated tag filter (OR logic).
- **`assignee_id`**: Filter to tasks assigned to a specific user.
- **`has_value`**: Filter to tasks with business value set.

**Recommended pattern for large projects**: Start with
`list_tasks(fields="title,status,deps", exclude_closed=true)` to get the
graph shape, then use `get_task` on specific tasks for full details.

### search_tasks

Lightweight text search across task titles and descriptions. Returns only
`task_id`, `short_id`, `title`, and `statusId`. Use this to find specific
tasks without loading the full list.

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
