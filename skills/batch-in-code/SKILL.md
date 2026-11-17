---
name: batch-in-code
description: Fold many related tool calls into one script that returns only what you need, the way Code Mode does, without Code Mode. Use when a task needs many related, mechanical tool calls, such as the same edit across many files, a search whose results need filtering or counting before you read them, a check repeated over a list (files, PRs, hosts, links), or several independent commands that can run at once. Keeps push, merge, deploy, delete and remote writes as separate visible calls. Not for one or two calls, or for steps where each result needs judgement before the next.
---

# Batch in code

Claude Code's [Code Mode](https://code.claude.com/docs/en/code-mode) lets Claude write one piece of JavaScript
that makes several tool calls, uses one result in the next, runs independent calls in parallel and returns only
what it needs to read. It saves turns and context, but it won't start with OpenTelemetry export or Remote
Control on, and it doesn't run under `-p`, in cloud sessions or in the Desktop app.

You get most of the same benefit with the tools you already have:

- **one Bash script** for a loop, a filter or a chain of shell steps;
- **parallel tool calls in one message** for what a script can't reach (MCP tools, subagents, Read, Edit).

## When it applies

Use it when the task needs about four or more related calls and you don't need to judge each intermediate result:

- the same mechanical change in many files (rename, version bump, import path, config key);
- a search whose raw output is large and needs filtering, grouping or counting before you read it;
- a check repeated over a list: links in Markdown files, status of a set of PRs or issues, a command per package;
- independent commands that can run at the same time (lint, typecheck, unit tests in different packages).

Don't use it when:

- each step depends on reading and judging the previous result (debugging, reviewing, designing);
- one or two calls do the job;
- the step is outward or destructive (see "What stays outside a batch").

## Procedure

1. **Look first, small.** Make one or two cheap calls to learn the shape of the data, for example
   `rg -l pattern | head`, one sample file or `--help`. Don't write a loop over data you haven't seen.
2. **Write the script so the result is the output.** Print what you need to decide the next step, not the raw
   data: counts, paths, failures, a short table, the first N matches. Bound every list (`head -n 50`, `wc -l`,
   `sort | uniq -c | sort -rn | head`). Tool output is truncated past about 30,000 characters, so a large dump
   costs context and may lose the part you need.
3. **Fail loudly.** Start with `set -euo pipefail`. Report failures by item and exit non-zero when something
   failed. Use `|| true` only where you mean it, and say why in a comment.
4. **Keep it readable.** The user sees the script in the transcript, which is something Code Mode hides. For
   anything over about 15 lines, write it to a file in the session's scratch directory with a heredoc, then run
   it. Name the variables, and keep scratch scripts out of the repo unless the user wants them.
5. **Run independent work in parallel.** Inside a script, use `cmd1 & cmd2 & wait`, capturing each exit status.
   Across tools, put independent calls (Read, Grep, MCP calls, subagents) in one message.
6. **Respect time limits.** The Bash tool times out at 2 minutes by default and 10 at most (`timeout` is in
   milliseconds). Run longer builds and test suites with `run_in_background` and wait for the notification, or
   watch them with Monitor instead of polling.

### Bulk edits

1. **Dry-run.** Print the planned change set first, for example the files and line counts that match, or the
   output of `sed -n 's/old/new/p'`. Check that the count matches what you expect.
2. **Apply with an exact, anchored pattern.** Use `perl -pi -e` (the same on GNU and BSD), or a short script that
   reads, replaces and writes. Prefer a literal match (`\Q...\E`) over a loose regex.
3. **Verify.** Run `git diff --stat`, show a sample of the diff (`git diff | head -n 60`), then run the project's
   check (tests, typecheck, validator).

For one to three edits, use the Edit tool instead. The diff it shows is clearer than a script.

## What stays outside a batch

Each of these is its own tool call, run after the batch has reported back and you've read the result:

- `git push`, opening, merging or closing PRs, tagging or publishing a release;
- deploys, restarts and writes to remote services or APIs, including MCP tools that change state;
- deleting files or branches, `rm -rf`, `git reset --hard`, force pushes;
- anything that sends content outside the machine.

The reason is review. Permission rules, hooks and the auto-mode classifier see the command text of each tool
call. They don't see values a script computes at run time, such as a path taken from search output. A
destructive step buried inside a loop gets less review than the same step on its own. Code Mode has the same
weakness: in auto mode its classifier reviews the code, not each call. Keep the review where it belongs.

A batch may *prepare* such a step, for example list the branches that are safe to delete. Then show the list
and run the step as a separate call that names its targets explicitly.

## Examples

Broken local links in Markdown, one call, bounded output:

```sh
set -euo pipefail
# rg exits 1 when nothing matches; that is not a failure here.
{ rg -o --no-heading -n '\]\((\.{0,2}/?[^)#:]+)(#[^)]*)?\)' -r '$1' -g '*.md' . || true; } |
  while IFS=: read -r file line target; do
    [ -e "$(dirname "$file")/$target" ] || printf '%s:%s -> %s\n' "$file" "$line" "$target"
  done | sort | head -n 100
```

Status of several PRs, with one line each instead of one call each:

```sh
for pr in 101 102 103 104; do
  gh pr view "$pr" --json number,state,mergeStateStatus,statusCheckRollup \
    --jq '"\(.number) \(.state) \(.mergeStateStatus) failing=\([.statusCheckRollup[]? | select(.conclusion == "FAILURE") | .name] | join(","))"'
done
```

Independent checks at once, with a summary at the end:

```sh
set -u
dir=$(mktemp -d)
(npm run lint >"$dir/lint" 2>&1; echo $? >"$dir/lint.rc") &
(npm run typecheck >"$dir/tsc" 2>&1; echo $? >"$dir/tsc.rc") &
(npm test >"$dir/test" 2>&1; echo $? >"$dir/test.rc") &
wait
for c in lint tsc test; do
  rc=$(cat "$dir/$c.rc")
  echo "$c: exit $rc"
  [ "$rc" = 0 ] || tail -n 20 "$dir/$c"
done
```
