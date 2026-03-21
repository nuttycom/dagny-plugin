#!/usr/bin/env bash
# PostToolUse hook for Bash(git commit:*)
# After a commit, checks if the message references a GitHub issue (Fixes #N)
# and reminds Claude to update the Dagny task status.

set -euo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
tool_input=$(echo "$input" | jq -r '.tool_input.command // empty')
tool_output=$(echo "$input" | jq -r '.tool_output.stdout // empty')

if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

case "$tool_input" in
  *"git commit"*)
    # Check if the commit succeeded (output typically contains the branch and commit summary)
    if [[ -z "$tool_output" ]]; then
      exit 0
    fi

    # Look for Fixes/Closes/Resolves #N in the commit command
    if echo "$tool_input" | grep -qiE '(fixes|closes|resolves)\s+#[0-9]+'; then
      echo '{"message": "This commit references a GitHub issue. Consider transitioning the corresponding Dagny task to \"In Review\" if a PR is being created, or \"In Progress\" if work continues."}'
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
