#!/usr/bin/env bash
# Install Recipe-Driven Development into a repo. Safe to re-run: existing files are never overwritten
# (spec-lint.mjs, specs/README.md, the skills and the CLAUDE.md rules block are refreshed only with --update).
#   ./install.sh <repo> [--update]
set -euo pipefail

kit="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:?usage: install.sh <repo> [--update]}"
update="${2:-}"
target="$(cd "$target" && pwd)"
tpl="$kit/template"

copy() { # copy <src> <dest> [refreshable]
  local src="$1" dest="$2" refreshable="${3:-}"
  if [[ -e "$dest" && ! ( "$refreshable" == yes && "$update" == --update ) ]]; then
    echo "  keep    ${dest#"$target"/}"
  else
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    echo "  write   ${dest#"$target"/}"
  fi
}

# The kit's version lives in spec-lint.mjs. Read it from the file rather than running it, since an install
# from before versioning has no --version flag.
version_of() { sed -n 's/^const VERSION = "\(.*\)"$/\1/p' "$1" 2>/dev/null; }
version="$(version_of "$tpl/scripts/spec-lint.mjs")"
echo "Installing Recipe-Driven Development $version into $target"
if [[ -f "$target/scripts/spec-lint.mjs" ]]; then
  installed="$(version_of "$target/scripts/spec-lint.mjs")"
  # sort -V puts the newer of two versions last; no version at all counts as older than any.
  newest="$(printf '%s\n%s\n' "${installed:-0}" "$version" | sort -V | tail -1)"
  if [[ "$installed" == "$version" ]]; then
    echo "  already at $version"
  elif [[ "$newest" == "$installed" ]]; then
    echo "  this repo has $installed, which is newer than this kit ($version); update your copy of the kit first"
    [[ "$update" == --update ]] && { echo "  refusing to downgrade with --update; nothing was changed" >&2; exit 1; }
  elif [[ "$update" == --update ]]; then
    echo "  updating from ${installed:-a version before 0.1.0} to $version; see CHANGELOG.md for what changed"
  else
    echo "  this repo has ${installed:-a version before 0.1.0}; run with --update to refresh spec-lint.mjs, specs/README.md, the skills and the CLAUDE.md rules"
  fi
fi
# specs/README.md is the format definition, so it's the kit's to keep current; the rest of specs/ is yours. If the
# copy being replaced differs from the kit's, it's kept as specs/README.md.old, so notes a team added aren't lost.
readme="$target/specs/README.md"
if [[ "$update" == --update && -f "$readme" ]] && ! cmp -s "$tpl/specs/README.md" "$readme"; then
  cp "$readme" "$readme.old"
  echo "  backup  specs/README.md → specs/README.md.old (copy over any notes of your own)"
fi
copy "$tpl/specs/README.md" "$readme" yes
for f in tokens.md outline.md _templates/{screen,component,flow,model,api,policy}.md; do
  copy "$tpl/specs/$f" "$target/specs/$f"
done
mkdir -p "$target"/specs/{screens,components,flows,models,apis,policies,_reports}
copy "$tpl/scripts/spec-lint.mjs" "$target/scripts/spec-lint.mjs" yes
for s in spec-new spec-review spec-verify spec-migrate; do
  copy "$tpl/.claude/skills/$s/SKILL.md" "$target/.claude/skills/$s/SKILL.md" yes
done

# Hooks and kitchen spinner verbs: merge into .claude/settings.json without touching anything else in it.
node - "$target/.claude/settings.json" "$tpl/spinner-verbs.json" <<'EOF'
const fs = require("node:fs")
const [file, verbs] = process.argv.slice(2)
const settings = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {}
settings.hooks ??= {}
const entry = (matcher, flag) => ({
  ...(matcher ? { matcher } : {}),
  hooks: [{ type: "command", command: `node "$CLAUDE_PROJECT_DIR/scripts/spec-lint.mjs" ${flag}` }],
})
let added = false
for (const [event, matcher, flag] of [
  ["PreToolUse", "Edit|Write|MultiEdit", "--hook-pre"],
  ["PreToolUse", "Bash", "--hook-bash"],
  ["PostToolUse", "Edit|Write|MultiEdit", "--hook-post"],
  ["PostToolUse", "Bash", "--hook-bash-post"],
  ["SessionStart", null, "--hook-seen"],
  ["UserPromptSubmit", null, "--hook-seen"],
]) {
  settings.hooks[event] ??= []
  if (!JSON.stringify(settings.hooks[event]).includes(`spec-lint.mjs\\" ${flag}`)) {
    settings.hooks[event].push(entry(matcher, flag))
    added = true
  }
}
// Spinner verbs are a matter of taste: only set them if the repo hasn't chosen its own.
const spinner = !settings.spinnerVerbs
if (spinner) settings.spinnerVerbs = JSON.parse(fs.readFileSync(verbs, "utf8"))
fs.mkdirSync(require("node:path").dirname(file), { recursive: true })
fs.writeFileSync(file, JSON.stringify(settings, null, 2) + "\n")
console.log(`  ${added || spinner ? "merge  " : "keep   "} .claude/settings.json${[added && "hooks", spinner && "spinner verbs"].filter(Boolean).map((s) => ` (${s})`).join("")}`)
EOF

# .gitignore: what Claude last saw of each spec is per checkout, so a teammate's changes show up after a pull.
# Compare lines without CR line endings, trailing whitespace or a leading "/", so an existing entry is recognised.
# One awk reading the file itself, not a pipeline: under pipefail, a grep -q that stops early fails the pipe.
if ! awk '{ sub(/\r$/, ""); sub(/[ \t]+$/, ""); sub(/^\//, "") } $0 == "specs/.last-seen.json" { found = 1 } END { exit !found }' \
  "$target/.gitignore" 2>/dev/null; then
  { [[ -s "$target/.gitignore" && -n "$(tail -c1 "$target/.gitignore")" ]] && echo; echo "specs/.last-seen.json"; } >> "$target/.gitignore"
  echo "  append  .gitignore (specs/.last-seen.json)"
else
  echo "  keep    .gitignore"
fi

# CLAUDE.md: append the rules block once. --update replaces it in place, including a block
# written before the rename (marked spec-kit:start / spec-kit:end).
if grep -qsE "(rdd|spec-kit):start" "$target/CLAUDE.md"; then
  if [[ "$update" == --update ]]; then
    node - "$target/CLAUDE.md" "$tpl/CLAUDE.spec-rules.md" <<'EOF'
const fs = require("node:fs")
const [file, rules] = process.argv.slice(2)
const block = fs.readFileSync(rules, "utf8").trimEnd()
const text = fs.readFileSync(file, "utf8")
fs.writeFileSync(file, text.replace(/<!-- (rdd|spec-kit):start -->[\s\S]*?<!-- (rdd|spec-kit):end -->/, () => block))
EOF
    echo "  update  CLAUDE.md (spec rules)"
  else
    echo "  keep    CLAUDE.md (spec rules already present)"
  fi
else
  { [[ -s "$target/CLAUDE.md" ]] && echo; cat "$tpl/CLAUDE.spec-rules.md"; } >> "$target/CLAUDE.md"
  echo "  append  CLAUDE.md"
fi

echo "Done. In Claude Code, run /spec-new <Name>: <what it's for>, or list what you need in specs/outline.md and run /spec-new"
echo "     Without Claude: node scripts/spec-lint.mjs --scaffold, or --new screen <Name>"
