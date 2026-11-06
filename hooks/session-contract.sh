#!/bin/sh
# SessionStart hook (agent-harness plugin): injects the session contract as context. A CLAUDE.md inside a
# plugin is not loaded, so the contract that nix appends to each global CLAUDE.md is delivered this way.
# Prints the fragment body (frontmatter stripped) as SessionStart additionalContext. Always exits 0.
set -u
root=${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}
fragment="$root/fragments/session-contract.md"
[ -r "$fragment" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } fm { next } !started && $0 == "" { next } { started = 1; print }' "$fragment" |
  jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
exit 0
