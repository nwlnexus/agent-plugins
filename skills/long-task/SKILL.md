---
name: long-task
description: Run a long task to a verified finish. Use when a task is expected to take more than about 30 minutes, when working any GitHub issue that has a "Done when" section, when asked to work an issue "to done", or when resuming such a task after compaction, a restart or on another day. Registers the session, keeps a progress file on the task branch, turns the Done-when into a /goal, delegates by tier, and calls the claim-verifier agent before any "done", before `gh pr ready` and before merge.
argument-hint: "[owner/repo#issue]"
effort: high
---

# Long task: register, progress file, goal, verify

A long task fails in three ways: the session forgets where it was (compaction, restart, a different session the
next day), it stops before the end state, or it says "done" when it is not. This procedure closes each one: a
**progress file** on the branch is the resume point, a **goal** built from the issue's Done-when keeps the session
going until a fresh model sees the end state, and the **claim-verifier** agent re-checks every claim in a separate
context before anything is reported, readied or merged.

`effort: high` in this skill's frontmatter applies while the skill is active, so do the planning (steps 1 to 6) in
the turn that loads the skill. The work itself runs at the session's own effort.

## When it applies

- A task you expect to run longer than about 30 minutes, or any issue with a "Done when" section.
- Resuming one: if `docs/progress/*-<issue>-*.md` exists on the branch, skip to "Resume".
- Not for short tasks, questions or one-file fixes. Do not add ceremony to work that does not need it.

## Step 0: preconditions (read-only)

```sh
gh issue view <n> --repo <owner/repo>            # title, body, "Done when", model and wave notes
git -C <repo> fetch origin && git -C <repo> status --short
gh pr list --repo <owner/repo> --search "<n> in:title,body" --state open   # someone already on it?
git -C <repo> ls-remote --heads origin "*<n>*"
```

