#!/usr/bin/env bash
# Tests for hooks/scripts/check-pr-fixes-keyword.sh
#
# The hook is a reminder: it never refuses a command. It has three outcomes,
# and which one it picks is the whole point:
#
#   allow       the hook says nothing: the body was read and has a closing
#               keyword, or the command has no body option, or it is not a
#               pull request creation
#   missing     the hook asks the operator: the body was read and has no
#               closing keyword
#   unverified  the hook asks the operator: the command gives a body that
#               could not be read, so nothing was verified
#
# A refusal ("block") is never the right outcome, so no case expects it.
# Neither is an exit status other than 0: every case fails on one.
#
# Run: tests/check-pr-fixes-keyword.test.sh

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="$HERE/../hooks/scripts/check-pr-fixes-keyword.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/dir with space"
printf 'Body text.\n\nCloses #201.\n' > "$WORK/good.md"
printf 'Body text with no keyword.\n' > "$WORK/bad.md"
printf 'Body.\n\nFixes #7\n'          > "$WORK/dir with space/good.md"
printf 'Body.\n\nFixes #8\n'          > "$WORK/body\$cost.md"
# A body that starts with the keyword and is far longer than a pipe holds.
{ printf 'Fixes #1\n'; yes 'another line of the body' | head -n 100000; } > "$WORK/large.md"
mkdir "$WORK/a-directory"

passed=0
failed=0

# The schema documented for PreToolUse hooks, and only that: output in any other
# shape is a failure in its own right, not an outcome to be interpreted.
classify() {
  local out=$1
  if [[ -z "$out" ]]; then
    echo allow
  elif printf '%s' "$out" \
       | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo block
  elif printf '%s' "$out" \
       | jq -e '.hookSpecificOutput.permissionDecision == "ask"
                and (.hookSpecificOutput.permissionDecisionReason | test("^Could not verify"))' >/dev/null 2>&1; then
    echo unverified
  elif printf '%s' "$out" \
       | jq -e '.hookSpecificOutput.permissionDecision == "ask"
                and (.hookSpecificOutput.permissionDecisionReason | test("has no closing keyword"))' >/dev/null 2>&1; then
    echo missing
  else
    echo "unrecognized:$out"
  fi
}

# Print the tool event for a Bash command. The command goes to jq on stdin,
# so that a very long one is not an argument.
event() {
  printf '%s' "$1" | jq -Rs --arg w "$WORK" \
    '{tool_name: "Bash", tool_input: {command: .}, cwd: $w}'
}

