#!/usr/bin/env bash
# Tests for hooks/scripts/check-pr-fixes-keyword.sh
#
# The hook has three outcomes, and which one it picks is the whole point:
#
#   block  the body was read and has no closing keyword
#   warn   the body could not be read, so nothing was verified
#   allow  the body was read and has a closing keyword (or this is not ours:
#          the command is a plain command of a short list of tools, and it
#          only mentions "gh pr create")
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
printf 'Body.\n\nFixes #14\n'         > "$WORK/body\$cost.md"

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

# Runs the hook on a command, as Claude Code would.
#
# Preconditions: none.
#
# Inputs: $1 is the text of the Bash command.
#
# Output: prints the hook's standard output. The exit status is the hook's.
#
# Side effects: none outside the hook itself.
run_hook() {
  jq -n --arg c "$1" --arg w "$WORK" \
     '{tool_name: "Bash", tool_input: {command: $c}, cwd: $w}' \
    | bash "$HOOK" 2>/dev/null
}

# Asserts that the hook's output is exactly one JSON object that satisfies a
# jq predicate.
#
# Preconditions: none.
#
# Inputs: $1 describes the case, $2 is the command, $3 is the jq predicate.
#
# Output: prints one result line.
#
# Side effects: counts the case as passed or failed. A non-zero exit status
# of the hook fails the case.
check_output() {
  local desc=$1 cmd=$2 filter=$3 out status
  out=$(run_hook "$cmd")
  status=$?
  if (( status != 0 )); then
    printf '  FAIL  %-52s %s\n' "$desc" "the hook exited with status $status"
    failed=$((failed + 1))
  elif printf '%s' "$out" | jq -e -s 'length == 1' >/dev/null 2>&1 &&
       printf '%s' "$out" | jq -e "$filter" >/dev/null 2>&1; then
    printf '  ok    %-52s %s\n' "$desc" "matches"
    passed=$((passed + 1))
  else
    printf '  FAIL  %-52s %s\n' "$desc" "got: ${out:-<empty>}"
    failed=$((failed + 1))
  fi
}

# Asserts the hook's outcome for a command.
#
# Preconditions: none.
#
# Inputs: $1 describes the case, $2 is the command, $3 is the outcome wanted:
# allow, warn or block.
#
# Output: prints one result line.
#
# Side effects: counts the case as passed or failed. A non-zero exit status
# of the hook fails the case.
check() {
  local desc=$1 cmd=$2 want=$3
  local out got status
  out=$(run_hook "$cmd")
  status=$?
  if (( status != 0 )); then
    got="exit-status-$status"
  else
    got=$(classify "$out")
  fi
  if [[ "$got" == "$want" ]]; then
    printf '  ok    %-52s %s\n' "$desc" "$got"
    passed=$((passed + 1))
  else
    printf '  FAIL  %-52s got=%s want=%s\n' "$desc" "$got" "$want"
    failed=$((failed + 1))
  fi
}

