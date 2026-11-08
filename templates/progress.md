# Progress: <owner/repo>#<issue> <issue title>

<!--
Created by the long-task skill. Path: docs/progress/<yyyy-mm-dd>-<issue>-<slug>.md on the task branch.
Committed with the work; removed in the final commit before merge, its summary moved into the PR body.
This file is the resume point: a session that resumes, compacts or picks the task up on another day reads it first.
Keep it short and factual. No secrets or token values.
-->

- **Issue:** `https://github.com/<owner>/<repo>/issues/<issue>`
- **Branch / worktree:** `<type>/<issue>-<slug>` in `<worktree path>`
- **Session:** `<account>-<repo>-<issue>` on `<host>`; registry id `<memory fact id | none: memory MCP absent>`
- **Started:** <yyyy-mm-dd hh:mm tz> · **Turn cap:** <N>
- **Draft PR:** <url | not yet>

## Goal

<!-- The /goal condition, verbatim, exactly as set (or as handed to the owner to set). -->

```text
<Done-when from the issue>. Checks: <command 1> <expected>; <command 2> <expected>. Or stop after <N> turns.
```

## Done-when checks

<!-- One row per check in the Goal. The claim-verifier re-runs every command in this table, from the worktree root. -->

| # | Check (command) | Expected result | Last result | Commit |
| --- | --- | --- | --- | --- |
| 1 | `<command>` | <exit 0 / output contains ...> | <not run / PASS / FAIL: line> | <sha> |

## Plan

### Blast radius

<!--
Repo with a GitNexus index (.gitnexus/ present, or the gitnexus MCP list_repos lists it): one row per symbol or
file the plan changes, from `impact` (direction upstream, maxDepth >= 2) or the gitnexus-plan skill. Name every
HIGH or CRITICAL target in Decisions with how the plan contains it, before work starts.
No index: replace the table with one line: Blast radius: no index (<reason>).
-->

| Target (symbol or file) | d=1 dependents | Affected processes | Risk |
| --- | --- | --- | --- |
| `<symbol>` | <callers / importers> | <process names> | <LOW/MEDIUM/HIGH/CRITICAL> |

### Steps

<!-- State: todo | doing | done | blocked | dropped. Model and tier per step (subagent / Workflow / second session / main). -->

| # | Step | Model | Tier | State |
| --- | --- | --- | --- | --- |
| 1 | <step> | <opus/sonnet/haiku/fable> | <main/subagent/Workflow/session> | todo |

## Evidence log

<!-- Append only. One row per command that proves something. Key output line copied, not paraphrased. -->

| When | Command | Exit | Key output line | Commit |
| --- | --- | --- | --- | --- |
| <hh:mm> | `<command>` | <0> | `<line>` | <sha> |

## Decisions

<!-- Choices made on the way and why; link the issue comment when the owner was told. -->

- <yyyy-mm-dd>: <decision>. Why: <reason>.

## Blocked-on

<!-- What stops progress, who or what can unblock it. "none" when clear. -->

- none

## Next

<!-- The very next action, concrete enough for a fresh session to start without re-reading the transcript. -->

1. <next action>