# Assert a jq predicate against the hook's raw output.
check_output() {
  local desc=$1 cmd=$2 filter=$3 out
  out=$(event "$cmd" | bash "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | jq -e "$filter" >/dev/null 2>&1; then
    printf '  ok    %-52s %s\n' "$desc" "matches"
    passed=$((passed + 1))
  else
    printf '  FAIL  %-52s %s\n' "$desc" "got: ${out:-<empty>}"
    failed=$((failed + 1))
  fi
}

# Report one case: the outcome that the hook gave, against the one wanted.
report() {
  local desc=$1 got=$2 want=$3
  if [[ "$got" == "$want" ]]; then
    printf '  ok    %-52s %s\n' "$desc" "$got"
    passed=$((passed + 1))
  else
    printf '  FAIL  %-52s got=%s want=%s\n' "$desc" "$got" "$want"
    failed=$((failed + 1))
  fi
}

# Give the hook raw text as its input, and report its outcome. An exit
# status other than 0 is an outcome of its own, "error:<status>".
check_raw() {
  local desc=$1 raw=$2 want=$3
  local out status
  out=$(printf '%s' "$raw" | bash "$HOOK" 2>/dev/null)
  status=$?
  if (( status != 0 )); then
    report "$desc" "error:$status" "$want"
  else
    report "$desc" "$(classify "$out")" "$want"
  fi
}

# Give the hook the tool event of a Bash command, and report its outcome.
check() {
  check_raw "$1" "$(event "$2")" "$3"
}

echo "the body is a file, and it has the keyword -> allow"
check "--body-file"                       "gh pr create --body-file $WORK/good.md"                      allow
check "--body-file="                      "gh pr create --body-file=$WORK/good.md"                      allow
check "-F"                                "gh pr create -F $WORK/good.md"                               allow
check "quoted path with spaces"           "gh pr create --body-file \"$WORK/dir with space/good.md\""   allow
check "path relative to cwd"              "gh pr create --body-file good.md"                            allow
check "repeated flag takes the last"      "gh pr create -F $WORK/bad.md -F $WORK/good.md"               allow
check "--body then --body-file, last wins" "gh pr create --body 'no keyword' --body-file $WORK/good.md" allow

echo "the body is a file, and it lacks the keyword -> missing"
check "--body-file"                       "gh pr create --body-file $WORK/bad.md"                       missing
check "-F"                                "gh pr create -F $WORK/bad.md"                                missing
check "keyword in the command, not the file" "gh pr create -F $WORK/bad.md --title 'Closes #1'"         missing

echo "the body is inline -> read from the --body argument"
check "--body with the keyword"           "gh pr create --body 'Closes #201.'"                          allow
check "--body= with the keyword"          "gh pr create --body='Fixes #3'"                              allow
check "--body without the keyword"        "gh pr create --body 'no keyword here'"                       missing
check "keyword is case-insensitive"       "gh pr create --body 'fixes #12'"                             allow
check "issue number missing"              "gh pr create --body 'Closes the thing'"                      missing
check "multi-line body"                   "gh pr create --body 'first line

Closes #1'"                                                                                             allow
check "--body-file then --body, last wins" "gh pr create --body-file $WORK/good.md --body 'no keyword'"  missing

echo "the inline body cannot be separated exactly -> unverified, not missing"
check "an apostrophe truncates the capture" "gh pr create --body 'it'\\''s here, Closes #1'"             unverified
check "keyword only in --title"            "gh pr create --body 'no keyword' --title 'Closes #1'"        unverified

echo "every closing keyword GitHub accepts -> allow"
for kw in close closes closed fix fixes fixed resolve resolves resolved; do
  check "$kw #1"                          "gh pr create --body '$kw #1'"                                allow
done
check "cross-repo reference"              "gh pr create --body 'Closes owner/repo#1'"                   allow
check "full issue URL"                    "gh pr create --body 'Fixed https://github.com/o/r/issues/1'" allow
check "keyword mid-sentence"              "gh pr create --body 'This resolves #1 at last.'"             allow

echo "near misses that are not closing keywords -> missing"
check "a longer word ending in a keyword" "gh pr create --body 'This prefixes #1 nicely'"               missing
check "a different verb"                  "gh pr create --body 'Addresses #1'"                          missing
check "no space before the number"        "gh pr create --body 'Closes#1'"                              missing

echo "the body is a heredoc on stdin -> its text decides"
check "quoted delimiter, keyword"         $'gh pr create --title t --body-file - <<\'EOF\'\nSummary.\n\nFixes #12\nEOF'      allow
check "unquoted delimiter, keyword"       $'gh pr create --body-file - <<EOF\nCloses #3\nEOF'                    allow
check "-F -, other delimiter"             $'gh pr create -F - <<"BODY"\nResolves #9\nBODY'                       allow
check "<<- with tab-indented end"         $'gh pr create --body-file - <<-EOF\n\tFixes #4\n\tEOF'               allow
check "heredoc without a keyword"         $'gh pr create --body-file - <<\'EOF\'\nJust a summary.\nEOF'         missing
check "keyword only outside the heredoc"  $'gh pr create --title \'Fixes #5\' --body-file - <<\'EOF\'\nNo keyword.\nEOF' missing
check "keyword after the heredoc ends"    $'gh pr create --body-file - <<\'EOF\'\nNo keyword.\nEOF\necho Fixes #6'  missing

echo "the command gives a body that cannot be read -> unverified, never a silent pass"
check "--body-file - (stdin, no heredoc)"  "gh pr create --body-file -"                                  unverified
check "stdin from a pipe"                 "cat notes.md | gh pr create --body-file -"                   unverified
check "a heredoc that feeds another line"  $'cat > b.md <<\'EOF\'\nFixes #8\nEOF\ngh pr create --body-file - < b.md'  unverified
check "unreadable body file"              "gh pr create --body-file $WORK/absent.md"                    unverified
check "a directory as the body file"      "gh pr create --body-file $WORK/a-directory"                  unverified
if command -v timeout >/dev/null 2>&1 && mkfifo "$WORK/a-pipe" 2>/dev/null; then
  # Reading a named pipe would wait for a writer. The hook must answer at once.
  out=$(event "gh pr create --body-file $WORK/a-pipe" | timeout 10 bash "$HOOK" 2>/dev/null)
  status=$?
  if (( status != 0 )); then
    report "a named pipe as the body file" "error:$status" unverified
  else
    report "a named pipe as the body file" "$(classify "$out")" unverified
  fi
else
  printf '  skip  %-52s %s\n' "a named pipe as the body file" "needs timeout and mkfifo"
fi

echo "a long body that starts with the keyword -> allow"
check "a body file of 100,000 lines"      "gh pr create --body-file $WORK/large.md"                     allow

echo "the body file's path needs the shell to expand it -> unverified, and say so"
check "a variable in the path"            'gh pr create --body-file $DIR/good.md'                       unverified
check "a quoted variable in the path"     'gh pr create --body-file "$DIR/good.md"'                     unverified
check "a command substitution in the path" 'gh pr create --body-file $(pwd)/good.md'                    unverified
check "a path under ~"                    'gh pr create --body-file ~/good.md'                          unverified
check "single quotes keep the dollar sign" "gh pr create --body-file 'body\$cost.md'"                   allow
check "double quotes expand the dollar sign" 'gh pr create --body-file "body$cost.md"'                  unverified
check "an escaped dollar sign in double quotes" 'gh pr create --body-file "body\$cost.md"'              unverified
check_output "the reason names the path and says that the shell may expand it" \
  'gh pr create --body-file $DIR/good.md' \
  '.hookSpecificOutput.permissionDecision == "ask"
     and (.hookSpecificOutput.permissionDecisionReason | test("\\$DIR/good.md"))
     and (.hookSpecificOutput.permissionDecisionReason | test("the shell may expand"))
     and (.hookSpecificOutput.permissionDecisionReason | test("does not expand"))'
long_path="\$DIR/$(printf 'x%.0s' {1..1000})$(yes 'a-long-path-segment/' | head -n 8000 | tr -d '\n')body.md"
check "a path of 160,000 characters"      "gh pr create --body-file $long_path"                         unverified
check_output "the reason shows a long path cut short" \
  "gh pr create --body-file $long_path" \
  '.hookSpecificOutput.permissionDecisionReason | length < 1000'

echo "the command has no body option -> allow: most often it only mentions the words"
check "a search for the words"            'grep -rn "gh pr create" docs/'                               allow
check "a search with rg in a pipeline"    "rg -n 'gh pr create' . | head -20"                           allow
check "a commit message that names it"    'git commit -m "Document when to run gh pr create"'           allow
check "a file written from a heredoc"     $'cat > notes.md <<\'EOF\'\nRun gh pr create when the branch is ready.\nEOF' allow
check "a creation with --fill"            "gh pr create --fill"                                         allow
check "a creation with only a title"      "gh pr create --title t"                                      allow

echo "a mention that quotes a body option is looked at -> a question at most"
check "a heredoc that quotes a body file" $'cat > notes.md <<\'EOF\'\ngh pr create --body-file body.md\nEOF' unverified
check "an echo that quotes an inline body" "echo 'gh pr create --body \"text\"'"                         missing

echo "the output uses the documented PreToolUse schema, and never refuses"
check_output "a body without a keyword asks, and says what merging will do" \
  "gh pr create --body 'no keyword here'" \
  '.hookSpecificOutput.hookEventName == "PreToolUse"
     and .hookSpecificOutput.permissionDecision == "ask"
     and (.hookSpecificOutput.permissionDecisionReason | test("has no closing keyword"))
     and (.hookSpecificOutput.permissionDecisionReason | test("Allow this if that is intended"))'
check_output "an unverifiable body asks, and says why" \
  "gh pr create --body-file $WORK/absent.md" \
  '.hookSpecificOutput.hookEventName == "PreToolUse"
     and .hookSpecificOutput.permissionDecision == "ask"
     and (.hookSpecificOutput.permissionDecisionReason | test("Could not verify"))
     and (.hookSpecificOutput.permissionDecisionReason | test("could not be read"))'

echo "input that the hook cannot decode -> allow, with no error"
check_raw "input that is not JSON"          'this is not JSON'                                          allow
check_raw "empty input"                     ''                                                          allow
check_raw "a tool input that is a string"   '{"tool_name": "Bash", "tool_input": "gh pr create --body x"}' allow
check_raw "an event without a command"      '{"tool_name": "Bash", "tool_input": {}}'                   allow
check     "an empty command"                ''                                                          allow

echo "not this hook's business -> allow"
check "a git commit mentioning an issue"  "git commit -m 'Closes #201'"                                 allow
check "gh pr view"                        "gh pr view 728"                                              allow

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
