#!/usr/bin/env bash
# Tests for hooks/scripts/check-pr-fixes-keyword.sh
#
# The hook has three outcomes, and which one it picks is the whole point:
#
#   block  the body was read and has no closing keyword
#   warn   the body could not be read, so nothing was verified
#   allow  the body was read and has a closing keyword (or this is not ours)
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
       | jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null 2>&1; then
    echo warn
  else
    echo "unrecognized:$out"
  fi
}

# Assert a jq predicate against the hook's raw output.
check_output() {
  local desc=$1 cmd=$2 filter=$3 out
  out=$(jq -n --arg c "$cmd" --arg w "$WORK" \
          '{tool_name: "Bash", tool_input: {command: $c}, cwd: $w}' \
        | bash "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | jq -e "$filter" >/dev/null 2>&1; then
    printf '  ok    %-52s %s\n' "$desc" "matches"
    passed=$((passed + 1))
  else
    printf '  FAIL  %-52s %s\n' "$desc" "got: ${out:-<empty>}"
    failed=$((failed + 1))
  fi
}

check() {
  local desc=$1 cmd=$2 want=$3
  local out got
  out=$(jq -n --arg c "$cmd" --arg w "$WORK" \
          '{tool_name: "Bash", tool_input: {command: $c}, cwd: $w}' \
        | bash "$HOOK" 2>/dev/null)
  got=$(classify "$out")
  if [[ "$got" == "$want" ]]; then
    printf '  ok    %-52s %s\n' "$desc" "$got"
    passed=$((passed + 1))
  else
    printf '  FAIL  %-52s got=%s want=%s\n' "$desc" "$got" "$want"
    failed=$((failed + 1))
  fi
}

echo "the body is a file, and it has the keyword -> allow"
check "--body-file"                       "gh pr create --body-file $WORK/good.md"                      allow
check "--body-file="                      "gh pr create --body-file=$WORK/good.md"                      allow
check "-F"                                "gh pr create -F $WORK/good.md"                               allow
check "quoted path with spaces"           "gh pr create --body-file \"$WORK/dir with space/good.md\""   allow
check "path relative to cwd"              "gh pr create --body-file good.md"                            allow
check "repeated flag takes the last"      "gh pr create -F $WORK/bad.md -F $WORK/good.md"               allow
check "--body then --body-file, last wins" "gh pr create --body 'no keyword' --body-file $WORK/good.md" allow

echo "the body is a file, and it lacks the keyword -> block"
check "--body-file"                       "gh pr create --body-file $WORK/bad.md"                       block
check "-F"                                "gh pr create -F $WORK/bad.md"                                block
check "keyword in the command, not the file" "gh pr create -F $WORK/bad.md --title 'Closes #1'"         block

echo "the body is inline -> read from the --body argument"
check "--body with the keyword"           "gh pr create --body 'Closes #201.'"                          allow
check "--body= with the keyword"          "gh pr create --body='Fixes #3'"                              allow
check "--body without the keyword"        "gh pr create --body 'no keyword here'"                       block
check "keyword is case-insensitive"       "gh pr create --body 'fixes #12'"                             allow
check "issue number missing"              "gh pr create --body 'Closes the thing'"                      block
check "multi-line body"                   "gh pr create --body 'first line

Closes #1'"                                                                                             allow
check "--body-file then --body, last wins" "gh pr create --body-file $WORK/good.md --body 'no keyword'"  block

echo "the inline body cannot be separated exactly -> warn rather than refuse"
check "an apostrophe truncates the capture" "gh pr create --body 'it'\\''s here, Closes #1'"             warn
check "keyword only in --title"            "gh pr create --body 'no keyword' --title 'Closes #1'"        warn

echo "every closing keyword GitHub accepts -> allow"
for kw in close closes closed fix fixes fixed resolve resolves resolved; do
  check "$kw #1"                          "gh pr create --body '$kw #1'"                                allow
done
check "cross-repo reference"              "gh pr create --body 'Closes owner/repo#1'"                   allow
check "full issue URL"                    "gh pr create --body 'Fixed https://github.com/o/r/issues/1'" allow
check "keyword mid-sentence"              "gh pr create --body 'This resolves #1 at last.'"             allow

echo "near misses that are not closing keywords -> block"
check "a longer word ending in a keyword" "gh pr create --body 'This prefixes #1 nicely'"               block
check "a different verb"                  "gh pr create --body 'Addresses #1'"                          block
check "no space before the number"        "gh pr create --body 'Closes#1'"                              block

echo "the body cannot be read -> warn, never a silent pass"
check "--fill"                            "gh pr create --fill"                                         warn
check "no body argument at all"           "gh pr create --title t"                                      warn
check "--body-file - (stdin)"             "gh pr create --body-file -"                                  warn
check "unreadable body file"              "gh pr create --body-file $WORK/absent.md"                    warn

echo "the output uses the documented PreToolUse schema"
check_output "a refusal is a permissionDecision of deny" \
  "gh pr create --body 'no keyword here'" \
  '.hookSpecificOutput.hookEventName == "PreToolUse"
     and .hookSpecificOutput.permissionDecision == "deny"
     and (.hookSpecificOutput.permissionDecisionReason | test("closing keyword"))'
check_output "an unverifiable body asks rather than deciding" \
  "gh pr create --fill" \
  '.hookSpecificOutput.hookEventName == "PreToolUse"
     and .hookSpecificOutput.permissionDecision == "ask"
     and (.hookSpecificOutput.permissionDecisionReason | test("Could not verify"))'

echo "not this hook's business -> allow"
check "a git commit mentioning an issue"  "git commit -m 'Closes #201'"                                 allow
check "gh pr view"                        "gh pr view 728"                                              allow

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
