#!/usr/bin/env sh
# Validate the package: skills/, agents/, fragments/, templates/. Exit 1 on any failure.
#   skills/<name>/SKILL.md  frontmatter `name` (== directory name), non-empty `description`, a valid `effort`
#                           if set; bundled shell scripts pass `sh -n` and shellcheck (when installed);
#                           symlinks inside a skill resolve and stay inside the repo.
#   agents/<name>.md        frontmatter `name` (== file name, no `:`), non-empty `description`, and valid
#                           `model` / `effort` / `memory` / `tools` values when set.
#   fragments/<name>.md     frontmatter `name` (== file name), `description`, `target`; the body (what nix
#                           appends to CLAUDE.md) starts with a `## ` heading, has no `# ` heading outside code
#                           fences and never contains the managed-block markers.
#   templates/progress.md   has every section the long-task skill relies on (including ### Blast radius).
#   hooks/<name>.sh         passes `sh -n` and shellcheck (when installed), is executable, has a row in
#                           README.md, and its test tests/<name>.sh (required) passes.
# Every frontmatter block must parse as a YAML mapping (checked with python3 + PyYAML when available, so a
# stray ` #` or `: ` in a plain scalar cannot silently truncate a description).
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fail=0
errors=0
err() { echo "FAIL: $*" >&2; fail=1; errors=$((errors + 1)); }
# ok <label>: report a clean item (only when nothing failed since `start=$errors`).
ok() { [ "$errors" = "$start" ] && echo "ok: $1"; }

have_yaml=0
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  have_yaml=1
else
  echo "note: python3 + PyYAML not found; skipping the YAML parse check" >&2
fi

