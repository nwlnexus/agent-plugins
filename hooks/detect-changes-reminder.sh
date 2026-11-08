#!/bin/sh
# PreToolUse hook (matcher Bash): remind the session to run GitNexus detect_changes before `git commit`.
#
# Reads the PreToolUse hook JSON on stdin (`tool_input.command`, `cwd`, `transcript_path`). When the command is a
# `git commit` in a repository with a GitNexus index (`.gitnexus/` in the work tree or in the main checkout) and
# the session transcript shows no detect_changes call (MCP tool `mcp__*gitnexus*__detect_changes`, or a Bash
# command running `gitnexus detect-changes` / `detect_changes`) since the repository's last commit, it prints
#   {"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "<reminder>"}}
# and prints nothing otherwise. It never sets a permission decision and always exits 0, so it cannot block the
# commit: the reminder is information only. Fail-open: anything it cannot read or parse means silence.
#
# The transcript scan covers the session transcript, its subagent transcripts (<session>/subagents/*.jsonl), and
# the parent transcript when the hook runs inside a subagent. Needs jq and git; silent without them.
# Portable: POSIX sh, GNU or BSD userland.
set -u
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null || true)
[ -n "$input" ] || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# Only `git commit`, optionally with `-C <dir>` / `-c <key=value>` before the subcommand.
printf '%s\n' "$cmd" |
  grep -Eq '(^|[;&|(`[:space:]])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)' ||
  exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd=$PWD
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$tp" ] && [ -r "$tp" ] || exit 0

# unquote <word>: strip one pair of surrounding quotes and expand a leading ~/.
unquote() {
  w=$1
  case $w in \"*\") w=${w#\"} w=${w%\"} ;; \'*\') w=${w#\'} w=${w%\'} ;; esac
  # shellcheck disable=SC2088 # matching a literal ~ on purpose, to expand it ourselves
  case $w in "~/"*) w=$HOME/${w#"~/"} ;; "~") w=$HOME ;; esac
  printf '%s' "$w"
}
# resolve <dir> <base>: an absolute path for dir, relative to base when it is relative.
resolve() { case $1 in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$2" "$1" ;; esac; }

dir=$cwd
lead_cd=$(printf '%s\n' "$cmd" | sed -n '1s/^[[:space:]]*cd[[:space:]]\{1,\}\([^[:space:];&|]\{1,\}\).*/\1/p')
[ -n "$lead_cd" ] && dir=$(resolve "$(unquote "$lead_cd")" "$dir")
git_c=$(printf '%s\n' "$cmd" | sed -n 's/.*git[[:space:]]\{1,\}-C[[:space:]]\{1,\}\([^[:space:];&|]\{1,\}\).*/\1/p' | head -n 1)
[ -n "$git_c" ] && dir=$(resolve "$(unquote "$git_c")" "$dir")
[ -d "$dir" ] || exit 0

root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$root" ] || exit 0
indexed=0
if [ -d "$root/.gitnexus" ]; then
  indexed=1
else
  common=$(cd "$root" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd) || common=
  [ -n "$common" ] && [ -d "$(dirname "$common")/.gitnexus" ] && indexed=1
fi
[ "$indexed" = 1 ] || exit 0

# The last commit's committer time (0 on an unborn branch: any detect_changes in the session counts).
since=$(git -C "$root" log -1 --format=%ct 2>/dev/null) || since=0
case $since in '' | *[!0-9]*) since=0 ;; esac
head_ref=$(git -C "$root" log -1 --format=%h 2>/dev/null) || head_ref=

# Transcripts of this session: the main one, its subagents, and the parent when this is a subagent's.
set -- "$tp"
sub_dir=${tp%.jsonl}/subagents
for f in "$sub_dir"/*.jsonl; do [ -r "$f" ] && set -- "$@" "$f"; done
case $tp in
  */subagents/*.jsonl)
    parent="$(dirname "$(dirname "$tp")").jsonl"
    [ -r "$parent" ] && set -- "$@" "$parent"
    ;;
esac

# Latest timestamp of a line that holds a detect_changes tool call. ISO-8601 UTC strings sort as text.
last=$(LC_ALL=C grep -h '"type":"tool_use"' "$@" 2>/dev/null |
  LC_ALL=C grep -E '"name":"mcp__[^"]*gitnexus[^"]*__detect_changes"|"command":"[^"]*gitnexus[^"]*detect[-_]changes' |
  sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p' | sort | tail -n 1)
if [ -n "$last" ]; then
  last_s=$(jq -rn --arg t "$last" '$t | sub("\\.[0-9]+"; "") | fromdateiso8601' 2>/dev/null) || last_s=
  case $last_s in '' | *[!0-9]*) exit 0 ;; esac
  [ "$last_s" -ge "$since" ] && exit 0
fi

if [ "$since" = 0 ]; then
  when="in this session"
else
  when="since the last commit ($head_ref)"
fi
msg="Reminder (detect-changes-reminder hook): this repository ($root) has a GitNexus index, and no detect_changes call shows in this session $when. Before committing a code change, run detect_changes (scope \"staged\", or \"compare\" against origin/main) to confirm the changed symbols and risk match what you intended, and log the result in the progress file's Evidence log. Docs-only commits can skip it. This is a warning; the commit is not blocked."
jq -n --arg c "$msg" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $c}}' 2>/dev/null
exit 0
