#!/usr/bin/env bash
# PreToolUse hook for Bash(gh pr create:*)
# Reads the tool use input from stdin and checks that the PR body
# contains a "Fixes #N" closing keyword.

set -euo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
tool_input=$(echo "$input" | jq -r '.tool_input.command // empty')

# Only check gh pr create commands
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

case "$tool_input" in
  *"gh pr create"*)
    # Extract the --body argument content
    body=""
    if echo "$tool_input" | grep -qiE '(fixes|closes|resolves)\s+#[0-9]+'; then
      exit 0
    else
      jq -n '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: "PR body is missing a closing keyword (Fixes #N, Closes #N, or Resolves #N). Add one to auto-close the linked GitHub issue on merge."
        }
      }'
      exit 0
    fi
    ;;
  *)
    exit 0
    ;;
esac
