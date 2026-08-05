#!/usr/bin/env bash
# PreToolUse hook for Bash(gh pr create:*)
# Reads the tool use input from stdin and checks that the PR body
# contains a "Fixes #N" closing keyword.

set -euo pipefail

# Hand the decision to the operator, saying why the check could not be carried
# out. Deferring instead would let the command through unremarked wherever it is
# already permitted, which is the silent pass this hook exists to avoid: a check
# that stops checking without saying so reads as a check that passed.
cannot_check() {
  jq -n --arg why "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: ("Could not verify that the PR body has a closing keyword (Fixes #N, Closes #N, or Resolves #N): " + $why + ". Check that the issue will be closed on merge before allowing this.")
    }
  }'
  exit 0
}

# GitHub links an issue from a PR body via any of nine keyword forms, and the
# issue may be named by "#N", "owner/repo#N", or its full URL.
# https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue
#
# The leading alternation stands in for a word boundary, so that "prefixes #1"
# does not read as "fixes #1".
has_keyword() {
  local keyword='(close[sd]?|fix(es|ed)?|resolve[sd]?)'
  local repo='[-_a-z0-9.]+/[-_a-z0-9.]+'
  local issue="((${repo})?#[0-9]+|https?://github\.com/${repo}/issues/[0-9]+)"

  echo "$1" | grep -qiE "(^|[^[:alnum:]])${keyword}[[:space:]]+${issue}"
}

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
tool_input=$(echo "$input" | jq -r '.tool_input.command // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

# Only check gh pr create commands
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

# gh takes the last body option given, whichever kind it is, so look for the
# last occurrence of any of them: the leading .* is greedy. Which flag matched
# then says whether its argument is a file to read or the body itself.
sq=\'
value="(\"([^\"]*)\"|${sq}([^${sq}]*)${sq}|([^[:space:]]+))"
body_re=".*(--body-file[=[:space:]]|[[:space:]]-F[[:space:]]|--body[=[:space:]]|[[:space:]]-b[[:space:]])[[:space:]]*${value}"

case "$tool_input" in
  *"gh pr create"*--body*|*"gh pr create"*" -b "*|*"gh pr create"*" -F "*)
    [[ "$tool_input" =~ $body_re ]] ||
      cannot_check "the body argument could not be read from the command"
    flag=${BASH_REMATCH[1]}
    arg="${BASH_REMATCH[3]}${BASH_REMATCH[4]}${BASH_REMATCH[5]}"

    case "$flag" in
      *--body-file*|*-F*)
        if [[ "$arg" == "-" ]]; then
          cannot_check "the body is read from stdin"
        fi

        case "$arg" in
          /*) path=$arg ;;
          *) path="${cwd:-.}/$arg" ;;
        esac

        if [[ ! -r "$path" ]]; then
          cannot_check "the body file $arg could not be read"
        fi

        # The file is the body exactly, so its verdict is final either way.
        if has_keyword "$(cat "$path")"; then
          exit 0
        fi
        ;;
      *)
        if has_keyword "$arg"; then
          exit 0
        fi

        # The extracted body is only as good as the quoting the regex could
        # follow: an apostrophe in the body ends the capture early, and what
        # survives may not be the whole body. Before refusing, look at the
        # command as a whole -- if the keyword is in there somewhere, this is
        # not a body we can honestly say lacks one.
        if has_keyword "$tool_input"; then
          cannot_check "the body could not be separated from the rest of the command, and a closing keyword appears somewhere in it"
        fi
        ;;
    esac
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "PR body is missing a closing keyword (Fixes #N, Closes #N, or Resolves #N). Add one to auto-close the linked GitHub issue on merge."
      }
    }'
    ;;
  # With no body flag at all, the body comes from --fill, a pull request
  # template, or an editor, none of which are visible from here.
  *"gh pr create"*)
    cannot_check "the command has no --body or --body-file; the body comes from --fill, a pull request template, or an editor"
    ;;
  *)
    exit 0
    ;;
esac
