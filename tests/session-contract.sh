#!/bin/sh
# Behaviour tests for hooks/session-contract.sh (the SessionStart and SubagentStart hook that injects the
# session contract).
#   sh tests/session-contract.sh      (needs jq; run by scripts/validate-skills.sh)
set -u
here=$(cd "$(dirname "$0")" && pwd)
root="$here/.."
hook="$root/hooks/session-contract.sh"
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

out=$(echo '{}' | CLAUDE_PLUGIN_ROOT="$root" sh "$hook")
status=$?
check "exits 0" [ "$status" -eq 0 ]
is_session_start() { printf %s "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null; }
starts_at_heading() { case "$ctx" in "## Session contract"*) return 0 ;; *) return 1 ;; esac; }
no_frontmatter() { case "$ctx" in *"target: global CLAUDE.md"*) return 1 ;; *) return 0 ;; esac; }
check "emits SessionStart hookSpecificOutput" is_session_start
ctx=$(printf %s "$out" | jq -r '.hookSpecificOutput.additionalContext')
check "context starts at the contract heading" starts_at_heading
check "frontmatter is stripped" no_frontmatter
body_lines=$(grep -c '^## \|^- ' "$root/fragments/session-contract.md")
ctx_lines=$(printf '%s\n' "$ctx" | grep -c '^## \|^- ')
check "whole fragment body is injected" [ "$ctx_lines" -eq "$body_lines" ]

session_ctx=$ctx
out=$(echo '{"hook_event_name":"SubagentStart","agent_type":"Explore"}' | CLAUDE_PLUGIN_ROOT="$root" sh "$hook" SubagentStart)
status=$?
check "SubagentStart: exits 0" [ "$status" -eq 0 ]
is_subagent_start() { printf %s "$out" | jq -e '.hookSpecificOutput.hookEventName == "SubagentStart"' >/dev/null; }
check "SubagentStart: emits SubagentStart hookSpecificOutput" is_subagent_start
ctx=$(printf %s "$out" | jq -r '.hookSpecificOutput.additionalContext')
check "SubagentStart: same context as SessionStart" [ "$ctx" = "$session_ctx" ]

out=$(echo '{}' | CLAUDE_PLUGIN_ROOT="$root" sh "$hook" Bogus)
check "unknown event argument: falls back to SessionStart" is_session_start

mkdir -p "$tmp/empty"
out=$(echo '{}' | CLAUDE_PLUGIN_ROOT="$tmp/empty" sh "$hook")
status=$?
check "missing fragment: exits 0" [ "$status" -eq 0 ]
check "missing fragment: prints nothing" [ -z "$out" ]

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
