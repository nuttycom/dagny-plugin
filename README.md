# Dagny plugin for Claude Code

A [Claude Code](https://claude.com/claude-code) plugin for
[Dagny](https://dagny.co), a task tracker that models work as a directed
acyclic graph of dependencies. The plugin connects Claude Code to Dagny's
MCP server and adds a skill, agents, and hooks for a task-driven
pull-request workflow.

## Contents

| Component | Description |
|-----------|-------------|
| MCP server `dagny` | The Dagny tools (projects, tasks, statuses, dependencies, notes, GitHub and Linear integration) at `https://dagny.co/mcp`. |
| Skill `dagny-tasks` | How to use the tools: task references, filters, and the PR-based workflow. |
| Agent `task-planner` | Breaks a feature or bug into a graph of tasks with dependencies, estimates, and values. |
| Agent `pr-workflow` | Creates the branch and PR for an implemented task and updates the task's status. |
| Hook (before `gh pr create`) | Blocks a PR whose body has no `Fixes #N`, `Closes #N`, or `Resolves #N`. |
| Hook (after `git commit`) | Reminds Claude to update the Dagny task when a commit closes an issue. |

## Requirements

- Claude Code.
- A Dagny account at [dagny.co](https://dagny.co).
- `jq` on your `PATH`. The hooks use it.
- The GitHub CLI `gh`, for the PR workflow.

## Installation

Add this repository as a plugin marketplace, then install the plugin from
it. In a Claude Code session:

```
/plugin marketplace add nuttycom/dagny-plugin
/plugin install dagny@dagny-plugin
```

Or from a shell:

```sh
claude plugin marketplace add nuttycom/dagny-plugin
claude plugin install dagny@dagny-plugin
```

The plugin installs at user scope by default, so it is available in every
project. To install it for one project only, pass `--scope project`.

Restart Claude Code. Then authenticate the MCP server:

1. Run `/mcp`.
2. Select the `dagny` server. It shows "requires authentication".
3. Select **Authenticate**, and sign in to Dagny in the browser window that
   opens.

To check the connection, ask Claude to run `whoami`. It answers with your
Dagny username.

## Updating

An update has two steps: refresh the marketplace, then update the plugin.

```sh
claude plugin marketplace update dagny-plugin
claude plugin update dagny@dagny-plugin
```

In a session, `/plugin` opens the plugin manager, where you can do the
same. Restart Claude Code to load the new version.

To see the installed version:

```sh
claude plugin list
```

## Uninstalling

```sh
claude plugin uninstall dagny@dagny-plugin
claude plugin marketplace remove dagny-plugin
```

## Developing the plugin

To try local changes, load your checkout for one session. Disable the
installed copy first, so that only one copy of the plugin loads:

```sh
claude plugin disable dagny@dagny-plugin
claude --plugin-dir /path/to/dagny-plugin
```

Run `claude plugin enable dagny@dagny-plugin` when you are done.

Check the manifests before you commit:

```sh
claude plugin validate .
```
