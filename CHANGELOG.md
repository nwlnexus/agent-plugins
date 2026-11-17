# Changelog

## Releasing

1. Bump `version` in `.claude-plugin/plugin.json` and add an entry below.
2. Merge the PR, then on updated `main`: `claude plugin tag --push`
   (creates and pushes `agent-harness--v<version>`; use `--dry-run` first).

## 0.4.0

- New skill `batch-in-code`: fold many related, mechanical tool calls into one Bash script that prints a short,
  bounded result, and put independent MCP, subagent and file calls in one message. It gets most of Code Mode's
  benefit without Code Mode, which can't run with Remote Control or OpenTelemetry export on, under `-p` or in cloud
  sessions. Outward and destructive steps (push, merge, deploy, delete, remote writes) stay separate tool calls so
  permission rules, hooks and the auto-mode classifier review each one. Includes a dry-run and verify procedure for
  bulk edits, and examples that were run before release.

## 0.3.0

- Session contract: also injected into every subagent by a new `SubagentStart` hook (no matcher, so all agent
  types). `hooks/session-contract.sh` takes the event name as its first argument and sets `hookEventName` to
  `SubagentStart` or `SessionStart`; the SessionStart output is unchanged. Costs about 3.5 KB of context
  (roughly 900 tokens) per subagent start.

## 0.2.0

- `long-task`: the Plan carries a **Blast radius** section in repos with a GitNexus index (`impact` upstream,
  depth 2 or more, or the `gitnexus-plan` skill: d=1 dependents, affected processes, risk; HIGH/CRITICAL called out
  before work starts), or one line `Blast radius: no index (<reason>)`. The work loop logs a `detect_changes` row
  before each code commit. The progress template gains the `### Blast radius` subsection.
- `claim-verifier`: for a code change in an indexed repo, requires a `detect_changes` Evidence row whose scope
  matches the diff, and fails when it is missing or HIGH/CRITICAL risk is unaddressed.
- New hook `detect-changes-reminder` (PreToolUse, Bash): warns, never blocks, at `git commit` in an indexed repo
  when the session ran no `detect_changes` since the last commit.

## 0.1.1

- Session contract: memory ownership rule (three stores, one owner each, one-way proposals into the wiki inbox).

## 0.1.0

- First release of the `agent-harness` plugin.
