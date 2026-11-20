#!/usr/bin/env bash
# PreToolUse hook for Bash commands that run "gh pr create".
# Reads the tool use input from stdin and checks that the PR body
# contains a "Fixes #N" closing keyword. A command is let through unchecked
# only when only_mentions_pr_create recognizes it as a plain command of a
# short list of tools that does not create a pull request. Every other
# command that contains "gh pr create" is checked.

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

# Refuse the command: the body was read, and it has no closing keyword.
deny_missing() {
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "PR body is missing a closing keyword (Fixes #N, Closes #N, or Resolves #N). Add one to auto-close the linked GitHub issue on merge."
    }
  }'
  exit 0
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

# Tells whether a command only mentions "gh pr create": the whole command is
# a sentence of the small language below, and none of its simple commands
# creates a pull request. The language holds only plainly harmless commands.
# The function reads the command once, from left to right, and refuses at the
# first character or construct that the language does not name. It skips
# nothing that it does not know.
#
# Shape:
#
# - The command is one or more simple commands, separated by "|", "&&",
#   "||", ";", or a newline. Newlines may also follow "|", "&&" and "||".
#   Nothing else joins commands: no "&", no "|&".
# - There is no compound command and no grouping. "(", ")", "{" and "}" are
#   refused outside quotes. A shell keyword ("if", "for", "!", "time", and the
#   others) is never a command name, because no keyword is in the list of
#   command names below.
# - A comment is an unquoted "#" at the start of a word. It runs to the end
#   of its line.
# - A simple command is a command name, then words, with redirections among
#   the words. Nothing comes before the command name: no assignment, and no
#   redirection.
#
# Words:
#
# A word is one or more of these segments, written next to each other. Its
# value is the segments' texts joined.
#
# - Bare text: only the characters A-Z a-z 0-9 and
#   _ @ % + = : , . / - * ? ^ ~ [ ].
# - A single-quoted string: '...'. Its text is everything between the
#   quotes, newlines included.
# - A double-quoted string: "...". It contains no "$" and no backtick, and
#   no backslash in it is followed by "$", a backtick, a double quote,
#   another backslash, or a newline. Its text is everything between the
#   quotes.
#
# Outside single quotes, "$" is refused (with the one exception below), and
# so are a backtick, a backslash outside double quotes, $'...', and $"...".
# A word that ends where "<" or ">" begins is refused when it is only digits,
# because the shell reads those digits as a file descriptor.
#
# Redirections:
#
# Only these: "> word", ">> word", "2> word", "2>> word", "< word", "2>&1",
# and a heredoc <<'DELIM'. The delimiter of a heredoc is one single-quoted
# name of letters, digits and "_", written right after "<<", with nothing
# attached to it. The heredoc's body is the lines after the opener's line,
# up to a line that is exactly the delimiter. The body is plain text. A line
# opens at most one heredoc. Every other heredoc form (<<EOF, <<-, <<"EOF", a
# partly quoted delimiter), a here-string, a process substitution, and every
# ">&" or "<&" other than "2>&1" are refused.
#
# The one exception for "$":
#
# A word may be exactly the text below, and only as an argument of
# "git commit": a double quote and $(cat <<'DELIM', a newline, the lines of
# a body, a line that is exactly the delimiter, and a line that is exactly
# a closing parenthesis and a double quote. This is how a commit message is
# usually written. Nothing else may be inside the substitution.
#
#     "$(cat <<'DELIM'
#     ...lines...
#     DELIM
#     )"
#
# A line of the body may not contain "(", ")", a single quote, a double
# quote, a backtick, a backslash, or "$". Bash 3.2 finds the end of "$(" by
# matching parentheses and quotes in the raw text, not by parsing the
# heredoc. With such a character in the body it can end the substitution
# inside the body, and then it runs the rest of the body as commands.
#
# Command names:
#
# The command name is a bare word, without "=", and one of:
#
# - ": [ basename cat cd cmp column comm cp cut date df diff dirname du echo
#   egrep false fgrep file fold grep head jq ls mkdir mv nl paste printf pwd
#   readlink realpath rev rg rm sed sleep sort stat tac tail tee test touch
#   tr true uniq wc xxd", with these refusals, judged on the values of the
#   command's words:
#   - printf, test and [: a word whose value is "-v". With -v these builtins
#     evaluate an array subscript in a variable name, and that evaluation
#     runs a command substitution written in the subscript.
#   - sort: a word whose value begins with "--co" (--compress-program, or an
#     abbreviation of it).
#   - rg: a word whose value begins with "--pre" or "--hostname-bin".
# - git, in the form "git [-C <dir>] <subcommand> ...". The subcommand is
#   one of "add commit diff grep log notes show status tag", and nothing else
#   stands before it. For "git grep", a word is refused when its value begins
#   with "--op" (--open-files-in-pager), or begins with a single "-" and
#   contains "O".
# - gh, in the form "gh <group> ...". The group is one of "api issue label pr
#   release run search workflow". A word whose value is "--" is refused.
#
# The refusals above judge a word by its value, and the shell expands a bare
# "*", "?" or "[" into the names of files. A file can be named "-v" or
# "-Osh". So a word of printf, test, [, sort, sed, xxd, rg, git grep, or gh
# is refused when one of its bare text segments contains "*", "?" or "[".
#
# These lists are the whole lists. declare, local, export, read, unset, eval,
# the shells, env, xargs, and every other command are not in the language.
#
# GNU sed's "e" command and the "e" flag of its "s" command run a command.
# This function does not look for them, and accepts that limit.
#
# Writing a file, and git or gh, in one command:
#
# git and gh run programs that their files name: a hook in ".git/hooks", an
# editor, a pager, or a file-system monitor in a configuration file. A
# command of this language could write such a file, with the words in it,
# and then run git. So a command that writes a file and also runs git or gh
# is refused. A command writes a file when it has one of these:
#
# - a redirection of output: ">", ">>", "2>", or "2>>" ("2>&1" writes no
#   file);
# - one of the commands cp, mv, rm, mkdir, touch, tee;
# - sed with a word that begins with "--in", or that begins with a single
#   "-" and contains "i" (edit in place);
# - sort with a word that begins with "--o", or that begins with a single
#   "-" and contains "o" (the output file);
# - xxd with a word that begins with a single "-" and contains "r".
#
# Creating a pull request: a gh command whose group is "pr", and which has a
# later word whose value is "create", creates a pull request or may create
# one. The later word need not come right after "pr", because an option such
# as "-R owner/repo" may stand between them.
#
# Preconditions: none.
#
# Inputs: $1 is the text of a shell command.
#
# Output: succeeds when the command is a sentence of the language and none of
# its simple commands creates a pull request. Fails otherwise.
#
# Side effects: none.
only_mentions_pr_create() {
  local LC_ALL=C
  local cmd=$1
  local n=${#cmd} i=0 c rest seg line delim word bare glob ending
  local data_names=' : [ basename cat cd cmp column comm cp cut date df diff dirname du echo egrep false fgrep file fold grep head jq ls mkdir mv nl paste printf pwd readlink realpath rev rg rm sed sleep sort stat tac tail tee test touch tr true uniq wc xxd '
  local git_subcommands=' add commit diff grep log notes show status tag '
  local gh_groups=' api issue label pr release run search workflow '
  # need_command: a command must come next, after "|", "&&" or "||".
  # in_command: the name of the current simple command has been read.
  # redirect_target: the next word names the file of a redirection.
  # heredoc: the delimiter of the heredoc whose body starts after this line.
  # creation: a simple command creates a pull request.
  local need_command=0 in_command=0 redirect_target=0 heredoc='' creation=0
  # writes: a simple command writes a file. uses_git: a simple command is git
  # or gh.
  local writes=0 uses_git=0
  # The current simple command: its name; for git, how far its form has been
  # read (0 nothing, 1 after -C, 2 after the directory, 3 after the
  # subcommand) and its subcommand; for gh, its group.
  local name='' git_state=0 git_sub='' gh_group=''

  while :; do
    c=${cmd:i:1}
    if [[ $c == 2 && ${cmd:i+1:1} == '>' ]] && (( in_command && ! redirect_target )); then
      c='2>'
    fi
    ending=0
    case $c in
      '') ending=1 ;;
      ' '|$'\t')
        i=$(( i + 1 ))
        continue
        ;;
      $'\n') ending=1 ;;
      '#')
        (( ! redirect_target )) || return 1
        rest=${cmd:i}
        line=${rest%%$'\n'*}
        i=$(( i + ${#line} ))
        continue
        ;;
      ';')
        (( in_command )) || return 1
        ending=1
        ;;
      '|')
        (( in_command )) || return 1
        [[ ${cmd:i+1:1} != '&' ]] || return 1
        ending=1
        ;;
      '&')
        (( in_command )) || return 1
        [[ ${cmd:i+1:1} == '&' ]] || return 1
        ending=1
        ;;
      '<'|'>'|'2>')
        (( in_command && ! redirect_target )) || return 1
        if [[ $c == '2>' ]]; then
          if [[ ${cmd:i:4} == '2>&1' ]]; then
            i=$(( i + 4 ))
            case ${cmd:i:1} in
              ''|' '|$'\t'|$'\n'|';'|'|'|'&'|'<'|'>') continue ;;
              *) return 1 ;;
            esac
          fi
          i=$(( i + 2 ))
          if [[ ${cmd:i:1} == '>' ]]; then i=$(( i + 1 )); fi
          writes=1
        elif [[ $c == '>' ]]; then
          i=$(( i + 1 ))
          if [[ ${cmd:i:1} == '>' ]]; then i=$(( i + 1 )); fi
          writes=1
        elif [[ ${cmd:i+1:1} == '<' ]]; then
          # A heredoc: <<'NAME' and nothing else.
          [[ -z $heredoc ]] || return 1
          [[ ${cmd:i+2:1} == "'" ]] || return 1
          rest=${cmd:i+3}
          [[ $rest == *"'"* ]] || return 1
          delim=${rest%%"'"*}
          [[ -n $delim && $delim != *[!A-Za-z0-9_]* ]] || return 1
          i=$(( i + 3 + ${#delim} + 1 ))
          case ${cmd:i:1} in
            ''|' '|$'\t'|$'\n'|';'|'|'|'&'|'<'|'>') ;;
            *) return 1 ;;
          esac
          heredoc=$delim
          continue
        else
          i=$(( i + 1 ))
        fi
        redirect_target=1
        continue
        ;;
    esac

    if (( ending )); then
      (( ! redirect_target )) || return 1
      if (( in_command )); then
        if [[ $name == git ]] && (( git_state != 3 )); then return 1; fi
        if [[ $name == gh && -z $gh_group ]]; then return 1; fi
        in_command=0 name='' git_state=0 git_sub='' gh_group=''
      fi
      case $c in
        '')
          (( ! need_command )) || return 1
          [[ -z $heredoc ]] || return 1
          (( ! (writes && uses_git) )) || return 1
          return $creation
          ;;
        $'\n')
          i=$(( i + 1 ))
          if [[ -n $heredoc ]]; then
            # The body runs up to a line that is exactly the delimiter.
            while :; do
              (( i < n )) || return 1
              rest=${cmd:i}
              line=${rest%%$'\n'*}
              i=$(( i + ${#line} + 1 ))
              [[ $line != "$heredoc" ]] || break
              [[ $rest == *$'\n'* ]] || return 1
            done
            if (( i > n )); then i=$n; fi
            heredoc=''
          fi
          ;;
        ';')
          i=$(( i + 1 ))
          need_command=0
          ;;
        '|')
          if [[ ${cmd:i+1:1} == '|' ]]; then i=$(( i + 2 )); else i=$(( i + 1 )); fi
          need_command=1
          ;;
        '&')
          i=$(( i + 2 ))
          need_command=1
          ;;
      esac
      continue
    fi

    # A word: one or more segments, then a character that ends the word.
    # bare: every segment is bare text. glob: a bare segment holds "*", "?"
    # or "[".
    word='' bare=1 glob=0
    while :; do
      c=${cmd:i:1}
      case $c in
        [A-Za-z0-9]|_|@|%|+|=|:|,|.|/|-|^|~|\])
          word+=$c
          i=$(( i + 1 ))
          ;;
        \*|\?|\[)
          word+=$c glob=1
          i=$(( i + 1 ))
          ;;
        "'")
          rest=${cmd:i+1}
          [[ $rest == *"'"* ]] || return 1
          seg=${rest%%"'"*}
          word+=$seg bare=0
          i=$(( i + ${#seg} + 2 ))
          ;;
        '"')
          if [[ -z $word && $bare == 1 && ${cmd:i:10} == "\"\$(cat <<'" ]]; then
            # The commit message: the whole word, as an argument of git
            # commit, on a line that opens no other heredoc.
            [[ $name == git && $git_state == 3 && $git_sub == commit ]] || return 1
            (( ! redirect_target )) || return 1
            [[ -z $heredoc ]] || return 1
            rest=${cmd:i+10}
            [[ $rest == *"'"* ]] || return 1
            delim=${rest%%"'"*}
            [[ -n $delim && $delim != *[!A-Za-z0-9_]* ]] || return 1
            i=$(( i + 10 + ${#delim} + 1 ))
            [[ ${cmd:i:1} == $'\n' ]] || return 1
            i=$(( i + 1 ))
            while :; do
              (( i < n )) || return 1
              rest=${cmd:i}
              [[ $rest == *$'\n'* ]] || return 1
              line=${rest%%$'\n'*}
              i=$(( i + ${#line} + 1 ))
              [[ $line != "$delim" ]] || break
              case $line in
                *'('*|*')'*|*"'"*|*'"'*|*'`'*|*'\'*|*'$'*) return 1 ;;
              esac
            done
            [[ ${cmd:i:2} == ')"' ]] || return 1
            i=$(( i + 2 ))
            [[ -z ${cmd:i:1} || ${cmd:i:1} == $'\n' ]] || return 1
            word+='commit message' bare=0
            continue
          fi
          rest=${cmd:i+1}
          [[ $rest == *'"'* ]] || return 1
          seg=${rest%%'"'*}
          case $seg in
            *'$'*|*'`'*|*'\\'*|*\\$'\n'*|*\\) return 1 ;;
          esac
          word+=$seg bare=0
          i=$(( i + ${#seg} + 2 ))
          ;;
        *) break ;;
      esac
    done
    [[ -n $word || $bare == 0 ]] || return 1
    case $c in
      ''|' '|$'\t'|$'\n'|';'|'|'|'&') ;;
      '<'|'>') [[ $bare == 0 || $word == *[!0-9]* ]] || return 1 ;;
      *) return 1 ;;
    esac

    if (( redirect_target )); then
      redirect_target=0
      continue
    fi

    if (( ! in_command )); then
      (( bare )) || return 1
      [[ $word != *=* ]] || return 1
      [[ $word == git || $word == gh || $data_names == *" $word "* ]] || return 1
      in_command=1 name=$word need_command=0
      case $word in
        cp|mv|rm|mkdir|touch|tee) writes=1 ;;
        git|gh) uses_git=1 ;;
      esac
      continue
    fi

    case $name in
      git)
        case $git_state in
          0)
            if [[ $word == -C ]]; then
              git_state=1
            elif [[ $word != *[!a-z]* && $git_subcommands == *" $word "* ]]; then
              git_state=3 git_sub=$word
            else
              return 1
            fi
            ;;
          1) git_state=2 ;;
          2)
            [[ -n $word && $word != *[!a-z]* && $git_subcommands == *" $word "* ]] || return 1
            git_state=3 git_sub=$word
            ;;
          3)
            if [[ $git_sub == grep ]]; then
              (( ! glob )) || return 1
              [[ $word != --op* ]] || return 1
              [[ $word != -* || $word == --* || $word != *O* ]] || return 1
            fi
            ;;
        esac
        ;;
      gh)
        (( ! glob )) || return 1
        [[ $word != -- ]] || return 1
        if [[ -z $gh_group ]]; then
          [[ -n $word && $word != *[!a-z]* && $gh_groups == *" $word "* ]] || return 1
          gh_group=$word
        elif [[ $gh_group == pr && $word == create ]]; then
          creation=1
        fi
        ;;
      printf|test|'[')
        (( ! glob )) || return 1
        [[ $word != -v ]] || return 1
        ;;
      sort)
        (( ! glob )) || return 1
        [[ $word != --co* ]] || return 1
        if [[ $word == --o* ]] || [[ $word == -* && $word != --* && $word == *o* ]]; then writes=1; fi
        ;;
      sed)
        (( ! glob )) || return 1
        if [[ $word == --in* ]] || [[ $word == -* && $word != --* && $word == *i* ]]; then writes=1; fi
        ;;
      xxd)
        (( ! glob )) || return 1
        if [[ $word == -* && $word != --* && $word == *r* ]]; then writes=1; fi
        ;;
      rg)
        (( ! glob )) || return 1
        [[ $word != --pre* && $word != --hostname-bin* ]] || return 1
        ;;
    esac
  done
}

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
tool_input=$(echo "$input" | jq -r '.tool_input.command // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

# Only check gh pr create commands
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi
if [[ "$tool_input" != *"gh pr create"* ]]; then
  exit 0
fi

# Some commands only mention "gh pr create": a search for the words, a file
# written from a quoted heredoc, a commit message. Such a command passes here
# when it is a plain command of the short list of tools that
# only_mentions_pr_create accepts. Every other command that contains the
# words is checked below, as a pull request would be.
if only_mentions_pr_create "$tool_input"; then
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
            deny_missing
          fi
          cannot_check "the body is read from stdin"
        fi

        # The shell expands these before gh sees the path, and this script
        # does not: the path as written here names no file. In single quotes
        # they are part of the name. In double quotes a ~ is too.
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
          cannot_check "the body file path $arg holds a shell variable, a command substitution, or a ~, and this check does not expand them. The body may well have the keyword. Write the path out in full to have it checked"
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
    deny_missing
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