# Asserts that a command really runs "gh pr create", so that a case which
# expects the hook to check it is about a command that creates a pull request.
#
# Preconditions: none.
#
# Inputs: $1 describes the case, $2 is the command. $3, when given, is the
# lowest major version of bash known to run the command as the case says;
# with an older bash the case is skipped. $4, when given, is the highest such
# major version; with a newer bash the case is skipped.
#
# Output: prints one result line.
#
# Side effects: runs the command with "bash -c" in a new empty directory
# under $WORK, with standard input from /dev/null and a stub gh first on
# PATH. The stub records its arguments in a file and does nothing else.
# Counts the case as passed or failed.
check_runs() {
  local desc=$1 cmd=$2 min_major=${3:-0} max_major=${4:-99} dir major
  major=$(bash -c 'echo "${BASH_VERSINFO[0]}"')
  if (( major < min_major )); then
    printf '  skip  %-52s %s\n' "$desc" "needs bash $min_major"
    return 0
  fi
  if (( major > max_major )); then
    printf '  skip  %-52s %s\n' "$desc" "runs only up to bash $max_major"
    return 0
  fi
  dir=$(mktemp -d "$WORK/run.XXXXXX")
  mkdir "$dir/bin" "$dir/cwd"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/calls"\n' "$dir" > "$dir/bin/gh"
  chmod +x "$dir/bin/gh"
  ( cd "$dir/cwd" && PATH="$dir/bin:$PATH" bash --noprofile --norc -c "$cmd" ) \
    </dev/null >/dev/null 2>&1
  if [[ -f "$dir/calls" ]] && grep -q '^pr create' "$dir/calls"; then
    printf '  ok    %-52s %s\n' "$desc" "runs it"
    passed=$((passed + 1))
  else
    printf '  FAIL  %-52s %s\n' "$desc" "the stub gh was not called with pr create"
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

echo "the body is a heredoc on stdin -> its text decides"
check "quoted delimiter, keyword"         $'gh pr create --title t --body-file - <<\'EOF\'\nSummary.\n\nFixes #12\nEOF'      allow
check "unquoted delimiter, keyword"       $'gh pr create --body-file - <<EOF\nCloses #3\nEOF'                    allow
check "-F -, other delimiter"             $'gh pr create -F - <<"BODY"\nResolves #9\nBODY'                       allow
check "<<- with tab-indented end"         $'gh pr create --body-file - <<-EOF\n\tFixes #4\n\tEOF'               allow
check "heredoc without a keyword"         $'gh pr create --body-file - <<\'EOF\'\nJust a summary.\nEOF'         block
check "keyword only outside the heredoc"  $'gh pr create --title \'Fixes #5\' --body-file - <<\'EOF\'\nNo keyword.\nEOF' block
check "keyword after the heredoc ends"    $'gh pr create --body-file - <<\'EOF\'\nNo keyword.\nEOF\necho Fixes #6'  block

echo "the body cannot be read -> warn, never a silent pass"
check "--fill"                            "gh pr create --fill"                                         warn
check "no body argument at all"           "gh pr create --title t"                                      warn
check "--body-file - (stdin, no heredoc)"  "gh pr create --body-file -"                                  warn
check "stdin from a pipe"                 "cat notes.md | gh pr create --body-file -"                   warn
check "a heredoc that feeds another line"  $'cat > b.md <<\'EOF\'\nFixes #8\nEOF\ngh pr create --body-file - < b.md'  warn
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

echo "the body file's path needs the shell to expand it -> warn, and say so"
check "a variable in the path"            'gh pr create --body-file $DIR/good.md'                       warn
check "a quoted variable in the path"     'gh pr create --body-file "$DIR/good.md"'                     warn
check "a variable in braces"              'gh pr create -F ${DIR}/good.md'                              warn
check "a command substitution in the path" 'gh pr create --body-file $(mktemp)'                         warn
check "a path under ~"                    'gh pr create --body-file ~/good.md'                          warn
check_output "the reason names the unexpanded path" \
  'gh pr create --body-file $DIR/good.md' \
  '.hookSpecificOutput.permissionDecision == "ask"
     and (.hookSpecificOutput.permissionDecisionReason | test("shell variable"))
     and (.hookSpecificOutput.permissionDecisionReason | test("\\$DIR/good.md"))'

echo "the command only mentions gh pr create, as a plain command of the listed tools -> allow"
check "a search for the words"            'grep -rn "gh pr create" docs/'                               allow
check "a search, single-quoted"           "cat notes.md | grep 'gh pr create'"                          allow
check "a search with ripgrep"             'rg -n "gh pr create" hooks tests'                            allow
check "printing the words"                'echo "then run gh pr create --fill"'                         allow
check "a file written from a heredoc"     $'cat > release.sh <<\'EOF\'\ngh pr create --fill\nEOF'       allow
check "a commit message"                  'git commit -m "docs: explain gh pr create"'                  allow
check "a commit message from a heredoc"   $'git commit -m "$(cat <<\'EOF\'\nfix: the gh pr create hook\nEOF\n)"' allow
check "git with an option before commit"  'git -C repo commit -m "about gh pr create"'                  allow
check "a comment on an issue"             'gh issue comment 5 --body "use gh pr create --fill"'         allow
check "another gh pr subcommand"          'gh pr edit 7 --body "made with gh pr create"'                allow
check "a shell comment"                   $'ls # gh pr create --fill\nls'                               allow
check "a mention after a redirection"     'grep -rn "gh pr create" . 2>&1 | tail -3'                    allow
check "a mention through filters"         'grep -rn "gh pr create" . | sort | uniq -c | head -5'        allow
check "every listed redirection"          'grep -n "gh pr create" < in.txt > out.txt 2>> err.txt'       allow
check "a list that goes on over lines"    $'grep -rn "gh pr create" . |\n  head -3 &&\n  echo done'     allow
check "a word of several segments"        $'grep -n gh\' pr \'"create" notes.md'                       allow
check "a comment after a pipe"            $'grep -rn "gh pr create" . | # first matches\n  head -3'     allow
check "git grep with a directory"         'git -C repo grep -n "gh pr create" -- hooks'                 allow
check "printf with a format"              $'printf \'%s\\n\' \'gh pr create\''                           allow
check "a heredoc into a command of the list" $'tee -a notes.md <<\'EOF\' >/dev/null\nrun gh pr create next\nEOF' allow
check "jq reading a gh result"            $'gh pr view 7 --json body | jq -r .body | grep -c \'gh pr create\'' allow
check "a glob for grep"                   'grep -n "gh pr create" *.md docs/[a-z]*'                     allow
check "a quoted glob for git grep"        $'git grep -n "gh pr create" -- \'*.md\''                     allow

echo "the command only mentions gh pr create, in a form outside the short language -> warn on purpose"
check "a heredoc into tee"                $'tee -a notes.md <<EOF\nrun gh pr create next\nEOF'          warn
check "a test of a string"                '[ "$cmd" = "gh pr create" ] && echo yes'                     warn
check "an assignment from a search"       'n=$(grep -c "gh pr create" log.txt); echo "$n"'              warn
check "a mention in a subshell"           '( cd docs && grep -rn "gh pr create" . ) | head'             warn
check "a mention read in a loop"          $'grep -rn "gh pr create" . | while read -r l; do echo "$l"; done' warn
check "a for loop over a search"          $'for f in $(grep -rl "gh pr create" .); do wc -l "$f"; done' warn
check "a mention inside a case"           $'case $x in\n  a) echo "gh pr create" ;;\nesac'              warn
check "a here-string to a search"         'grep -c create <<< "gh pr create"'                           warn
check "a backslash quotes the delimiter"  $'cat <<\\EOF\n$(gh pr create --fill)\nEOF'                   warn
check "a mention in a case in a substitution" $'echo "$(case x in x) echo \'gh pr create\' ;; esac)"'   warn
check "a mention in a case pattern"       $'case $cmd in *"gh pr create"*) echo yes ;; esac'            warn
check "a mention in if in a substitution" $'echo "$(if true; then echo \'gh pr create\'; fi)"'          warn
check "a function that only mentions"     'f() { grep -rn "gh pr create" .; }; f'                       warn
check "a mention after set"               'set -euo pipefail; grep -rn "gh pr create" .'                warn
check "a brace group writing a quoted heredoc" $'{ cat <<\'EOF\'\ngh pr create --fill\nEOF\n} > notes.md' warn

echo "the first thing just outside the language -> warn"
check "a backslash in a bare word"        'grep -n "gh pr create" a\ b.txt'                             warn
check "an ANSI-C quoted string"           $'grep -n $\'gh pr create\' notes.md'                         warn
check "a locale-quoted string"            $'grep -n $"gh pr create" notes.md'                           warn
check "a double-quoted string with \$"    'grep -n "gh pr create $x" notes.md'                          warn
check "a double-quoted string with a backtick" 'grep -n "gh pr create `x`" notes.md'                    warn
check "a double-quoted string with \\\""  'grep -n "gh pr create \"x\"" notes.md'                       warn
check "a double-quoted string with \\\\"  'grep -n "gh pr create \\" notes.md'                          warn
check "a double-quoted string with \\ and newline" $'grep -n "gh pr create \\\nx" notes.md'             warn
check "a quote that does not end"         "grep -n 'gh pr create notes.md"                              warn
check "a partly quoted delimiter"         $'cat > f <<\'E\'O\ngh pr create\nEO'                          warn
check "an unquoted delimiter"             $'cat > f <<EOF\ngh pr create\nEOF'                           warn
check "a double-quoted delimiter"         $'cat > f <<"EOF"\ngh pr create\nEOF'                         warn
check "a heredoc with <<-"                $'cat > f <<-\'EOF\'\ngh pr create\nEOF'                      warn
check "a space before the delimiter"      $'cat > f << \'EOF\'\ngh pr create\nEOF'                      warn
check "a delimiter that is not a name"    $'cat > f <<\'E-F\'\ngh pr create\nE-F'                       warn
check "two heredocs on one line"          $'cat <<\'A\' <<\'B\'\nx\nA\ngh pr create\nB'                 warn
check "a heredoc that does not end, quoted" $'cat > f <<\'EOF\'\ngh pr create'                          warn
check "|&"                                'grep -n "gh pr create" notes.md |& head'                     warn
check "&"                                 'grep -n "gh pr create" notes.md &'                           warn
check "a keyword as command name"         'if grep -q "gh pr create" notes.md; then echo y; fi'         warn
check "! before a command"                '! grep -q "gh pr create" notes.md'                           warn
check "time before a command"             'time grep -q "gh pr create" notes.md'                        warn
check "a brace group"                     '{ grep -q "gh pr create" notes.md; }'                        warn
check "an assignment before a listed command" 'LC_ALL=C grep -n "gh pr create" notes.md'                warn
check "a quoted command name"             '"grep" -n "gh pr create" notes.md'                           warn
check "a command that is not listed"      'awk "/gh pr create/" notes.md'                               warn
check "a redirection before the command name" '> out.txt grep -n "gh pr create" notes.md'              warn
check "a redirection from another descriptor" 'grep -n "gh pr create" notes.md 3> out.txt'             warn
check "a descriptor joined to a word"     'grep -n "gh pr create" notes.md 1>out.txt'                   warn
check ">&2"                               'echo "gh pr create" >&2'                                     warn
check "2>&2"                              'echo "gh pr create" 2>&2'                                    warn
check ">|"                                'echo "gh pr create" >| out.txt'                              warn
check "<>"                                'grep "gh pr create" <> notes.md'                             warn
check "a redirection with no file"        'grep -n "gh pr create" notes.md >'                           warn
check "a # inside a word"                 'grep -n x#"gh pr create" notes.md'                           warn
check "an empty command"                  'grep -n "gh pr create" notes.md ; ; ls'                      warn
check "a pipe with nothing after it"      'grep -n "gh pr create" notes.md |'                           warn
check "git -c"                            'git -c core.pager=cat log --grep "gh pr create"'             warn
check "git -C twice"                      'git -C a -C b log --grep "gh pr create"'                     warn
check "git with an unlisted subcommand"   'git stash push -m "gh pr create"'                            warn
check "git grep -O in a quoted word"      'git grep "-O"cat "gh pr create"'                             warn
check "gh with an option before the group" 'gh -R o/r issue list --search "gh pr create"'               warn
check "gh with an unlisted group"         'gh repo view o/r # gh pr create'                             warn
check "gh repo clone ... --"              'gh repo clone o/r dir -- --depth=1 # gh pr create'           warn
check "gh with -- in a listed group"      'gh issue list --search "gh pr create" --'                    warn
check "sort --compress-program"           $'printf \'gh pr create\\n\' | sort --compress-program=gzip'  warn
check "sort with the option in quotes"    $'printf \'gh pr create\\n\' | sort "--co"mpress-program=gzip' warn
check "rg --pre in quotes"                'rg "--pre"=cat "gh pr create" notes.md'                      warn
check "a glob for git grep"               'git grep -n "gh pr create" -- *.md'                          warn
check "a glob for sort"                   $'printf \'gh pr create\\n\' | sort ?'                         warn
check "a glob for rg"                     'rg -n "gh pr create" [a-z]*'                                 warn
check "a glob for printf"                 $'printf \'gh pr create\' ??'                                  warn
check "a glob for gh"                     'gh issue list --search "gh pr create" -?'                    warn
check "a glob that names an option for git grep" $'touch -- "-Osh -c \'gh pr create --body nope\' --"\ngit grep [-]O* x' block
check "printf -v"                         $'printf -v x \'gh pr create\''                               warn
check "test -v"                           'test -v "gh pr create"'                                      warn
check "the commit shape with more inside"  $'git commit -m "$(cat <<\'EOF\'\ngh pr create\nEOF\necho hi\n)"' warn
check "the commit shape with a pipe inside" $'git commit -m "$(cat <<\'EOF\' | tr a b\ngh pr create\nEOF\n)"' warn
check "the commit shape after other text"  $'git commit -m x"$(cat <<\'EOF\'\ngh pr create\nEOF\n)"'    warn
check "the commit shape with text after it" $'git commit -m "$(cat <<\'EOF\'\ngh pr create\nEOF\n)" && git log' warn
check "the commit shape for another command" $'echo "$(cat <<\'EOF\'\ngh pr create\nEOF\n)"'           warn
check "the commit shape for git log"       $'git log --grep "$(cat <<\'EOF\'\ngh pr create\nEOF\n)"'    warn
check "the commit shape as a redirection target" $'git commit -m x > "$(cat <<\'EOF\'\ngh pr create\nEOF\n)"' warn
check "the commit shape beside a heredoc"  $'git commit -F - <<\'A\' -m "$(cat <<\'B\'\ngh pr create\nB\n)"\nA' warn
check "the commit shape without its end"   $'git commit -m "$(cat <<\'EOF\'\ngh pr create\nEOF'           warn
check "an apostrophe in the commit shape"  $'git commit -m "$(cat <<\'EOF\'\nit\'s the gh pr create hook\nEOF\n)"' warn
check "a parenthesis in the commit shape"  $'git commit -m "$(cat <<\'EOF\'\nfix(hooks): the gh pr create hook\nEOF\n)"' warn

echo "a mention beside a real gh pr create -> the real one is checked"
check "the body file has the keyword"     "grep -c 'gh pr create' x; gh pr create --body-file $WORK/good.md"  allow
check "the body file lacks the keyword"   "grep -c 'gh pr create' x; gh pr create --body-file $WORK/bad.md"   block
check "after writing the body by heredoc" $'cat > b.md <<\'EOF\'\nSee gh pr create.\nEOF\ngh pr create --fill' warn

echo "the command may run gh pr create -> checked as before"
check "after cd"                          'cd repo && gh pr create --fill'                              warn
check "in a subshell"                     '(cd repo; gh pr create --fill)'                              warn
check "with a variable set for it"        'GH_TOKEN=x gh pr create --fill'                              warn
check "through env"                       'env GH_TOKEN=x gh pr create --fill'                          warn
check "under time"                        'time gh pr create --fill'                                    warn
check "inside if"                         'if true; then gh pr create --fill; fi'                       warn
check "in a command substitution"         'url=$(gh pr create --fill)'                                  warn
check "substituted into a data command"   'echo "$(gh pr create --fill)"'                               warn
check "in backticks"                      'echo `gh pr create --fill`'                                  warn
check "as the text of bash -c"            "bash -c 'gh pr create --fill'"                               warn
check "as the text of eval"               'eval "gh pr create --fill"'                                  warn
check "a heredoc that feeds a shell"      $'bash <<\'EOF\'\ngh pr create --fill\nEOF'                   warn
check "a here-string that feeds a shell"  'bash <<< "gh pr create --fill"'                              warn
check "printed, and piped into a shell"   "echo 'gh pr create --fill' | sh"                             warn
check "a heredoc piped into a shell"      $'cat <<\'EOF\' | bash\ngh pr create --fill\nEOF'             warn
check "a pipe that goes on the next line" $'cat <<\'EOF\' |\ngh pr create --fill\nEOF\nbash'            warn
check "a subshell piped into a shell"     "( echo 'gh pr create --fill' ) | sh"                         warn
check "a substitution piped into a shell" $'echo "$(cat <<\'EOF\'\ngh pr create --fill\nEOF\n)" | sh'   warn
check "through xargs"                     'echo x | xargs -I{} gh pr create --fill'                     warn
check "inside a function"                 'f() { gh pr create --fill; }; f'                             warn
check "inside a case"                     $'case $x in\n  a) gh pr create --fill ;;\nesac'              warn
check "a script written to python"        $'python3 - <<\'EOF\'\nrun("gh pr create --fill")\nEOF'       warn
check "git rebase --exec"                 "git rebase --exec 'gh pr create --fill' HEAD~1"              warn
check "the output of a command is run"    '$(echo gh pr create --fill)'                                 warn
check "a command this hook does not know" 'retry 3 gh pr create --fill'                                 warn
check "a quote that does not end"         'echo "gh pr create --fill'                                   warn
check "a heredoc that does not end"       $'cat <<EOF\ngh pr create --fill'                             warn
check "a checked body after cd"           "cd repo && gh pr create --body 'Fixes #1'"                   allow
check "a refused body in a subshell"      "(cd repo && gh pr create --body 'no keyword')"               block

echo "a dollar sign in a single-quoted path is part of the name -> read the file"
check "single quotes keep the dollar sign"  "gh pr create --body-file 'body\$cost.md'"               allow
check "double quotes expand it"             'gh pr create --body-file "body$cost.md"'                 warn
check_output "the reason for double quotes says it needs expanding" \
  'gh pr create --body-file "body$cost.md"' \
  '.hookSpecificOutput.permissionDecision == "ask"
     and (.hookSpecificOutput.permissionDecisionReason | test("shell variable"))'

echo "an unquoted heredoc runs its substitutions, whoever reads it -> checked"
c=$'cat <<EOF\n$(gh pr create --body nope)\nEOF'
check     "a substitution in the body"            "$c" block
check_runs "a substitution in the body"           "$c"
c=$'cat <<EOF\n`gh pr create --body nope`\nEOF'
check     "a backtick in the body"                "$c" block
check_runs "a backtick in the body"               "$c"
c=$'cat <<EOF\n$(\ngh pr create --body nope\n)\nEOF'
check     "a substitution over several lines"     "$c" block
check_runs "a substitution over several lines"    "$c"
check     "a brace substitution in the body"      $'cat <<EOF\n${ gh pr create --body nope; }\nEOF' block
check     "a quoted heredoc is only text"         $'cat <<\'EOF\'\n$(gh pr create --fill)\nEOF'   allow

echo "a pipe into a compound command carries its text in -> checked"
c=$'printf \'gh pr create --body nope\\n\' | (sh)'
check     "a pipe into a subshell"                "$c" block
check_runs "a pipe into a subshell"               "$c"
c=$'printf \'gh pr create --body nope\\n\' | { :; sh; }'
check     "a pipe into a brace group"             "$c" block
check_runs "a pipe into a brace group"            "$c"
c=$'printf \'gh pr create --body nope\\n\' | if true; then sh; fi'
check     "a pipe into if"                        "$c" block
check_runs "a pipe into if"                       "$c"
c=$'printf \'gh pr create --body nope\\n\' | while read -r l; do $l; done'
check     "a pipe into while"                     "$c" block
check_runs "a pipe into while"                    "$c"
c=$'printf \'gh pr create --body nope\\n\' | case x in x) sh ;; esac'
check     "a pipe into case"                      "$c" block
check_runs "a pipe into case"                     "$c"
c=$'printf \'gh pr create --body nope\\n\' | { "}"; sh; }'
check     "a quoted closing brace closes nothing" "$c" block
check_runs "a quoted closing brace closes nothing" "$c"
c=$'printf \'gh pr create --body nope\\n\' | echo "$(sh)"'
check     "a substitution reads the pipe"         "$c" block
check_runs "a substitution reads the pipe"        "$c"
c=$'printf \'gh pr create --body nope\\n\' | cat <(sh)'
check     "a process substitution reads the pipe" "$c" block
check_runs "a process substitution reads the pipe" "$c"
check     "tee into a process substitution"       $'printf \'gh pr create --body nope\\n\' | tee >(sh)' block
c=$'cat <<\'EOF\' | (sh)\ngh pr create --body nope\nEOF'
check     "a heredoc piped into a subshell"       "$c" block
check_runs "a heredoc piped into a subshell"      "$c"
c=$'{ sh; } <<\'EOF\'\ngh pr create --body nope\nEOF'
check     "a heredoc read by a brace group"       "$c" block
check_runs "a heredoc read by a brace group"      "$c"
check     "a closing word with no frame"          $'ls; }\ngh pr create --fill'                    warn

echo "the ) of a case pattern closes no substitution -> checked"
c='echo "$(case x in x) : ;; esac; gh pr create --body nope)"'
check     "a case inside a substitution"          "$c" block
check_runs "a case inside a substitution"         "$c" 5
check     "if inside a substitution"              'echo "$(if true; then echo x; fi; gh pr create --body nope)"' block
c='echo `echo \`gh pr create --body nope\``'
check     "a nested backtick substitution"        "$c" block
check_runs "a nested backtick substitution"       "$c"

echo "a listed command in a form that runs text -> checked"
check     "git -c core.editor"                    "git -c core.editor='gh pr create --body nope' commit --allow-empty -e -m probe" block
check     "git --config-env"                      "ED='gh pr create --body nope' git --config-env=core.editor=ED commit -e" block
check     "git grep --open-files-in-pager"        "git grep --open-files-in-pager='gh pr create --body nope' x" block
check     "git grep with an abbreviated pager option" "git grep --open='gh pr create --body nope' x" block
check     "git grep -O"                           "git grep -O'gh pr create --body nope' x"         block
check     "git grep with -O among short options"  "git grep -nO'gh pr create --body nope' x"        block
check     "an environment variable for git"       "GIT_EXTERNAL_DIFF='gh pr create --body nope' git diff" block
check     "an exported variable for git"          "export GIT_EXTERNAL_DIFF='gh pr create --body nope'; git diff" block
check     "rg --pre"                              "rg --pre 'gh pr create --body nope' x input"     block
check     "rg --hostname-bin"                     "rg --hostname-bin='gh pr create --body nope' x"  block
check     "sort --compress-program"               "printf 'gh pr create --body nope\\n' | sort -S 1b --compress-program=sh" block
check     "sort with an abbreviated option"       "printf 'gh pr create --body nope\\n' | sort --compress=sh" block
check     "sort with an option from a substitution" "printf 'gh pr create --body nope\\n' | sort \"\$(echo --compress-program=sh)\"" block
check     "gh codespace ssh"                      'gh codespace ssh -c example -- gh pr create --body nope' block
check     "gh extension exec"                     'gh extension exec x gh pr create --body nope'   block
check     "gh pr with an option before create"    'gh pr -R o/r create --body nope # gh pr create'  warn
c=$'declare -a a; declare \'a[$(gh pr create --body nope)]=x\''
check     "declare with an array subscript"       "$c" block
check_runs "declare with an array subscript"      "$c"
c=$'f() { local -a \'a[$(gh pr create --body nope)]=x\'; }; f'
check     "local with an array subscript"         "$c" block
check_runs "local with an array subscript"        "$c"
c=$'typeset -a \'a[$(gh pr create --body nope)]=x\''
check     "typeset with an array subscript"       "$c" block
check_runs "typeset with an array subscript"      "$c"
check     "readonly with an array subscript"      $'declare -a a; readonly \'a[$(gh pr create --body nope)]=x\'' block
check     "export with an array subscript"        $'export \'a[$(gh pr create --body nope)]=x\'' block
c=$'declare -a a; printf -v \'a[$(gh pr create --body nope)]\' \'%s\' x'
check     "printf -v with an array subscript"     "$c" block
check_runs "printf -v with an array subscript"    "$c" 5
c=$'declare -a a; read \'a[$(gh pr create --body nope)]\' <<< x'
check     "read with an array subscript"          "$c" block
check_runs "read with an array subscript"         "$c"
c=$'declare -a a=(x); unset \'a[$(gh pr create --body nope)]\''
check     "unset with an array subscript"         "$c" block
check_runs "unset with an array subscript"        "$c"
c=$'declare -a a=(x); test -v \'a[$(gh pr create --body nope)]\''
check     "test -v with an array subscript"       "$c" block
check_runs "test -v with an array subscript"      "$c" 5
c=$'declare -a a=(x); [ -v \'a[$(gh pr create --body nope)]\' ]'
check     "[ -v with an array subscript"          "$c" block
check_runs "[ -v with an array subscript"         "$c" 5
c='declare -a a; declare "a[\$(gh pr create --body nope)]=x"'
check     "declare with an escaped substitution"  "$c" block
check_runs "declare with an escaped substitution" "$c"
c=$'declare -a a; declare "$(printf \'a[$(gh pr create --body nope)]=x\')"'
check     "declare with a substituted name"       "$c" block
check_runs "declare with a substituted name"      "$c"
c=$'declare -i x; x=\'a[$(gh pr create --body nope)]\''
check     "an assignment to an integer variable"  "$c" block
check_runs "an assignment to an integer variable" "$c"
c=$'a=(1); echo ${a[\'$(gh pr create --body nope)\']}'
check     "a subscript in a parameter expansion"  "$c" block
check_runs "a subscript in a parameter expansion" "$c" 5
c=$'PS4=\'$(gh pr create --body nope)\'; set -x; echo hi'
check     "PS4 under set -x"                      "$c" block
check_runs "PS4 under set -x"                     "$c"
check     "a brace substitution"                  'echo ${ gh pr create --body nope; }'             block

echo "the command changes what a listed name runs -> checked"
c='echo() { "$@"; }; echo gh pr create --body nope'
check     "a function named echo"                 "$c" block
check_runs "a function named echo"                "$c"
c='function echo { "$@"; }; echo gh pr create --body nope'
check     "a function named echo, with the keyword" "$c" block
check_runs "a function named echo, with the keyword" "$c"
c=$'cat () { sh; }; cat <<\'EOF\'\ngh pr create --body nope\nEOF'
check     "a function named cat"                  "$c" block
check_runs "a function named cat"                 "$c"
check     "a function named gh"                   'gh() { :; }; gh pr create --body nope'           block
check     "an alias"                              $'alias echo=eval\necho gh pr create --body nope' block
check     "a disabled builtin"                    'enable -n echo; echo gh pr create --body nope'   block
c=$'hash -p /bin/sh cat; cat <<\'EOF\'\ngh pr create --body nope\nEOF'
check     "a remembered path"                     "$c" block
check_runs "a remembered path"                    "$c"
c=$'BASH_CMDS[cat]=/bin/sh; cat <<\'EOF\'\ngh pr create --body nope\nEOF'
check     "a path set in BASH_CMDS"               "$c" block
check_runs "a path set in BASH_CMDS"              "$c" 5
c=$'trap \'set -- $BASH_COMMAND; shift; "$@"\' DEBUG; echo gh pr create --body nope'
check     "a trap that runs each command"         "$c" block
check_runs "a trap that runs each command"        "$c"
c=$'eval \'echo() { "$@"; }\'; echo gh pr create --body nope'
check     "a function defined by eval"            "$c" block
check_runs "a function defined by eval"           "$c"
c=$'builtin trap \'set -- $BASH_COMMAND; shift; "$@"\' DEBUG; echo gh pr create --body nope'
check     "a trap set through builtin"            "$c" block
check_runs "a trap set through builtin"           "$c"
c=$'a=(1); cat > ${a[\'$(gh pr create --body nope)\']}'
check     "a subscript in a redirection target"   "$c" block
check_runs "a subscript in a redirection target"  "$c" 5
c=$'read -r PS4 <<\'EOF\'\n$(gh pr create --body nope)\nEOF\nset -x; echo hi'
check     "PS4 read from a heredoc, under set -x" "$c" block
check_runs "PS4 read from a heredoc, under set -x" "$c"

echo "bash 3.2 ends a substitution at a parenthesis in a heredoc body -> checked"
c=$'git commit -m "$(cat <<\'EOF\'\nx)" ; gh pr create --body nope ; echo "\nEOF\n)"'
check     "a parenthesis and a quote in the commit body" "$c" block
check_runs "a parenthesis and a quote in the commit body" "$c" 0 3

echo "codex's second review -> checked"
c=$'cat <<\'E\'O\'F\'\nbody\nEOF\ngh pr create --body nope\nE'
check     "a delimiter quoted in parts"           "$c" block
check_runs "a delimiter quoted in parts"          "$c"
c=$'cat <<"E"O"F"\nbody\nEOF\ngh pr create --body nope\nE'
check     "a delimiter double-quoted in parts"    "$c" block
check_runs "a delimiter double-quoted in parts"   "$c"
c=$'cat <<\'E\'O\'F\' | cat\nbody\nEOF\ngh pr create --body nope\nE'
check     "a delimiter quoted in parts, piped"    "$c" block
check_runs "a delimiter quoted in parts, piped"   "$c"
c=$'printf \'gh pr create --body %4096s\\n\' nope{1..40} | sort -S 1b $\'--\\x63ompress-program=sh\''
check     "sort with an escaped option"           "$c" block
check_runs "sort with an escaped option"          "$c"
check     "git with an escaped -c"                $'git $\'-\\x63core.editor=gh pr create --body nope\' commit --allow-empty -e -m probe' block
check     "git grep with an escaped pager option" $'git grep $\'--\\x6fpen-files-in-pager=sh -c \\\'gh pr create --body nope\\\' --\' x' block
check     "git grep with an escaped -O"           $'git grep $\'-\\x4fsh -c \\\'gh pr create --body nope\\\' --\' x' block
check     "rg with an escaped --pre"              $'rg $\'--\\x70re=gh pr create --body nope\' x input' block
c=$'cat <<\'EOF\' | { cat; } | sh\ngh pr create --body nope\nEOF'
check     "a heredoc through a brace group"       "$c" block
check_runs "a heredoc through a brace group"      "$c"
c=$'cat <<\'EOF\' | { { cat; }; } | sh\ngh pr create --body nope\nEOF'
check     "a heredoc through nested groups"       "$c" block
check_runs "a heredoc through nested groups"      "$c"
c=$'cat <<\'EOF\' | if true; then cat; fi | sh\ngh pr create --body nope\nEOF'
check     "a heredoc through if"                  "$c" block
check_runs "a heredoc through if"                 "$c"
c=$'printf \'gh pr create --body nope\\n\' | { true && sh; }'
check     "a pipe into a group with &&"           "$c" block
check_runs "a pipe into a group with &&"          "$c"
c=$'printf \'gh pr create --body nope\\n\' | { false || sh; }'
check     "a pipe into a group with ||"           "$c" block
check_runs "a pipe into a group with ||"          "$c"
c=$'{ printf \'gh pr create --body nope\\n\'; } | sh'
check     "a group's output into a shell"         "$c" block
check_runs "a group's output into a shell"        "$c"
c=$'(printf \'gh pr create --body nope\\n\') | sh'
check     "a subshell's output into a shell"      "$c" block
check_runs "a subshell's output into a shell"     "$c"
c=$'{ printf \'gh pr create --body nope\\n\'; } | { :; sh; }'
check     "groups on both sides of a pipe"        "$c" block
check_runs "groups on both sides of a pipe"       "$c"
c=$'printf \'gh pr create --body nope\\n\' | \\\n(sh)'
check     "a pipe continued into a subshell"      "$c" block
check_runs "a pipe continued into a subshell"     "$c"
c=$'printf \'gh pr create --body nope\\n\' | \\\n{ sh; }'
check     "a pipe continued into a brace group"   "$c" block
check_runs "a pipe continued into a brace group"  "$c"
check     "output into a process substitution"    $'printf \'gh pr create --body nope\\n\' > >(sh)' block
check     "tee into a group in a process substitution" $'tee >({ :; sh; }) <<\'EOF\'\ngh pr create --body nope\nEOF' block
c=$'{ sh; } <<< \'gh pr create --body nope\''
check     "a here-string into a brace group"      "$c" block
check_runs "a here-string into a brace group"     "$c"
c=$'if true; then sh; fi <<< \'gh pr create --body nope\''
check     "a here-string into if"                 "$c" block
check_runs "a here-string into if"                "$c"
c=$'(sh) <<< \'gh pr create --body nope\''
check     "a here-string into a subshell"         "$c" block
check_runs "a here-string into a subshell"        "$c"
check     "gh repo clone with git options"        $'gh repo clone git@github.com:probe/example.git cloned -- -c "core.sshCommand=sh -c \'gh pr create --body nope; exit 1\' --"' block
c='coproc { gh pr create --body nope; }; wait'
check     "coproc"                                "$c" block
check_runs "coproc"                               "$c" 4
c=$'printf \'gh pr create --body nope\\n\' | { time sh; }'
check     "time in a group"                       "$c" block
check_runs "time in a group"                      "$c"
c=$'printf \'gh pr create --body nope\\n\' | { ! sh; }'
check     "! in a group"                          "$c" block
check_runs "! in a group"                         "$c"
c='echo "$(case x in (x) : ;; esac; gh pr create --body nope)"'
check     "a parenthesized case pattern in a substitution" "$c" block
check_runs "a parenthesized case pattern in a substitution" "$c"
c='function f { gh pr create --body nope; }; f'
check     "a function without parentheses"        "$c" block
check_runs "a function without parentheses"       "$c"
c='echo "$(case x in x) gh pr create --body nope ;; esac)"'
check     "gh pr create in a case in a substitution" "$c" block
check_runs "gh pr create in a case in a substitution" "$c" 5
c='declare -a a=(x); echo ${a[$(gh pr create --body nope; printf 0)]}'
check     "a substitution in an array subscript"  "$c" block
check_runs "a substitution in an array subscript" "$c"
c='(( $(gh pr create --body nope; printf 1) ))'
check     "a substitution in an arithmetic command" "$c" block
check_runs "a substitution in an arithmetic command" "$c"
c=$'SHELL=sh printf \'gh pr create --body nope\\n\' | sh'
check     "an assignment before a data command"   "$c" block
check_runs "an assignment before a data command"  "$c"
c=$'sh \\\n -c \'gh pr create --body nope\''
check     "a command continued over a line"       "$c" block
check_runs "a command continued over a line"      "$c"
check     "closing words as arguments"            $'printf \'%s\\n\' \'}\' \'fi\' \'gh pr create --body nope\' | sh' block

echo "a command that writes a file and also runs git or gh -> checked"
check "a hook written, then a commit"     $'cp .git/hooks/pre-commit.sample .git/hooks/pre-commit\ncat > .git/hooks/pre-commit <<\'EOF\'\ngh pr create --body nope\nEOF\ngit commit -m x' block
check "a config line appended, then git status" $'cat >> .git/config <<\'EOF\'\n[core]\n  fsmonitor = gh pr create --body nope\nEOF\ngit status' block
check "a file written, then git add"      $'cat > notes.md <<\'EOF\'\nrun gh pr create next\nEOF\ngit add notes.md'  warn
check "git first, then a file written"    $'git status\ncat > notes.md <<\'EOF\'\nrun gh pr create next\nEOF'      warn
check "tee writes, then gh"               "echo 'gh pr create' | tee notes.md; gh issue list"                     warn
check "sed edits in place, then git"      "sed -i 's/x/gh pr create/' notes.md; git diff"                         warn
check "sed -ni edits in place, then git"  "sed -ni '/gh pr create/p' notes.md; git diff"                          warn
check "sort writes its output, then git"  "sort -o notes.md notes.md; git log --grep='gh pr create'"              warn
check "stderr to a file, then git"        "grep -rn 'gh pr create' . 2> errors.txt; git status"                   warn
check "cp, then git"                      "cp a b; git log --grep='gh pr create'"                                 warn

echo "a command that only writes, or only runs git or gh -> allow"
check "a file written, nothing else"      $'cat > notes.md <<\'EOF\'\nrun gh pr create next\nEOF'                   allow
check "sed edits in place, nothing else"  "sed -i 's/x/gh pr create/' notes.md"                                   allow
check "git only, stderr joined to stdout" "git log --grep='gh pr create' 2>&1 | head -3"                          allow
check "gh only"                           'gh issue comment 5 --body "use gh pr create --fill"'                   allow

echo "not this hook's business -> allow"
check "a git commit mentioning an issue"  "git commit -m 'Closes #201'"                                 allow
check "gh pr view"                        "gh pr view 728"                                              allow

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
