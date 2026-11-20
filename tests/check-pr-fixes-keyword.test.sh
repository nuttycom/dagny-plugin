#!/usr/bin/env bash
# Tests for hooks/scripts/check-pr-fixes-keyword.sh
#
# The hook has three outcomes, and which one it picks is the whole point:
#
#   block  the body was read and has no closing keyword
#   warn   the body could not be read, so nothing was verified
#   allow  the body was read and has a closing keyword (or this is not ours:
#          the command is a sentence of the small language that the hook
#          states, and it only mentions "gh pr create")
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
# Side effects: those of check_runs_in, with no fixture.
check_runs() {
  check_runs_in "$1" '' "$2" "${3:-0}" "${4:-99}"
}

# Asserts, as check_runs does, that a command really runs "gh pr create",
# for a command that needs GNU sed.
#
# Preconditions: none.
#
# Inputs: $1 describes the case, $2 is the command.
#
# Output: prints one result line.
#
# Side effects: when the sed on PATH is GNU sed, those of check_runs.
# Otherwise none: the case is skipped, and the line says so.
check_runs_with_gnu_sed() {
  if ! sed --version 2>/dev/null | head -n 1 | grep -q 'GNU sed'; then
    printf '  skip  %-52s %s\n' "$1" "needs GNU sed"
    return 0
  fi
  check_runs "$1" "$2"
}

# Asserts that a command really runs "gh pr create" in a directory that a
# fixture has prepared.
#
# Preconditions: none.
#
# Inputs: $1 describes the case. $2 is the name of a fixture function, or
# empty for none. $3 is the command. $4 and $5, when given, are the lowest
# and the highest major version of bash known to run the command as the case
# says; with a bash outside them the case is skipped.
#
# Output: prints one result line.
#
# Side effects: those of run_case, unless the case is skipped. Counts the
# case as passed or failed.
check_runs_in() {
  local desc=$1 fixture=$2 cmd=$3 min_major=${4:-0} max_major=${5:-99} major
  major=$(bash -c 'echo "${BASH_VERSINFO[0]}"')
  if (( major < min_major )); then
    printf '  skip  %-52s %s\n' "$desc" "needs bash $min_major"
    return 0
  fi
  if (( major > max_major )); then
    printf '  skip  %-52s %s\n' "$desc" "runs only up to bash $max_major"
    return 0
  fi
  run_case "$desc" "$fixture" "$cmd" || return 0
  if [[ -f "$case_dir/calls" ]] && grep -q '^pr create' "$case_dir/calls"; then
    printf '  ok    %-52s %s\n' "$desc" "runs it"
    passed=$((passed + 1))
  else
    printf '  FAIL  %-52s %s\n' "$desc" "the stub gh was not called with pr create"
    failed=$((failed + 1))
  fi
}

# Asserts that a command runs the program that a fixture made, with an
# argument that holds "gh pr create". The fixture's program records its
# arguments in the file "ran" of the case's directory.
#
# Preconditions: none.
#
# Inputs: $1 describes the case, $2 is the name of the fixture function, $3
# is the command.
#
# Output: prints one result line.
#
# Side effects: those of run_case. Counts the case as passed or failed.
check_runs_program() {
  local desc=$1 fixture=$2 cmd=$3
  run_case "$desc" "$fixture" "$cmd" || return 0
  if [[ -f "$case_dir/ran" ]] && grep -q 'gh pr create' "$case_dir/ran"; then
    printf '  ok    %-52s %s\n' "$desc" "runs the fixture's program"
    passed=$((passed + 1))
  else
    printf '  FAIL  %-52s %s\n' "$desc" "the fixture's program did not run"
    failed=$((failed + 1))
  fi
}

