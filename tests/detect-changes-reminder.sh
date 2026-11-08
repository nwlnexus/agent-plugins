#!/bin/sh
# Behaviour tests for hooks/detect-changes-reminder.sh (the PreToolUse hook that reminds about detect_changes).
#   sh tests/detect-changes-reminder.sh        (needs git and jq; run by scripts/validate-skills.sh)
set -u
here=$(cd "$(dirname "$0")" && pwd)
hook="$here/../hooks/detect-changes-reminder.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
check() { # name, command...
  name=$1
  shift
  if "$@"; then ok "$name"; else bad "$name"; fi
}
if ! command -v jq >/dev/null 2>&1; then
  echo "note: jq not found; the hook is silent without it, skipping behaviour tests"
  exit 0
fi
# run_hook <json>: stdout of the hook; exit status in $tmp/status, stderr in $tmp/stderr.
run_hook() {
  out=$(printf '%s' "$1" | sh "$hook" 2>"$tmp/stderr")
  echo $? >"$tmp/status"
  printf '%s' "$out"
}
status() { cat "$tmp/status"; }
# iso <seconds offset from now>: an ISO-8601 UTC timestamp with milliseconds, as Claude Code writes them.
iso() {
  ts=$(($(date +%s) + $1))
  date -u -d "@$ts" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -r "$ts" +%Y-%m-%dT%H:%M:%S.000Z
}
# input <cwd> <command> [transcript]: a PreToolUse hook payload for a Bash call.
input() {
  jq -nc --arg cwd "$1" --arg cmd "$2" --arg tp "${3:-$transcript}" \
    '{session_id: "s", transcript_path: $tp, cwd: $cwd, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $cmd}}'
}
# mcp_line <offset>, cli_line <offset>, mention_line <offset>: transcript lines in Claude Code's JSONL shape.
mcp_line() {
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"mcp__gitnexus__detect_changes","input":{"scope":"staged"}}]},"timestamp":"%s"}\n' "$(iso "$1")"
}
cli_line() {
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"npx gitnexus detect-changes --scope staged"}}]},"timestamp":"%s"}\n' "$(iso "$1")"
}
mention_line() { # text that names the tool without calling it (a deferred tool list, a prose mention)
  printf '{"type":"attachment","attachment":{"names":["mcp__gitnexus__detect_changes"]},"timestamp":"%s"}\n' "$(iso "$1")"
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t3","name":"Edit","input":{"new_string":"run gitnexus detect-changes first"}}]},"timestamp":"%s"}\n' "$(iso "$1")"
}
reminds() { printf '%s' "$1" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and (.hookSpecificOutput.additionalContext | contains("detect_changes"))' >/dev/null 2>&1; }
no_decision() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == null and .decision == null' >/dev/null 2>&1; }

repo="$tmp/repo"
mkdir -p "$repo/.gitnexus" "$repo/src"
git -C "$repo" init -q
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
transcript="$tmp/session.jsonl"
: >"$transcript"

# 1. indexed repo, no detect_changes in the transcript: reminder, no decision, exit 0
out=$(run_hook "$(input "$repo" 'git commit -m "feat: x"')")
check "no call: exits 0" [ "$(status)" = 0 ]
check "no call: reminder as PreToolUse additionalContext" reminds "$out"
check "no call: never sets a permission decision" no_decision "$out"
check "no call: names the last commit" [ -n "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep 'since the last commit')" ]
check "no call: nothing on stderr" [ ! -s "$tmp/stderr" ]

# 2. mentions of the tool name that are not calls do not count
mention_line 60 >>"$transcript"
out=$(run_hook "$(input "$repo" 'git commit -m x')")
check "mentions only: still reminds" reminds "$out"

# 3. an MCP detect_changes call after the last commit: silent
mcp_line 60 >>"$transcript"
out=$(run_hook "$(input "$repo" 'git commit -m x')")
check "MCP call after commit: silent" [ -z "$out" ]
check "MCP call after commit: exits 0" [ "$(status)" = 0 ]

# 4. a call older than the last commit does not count
: >"$transcript"
mcp_line -3600 >>"$transcript"
out=$(run_hook "$(input "$repo" 'git commit -m x')")
check "call before last commit: reminds" reminds "$out"

# 5. the CLI form in a Bash call counts
cli_line 60 >>"$transcript"
out=$(run_hook "$(input "$repo" 'git commit -m x')")
check "CLI call after commit: silent" [ -z "$out" ]

# 6. a call in a subagent transcript of the same session counts; and a subagent's hook sees the parent's call
: >"$transcript"
mkdir -p "$tmp/session/subagents"
mcp_line 60 >"$tmp/session/subagents/agent-a.jsonl"
out=$(run_hook "$(input "$repo" 'git commit -m x')")
check "call in a subagent transcript: silent" [ -z "$out" ]
: >"$tmp/session/subagents/agent-a.jsonl"
mcp_line 60 >>"$transcript"
out=$(run_hook "$(input "$repo" 'git commit -m x' "$tmp/session/subagents/agent-a.jsonl")")
check "subagent hook, call in the parent transcript: silent" [ -z "$out" ]
: >"$transcript"

# 7. command forms: -C <dir>, leading cd, -c key=value, chained commands
out=$(run_hook "$(input "$tmp" "git -C $repo commit -m x")")
check "git -C <repo> commit from outside: reminds" reminds "$out"
out=$(run_hook "$(input "$tmp" "cd $repo && git add -A && git commit -m x")")
check "cd <repo> && git commit: reminds" reminds "$out"
out=$(run_hook "$(input "$repo" 'git -c core.hooksPath=/dev/null commit -m x')")
check "git -c k=v commit: reminds" reminds "$out"
out=$(run_hook "$(input "$repo/src" 'git commit --amend --no-edit')")
check "subdirectory cwd: reminds" reminds "$out"

# 8. not a commit: silent
for c in 'git status' 'git log --oneline -3' 'echo git commit' 'git commit-tree HEAD^{tree}' 'npm test'; do
  out=$(run_hook "$(input "$repo" "$c")")
  case $c in
    'echo git commit') check "'$c': exits 0" [ "$(status)" = 0 ] ;; # a mention may warn; it must not fail
    *) check "'$c': silent" [ -z "$out" ] ;;
  esac
