#!/usr/bin/env bash
# PreToolUse hook for Bash commands that create a pull request with
# "gh pr create".
#
# Reads the tool use input from stdin, and looks in the body of the pull
# request for a closing keyword such as "Fixes #N". Merging a pull request
# with such a keyword closes the issue, and Dagny then completes the task
# that the issue belongs to.
#
# The hook is a reminder. It never refuses a command. Its outcomes:
#
# - The body has a closing keyword: the hook says nothing.
# - The body has no closing keyword: the hook asks the operator. A pull
#   request that closes no issue can be what is wanted.
# - The command gives a body that the hook cannot read: the hook asks the
#   operator, and says why.
# - The command has no body option: the hook says nothing. See the last
#   case of the statement at the end of this file.

set -euo pipefail

# Ask the operator to decide, and end the hook.
#
# Inputs: the reason to show the operator.
ask() {
  jq -n --arg why "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $why
    }
  }'
  exit 0
}

# Ask the operator because the command gives a body that could not be read.
# Saying nothing here would let the command through wherever it is already
# permitted, and a check that stops checking without saying so reads as a
# check that passed.
#
# Inputs: why the body could not be read.
cannot_check() {
  ask "Could not verify that the PR body has a closing keyword (Fixes #N, Closes #N, or Resolves #N): $1. Check that the issue will be closed on merge before allowing this."
}

# Ask the operator because the body was read, and it has no closing keyword.
ask_missing() {
  ask "The PR body has no closing keyword (Fixes #N, Closes #N, or Resolves #N), so merging this pull request will close no issue. Allow this if that is intended. Otherwise add a keyword to the body."
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

  # The text comes in a here-string, not through a pipe: grep stops at the
  # first match, and under pipefail a writer that it cut off would turn the
  # match into a failure.
  grep -qiE "(^|[^[:alnum:]])${keyword}[[:space:]]+${issue}" <<< "$1"
}

# Print a path for a reason shown to the operator, cut to a length that a
# person can read.
shown_path() {
  local path=$1
  if (( ${#path} > 200 )); then
    path="${path:0:200}..."
  fi
  printf '%s' "$path"
}

# Print the text of the heredoc that feeds the gh pr create line of a
# command: the lines after that line, up to the delimiter. "<<-" strips
# leading tabs, as the shell does. Fails when the gh line opens no heredoc.
heredoc_body() {
  local opener="<<(-?)[[:space:]]*[\"']?([A-Za-z_][A-Za-z0-9_]*)[\"']?"
  local line strip="" delim="" in_body=false
  while IFS= read -r line; do
    if $in_body; then
      [[ -n "$strip" ]] && line="${line#"${line%%[!$'\t']*}"}"
      [[ "$line" == "$delim" ]] && return 0
      printf '%s\n' "$line"
    elif [[ "$line" == *"gh pr create"* && "$line" =~ $opener ]]; then
      strip=${BASH_REMATCH[1]}
      delim=${BASH_REMATCH[2]}
      in_body=true
    fi
  done <<< "$1"
  $in_body
}

# Input that cannot be decoded gets no answer: the hook has nothing to say
# about a command that it cannot read, and must not fail on it.
input=$(cat)
tool_name=$(jq -r '.tool_name? // empty' <<< "$input" 2>/dev/null) || exit 0
tool_input=$(jq -r '.tool_input.command? // empty' <<< "$input" 2>/dev/null) || exit 0
cwd=$(jq -r '.cwd? // empty' <<< "$input" 2>/dev/null) || exit 0

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
    written=${BASH_REMATCH[2]}
    arg="${BASH_REMATCH[3]}${BASH_REMATCH[4]}${BASH_REMATCH[5]}"

    case "$flag" in
      *--body-file*|*-F*)
        if [[ "$arg" == "-" ]]; then
          # A heredoc on the gh line is gh's stdin, so its text is the body
          # exactly and its verdict is final either way. Any other stdin
          # (a pipe, a redirect) is not visible from here.
          if body=$(heredoc_body "$tool_input"); then
            has_keyword "$body" && exit 0
            ask_missing
          fi
          cannot_check "the body is read from stdin"
        fi

        # The shell can expand a "$", a backtick, and a leading ~ before gh
        # sees the path, and this script does not: the path as written here
        # may name no file. In single quotes they are part of the name. In
        # double quotes a ~ is too. This does not follow the shell exactly: a
        # "$" that the shell would leave alone is asked about as well.
        needs_expanding=false
        case "$written" in
          "$sq"*) ;;
          '"'*)
            case "$arg" in *'$'*|*'`'*) needs_expanding=true ;; esac
            ;;
          *)
            case "$arg" in *'$'*|*'`'*|'~'*) needs_expanding=true ;; esac
            ;;
        esac
        if $needs_expanding; then
          cannot_check "the body file path $(shown_path "$arg") holds a \$, a backtick, or a leading ~, which the shell may expand, and this check does not expand them. The body may well have the keyword. Write the path out in full to have it checked"
        fi

        case "$arg" in
          /*) path=$arg ;;
          *) path="${cwd:-.}/$arg" ;;
        esac

        # Only a regular file is read. A directory has no text, and reading
        # a named pipe would wait for a writer.
        if [[ ! -f "$path" || ! -r "$path" ]] || ! body=$(cat "$path" 2>/dev/null); then
          cannot_check "the body file $(shown_path "$arg") could not be read"
        fi

        # The file is the body exactly, so its verdict is final either way.
        if has_keyword "$body"; then
          exit 0
        fi
        ;;
      *)
        if has_keyword "$arg"; then
          exit 0
        fi

        # The extracted body is only as good as the quoting the regex could
        # follow: an apostrophe in the body ends the capture early, and what
        # survives may not be the whole body. Before saying that the body
        # lacks a keyword, look at the command as a whole -- if the keyword
        # is in there somewhere, this is not a body we can honestly say lacks
        # one.
        if has_keyword "$tool_input"; then
          cannot_check "the body could not be separated from the rest of the command, and a closing keyword appears somewhere in it"
        fi
        ;;
    esac
    ask_missing
    ;;
  # Every other command gets no answer. That includes a command that
  # contains the words "gh pr create" and has no body option. Most often such
  # a command only mentions the words: a search for them, a commit message, a
  # file written from a heredoc. When it does create a pull request, the body
  # comes from --fill, a pull request template, or an editor, and none of
  # these is visible from here: a question would give the operator nothing
  # to check.
  *)
    exit 0
    ;;
esac
