# Changelog

## Releasing

1. Bump `version` in `.claude-plugin/plugin.json` and add an entry below.
2. Merge the PR, then on updated `main`: `claude plugin tag --push`
   (creates and pushes `agent-harness--v<version>`; use `--dry-run` first).

## 0.1.0

- First release of the `agent-harness` plugin.