done

# 9. repo without an index: silent; an index in the main checkout covers its worktrees
plain="$tmp/plain"
mkdir -p "$plain"
git -C "$plain" init -q
git -C "$plain" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
out=$(run_hook "$(input "$plain" 'git commit -m x')")
check "no index: silent" [ -z "$out" ]
git -C "$repo" worktree add -q "$tmp/wt" -b wt-branch 2>/dev/null
out=$(run_hook "$(input "$tmp/wt" 'git commit -m x')")
check "worktree of an indexed main checkout: reminds" reminds "$out"

# 10. fail-open: missing transcript, bad JSON, empty stdin, not a repo, missing cwd dir
out=$(run_hook "$(input "$repo" 'git commit -m x' "$tmp/missing.jsonl")")
check "missing transcript: silent" [ -z "$out" ]
check "missing transcript: exits 0" [ "$(status)" = 0 ]
out=$(run_hook 'not json at all')
check "bad JSON: silent" [ -z "$out" ]
check "bad JSON: exit 0" [ "$(status)" = 0 ]
out=$(run_hook '')
check "empty stdin: exit 0" [ "$(status)" = 0 ]
mkdir -p "$tmp/norepo"
out=$(run_hook "$(input "$tmp/norepo" 'git commit -m x')")
check "not a git repo: silent" [ -z "$out" ]
out=$(run_hook "$(input /nonexistent/dir 'git -C /nonexistent/dir commit -m x')")
check "missing dir: exit 0" [ "$(status)" = 0 ]

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