# Runs a command for check_runs_in or check_runs_program.
#
# Preconditions: none.
#
# Inputs: $1 describes the case. $2 is the name of a fixture function, or
# empty for none. $3 is the command.
#
# Output: sets case_dir to the case's directory. Fails, after it prints a
# result line and counts the case as failed, when the fixture fails.
#
# Side effects: makes a new empty directory under $WORK, with a stub gh
# first on PATH. The stub records its arguments in the file "calls" of the
# case's directory and does nothing else. Runs the fixture in the
# directory, then the command with "bash -c", both with standard input from
# /dev/null. Both run with the C locale, without the system's or the user's
# git configuration, with a git author and committer of their own, and with
# git kept from looking for a repository above the case's directory.
run_case() {
  local desc=$1 fixture=$2 cmd=$3
  case_dir=$(mktemp -d "$WORK/run.XXXXXX")
  mkdir "$case_dir/bin" "$case_dir/cwd"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/calls"\n' "$case_dir" > "$case_dir/bin/gh"
  chmod +x "$case_dir/bin/gh"
  if [[ -n $fixture ]] &&
     ! ( in_run_environment "$case_dir" && "$fixture" ) </dev/null >/dev/null 2>&1; then
    printf '  FAIL  %-52s %s\n' "$desc" "the fixture $fixture failed"
    failed=$((failed + 1))
    return 1
  fi
  ( in_run_environment "$case_dir" && bash --noprofile --norc -c "$cmd" ) \
    </dev/null >/dev/null 2>&1
  return 0
}

# Prepares the current shell to run a case of check_runs_in.
#
# Preconditions: called in a subshell, because it changes the directory and
# the environment.
#
# Inputs: $1 is the case's directory, which holds bin/ and cwd/.
#
# Output: fails when the directory cannot be entered.
#
# Side effects: enters cwd/, and exports PATH with bin/ first, the C locale,
# a git configuration of nothing but the case's own repository, a git author
# and committer, and $1 as the ceiling of git's search for a repository.
in_run_environment() {
  cd "$1/cwd" || return 1
  export PATH="$1/bin:$PATH" LC_ALL=C GIT_CEILING_DIRECTORIES="$1" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid \
    GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
}

# Fixtures for check_runs_in. Each one runs in the empty directory of a
# case, before the case's command. Each fails when it cannot prepare the
# directory.

# Makes a git repository with one commit.
fixture_repository() {
  git init -q && git commit -q --allow-empty -m initial
}

# Makes a git repository whose pre-commit hook is executable and does
# nothing.
fixture_repository_with_hook() {
  fixture_repository &&
    printf '#!/bin/sh\nexit 0\n' > .git/hooks/pre-commit &&
    chmod +x .git/hooks/pre-commit
}

# Makes a git repository that holds a directory named "-C", a file named
# "-c", and a file whose name sets git's file-system monitor to a command.
fixture_repository_with_option_names() {
  fixture_repository &&
    mkdir -- -C &&
    : > -c &&
    : > "core.fsmonitor=sh -c 'gh pr create --body nope' --"
}

# Makes an executable program named rev, which does nothing, in ../bin. That
# directory is first on PATH, and the case's command can write into it.
fixture_program_on_path() {
  printf '#!/bin/sh\nexit 0\n' > ../bin/rev && chmod +x ../bin/rev
}