# frontmatter <file>: the lines between the opening and closing `---` (empty when there is none).
frontmatter() { awk 'NR==1{next} /^---$/{exit} {print}' "$1"; }
# body <file>: everything after the closing `---`.
body() { awk 'f{print} NR>1 && /^---$/ && !f{f=1}' "$1"; }
# field <frontmatter-text> <key>: the first value of a top-level `key:` line.
field() { printf '%s\n' "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n 1; }

check_frontmatter() { # label file
  [ "$(sed -n 1p "$2")" = "---" ] || { err "$1: must start with --- frontmatter"; return 1; }
  [ "$(awk 'NR>1 && /^---$/{print "closed"; exit}' "$2")" = "closed" ] || { err "$1: frontmatter is not closed with ---"; return 1; }
  if [ "$have_yaml" = 1 ]; then
    frontmatter "$2" | python3 -I -c '
import sys, yaml
try:
    data = yaml.safe_load(sys.stdin.read())
except yaml.YAMLError as e:
    print("YAML error: %s" % str(e).replace("\n", " "), file=sys.stderr); sys.exit(1)
if not isinstance(data, dict):
    print("frontmatter is not a mapping", file=sys.stderr); sys.exit(1)
desc = data.get("description")
if desc is not None and not isinstance(desc, str):
    print("description is not a string", file=sys.stderr); sys.exit(1)
' || { err "$1: frontmatter does not parse as YAML"; return 1; }
  fi
  return 0
}

check_enum() { # label key value allowed...
  label=$1 key=$2 value=$3
  shift 3
  [ -z "$value" ] && return 0
  for allowed in "$@"; do [ "$value" = "$allowed" ] && return 0; done
  err "$label: $key '$value' is not one of: $*"
}

# --- skills ---------------------------------------------------------------------------------------------------
for dir in "$ROOT"/skills/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  start=$errors
  md="$dir/SKILL.md"
  if [ ! -f "$md" ]; then err "skill $name: missing SKILL.md"; continue; fi
  check_frontmatter "skill $name" "$md" || continue
  fm=$(frontmatter "$md")
  fm_name=$(field "$fm" name)
  [ "$fm_name" = "$name" ] || err "skill $name: frontmatter name is '$fm_name', expected '$name'"
  printf '%s\n' "$fm" | grep -q '^description:[[:space:]]*[^[:space:]]' || err "skill $name: frontmatter needs a non-empty description"
  check_enum "skill $name" effort "$(field "$fm" effort)" low medium high xhigh max
  for sh_file in "$dir"/scripts/*.sh; do
    [ -f "$sh_file" ] || continue
    sh -n "$sh_file" || err "skill $name: $(basename "$sh_file") has a syntax error"
    if command -v shellcheck >/dev/null 2>&1; then
      shellcheck "$sh_file" || err "skill $name: shellcheck failed on $(basename "$sh_file")"
    fi
  done
  links=$(mktemp)
  find "$dir" -type l >"$links"
  while IFS= read -r link; do
    [ -e "$link" ] || { err "skill $name: broken symlink ${link#"$ROOT"/}"; continue; }
    target=$(cd "$(dirname "$link")" && cd "$(dirname "$(readlink "$link")")" && pwd)
    case "$target/" in
      "$ROOT"/*) ;;
      *) err "skill $name: symlink ${link#"$ROOT"/} points outside the repo" ;;
    esac
  done <"$links"
  rm -f "$links"
  ok "skill $name"
done

# --- agents ---------------------------------------------------------------------------------------------------
for md in "$ROOT"/agents/*.md; do
  [ -f "$md" ] || continue
  name=$(basename "$md" .md)
  start=$errors
  check_frontmatter "agent $name" "$md" || continue
  fm=$(frontmatter "$md")
  fm_name=$(field "$fm" name)
  [ "$fm_name" = "$name" ] || err "agent $name: frontmatter name is '$fm_name', expected '$name' (the file name)"
  case "$fm_name" in *:* | -*) err "agent $name: name must not contain ':' or start with '-'" ;; esac
  printf '%s\n' "$fm" | grep -q '^description:[[:space:]]*[^[:space:]]' || err "agent $name: frontmatter needs a non-empty description"
  model=$(field "$fm" model)
  case "$model" in
    "" | sonnet | opus | haiku | fable | inherit | claude-*) ;;
    *) err "agent $name: model '$model' is not an alias (sonnet, opus, haiku, fable, inherit) or a claude-* id" ;;
  esac
  check_enum "agent $name" effort "$(field "$fm" effort)" low medium high xhigh max
  check_enum "agent $name" memory "$(field "$fm" memory)" user project local
  tools=$(field "$fm" tools)
  if [ -n "$tools" ]; then
    for tool in $(printf '%s\n' "$tools" | tr ',' ' '); do
      case "$tool" in
        [A-Z]*) ;;
        *) err "agent $name: tools entry '$tool' does not look like a tool name" ;;
      esac
    done
  fi
  [ -n "$(body "$md" | tr -d '[:space:]')" ] || err "agent $name: empty system prompt (body)"
  ok "agent $name"
done

# --- fragments ------------------------------------------------------------------------------------------------
for md in "$ROOT"/fragments/*.md; do
  [ -f "$md" ] || continue
  name=$(basename "$md" .md)
  start=$errors
  check_frontmatter "fragment $name" "$md" || continue
  fm=$(frontmatter "$md")
  [ "$(field "$fm" name)" = "$name" ] || err "fragment $name: frontmatter name must be '$name' (the file name)"
  for key in description target; do
    printf '%s\n' "$fm" | grep -q "^$key:[[:space:]]*[^[:space:]]" || err "fragment $name: frontmatter needs a non-empty $key"
  done
  first=$(body "$md" | awk 'NF{print; exit}')
  case "$first" in
    "## "*) ;;
    *) err "fragment $name: body must start with a '## ' heading (it is appended under the file's own headings)" ;;
  esac
  body "$md" | awk '/^```/{f=!f; next} !f && /^# /{bad=1} END{exit bad}' || err "fragment $name: body has a '# ' heading outside code fences"
  if body "$md" | grep -q 'agent-skills:[a-z0-9-]*:\(start\|end\)'; then
    err "fragment $name: body must not contain the managed-block markers"
  fi
  ok "fragment $name"
done

# --- templates ------------------------------------------------------------------------------------------------
tpl="$ROOT/templates/progress.md"
if [ -f "$tpl" ]; then
  start=$errors
  for section in "Goal" "Done-when checks" "Plan" "Evidence log" "Decisions" "Blocked-on" "Next"; do
    grep -qx "## $section" "$tpl" || err "template progress: missing section '## $section'"
  done
  grep -qx "### Blast radius" "$tpl" || err "template progress: missing '### Blast radius' under ## Plan"
  ok "template progress"
else
  err "templates/progress.md is missing (the long-task skill copies it)"
fi

# --- hooks ----------------------------------------------------------------------------------------------------
for hook in "$ROOT"/hooks/*.sh; do
  [ -f "$hook" ] || continue
  name=$(basename "$hook" .sh)
  start=$errors
  sh -n "$hook" || err "hook $name: syntax error"
  [ -x "$hook" ] || err "hook $name: not executable"
  grep -q "(hooks/$name.sh)" "$ROOT/README.md" || err "hook $name: no row in README.md"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$hook" || err "hook $name: shellcheck failed"
  fi
  if [ -f "$ROOT/tests/$name.sh" ]; then
    if command -v shellcheck >/dev/null 2>&1; then
      shellcheck "$ROOT/tests/$name.sh" || err "hook $name: shellcheck failed on tests/$name.sh"
    fi
    sh "$ROOT/tests/$name.sh" >/dev/null || err "hook $name: tests/$name.sh failed (run it to see which check)"
  else
    err "hook $name: missing tests/$name.sh"
  fi
  ok "hook $name"
done

exit $fail
