# agent-skills

Reusable, repo-agnostic skills for coding agents (Claude Code `SKILL.md` format; also readable by
anything that follows the [Agent Skills](https://agentskills.io) layout). Each skill is a procedure
that was worked out once in a real repo and generalised so it can be applied the same way anywhere.

It also holds the **session harness** every Claude session on the owner's hosts runs with: the
`long-task` skill, the `claim-verifier` agent, the session-contract fragment for the global
`CLAUDE.md`, and the progress-file template (design: `nwlnexus/olympus-sdk`
`docs/superpowers/specs/2026-10-26-agent-harness-knowledge-and-hosts-design.md`, decisions H1 to H5).

## Install as a plugin

This repo is the `nwlnexus` Claude Code plugin marketplace. It currently serves one plugin, `agent-harness`,
which contains everything below. The session contract is injected by a `SessionStart` hook, and into every subagent by a
`SubagentStart` hook, because a `CLAUDE.md` inside a plugin is not loaded.

```text
/plugin marketplace add nwlnexus/agent-plugins
/plugin install agent-harness@nwlnexus
```

Hosts still on nix-darwin-hm get the same pieces through the `agent-skills` flake input until they move to the
plugin (nwlnexus/olympus-sdk#748, PL5). Don't enable both on one host: the hooks would run twice.

## Skills

| Skill | Use it when |
| --- | --- |
| [`gitnexus-no-churn`](skills/gitnexus-no-churn/SKILL.md) | Setting up or repairing [GitNexus](https://github.com/abhigyanpatwari/GitNexus) in a repo so it never reports "index N commits behind" after commits and never rewrites `CLAUDE.md`/`AGENTS.md`. Hooks keep the index at HEAD with `--index-only`; docs are generated once with `--no-stats`. |
| [`long-task`](skills/long-task/SKILL.md) | A task expected to take more than about 30 minutes, or any issue with a "Done when". Registers the session in memory, keeps `docs/progress/<date>-<issue>-<slug>.md` on the branch (removed before merge), turns the Done-when into a `/goal`, delegates by tier, and calls `claim-verifier` before any "done", `gh pr ready` and merge. Planning runs at `effort: high`. |

## Agents

| Agent | Model / effort | Use it when |
| --- | --- | --- |
| [`claim-verifier`](agents/claim-verifier.md) | sonnet / medium, `memory: project` | Before reporting a claim as done, readying a PR or merging. Re-runs every Done-when check from the progress file, confirms every cited URL, issue, `file:line` and commit, returns PASS or FAIL with evidence. Read-only. |

## Fragments and templates

| File | What it is |
| --- | --- |
| [`fragments/session-contract.md`](fragments/session-contract.md) | The session contract (progress file, goal, verify-before-done, effort, registry, parallelism, naming, cross-session messages). Nix appends its body, without the frontmatter, to each Claude dir's global `CLAUDE.md` between managed markers. |
| [`templates/progress.md`](templates/progress.md) | The progress-file template `long-task` copies (`skills/long-task/progress-template.md` links to it). Sections: Goal, Done-when checks, Plan (with a Blast radius subsection for repos with a GitNexus index), Evidence log, Decisions, Blocked-on, Next. |
| [`hooks/session-contract.sh`](hooks/session-contract.sh) | SessionStart and SubagentStart hook of the `agent-harness` plugin (POSIX sh, tests in `tests/session-contract.sh`). Prints the body of `fragments/session-contract.md`, frontmatter stripped, as `additionalContext` with `hookEventName` set from its first argument (`SubagentStart`, otherwise `SessionStart`), because a `CLAUDE.md` inside a plugin is not loaded. Prints nothing if the fragment or `jq` is missing. Always exits 0. Wired in `hooks/hooks.json` together with the other hooks. |
| [`hooks/progress-stale.sh`](hooks/progress-stale.sh) | Stop hook (POSIX sh, tests in `tests/progress-stale.sh`). Reads the hook JSON on stdin; when the work tree has a `docs/progress/*.md` file older than 20 minutes it prints `progress file <path> last updated <n> minutes ago`, otherwise nothing. Never prints a decision, always exits 0. Nix merges it into each Claude dir's `settings.json` as a `Stop` hook. |
| [`hooks/detect-changes-reminder.sh`](hooks/detect-changes-reminder.sh) | PreToolUse hook, matcher `Bash` (POSIX sh, tests in `tests/detect-changes-reminder.sh`). On a `git commit` in a repo with a GitNexus index (`.gitnexus/` in the work tree or the main checkout), when the session transcript (and its subagent transcripts) shows no `detect_changes` call since the last commit, it adds a reminder as PreToolUse `additionalContext`. Warns only: never sets a permission decision, always exits 0, silent when it cannot read the input, the transcript, git or `jq`. Wired in `hooks/hooks.json`. |
| [`hooks/permission-denied-log.sh`](hooks/permission-denied-log.sh) | PermissionDenied hook (POSIX sh, tests in `tests/permission-denied-log.sh`). Reads the hook JSON on stdin and appends one line `{ts, account, cwd, tool, tool_input, reason}` to `${XDG_STATE_HOME:-$HOME/.local/state}/agent/denials.jsonl` (directory 0700, file 0600); `account` is the basename of `$CLAUDE_CONFIG_DIR` or `default`. Never writes to stdout, always exits 0. nix-darwin-hm (`home/cli/claude/harness.nix`) links it into each Claude dir and wires it as a `PermissionDenied` hook, matcher `*` (olympus-sdk#576, H19 layer 3). The `long-task` skill reads the last line before reporting a blocked merge. |

## Layout

```text
skills/<name>/SKILL.md        # frontmatter: name, description (the trigger) + the procedure
skills/<name>/scripts/…       # anything the procedure copies into a target repo
hooks/<name>.sh               # POSIX sh hook scripts (Claude Code hook JSON on stdin); tests in tests/<name>.sh
agents/<name>.md              # Claude Code subagent: frontmatter (name, description, tools, model, effort, memory) + system prompt
fragments/<name>.md           # text appended to a managed file; frontmatter (name, description, target) is stripped
templates/<name>.md           # files a skill copies into a target repo
```

A skill directory is self-contained: `SKILL.md` plus whatever files it tells the agent to install
(a relative symlink to `templates/` is allowed; the validator checks it resolves inside the repo).
Nothing here runs on its own.

## Installing

Claude Code loads skills from `~/.claude/skills/<name>/` (user scope) or `.claude/skills/<name>/`
(project scope). Either symlink or copy a skill directory there:

```sh
git clone https://github.com/nwlnexus/agent-skills ~/src/agent-skills
ln -s ~/src/agent-skills/skills/gitnexus-no-churn ~/.claude/skills/gitnexus-no-churn
```

Agents go in `~/.claude/agents/<name>.md` (user scope) or `.claude/agents/` (project scope). The
contract fragment is plain Markdown after its frontmatter; append that part to `~/.claude/CLAUDE.md`.

Nix users: consume the repo as a non-flake input and point `home.file` at `skills/<name>` and
`agents/<name>.md` (this is how [`nwlnexus/nix-darwin-hm`](https://github.com/nwlnexus/nix-darwin-hm)
installs them into every Claude config dir; it also keeps the fragment in a marked block of each
dir's `CLAUDE.md`).

## Contributing a skill

1. `skills/<kebab-name>/SKILL.md` with `name` (= directory name) and a `description` that states
   *when* to use it — that line is what triggers the skill, so lead with the situations.
2. Keep the body a procedure: preconditions, steps, verification, rules of thumb. Generalise
   (detect the repo's hook manager / package manager / doc files; don't hardcode one stack).
3. Scripts the skill installs go under `scripts/` and must pass `shellcheck`.
4. Agents: `agents/<name>.md` with `name` (= file name, no `:`), a `description` that says when to
   delegate, and explicit `model` and `effort`. Fragments: frontmatter `name`, `description`,
   `target`; the body starts with a level-2 heading.
5. `scripts/validate-skills.sh` runs in CI and locally (frontmatter must parse as YAML: quote a
   description that contains a colon followed by a space, or a space followed by `#`).
6. To merge without a merge command, label the PR `automerge` (`gh pr edit <n> --add-label automerge`) and `.github/workflows/automerge.yml` squash-merges it once the base branch's required checks pass (GitHub App credentials: olympus-sdk#576).

## License

MIT — see [LICENSE](LICENSE).