# Makes an executable program named cat in the directory "0", which is on
# no PATH. The program only records its arguments in ../ran, the file "ran"
# of the case's directory.
fixture_program_in_directory_0() {
  mkdir 0 &&
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> ../ran\n' > 0/cat &&
    chmod +x 0/cat
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

echo "the command only mentions gh pr create, as a sentence of the language -> allow"
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
check "a heredoc into a command of the list" $'tee -a notes.md <<\'EOF\' >/dev/null\nrun gh pr create next\nEOF' allow
check "gh selecting with its own --jq"    $'gh pr view 7 --json body --jq .body | grep -c \'gh pr create\'' allow
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
check "sort --compress-program"           $'echo \'gh pr create\' | sort --compress-program=gzip'  warn
check "sort with the option in quotes"    $'echo \'gh pr create\' | sort "--co"mpress-program=gzip' warn
check "rg --pre in quotes"                'rg "--pre"=cat "gh pr create" notes.md'                      warn
check "a glob for git grep"               'git grep -n "gh pr create" -- *.md'                          warn
check "a glob for sort"                   $'echo \'gh pr create\' | sort ?'                         warn
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

echo "codex's third review -> checked"
c=$'printf \'-va[$(gh pr create --body nope)]\' \'%s\' x'
check         "printf with -v and a name in one quoted word" "$c" block
check_runs    "printf with -v and a name in one quoted word" "$c" 5
c=$'printf -v\'a[$(gh pr create --body nope)]\' \'%s\' x'
check         "printf with a quoted name attached to -v"    "$c" block
check_runs    "printf with a quoted name attached to -v"    "$c" 5
c=$'sed -n \'w .git/config\' <<\'EOF\'\n[core]\nfsmonitor = sh -c \'gh pr create --body nope\' --\nEOF\ngit status --porcelain'
check         "sed's w command writes git's configuration"  "$c" block
check_runs_in "sed's w command writes git's configuration"  fixture_repository "$c"
c=$'sed -n \'s/^//w .git/config\' <<\'EOF\'\n[core]\nfsmonitor = sh -c \'gh pr create --body nope\' --\nEOF\ngit status --porcelain'
check         "the w flag of sed's s writes the configuration" "$c" block
check_runs_in "the w flag of sed's s writes the configuration" fixture_repository "$c"
c=$'uniq - .git/config <<\'EOF\'\n[core]\nfsmonitor = sh -c \'gh pr create --body nope\' --\nEOF\ngit status --porcelain'
check         "uniq's output operand writes the configuration" "$c" block
check_runs_in "uniq's output operand writes the configuration" fixture_repository "$c"
c=$'git log -1 --format="[core]%nfsmonitor = sh -c \'gh pr create --body nope\' --" --output=.git/config; git status --porcelain'
check         "git log --output writes the configuration"   "$c" block
check_runs_in "git log --output writes the configuration"   fixture_repository "$c"
c=$'git show --no-patch --format="[core]%nfsmonitor = sh -c \'gh pr create --body nope\' --" --output=.git/config; git status --porcelain'
check         "git show --output writes the configuration"  "$c" block
check_runs_in "git show --output writes the configuration"  fixture_repository "$c"
c=$'xxd -c 256 - .git/hooks/pre-commit <<\'EOF\'\n; gh pr create --body nope; #\nEOF\ngit commit -q --allow-empty -m probe'
check         "xxd's output operand overwrites a hook"      "$c" block
check_runs_in "xxd's output operand overwrites a hook"      fixture_repository_with_hook "$c"
c='git -C [-c]* status --porcelain # gh pr create --body nope'
check         "a glob for git -C expands to options"        "$c" block
check_runs_in "a glob for git -C expands to options"        fixture_repository_with_option_names "$c"

echo "a file written, then a program that the shell finds through PATH -> checked"
c=$'cp /bin/sh ../bin/rev; rev -c \'gh pr create --body nope\''
check         "a shell copied into a directory of PATH"     "$c" block
check_runs    "a shell copied into a directory of PATH"     "$c"
c=$'printf \'#!/bin/sh\\ngh pr create --body nope\\n\' > ../bin/rev; rev'
check         "a program on PATH rewritten by printf"       "$c" block
check_runs_in "a program on PATH rewritten by printf"       fixture_program_on_path "$c"
c=$'echo \'#!/bin/sh\' > ../bin/rev; echo \'gh pr create --body nope\' >> ../bin/rev; rev'
check         "a program on PATH rewritten by echo"         "$c" block
check_runs_in "a program on PATH rewritten by echo"         fixture_program_on_path "$c"

echo "a file written, with only builtins beside the one program that writes -> allow"
check "a heredoc into a file, then echo"         $'cat > notes.md <<\'EOF\'\nrun gh pr create next\nEOF\necho written' allow
check "echo into a file, twice"                  $'echo \'gh pr create\' > notes.md; echo done >> notes.md' allow
check "echo piped into tee"                      $'echo \'gh pr create\' | tee notes.md' allow
check "uniq writing its output file, and nothing else" $'uniq notes.md out.md # gh pr create' allow

echo "a file written, and another program -> warn"
check "a heredoc into a file, then wc"           $'cat > notes.md <<\'EOF\'\nrun gh pr create next\nEOF\nwc -l notes.md' warn
check "mkdir, then a heredoc into a file"        $'mkdir -p docs && cat > docs/x.md <<\'EOF\'\nrun gh pr create next\nEOF' warn
check "echo into a file, then cat"               $'echo \'gh pr create\' > notes.md; cat notes.md' warn
check "a search into a file, then a pipe"        $'grep -rn \'gh pr create\' . > hits.txt | head' warn
check "a search into a file, then echo into another" $'grep -rn \'gh pr create\' . > hits.txt; echo x > y.txt' warn

echo "the words that make uniq, xxd and git write a file -> edges, with git"
check "uniq with options only, then git"         $'grep \'gh pr create\' notes.md | uniq -c; git status' allow
check "uniq with an output operand, then git"    $'grep \'gh pr create\' notes.md | uniq - out.md; git status' warn
check "uniq with operands after --, then git"    $'grep \'gh pr create\' notes.md | uniq -- -in -out; git status' warn
check "xxd with attached option values, then git" $'echo \'gh pr create\' | xxd -c8 -g1; git status' allow
check "xxd with an option value apart, then git" $'echo \'gh pr create\' | xxd -c 8; git status' warn
check "xxd --r, then git"                        $'echo \'gh pr create\' | xxd --r; git status' warn
check "git log --oneline"                        $'git log --oneline --grep \'gh pr create\'' allow
check "git log --output-indicator-new"           $'git log -p --output-indicator-new=+ --grep \'gh pr create\'' allow
check "git log --output with the file apart"     $'git log --output log.txt --grep \'gh pr create\'' warn
check "git log with --output abbreviated"        $'git log --outp=log.txt --grep \'gh pr create\'' warn
check "git diff --output"                        'git diff --output=d.txt # gh pr create' warn

echo "an option that runs a program -> edges"
check "printf with -v and a name attached"       $'printf -vx \'%s\' \'gh pr create\'' warn
check "test -n"                                  $'test -n \'gh pr create\'' allow
check "test with an option that holds v"         $'test -nv \'gh pr create\'' warn
check "diff -u"                                  $'diff -u a.md b.md | grep \'gh pr create\'' allow
check "diff -l"                                  $'diff -l a.md b.md | grep \'gh pr create\'' warn
check "diff with l among short options"          $'diff -ul a.md b.md | grep \'gh pr create\'' warn
check "diff --paginate abbreviated"              $'diff --pag a.md b.md | grep \'gh pr create\'' warn
check "rg --no-search-zip"                       $'rg --no-search-zip \'gh pr create\' logs' allow
check "rg -z"                                    $'rg -z \'gh pr create\' logs' warn
check "rg with z among short options"            $'rg -iz \'gh pr create\' logs' warn
check "rg --search-zip"                          $'rg --search-zip \'gh pr create\' logs' warn

echo "a glob in a word that the rules judge -> edges"
check "a quoted glob for git log"                $'git log --grep \'gh pr create\' -- \'*.md\'' allow
check "a glob for git log"                       $'git log --grep \'gh pr create\' -- *.md' warn
check "a glob for the directory of git -C"       $'git -C [r]epo log --grep \'gh pr create\'' warn
check "a glob for diff"                          $'diff -u a.md ?.md | grep \'gh pr create\'' warn
check "a glob for uniq"                          $'grep \'gh pr create\' notes.md | uniq -c ?' warn
check "a glob for xxd"                           $'xxd -c8 *.bin # gh pr create' warn

echo "gh: only the listed commands, right after the group -> edges"
check "gh issue view"                            'gh issue view 5 --comments # gh pr create' allow
check "gh search prs"                            $'gh search prs \'gh pr create\'' allow
check "gh release view"                          'gh release view v1 # gh pr create' allow
check "gh pr new, the alias of create"           'gh pr new --body nope # gh pr create' warn
check "gh pr revert, which opens a pull request" 'gh pr revert 5 --body nope # gh pr create' warn
check "gh api"                                   $'gh api repos/o/r/pulls -f head=x -f base=main -f title=\'gh pr create\'' warn
check "gh release download"                      'gh release download v1 -D .git/hooks # gh pr create' warn
check "gh run download"                          'gh run download 5 -D .git # gh pr create' warn
check "gh pr checkout"                           'gh pr checkout 5 # gh pr create' warn
check "gh issue develop"                         'gh issue develop 5 --checkout # gh pr create' warn
check "gh issue artifact download"               'gh issue artifact download 5 # gh pr create' warn
check "gh pr with an option before view"         'gh pr -R o/r view 5 # gh pr create' warn
check "gh pr with no command"                    'gh pr # gh pr create' warn
check "gh pr view with a later word create"      'gh pr view create # gh pr create' warn
check "gh issue view with a later word create"   'gh issue view create # gh pr create' allow

echo "a command taken out of the language -> warn"
check "file"                                     'file notes.md # gh pr create' warn
check "egrep"                                    $'egrep -n \'gh pr create\' notes.md' warn
check "fgrep"                                    $'fgrep -n \'gh pr create\' notes.md' warn
check "grep -E, which replaces egrep"            $'grep -En \'gh pr create\' notes.md' allow
check "jq, whose filter can load files as code"  $'gh pr view 7 --json body | jq -r .body | grep -c \'gh pr create\'' warn
check "jq with a filter that includes a module"  $'jq -n \'include "notes"; .\' # gh pr create' warn
check "jq reading its filter from a file"        $'jq -f filter.jq notes.json # gh pr create' warn

echo "codex's fourth review: sed runs a command that its script gives -> checked"
c=$'sed -n \'1e gh pr create --body nope\' <<\'EOF\'\nx\nEOF'
check                   "sed's e command"                       "$c" block
check_runs_with_gnu_sed "sed's e command"                       "$c"
c=$'sed -n \'s/^.*$/gh pr create --body nope/e\' <<\'EOF\'\nx\nEOF'
check                   "the e flag of sed's s"                 "$c" block
check_runs_with_gnu_sed "the e flag of sed's s"                 "$c"
check "the same text as a pattern of grep"       $'grep -n \'1e gh pr create --body nope\' notes.md' allow
check "the same text through head"               $'head -n 1 <<\'EOF\'\n1e gh pr create --body nope\nEOF' allow

echo "codex's fifth review: printf's %n sets PATH for the next command -> checked"
c=$'printf \'%n\' PATH; cat \'gh pr create\''
check              "printf %n sets PATH, then cat runs from 0/"  "$c" warn
check_runs_program "printf %n sets PATH, then cat runs from 0/"  fixture_program_in_directory_0 "$c"
check              "printf %n with a flag and a width"           $'printf \'%-3n\' PATH; cat \'gh pr create\'' warn
check              "the same words through echo"                 $'echo \'%n\' PATH; cat \'gh pr create\'' allow

echo "printf is not in the language: forms that passed before -> checked"
check "printf with a format"                     $'printf \'%s\\n\' \'gh pr create\'' warn
check "printf with -- before the format"         $'printf -- \'%s\\n\' \'gh pr create\'' warn
check "printf into a file, twice"                $'printf \'gh pr create\\n\' > notes.md; printf \'done\\n\' >> notes.md' warn
check "printf piped into tee"                    $'printf \'gh pr create\\n\' | tee notes.md' warn
check "printf feeding xxd, then git"             $'printf \'gh pr create\' | xxd -c8 -g1; git status' warn

echo "sed is not in the language: forms that passed before -> checked"
check "sed printing matches"                     $'sed -n \'/gh pr create/p\' notes.md' warn
check "sed printing matches, then git"           $'sed -n \'/gh pr create/p\' notes.md; git status' warn
check "sed writing with w, and nothing else"     $'sed -n \'/gh pr create/w hits.txt\' notes.md' warn
check "sed editing in place, and nothing else"   "sed -i 's/x/gh pr create/' notes.md"                     warn
check "sed editing in place, then git"           "sed -i 's/x/gh pr create/' notes.md; git diff"           warn
check "sed -ni editing in place, then git"       "sed -ni '/gh pr create/p' notes.md; git diff"            warn
check "sed with w in its script, then git"       $'sed -n \'/gh pr create/w hits.txt\' notes.md; git status' warn
check "sed with W in its script, then git"       $'sed -n \'/gh pr create/W hits.txt\' notes.md; git status' warn
check "sed with -f, then git"                    $'sed -f edit.sed notes.md; git log --grep \'gh pr create\'' warn
check "sed with -f among short options, then git" $'sed -nf edit.sed notes.md; git log --grep \'gh pr create\'' warn
check "sed with --file, then git"                $'sed --file=edit.sed notes.md; git log --grep \'gh pr create\'' warn
check "sed with --in-place abbreviated, then git" $'sed --i \'s/x/gh pr create/\' notes.md; git diff' warn
check "sed with the -I of BSD sed, then git"     $'sed -I \'\' \'s/x/gh pr create/\' notes.md; git diff' warn
check "a glob for sed"                           $'sed -n \'/gh pr create/p\' *.md' warn

echo "a command that writes a file and also runs git or gh -> checked"
check "a hook written, then a commit"     $'cp .git/hooks/pre-commit.sample .git/hooks/pre-commit\ncat > .git/hooks/pre-commit <<\'EOF\'\ngh pr create --body nope\nEOF\ngit commit -m x' block
check "a config line appended, then git status" $'cat >> .git/config <<\'EOF\'\n[core]\n  fsmonitor = gh pr create --body nope\nEOF\ngit status' block
check "a file written, then git add"      $'cat > notes.md <<\'EOF\'\nrun gh pr create next\nEOF\ngit add notes.md'  warn
check "git first, then a file written"    $'git status\ncat > notes.md <<\'EOF\'\nrun gh pr create next\nEOF'      warn
check "tee writes, then gh"               "echo 'gh pr create' | tee notes.md; gh issue list"                     warn
check "sort writes its output, then git"  "sort -o notes.md notes.md; git log --grep='gh pr create'"              warn
check "stderr to a file, then git"        "grep -rn 'gh pr create' . 2> errors.txt; git status"                   warn
check "cp, then git"                      "cp a b; git log --grep='gh pr create'"                                 warn

echo "a command that only writes, or only runs git or gh -> allow"
check "a file written, nothing else"      $'cat > notes.md <<\'EOF\'\nrun gh pr create next\nEOF'                   allow
check "sort writes its output, nothing else" "sort -o notes.md notes.md # gh pr create"                           allow
check "git only, stderr joined to stdout" "git log --grep='gh pr create' 2>&1 | head -3"                          allow
check "gh only"                           'gh issue comment 5 --body "use gh pr create --fill"'                   allow

echo "not this hook's business -> allow"
check "a git commit mentioning an issue"  "git commit -m 'Closes #201'"                                 allow
check "gh pr view"                        "gh pr view 728"                                              allow

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