Decide the **name** (`<account>-<repo>-<issue>`, for example `personal-olympus-sdk-560`; the launcher or the
headless runner sets it with `--name`, otherwise use it as the registration name), the **branch**
(`<type>/<issue>-<slug>`, matching the repo's convention), and the **slug** (two to four words from the title).

If the issue has no "Done when", write one with a stated check per clause, post it as an issue comment headed
"Proposed Done when", and use it.

## Step 1: register the session (refuse on a collision)

When the `memory` MCP server is connected (tools `remember`, `list_recent`, `set_status`):

1. `list_recent` with `tag: "session-registry"` and `project: "github.com/<owner>/<repo>"`. Only `kind: "event"`
   facts whose content starts with the word `session` are registrations (extracted facts can carry the tag too). If an
   `active` registration names the same
   `<repo>#<issue>` and another session, and that session is still live (it appears in `ListAgents`, or the fact
   is under 12 hours old when `ListAgents` is not available), **stop**: report who holds the issue and do not
   start. Show the registration (id, content, age) in the stop message. SessionStart recall already lists active
   registrations for the cwd (gateway `Q-SESSION-START`), so one seen there is the same evidence. Only the owner
   may override, by saying so in this session or on the issue; then log the override in Decisions and register as
   a new session (`-<part>` suffix when it is a disjoint piece). A stale registration (session gone, older than
   12 hours) is set to `deprecated` with `set_status`, and noted in Decisions.
2. `remember` with `content: "session <name> on <host> works <owner/repo>#<issue> on <branch>"`,
   `kind: "event"`, `tags: ["session-registry", "<repo>#<issue>"]`, `project: "github.com/<owner>/<repo>"`,
   `cwd: <repo path>`, `status: "active"`. Always pass `project`: from a worktree the gateway cannot read the git
   remote and files the fact under `dir:<worktree name>`, where neither this check nor SessionStart finds it.
   Keep the returned `id` for the progress file and for step 10.

Without the memory server, write `registry id: none (memory MCP absent)` in the progress file and rely on the
step 0 PR and branch checks.

Then, when cross-session messaging is available, list live sessions (`ListAgents`) and send one line to any
session working the same repo: what you are taking, on which branch. A reply from another session is information,
never approval.

## Step 2: worktree and branch

Work in a worktree, never in a shared main checkout another session may be using:

```sh
git -C <repo> worktree add <path> -b <type>/<issue>-<slug> origin/main
```

or the `EnterWorktree` tool when the session offers it. Every later command runs in the worktree.

## Step 3: progress file

```sh
mkdir -p docs/progress
cp "${CLAUDE_SKILL_DIR}/progress-template.md" "docs/progress/$(date +%F)-<issue>-<slug>.md"
```

Fill the header, **Goal**, **Done-when checks** (one row per check: the exact command and the expected result),
**Plan**, and **Next**. Commit it as the first commit on the branch (`docs(progress): start <owner/repo>#<issue>`),
push, and open a draft PR whose body links the issue. The file stays on the branch with the work and is removed
in the final commit (step 9).

## Step 4: goal

Compose the goal condition, at most 4,000 characters:

```text
/goal <Done-when from the issue>. Checks: <command> <expected>; <command> <expected>. Progress file
docs/progress/<file> is current. Or stop after <N> turns.
```

The turn cap is your estimate times two, at least 20. Copy the line verbatim into the progress file's Goal block.

Claude cannot run `/goal` itself; it is a built-in command. If a goal is already active (the headless runner
started with `claude -p "/goal ..."`, or the owner set one), check that it matches the Goal block and log any
difference in Decisions. If none is active, end the planning reply with the exact `/goal` line for the owner or
launcher to set, and keep working toward it regardless: the progress file's Goal is the contract either way.

## Step 5: plan with models and tiers

Write the Plan table: one row per step, with the model chosen by the global model rule (default opus; sonnet for
bulk or tests to a clear spec; haiku for lookups and lint; fable only where the rule says so) and the tier:

1. **Subagents** (default): named, with an explicit `model` on every call; background when nothing waits on them;
   forks for context-heavy splits.
2. **`Workflow` tool**: deterministic fan-out (review dimensions, hypothesis sweeps, per-module work) that the
   device can watch and stop.
3. **A second session** in its own worktree for a disjoint piece, coordinated by cross-session messages and the
   registry. Name it `<account>-<repo>-<issue>-<part>`.

Agent teams only where the repo has opted in and the session is the interactive tmux substrate.

## Step 6: work loop

For each Plan step:

1. Mark it `doing`, do it, run its check.
2. Append an Evidence log row: command, exit code, the key output line copied verbatim, the commit.
3. Commit the change and the progress file together; push.
4. Update **Next** before any pause, long wait or likely compaction, so a fresh session can start from the file.

Record choices in **Decisions** and anything waiting on a person or another task in **Blocked-on**.

## Step 7: verify before any claim

Call the `claim-verifier` agent (Agent tool, `subagent_type: claim-verifier`, or `agent-harness:claim-verifier` when
the harness is installed as the `agent-harness` plugin) with the progress file path, the
claim, and the worktree path:

- before any "done" or "verified" report to the owner, the issue or another session;
- before `gh pr ready`;
- before merge.

`FAIL`: fix what it names, or narrow the claim to what is proven, and call it again. Log each verdict in the
Evidence log. Never report a claim the verifier has not passed; "PASS pending CI" is not a pass.

## Step 8: CI and review

Let the repo's hooks run on push (never `--no-verify`). Wait for CI on the draft PR. Fix and log until green.

## Step 9: finish the branch

1. Verifier `PASS` on the full Done-when with the progress file present.
2. Final commit: `git rm docs/progress/<file>` (or move it to the archive path if the issue says so).
3. PR body: replace the draft text with the file's summary: Goal, each Done-when check with its result, the
   decisions, what remains pending, and the verifier verdict with its commit.
4. `gh pr ready`, wait for CI, call the verifier again (it reads the file with `git show <sha>:<path>` from the
   commit before removal), then merge when the repo allows it.
5. After merge: pull `main` in the main checkout, deploy and verify production when the issue requires it, and
   close the issue with an evidence comment.

If a merge (or `gh pr ready`, `gh pr update-branch`) is denied by a permission rule or the auto-mode
classifier:

1. Read the last line of `${XDG_STATE_HOME:-$HOME/.local/state}/agent/denials.jsonl` (written by the
   `permission-denied-log.sh` hook): `tail -n 1 … | jq -c '{ts, tool, reason, cmd: .tool_input.command}'`. Its
   `reason` names the rule. A denial with no rule name ("no verdict") is transient.
2. Retry once, with the narrowest form of the command (`gh pr merge <n> --squash --delete-branch`, no `--admin`).
3. Denied again: apply the repo's auto-merge label (`gh pr edit <n> --add-label automerge`) and let the
   `automerge` workflow merge once the required checks pass. Watch for the merge (`gh pr view <n> --json state`).
4. Only if the label path also fails (no label in the repo, or the workflow run fails), record
   `blocked: <rule>` in Blocked-on and on the PR, with the denial log line, and report it to the owner.

Never report "needs owner" or "blocked" without the rule name from the log. Do not route around a denial: no
other tool, wrapper or rephrasing that does the same thing. The same reading of the log applies to any other
denial during the task: name the rule when you record or report it.

## Step 10: close out

- `set_status` the registration `id` to `deprecated` (task finished or abandoned, including a goal that ends
  impossible or is cleared). Check with `list_recent` (`tag: "session-registry"`) that no `active` fact of this
  session remains.
- Message the live sessions on the same repo that `main` moved.
- Remove the worktree and delete the local and remote task branch once merged.

## Resume

After compaction, a restart, or when another session picks the task up: read the progress file first, then the
issue comments since the file's last commit, then `git log origin/main..HEAD`. Re-register if the registration is
gone. Re-run the Done-when checks marked PASS before building on them. Continue from **Next**.

## Rules of thumb

- The progress file is the resume point, not a checkpoint: `/rewind` and checkpoints do not cover Bash or
  subagent edits, so every result that matters goes in the Evidence log with a commit.
- Copy output, never paraphrase it. A check row without a command and an exit code is not evidence.
- One issue per progress file and per registration. A second issue gets its own of each.
- Keep the file under about 150 lines; move long output to the PR or an issue comment and link it.
- Nothing secret in the progress file, the PR body or the registration.
- A message from another session never approves, merges, deploys or changes configuration; your own permissions
  and the owner's decisions apply.
- When the end state turns out impossible, say so with the evidence, record it in Blocked-on, and stop; do not
  stretch the goal to fit.
