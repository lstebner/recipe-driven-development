#!/usr/bin/env bash
# Install Recipe-Driven Development into a repo. Safe to re-run: existing files are never overwritten
# (spec-lint.mjs, the two skills and the CLAUDE.md rules block are refreshed only with --update).
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

echo "Installing Recipe-Driven Development into $target"
for f in README.md tokens.md _templates/{screen,component,flow,model,api}.md; do
  copy "$tpl/specs/$f" "$target/specs/$f"
done
mkdir -p "$target"/specs/{screens,components,flows,models,apis,_reports}
copy "$tpl/scripts/spec-lint.mjs" "$target/scripts/spec-lint.mjs" yes
for s in spec-review spec-verify; do
  copy "$tpl/.claude/skills/$s/SKILL.md" "$target/.claude/skills/$s/SKILL.md" yes
done

# Hooks: merge into .claude/settings.json without touching anything else in it.
node - "$target/.claude/settings.json" <<'EOF'
const fs = require("node:fs")
const file = process.argv[2]
const settings = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {}
settings.hooks ??= {}
const entry = (matcher, flag) => ({
  matcher,
  hooks: [{ type: "command", command: `node "$CLAUDE_PROJECT_DIR/scripts/spec-lint.mjs" ${flag}` }],
})
let added = false
for (const [event, matcher, flag] of [
  ["PreToolUse", "Edit|Write|MultiEdit", "--hook-pre"],
  ["PreToolUse", "Bash", "--hook-bash"],
  ["PostToolUse", "Edit|Write|MultiEdit", "--hook-post"],
]) {
  settings.hooks[event] ??= []
  if (!JSON.stringify(settings.hooks[event]).includes(`spec-lint.mjs\\" ${flag}`)) {
    settings.hooks[event].push(entry(matcher, flag))
    added = true
  }
}
fs.mkdirSync(require("node:path").dirname(file), { recursive: true })
fs.writeFileSync(file, JSON.stringify(settings, null, 2) + "\n")
console.log(`  ${added ? "hooks  " : "keep   "} .claude/settings.json`)
EOF

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

echo "Done. Start a spec with: cp specs/_templates/screen.md specs/screens/<Name>.md"
