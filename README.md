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
| Hook (before `gh pr create`) | Asks you before it lets Claude create a PR whose body has no `Fixes #N`, `Closes #N`, or `Resolves #N`, or whose body it cannot read. It never blocks a command, and it says nothing when the command gives no body. |
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
4. Dagny then shows a page with a **Continue** link. Select it.

If Claude Code runs on a different machine from your browser, for example
over SSH, in a container, or in a cloud session, the page after
**Continue** may fail to load. Then copy that page's URL from the
browser's address bar, and paste it into the Claude Code session.

To check the connection, ask Claude to run `whoami`. It answers with your
Dagny username.

### Connecting without a browser

An agent that runs with no person at a browser, such as a scheduled job
or a CI run, cannot sign in this way. It can use a personal access token
instead. A personal access token is a secret that you create in Dagny,
and a request that carries it acts as you.

1. In Dagny, open your user settings. Under **Access Tokens**, select
   **New token**. Give the token a name, and choose when it expires: in 30
   days, in 90 days, in 1 year, or never. If your account has a password,
   enter it too.
2. Copy the token. Dagny shows it once, and cannot show it again.
3. Register Dagny's MCP server in Claude Code with the token as a header:

   ```sh
   claude mcp add --scope user --transport http dagny https://dagny.co/mcp --header "Authorization: Bearer <token>"
   ```

   The dialog that shows the token also shows this command, with the token
   filled in. Claude Code before version 2.1.157 ignores the header for a
   server that offers a browser sign-in, as Dagny does, so use version
   2.1.157 or later.

With the plugin installed, Claude Code then has two entries for the same
server: the plugin's own, and this one. It connects once, with the token,
and skips the plugin's entry, because both name the same URL. An entry
named `dagny` that a project has of its own, at local or project scope,
takes precedence over this one in that project.

While Claude Code uses this entry, it does not fall back to the browser
sign-in: when the token stops working, the connection fails. To go back
to the browser sign-in, remove this entry with
`claude mcp remove --scope user dagny`.

A token acts as you in every project that you belong to. It cannot change
your password, delete your account, manage access tokens, link a GitHub
account, or use the site administration. It stops working in these cases:

- It expires.
- You revoke it under **Access Tokens**.
- Your password is changed or reset. That revokes all of your tokens.
- Your account is deleted.

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
