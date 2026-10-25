#!/usr/bin/env bash
# End-to-end check of Recipe-Driven Development in a throwaway repo: install, lint, fix, hooks, tasting.
set -uo pipefail
kit="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT
fails=0
pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; echo "$2" | sed 's/^/      /'; fails=$((fails + 1)); }
lint() { node "$repo/scripts/spec-lint.mjs" --root "$repo" "$@" 2>&1; }
expect_ok() { local out; out="$(lint)" && pass "$1" || fail "$1" "$out"; }  # extra args ignored, so mutate can use it
expect_err() { # expect_err <name> <substring>
  local out; out="$(lint)"
  [[ $? -ne 0 && "$out" == *"$2"* ]] && pass "$1" || fail "$1" "$out"
}
expect_warn() { local out; out="$(lint)"; [[ "$out" == *"$2"* ]] && pass "$1" || fail "$1" "$out"; }
hook() { # hook <pre|bash|post> <json>
  echo "$2" | CLAUDE_PROJECT_DIR="$repo" node "$repo/scripts/spec-lint.mjs" "--hook-$1" 2>&1
}
bash_json() { node -e 'console.log(JSON.stringify({ tool_name: "Bash", tool_input: { command: process.argv[1] } }))' "$1"; }
write_json() { node -e 'console.log(JSON.stringify({ tool_name: "Write", tool_input: { file_path: process.argv[1], content: process.argv[2] } }))' "$1" "$2"; }
edit_json() { # edit_json <file> <old> <new>
  node -e 'console.log(JSON.stringify({ tool_name: "Edit", tool_input: { file_path: process.argv[1], old_string: process.argv[2], new_string: process.argv[3] } }))' "$1" "$2" "$3"
}

deprecate_json() { # deprecate_json <file> <frontmatter that replaces "status: approved"> [decision]: a Write that deprecates, with a Decisions line
  node -e '
    const fs = require("fs"); const [file, fm, decision] = process.argv.slice(1); const t = fs.readFileSync(file, "utf8")
    let after = t.replace("status: approved", fm)
    if (decision) after = /^## Decisions$/m.test(after) ? after.replace(/^## Decisions\n/m, `## Decisions\n${decision}\n`) : `${after.trimEnd()}\n\n## Decisions\n${decision}\n`
    console.log(JSON.stringify({ tool_name: "Write", tool_input: { file_path: file, content: after } }))' "$1" "$2" "${3:-}"
}

echo "install"
out="$("$kit/install.sh" "$repo")" || fail "install" "$out"
out2="$("$kit/install.sh" "$repo")"
version="$(node "$kit/template/scripts/spec-lint.mjs" --version)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && pass "--version prints the kit version" || fail "--version" "$version"
grep -q "^## $version " "$kit/CHANGELOG.md" && pass "CHANGELOG.md has an entry for $version" || fail "changelog entry" "no '## $version' heading in CHANGELOG.md"
[[ "$out" == *"Recipe-Driven Development $version into"* && "$out2" == *"already at $version"* ]] \
  && pass "install names the version, and says when a repo is already at it" || fail "install version" "$out"$'\n'"$out2"
older="$(mktemp -d)"; "$kit/install.sh" "$older" >/dev/null
sed -i '/^const VERSION = /d' "$older/scripts/spec-lint.mjs"
out="$("$kit/install.sh" "$older")"
[[ "$out" == *"this repo has a version before 0.1.0; run with --update"* ]] && pass "install points an older repo at --update" || fail "install older" "$out"
out="$("$kit/install.sh" "$older" --update)"
[[ "$out" == *"updating from a version before 0.1.0 to $version"* && "$(node "$older/scripts/spec-lint.mjs" --version)" == "$version" ]] \
  && pass "--update says which version it's updating from" || fail "--update version" "$out"
sed -i 's/^const VERSION = .*/const VERSION = "9.9.9"/' "$older/scripts/spec-lint.mjs"
out="$("$kit/install.sh" "$older" --update 2>&1)"; code=$?
[[ $code -ne 0 && "$out" == *"9.9.9, which is newer than this kit"* && "$(node "$older/scripts/spec-lint.mjs" --version)" == "9.9.9" ]] \
  && pass "--update refuses to downgrade" || fail "--update downgrade" "$out"
out="$("$kit/install.sh" "$older" 2>&1)"; [[ $? -eq 0 && "$out" == *"newer than this kit"* ]] && pass "  ...and a plain install says the repo is newer" || fail "install newer" "$out"
echo "my notes" >> "$older/specs/README.md"
"$kit/install.sh" "$older" >/dev/null 2>&1
grep -q "^my notes$" "$older/specs/README.md" && pass "a plain install keeps specs/README.md" || fail "install keeps format docs" "$(tail -2 "$older/specs/README.md")"
sed -i 's/^const VERSION = .*/const VERSION = "0.0.1"/' "$older/scripts/spec-lint.mjs"
"$kit/install.sh" "$older" --update >/dev/null 2>&1
cmp -s "$older/specs/README.md" "$kit/template/specs/README.md" && pass "--update refreshes specs/README.md, the format docs" || fail "--update format docs" "$(tail -2 "$older/specs/README.md")"
grep -q "^my notes$" "$older/specs/README.md.old" && pass "  ...keeping the old copy as specs/README.md.old" || fail "format docs backup" "$(ls "$older/specs")"
rm "$older/specs/README.md.old"; "$kit/install.sh" "$older" --update >/dev/null 2>&1
[[ ! -e "$older/specs/README.md.old" ]] && pass "  ...but only when it differs from the kit's" || fail "needless backup" "$(ls "$older/specs")"
rm -rf "$older"
[[ "$(grep -c spec-lint.mjs "$repo/.claude/settings.json")" == 6 && "$(grep -c rdd:start "$repo/CLAUDE.md")" == 1 && "$(grep -cxF specs/.last-seen.json "$repo/.gitignore")" == 1 ]] \
  && pass "install is idempotent" || fail "install is idempotent" "$out2"
[[ -f "$repo/.claude/skills/spec-new/SKILL.md" && -f "$repo/.claude/skills/spec-review/SKILL.md" && -f "$repo/.claude/skills/spec-verify/SKILL.md" ]] \
  && pass "install adds the three skills" || fail "skills installed" "$(ls "$repo/.claude/skills")"
old="$(mktemp -d)"
printf '# Mine\n\n<!-- spec-kit:start -->\nold rules\n<!-- spec-kit:end -->\n\nafter\n' > "$old/CLAUDE.md"
mkdir -p "$old/.claude"
echo '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"node \"$CLAUDE_PROJECT_DIR/scripts/spec-lint.mjs\" --hook-pre"}]}]}}' > "$old/.claude/settings.json"
"$kit/install.sh" "$old" --update >/dev/null
[[ "$(grep -c rdd:start "$old/CLAUDE.md")" == 1 && "$(grep -c spec-kit "$old/CLAUDE.md")" == 0 && "$(grep -c '^after$' "$old/CLAUDE.md")" == 1 ]] \
  && pass "--update replaces an old spec-kit rules block in place" || fail "--update rules block" "$(cat "$old/CLAUDE.md")"
[[ "$(grep -c spec-lint.mjs "$old/.claude/settings.json")" == 6 ]] && pass "re-install adds the missing hooks" || fail "hook merge" "$(cat "$old/.claude/settings.json")"
node -e 'const s = require(process.argv[1]); process.exit(s.spinnerVerbs?.mode === "replace" && s.spinnerVerbs.verbs.includes("Checking the pantry") ? 0 : 1)' "$repo/.claude/settings.json" \
  && pass "install sets kitchen spinner verbs" || fail "spinner verbs" "$(cat "$repo/.claude/settings.json")"
mine="$(mktemp -d)"; mkdir -p "$mine/.claude"; echo '{"spinnerVerbs":{"mode":"append","verbs":["Mine"]}}' > "$mine/.claude/settings.json"
"$kit/install.sh" "$mine" >/dev/null
node -e 'const s = require(process.argv[1]); process.exit(JSON.stringify(s.spinnerVerbs) === JSON.stringify({ mode: "append", verbs: ["Mine"] }) ? 0 : 1)' "$mine/.claude/settings.json" \
  && pass "install keeps a repo's own spinner verbs" || fail "spinner verbs kept" "$(cat "$mine/.claude/settings.json")"
rm -rf "$mine"
rm -rf "$old"

cat > "$repo/specs/tokens.md" <<'EOF'
---
status: approved
---
## Color
| token | value |
|---|---|
| color.accent | #3355ff |
## Radius & shadow
| token | value |
|---|---|
| radius.md | 8px |
| shadow.card | 0 1px 3px #0003 |
EOF
cat > "$repo/specs/screens/AlbumDetail.md" <<'EOF'
---
screen: AlbumDetail
status: approved
uses: [ArtistBadge, PrimaryButton]
local: [ReleaseTimeline]
source: [src/AlbumDetail.tsx]
---
## Goal
Let a listener see an album's details and release history, and buy it.

## Layout
- Header: [[ArtistBadge variant=compact]] · {copy.title}
- Body (≥md: row · <md: stack)
  - [[~ReleaseTimeline]]                  → R2
  - ?!owned [[PrimaryButton]] {copy.buy}  → R1
  - ?owned {copy.owned}                   → R1

## Rules
- AlbumDetail.R1: Buy is hidden when owned.
- AlbumDetail.R2: Timeline is newest first.

## Copy
| key | text |
|---|---|
| title | {album.title} |
| buy | Buy for {price} |
| owned | In your library |

## Style
- Artwork uses $radius.md and $shadow.card.

## Open amendments

## Decisions
EOF
for c in ArtistBadge PrimaryButton; do
  cat > "$repo/specs/components/$c.md" <<EOF
---
component: $c
status: approved
---
## Purpose
The $c.

## Variants
- default: standard
- compact: small

## Must not
- Fetch data.
EOF
done
mkdir -p "$repo/src"
cat > "$repo/src/AlbumDetail.tsx" <<'EOF'
import { ArtistBadge } from "@repo/ui"
import PrimaryButton from "@repo/ui/PrimaryButton"
export const AlbumDetail = () => null
EOF
cat > "$repo/src/AlbumDetail.test.tsx" <<'EOF'
it("[AlbumDetail.R1] hides buy when owned", () => {})
EOF

echo "lint"
expect_err "stale Used by is an error" '"Used by" is stale'
out="$(lint --fix)" && pass "--fix generates Used by and lint passes" || fail "--fix" "$out"
grep -q "^- AlbumDetail (screen)$" "$repo/specs/components/ArtistBadge.md" && pass "Used by lists AlbumDetail" || fail "Used by content" "$(cat "$repo/specs/components/ArtistBadge.md")"
out="$(lint --fix)"; [[ "$out" != *updated* ]] && pass "--fix is idempotent" || fail "--fix idempotent" "$out"
out="$(lint --summary)"
[[ "$out" == *"1/2"* && "$out" == *"~ReleaseTimeline"* && "$out" == *"ArtistBadge"*"← AlbumDetail"* ]] && pass "summary shows coverage + shared/one-off" || fail "summary" "$out"

screen="$repo/specs/screens/AlbumDetail.md"
mutate() { # mutate <name> <expect_err|expect_warn> <substring> <sed expr>
  cp "$screen" "$screen.bak"; sed -i "$4" "$screen"; "$2" "$1" "$3"; mv "$screen.bak" "$screen"
}
mutate "unknown component ref"   expect_err  "[[Ghost]] has no spec"               's/\[\[PrimaryButton\]\]/[[Ghost]]/'
mutate "bad copy key"            expect_err  "{copy.buyy} isn't in the Copy table" 's/{copy.buy}/{copy.buyy}/'
mutate "ref missing from uses"   expect_err  "not in \"uses\""                     's/^uses: .*/uses: [ArtistBadge]/'
mutate "unknown variant"         expect_err  'no variant "tiny"'                   's/variant=compact/variant=tiny/'
mutate "one-off with shared spec" expect_err "marked one-off but a shared spec"    's/\[\[~ReleaseTimeline\]\]/[[~ArtistBadge]]/'
mutate "rule link to missing rule" expect_err "AlbumDetail.R9, which isn't in Rules" 's/→ R2/→ R9/'
mutate "rule without ID"         expect_err  "rule has no ID"                      's/^- AlbumDetail.R2: /- /'
mutate "duplicate rule ID"       expect_err  "duplicate rule ID"                   's/AlbumDetail.R2:/AlbumDetail.R1:/'
mutate "rule prefixed with another spec" expect_err "belongs to another spec"      's/^- AlbumDetail.R2:/- Other.R2:/'
mutate "short rule IDs"          expect_ok   ""                                    's/^- AlbumDetail\.R\([12]\):/- R\1:/'
mutate "uses and local can be left out" expect_ok ""                               '/^uses:/d; /^local:/d'
mutate "unknown token"           expect_err  'unknown token $radius.xl'            's/\$radius.md/$radius.xl/'
mutate "raw value in Style"      expect_warn 'raw value "#fff"'                    's/and \$shadow.card/and #fff/'
mutate "missing required section" expect_err 'missing required section "## Goal"'  's/^## Goal/## Purpose/'
echo 'import { PrimaryButton } from "x"' > "$repo/src/Other.tsx"
mutate "implemented but import missing" expect_err "uses ArtistBadge but its source never imports it" 's/^status: approved/status: implemented/; s#^source: .*#source: [src/Other.tsx]#'
mutate "draft with empty Rules is only a warning" expect_warn 'Rules needs at least one rule' 's/^status: approved/status: draft/; /^- AlbumDetail.R/d; s/→ R[12]//'
cp "$screen" "$screen.bak"; sed -i 's/^status: approved/status: draft/; /^- AlbumDetail.R/d; s/→ R[12]//' "$screen"
out="$(lint)" && pass "  ...and doesn't fail the lint" || fail "draft leniency" "$out"; mv "$screen.bak" "$screen"
cp "$repo/specs/components/ArtistBadge.md" "$repo/specs/components/Other.md"
sed -i 's/^component: ArtistBadge/component: Other/; s/^uses: .*/uses: []/' "$repo/specs/components/Other.md"
cp "$screen" "$repo/specs/screens/Second.md"
sed -i 's/^screen: AlbumDetail/screen: Second/; s/AlbumDetail\.R/Second.R/g; /^source:/d' "$repo/specs/screens/Second.md"
lint --fix >/dev/null
expect_warn "same one-off in two specs warns" "also appears in Second — should it be shared?"
rm "$repo/specs/screens/Second.md" "$repo/specs/components/Other.md"; lint --fix >/dev/null

echo "flows, models, apis"
cat > "$repo/specs/models/Album.md" <<'EOF'
---
model: Album
status: approved
---
## Purpose
An album listed for sale.

## Fields
| field | type | required | notes |
|---|---|---|---|
| id | uuid | yes | |
| price | money | yes | |

## Rules
- Album.R1: price is never negative.
EOF
cat > "$repo/specs/apis/GetAlbum.md" <<'EOF'
---
api: GetAlbum
status: approved
endpoint: GET /albums/{id}
---
## Purpose
Fetch one album.

## Response
200: [[model:Album]]

## Errors
| code | status | when |
|---|---|---|
| not_found | 404 | no such album |

## Rules
- GetAlbum.R1: An unlisted album returns not_found.
EOF
cat > "$repo/specs/flows/Checkout.md" <<'EOF'
---
flow: Checkout
status: approved
---
## Goal
Buy an album.

## Steps
1. [[screen:AlbumDetail]] calls [[api:GetAlbum]]
   - ?[[api:GetAlbum#not_found]] → end      → R1
2. Pay, using [[model:Album#price]]
   - ?declined → step 2                   → R1

## Rules
- Checkout.R1: Failures never lose the listener's place.
EOF
expect_err "new Used by is stale until --fix" "specs/models/Album.md:"
out="$(lint --fix)" && pass "flow, model and api lint clean after --fix" || fail "new kinds --fix" "$out"
grep -q "^- GetAlbum (api)$" "$repo/specs/models/Album.md" && grep -q "^- Checkout (flow)$" "$repo/specs/apis/GetAlbum.md" \
  && pass "Used by lists who references models and APIs" || fail "Used by for models/apis" "$(cat "$repo/specs/models/Album.md" "$repo/specs/apis/GetAlbum.md")"
out="$(lint --summary)"; [[ "$out" == *"Models, APIs & policies"*"Album"*"← Checkout, GetAlbum"* ]] && pass "summary lists model and API users" || fail "summary models" "$out"
flow="$repo/specs/flows/Checkout.md"
mutate_in() { # mutate_in <file> <name> <expect_err|expect_warn> <substring> <sed expr>
  cp "$1" "$1.bak"; sed -i "$5" "$1"; "$3" "$2" "$4"; mv "$1.bak" "$1"
}
mutate_in "$flow" "flow: unknown screen"     expect_err "[[screen:Nope]] has no spec"        's/screen:AlbumDetail/screen:Nope/'
mutate_in "$flow" "flow: wrong kind of ref"  expect_err "[[model:GetAlbum]] has no spec"      's/\[\[api:GetAlbum\]\]/[[model:GetAlbum]]/'
mutate_in "$flow" "flow: step that doesn't exist" expect_err "goes to step 7"              's/→ step 2/→ step 7/'
mutate_in "$flow" "flow: unknown error code" expect_err 'GetAlbum has no error code "gone"'  's/#not_found/#gone/'
mutate_in "$flow" "flow: unknown model field" expect_err 'Album has no field "cost"'         's/#price/#cost/'
mutate_in "$flow" "flow: rule link checked in Steps" expect_err "Checkout.R4, which isn't in Rules" 's/→ R1$/→ R4/'
mutate_in "$flow" "flow: Steps required"     expect_err 'missing required section "## Steps"' 's/^## Steps/## Stages/'
mutate_in "$repo/specs/apis/GetAlbum.md" "api: endpoint required" expect_err 'missing "endpoint"' '/^endpoint:/d'
mutate_in "$repo/specs/models/Album.md" "model: duplicate field" expect_err 'duplicate key "id"' 's/^| price |/| id |/'
cp "$repo/specs/apis/GetAlbum.md" "$repo/specs/apis/GetAlbum2.md"; sed -i 's/^api: GetAlbum$/api: GetAlbum2/; s/GetAlbum\.R/GetAlbum2.R/' "$repo/specs/apis/GetAlbum2.md"
expect_err "two APIs can't claim one endpoint" 'endpoint "GET /albums/{id}" is also specced by GetAlbum'
rm "$repo/specs/apis/GetAlbum2.md"
cp "$repo/specs/models/Album.md" "$repo/specs/apis/Album.md"; sed -i 's/^model: Album$/api: Album\nendpoint: GET \/x/' "$repo/specs/apis/Album.md"
expect_err "names are unique across kinds" "the name Album is already taken"
rm "$repo/specs/apis/Album.md"; lint --fix >/dev/null

echo "policies"
policy="$repo/specs/policies/NavLinks.md"
mkdir -p "$repo/specs/policies"
cat > "$policy" <<'EOF'
---
policy: NavLinks
status: approved
---
## Purpose
Which navigation links a visitor sees.

## Inputs
| input | type | notes |
|---|---|---|
| user | [[model:Album]] | absent when signed out |
| region | string | |

## Output
An ordered list of links.

## Rules
- NavLinks.R1: Signed-out visitors see Home and Sign in.
EOF
for c in MobileNav DesktopNav; do
  cat > "$repo/specs/components/$c.md" <<EOF
---
component: $c
status: approved
---
## Purpose
The $c.

## Layout
- One row per link from [[policy:NavLinks]]  → R1

## Rules
- R1: Shows exactly the links [[policy:NavLinks]] gives, in its order.
EOF
done
expect_err "a new policy's Used by is stale until --fix" "specs/policies/NavLinks.md:"
out="$(lint --fix)" && pass "policies lint clean after --fix" || fail "policy --fix" "$out"
grep -q "^- DesktopNav (component)$" "$policy" && grep -q "^- MobileNav (component)$" "$policy" \
  && pass "Used by lists every spec that relies on a policy" || fail "policy Used by" "$(cat "$policy")"
out="$(lint --summary)"; [[ "$out" == *"NavLinks"*"← DesktopNav, MobileNav"* ]] && pass "summary lists policy users" || fail "summary policies" "$out"
mutate_in "$repo/specs/components/MobileNav.md" "policy: unknown policy ref" expect_err "[[policy:Nope]] has no spec — create specs/policies/Nope.md" 's/policy:NavLinks\]\]  →/policy:Nope]]  →/'
mutate_in "$repo/specs/components/MobileNav.md" "policy: no members" expect_err "only models (#field) and APIs (#error_code) have members" 's/policy:NavLinks\]\]  →/policy:NavLinks#admin]]  →/'
mutate_in "$policy" "policy: duplicate input" expect_err 'duplicate key "user" in Inputs' 's/^| region |/| user |/'
mutate_in "$policy" "policy: Rules required" expect_err 'missing required section "## Rules"' 's/^## Rules/## Notes/'
nav="$repo/specs/components/MobileNav.md"
navhash="$(lint --hash MobileNav)"
cp "$policy" "$policy.bak"; sed -i 's/see Home and Sign in./see Home only./' "$policy"
[[ "$(lint --hash MobileNav)" != "$navhash" ]] && pass "a spec's fingerprint covers the policies it references" || fail "policy in fingerprint" "$navhash"
mv "$policy.bak" "$policy"
[[ "$(lint --hash MobileNav)" == "$navhash" ]] && pass "  ...and only their content" || fail "policy fingerprint stable" "$(lint --hash MobileNav)"
printf '# MobileNav: verification report\nSpec: %s\n\n| rule | result | evidence |\n|---|---|---|\n| MobileNav.R1 | ✅ | test |\n' "$navhash" > "$repo/specs/_reports/MobileNav.md"
sed -i 's/^status: approved/status: verified/' "$nav"
expect_ok "a verified spec that relies on a policy lints clean"
mutate_in "$policy" "changing a policy makes a verified spec that relies on it stale" expect_err "older version of the spec or a policy it relies on (NavLinks)" 's/see Home and Sign in./see Home only./'
out="$(hook pre "$(edit_json "$policy" "see Home and Sign in." "see Home only.")")"
[[ "$out" == *'"permissionDecision":"ask"'* && "$out" == *"Rules"* && "$out" == *"DesktopNav, MobileNav rely on NavLinks; MobileNav will need re-verifying."* ]] \
  && pass "pre: changing a policy asks, naming the specs that rely on it" || fail "pre: policy Rules" "$out"
out="$(hook pre "$(deprecate_json "$policy" $'status: deprecated\ndeprecated: 2026-10-25' "- 2026-10-25: Deprecated: navigation moved to the sidebar.")")"
[[ "$out" == *'"ask"'* && "$out" == *"get a lint warning (DesktopNav, MobileNav)"* ]] && pass "pre: deprecating a policy names the specs that rely on it" || fail "pre: deprecate policy" "$out"
cp "$policy" "$policy.bak"; sed -i 's/^status: approved$/status: deprecated\ndeprecated: 2026-10-25/' "$policy"
[[ "$(lint --hash MobileNav)" == "$navhash" ]] && pass "deprecating a policy leaves the fingerprints of specs that use it alone" || fail "deprecated policy fingerprint" "$(lint)"
mv "$policy.bak" "$policy"
cp "$policy" "$policy.bak"; sed -i 's/^status: approved$/status: draft/' "$policy"
expect_err "a verified spec can't rely on a draft policy" "[[policy:NavLinks]] is still a draft, and its rules are part of what MobileNav asks for"
out="$(lint)"; [[ "$out" == *"DesktopNav.md"*"warning"*"is still a draft"* ]] && pass "  ...and an approved one is warned" || fail "approved on draft policy" "$out"
mv "$policy.bak" "$policy"
cat >> "$repo/specs/components/DesktopNav.md" <<'EOF'

## Inputs
| input | notes |
|---|---|
| user | |
| user | again |
EOF
out="$(lint)"; [[ "$out" != *'duplicate key "user"'* ]] && pass "only policies have their Inputs keys checked" || fail "inputs on a component" "$out"
cp "$policy" "$policy.bak"; sed -i 's/^Which navigation links a visitor sees.$/Which links a visitor sees in the navigation./' "$policy"
[[ "$(lint --hash MobileNav)" == "$navhash" ]] && pass "editing a policy's Purpose leaves dependent fingerprints alone" || fail "policy Purpose in fingerprint" "$(lint --hash MobileNav)"
mv "$policy.bak" "$policy"
out="$(hook pre "$(edit_json "$policy" "Which navigation links a visitor sees." "Which links a visitor sees.")")"
[[ "$out" == *'"ask"'* && "$out" != *"rely on NavLinks"* && "$out" != *"relies on NavLinks"* ]] && pass "pre: a Purpose edit to a policy doesn't send anyone back to re-verify" || fail "pre: policy Purpose" "$out"
order="$repo/specs/policies/NavOrder.md"
printf -- '---\npolicy: NavOrder\nstatus: approved\n---\n## Purpose\nThe order navigation links appear in.\n\n## Rules\n- R1: Home always comes first.\n' > "$order"
sed -i 's/^- NavLinks.R1: Signed-out visitors see Home and Sign in.$/- NavLinks.R1: Signed-out visitors see Home and Sign in, ordered by [[policy:NavOrder]]./' "$policy"
lint --fix >/dev/null
chainhash="$(lint --hash MobileNav)"
sed -i "s/^Spec: .*/Spec: $chainhash/" "$repo/specs/_reports/MobileNav.md"
expect_ok "a spec that relies on a chain of policies lints clean"
mutate_in "$order" "changing a policy reached through another makes the spec stale, naming the trail" expect_err "a policy it relies on (NavLinks, NavOrder (through NavLinks))" 's/Home always comes first./Home always comes last./'
out="$(hook pre "$(edit_json "$order" "Home always comes first." "Home always comes last.")")"
[[ "$out" == *"DesktopNav, MobileNav, NavLinks rely on NavOrder; MobileNav will need re-verifying."* ]] && pass "pre: changing it names every spec it reaches, through other policies too" || fail "pre: policy chain" "$out"
mutate_in "$order" "a draft policy reached through another is caught too" expect_err "[[policy:NavOrder]] (through NavLinks) is still a draft" 's/^status: approved$/status: draft/'
mv "$nav" "$nav.bak"; mv "$repo/specs/components/DesktopNav.md" "$repo/specs/components/DesktopNav.md.bak"
out="$(hook pre "$(edit_json "$order" "Home always comes first." "Home always comes last.")")"
[[ "$out" == *" NavLinks relies on NavOrder."* ]] && pass "pre: one spec relies, several rely" || fail "pre: grammar" "$out"
mv "$nav.bak" "$nav"; mv "$repo/specs/components/DesktopNav.md.bak" "$repo/specs/components/DesktopNav.md"; rm "$order"
rm "$policy" "$nav" "$repo/specs/components/DesktopNav.md" "$repo/specs/_reports/MobileNav.md"; lint --fix >/dev/null

echo "hooks"
out="$(hook pre "$(edit_json "$screen" "Buy is hidden when owned." "Buy is always shown.")")"
[[ "$out" == *'"permissionDecision":"ask"'* && "$out" == *"Rules"* ]] && pass "pre: editing Rules of approved spec asks" || fail "pre: Rules" "$out"
out="$(hook pre "$(edit_json "$screen" $'## Open amendments\n' $'## Open amendments\n### A1: thing\n- Finding: x\n')")"
[[ -z "$out" ]] && pass "pre: adding an amendment doesn't ask" || fail "pre: amendment" "$out"
cp "$screen" "$screen.bak"
sed -i 's/^## Open amendments$/## Open amendments\n### A1: Show the year\n- Finding: x\n- Change: Rules + `R3: The year is shown.`/' "$screen"
out="$(hook pre "$(edit_json "$screen" $'- AlbumDetail.R2: Timeline is newest first.\n' $'- AlbumDetail.R2: Timeline is newest first.\n- AlbumDetail.R3: The year is shown.\n')")"
[[ "$out" == *'"ask"'* && "$out" != *"Accept amendment"* ]] && pass "pre: a rule change with the amendment still open asks plainly" || fail "pre: amendment open" "$out"
apply="$(node -e '
  const fs = require("fs"); const t = fs.readFileSync(process.argv[1], "utf8")
  const after = t.replace(/### A1:[\s\S]*?(?=\n## )/, "").replace("- AlbumDetail.R2: Timeline is newest first.\n", "- AlbumDetail.R2: Timeline is newest first.\n- AlbumDetail.R3: The year is shown.\n")
  console.log(JSON.stringify({ tool_name: "Write", tool_input: { file_path: process.argv[1], content: after } }))' "$screen")"
out="$(hook pre "$apply")"
[[ "$out" == *'"ask"'* && "$out" == *"Accept amendment A1 (Show the year): Rules + "* && "$out" == *Rules* ]] && pass "pre: applying an amendment asks to accept it by name" || fail "pre: apply amendment" "$out"
mv "$screen.bak" "$screen"
out="$(hook pre "$(edit_json "$screen" $'## Goal\n' $'# Album detail\n\n## Goal\n')")"
[[ "$out" == *'"ask"'* && "$out" == *"intro"* ]] && pass "pre: text before the first heading is protected" || fail "pre: intro" "$out"
out="$(hook pre "$(edit_json "$screen" "status: approved" "status: implemented")")"
[[ -z "$out" ]] && pass "pre: approved → implemented doesn't ask" || fail "pre: status progress" "$out"
out="$(hook pre "$(edit_json "$screen" "uses: [ArtistBadge, PrimaryButton]" "uses: [ArtistBadge]")")"
[[ "$out" == *'"ask"'* && "$out" == *frontmatter* ]] && pass "pre: changing uses asks" || fail "pre: uses" "$out"
out="$(hook pre "$(edit_json "$screen" "- AlbumDetail.R2: Timeline is newest first."$'\n' "")")"
[[ "$out" == *'"ask"'* ]] && pass "pre: deleting a rule asks" || fail "pre: delete rule" "$out"
sed -i 's/^status: approved/status: draft/' "$repo/specs/components/ArtistBadge.md"
out="$(hook pre "$(edit_json "$repo/specs/components/ArtistBadge.md" "The ArtistBadge." "Anything.")")"
[[ -z "$out" ]] && pass "pre: editing a draft doesn't ask" || fail "pre: draft" "$out"
out="$(hook pre "$(edit_json "$repo/specs/components/ArtistBadge.md" "status: draft" "status: approved")")"
[[ "$out" == *'"ask"'* ]] && pass "pre: draft → approved asks" || fail "pre: approve" "$out"
out="$(hook pre "$(node -e 'console.log(JSON.stringify({tool_name:"Write",tool_input:{file_path:process.argv[1],content:"---\nscreen: AlbumDetail\nstatus: approved\n---\n## Goal\nOther\n"}}))' "$screen")")"
[[ "$out" == *'"ask"'* ]] && pass "pre: Write over approved spec asks" || fail "pre: Write" "$out"
out="$(hook pre "$(edit_json "$repo/src/AlbumDetail.tsx" "null" "1")")"
[[ -z "$out" ]] && pass "pre: non-spec files ignored" || fail "pre: non-spec" "$out"

out="$(hook pre "$(write_json "$repo/specs/screens/New.md" $'---\nscreen: New\nstatus: approved\n---\n## Goal\nx\n')")"
[[ "$out" == *'"ask"'* ]] && pass "pre: creating a spec straight into approved asks" || fail "pre: new approved" "$out"
out="$(hook pre "$(write_json "$repo/specs/screens/New.md" $'---\nscreen: New\nstatus: draft\n---\n## Goal\nx\n')")"
[[ -z "$out" ]] && pass "pre: creating a draft doesn't ask" || fail "pre: new draft" "$out"

echo "tasting"
hash="$(lint --hash AlbumDetail)"
[[ "$hash" =~ ^[0-9a-f]{12}$ ]] && pass "--hash prints a fingerprint" || fail "--hash" "$hash"
report="$repo/specs/_reports/AlbumDetail.md"
write_report() { # write_report <hash> <row>...
  local h="$1"; shift
  { echo "# AlbumDetail: verification report"; echo "Date: 2026-10-23 · Spec: $h · Status: implemented · Lint: clean"; echo
    echo "| rule | result | evidence |"; echo "|---|---|---|"; printf '%s\n' "$@"; } > "$report"
}
to_verified() { hook pre "$(edit_json "$screen" "status: approved" "status: verified")"; }
out="$(to_verified)"
[[ "$out" == *'"deny"'* && "$out" == *"no report"* ]] && pass "pre: verified without a report is refused" || fail "pre: no report" "$out"
write_report "$hash" "| AlbumDetail.R1 | ✅ | test |" "| AlbumDetail.R2 | ❌ | oldest first |"
out="$(to_verified)"
[[ "$out" == *'"deny"'* && "$out" == *"AlbumDetail.R2 as ❌"* ]] && pass "pre: a ❌ row is refused" || fail "pre: ❌ row" "$out"
write_report "$hash" "| AlbumDetail.R1 | ✅ | test |" "| Layout | ⚠️ | not checked |"
out="$(to_verified)"
[[ "$out" == *'"deny"'* && "$out" == *"no ✅ or 👤 row for AlbumDetail.R2"* && "$out" == *"Layout as ⚠️"* ]] && pass "pre: missing rule row and ⚠️ are refused" || fail "pre: missing row" "$out"
write_report "000000000000" "| AlbumDetail.R1 | ✅ | test |" "| AlbumDetail.R2 | ✅ | test |"
out="$(to_verified)"
[[ "$out" == *'"deny"'* && "$out" == *"older version"* ]] && pass "pre: a stale report is refused" || fail "pre: stale" "$out"
write_report "$hash" "| R1 | ✅ | test |" "| AlbumDetail.R2 | 👤 | needs a real device |" "| Layout | 👤 | visual |"
out="$(to_verified)"
[[ "$out" == *'"ask"'* && "$out" == *"1/2"* && "$out" == *"leaves AlbumDetail.R2, Layout for you to check by hand"* ]] \
  && pass "pre: 👤 rows pass through to the taste test, named" || fail "pre: 👤" "$out"
write_report "$hash" "| AlbumDetail.R1 | ✅ | test |" "| AlbumDetail.R2 | ✅ | test |"
out="$(to_verified)"
[[ "$out" == *'"ask"'* && "$out" == *"Taste test"* && "$out" == *"2/2"* && "$out" != *"by hand"* ]] && pass "pre: a passing report asks you to taste it" || fail "pre: taste" "$out"
sed -i 's/^status: approved/status: verified/' "$screen"
[[ "$(lint --hash AlbumDetail)" == "$hash" ]] && pass "status change doesn't change the fingerprint" || fail "hash stable" "$(lint --hash AlbumDetail)"
expect_ok "verified with a passing report lints clean"
out="$(hook pre "$(edit_json "$screen" "status: verified" "status: implemented")")"
[[ -z "$out" ]] && pass "pre: verified → implemented doesn't ask" || fail "pre: unverify" "$out"
cp "$screen" "$screen.bak"; sed -i 's/Timeline is newest first./Timeline is oldest first./' "$screen"
expect_err "changing a verified spec makes its report stale" "status is verified but"
mv "$screen.bak" "$screen"
write_report "$hash" "| AlbumDetail.R1 | ✅ | test |" "| AlbumDetail.R2 | ❌ | regressed |"
expect_err "verified with a failing report is a lint error" "marks AlbumDetail.R2 as ❌"
write_report "$hash" "| AlbumDetail.R1 | ✅ | test |" "| AlbumDetail.R2 | ✅ | test |"

echo "deprecation"
api="$repo/specs/apis/GetAlbum.md"
cp "$api" "$api.orig"
sed 's/^api: GetAlbum$/api: GetAlbumV2/; s/GetAlbum\.R/GetAlbumV2.R/; s/^status: approved/status: draft/' "$api" > "$repo/specs/apis/GetAlbumV2.md"
lint --fix >/dev/null
deprecate() { hook pre "$(deprecate_json "$api" "$1" "- 2026-10-24: Deprecated: GetAlbumV2 supersedes it.")"; }
out="$(deprecate "status: deprecated")"
[[ "$out" == *'"deny"'* && "$out" == *"must be the date it was deprecated"* ]] && pass "pre: deprecating without a date is refused" || fail "pre: no date" "$out"
out="$(deprecate $'status: deprecated\ndeprecated: 2026-10-24\nreplaced_by: Nope')"
[[ "$out" == *'"deny"'* && "$out" == *"Nope, which has no spec"* ]] && pass "pre: deprecating in favour of a missing spec is refused" || fail "pre: bad replacement" "$out"
out="$(deprecate $'status: deprecated\ndeprecated: 2026-02-30')"
[[ "$out" == *'"deny"'* && "$out" == *'(got \"2026-02-30\")'* ]] && pass "pre: a date that doesn't exist is refused" || fail "pre: impossible date" "$out"
out="$(deprecate $'status: deprecated\ndeprecated: 2026-10-24\nreplaced_by: Album')"
[[ "$out" == *'"deny"'* && "$out" == *"Album, which is a model spec; it must be another api spec"* ]] && pass "pre: a replacement of another kind is refused" || fail "pre: cross-kind replacement" "$out"
out="$(hook pre "$(node -e '
  const fs = require("fs"); const t = fs.readFileSync(process.argv[1], "utf8")
  const after = t.replace("status: approved", "status: deprecated\ndeprecated: 2026-10-24").replace("- Checkout (flow)\n", "")
  console.log(JSON.stringify({ tool_name: "Write", tool_input: { file_path: process.argv[1], content: after } }))' "$api")")"
[[ "$out" == *'"deny"'* && "$out" == *"edit of its own"*"Used by"* ]] && pass "pre: deprecating can't also change Used by or Open amendments" || fail "pre: deprecate + Used by" "$out"
out="$(hook pre "$(node -e '
  const fs = require("fs"); const t = fs.readFileSync(process.argv[1], "utf8")
  const after = t.replace("status: approved", "status: deprecated\ndeprecated: 2026-10-24").replace("returns not_found.", "returns 410.")
  console.log(JSON.stringify({ tool_name: "Write", tool_input: { file_path: process.argv[1], content: after } }))' "$api")")"
[[ "$out" == *'"deny"'* && "$out" == *"edit of its own"*"Rules"* ]] && pass "pre: deprecating alongside other changes is refused" || fail "pre: deprecate + change" "$out"
out="$(hook pre "$(edit_json "$repo/specs/apis/GetAlbumV2.md" "status: draft" $'status: deprecated\ndeprecated: 2026-10-24')")"
[[ "$out" == *'"deny"'* && "$out" == *"delete it instead"* ]] && pass "pre: a draft is deleted, not deprecated" || fail "pre: deprecate draft" "$out"
out="$(deprecate $'status: deprecated\ndeprecated: 2026-10-24\nreplaced_by: GetAlbumV2')"
[[ "$out" == *'"deny"'* && "$out" == *"GetAlbumV2, which is still a draft"* ]] && pass "pre: a draft can't be the replacement" || fail "pre: draft replacement" "$out"
sed -i 's/^status: draft$/status: approved/' "$repo/specs/apis/GetAlbumV2.md"
out="$(hook pre "$(node -e '
  const fs = require("fs"); const t = fs.readFileSync(process.argv[1], "utf8")
  const after = t.replace("status: approved", "status: deprecated\ndeprecated: 2026-10-24\nreplaced_by: GetAlbumV2").replace("## Purpose", "# A new title\n\n## Purpose")
  console.log(JSON.stringify({ tool_name: "Write", tool_input: { file_path: process.argv[1], content: after } }))' "$api")")"
[[ "$out" == *'"deny"'* && "$out" == *"edit of its own"*"intro"* ]] && pass "pre: deprecating can't also change the text before the first heading" || fail "pre: deprecate + intro" "$out"
out="$(hook pre "$(deprecate_json "$api" $'status: deprecated\ndeprecated: 2026-10-24\nreplaced_by: GetAlbumV2')")"
[[ "$out" == *'"deny"'* && "$out" == *"add a dated line under ## Decisions"*"use a single Write of the whole file, or a MultiEdit"* ]] && pass "pre: deprecating without a dated Decisions line is refused" || fail "pre: no decision" "$out"
out="$(deprecate $'status: deprecated\ndeprecated: 2026-10-24\nreplaced_by: GetAlbumV2')"
[[ "$out" == *'"ask"'* && "$out" == *"Deprecate GetAlbum (approved → deprecated), replaced by GetAlbumV2?"* ]] && pass "pre: deprecating asks, naming the replacement" || fail "pre: deprecate" "$out"
sed -i 's/^status: approved$/status: deprecated\ndeprecated: 2026-10-24\nreplaced_by: GetAlbumV2\nsource: [src\/gone.ts]/' "$api"
expect_err "a deprecated spec drops out of Used by" '"Used by" is stale'
lint --fix >/dev/null
expect_warn "a reference to a deprecated spec warns, naming the replacement" "[[api:GetAlbum]] points at GetAlbum, which is deprecated on 2026-10-24; use GetAlbumV2 instead"
expect_ok "  ...but deprecated specs aren't linted for content, sources or endpoints"
! grep -q "GetAlbum (api)" "$repo/specs/models/Album.md" && grep -q "GetAlbumV2 (api)" "$repo/specs/models/Album.md" \
  && pass "  ...and Used by lists only live specs" || fail "Used by without deprecated" "$(cat "$repo/specs/models/Album.md")"
out="$(hook pre "$(edit_json "$api" $'## Rules\n' $'## Decisions\n- note\n\n## Rules\n')")"
[[ "$out" == *'"deny"'* && "$out" == *"frozen"*"use GetAlbumV2 instead"* ]] && pass "pre: any edit to a deprecated spec is refused" || fail "pre: frozen" "$out"
out="$(hook pre "$(edit_json "$api" "status: deprecated" "status: approved")")"
[[ "$out" == *'"deny"'* ]] && pass "pre: Claude can't un-deprecate a spec" || fail "pre: undeprecate" "$out"
echo $'## APIs\n- GetAlbum' > "$repo/specs/outline.md.dep"; cp "$repo/specs/outline.md" "$repo/specs/outline.md.keep"; mv "$repo/specs/outline.md.dep" "$repo/specs/outline.md"
expect_err "a deprecated spec left in the outline is an error" "GetAlbum is deprecated on 2026-10-24; use GetAlbumV2 instead — take it off the outline"
mv "$repo/specs/outline.md.keep" "$repo/specs/outline.md"
mutate_in "$api" "deprecated needs a valid date" expect_err '"deprecated" must be the date' 's/^deprecated: .*/deprecated: last week/'
v2="$repo/specs/apis/GetAlbumV2.md"
cp "$v2" "$v2.bak"; sed -i 's/^status: draft$/status: approved/' "$v2"
out="$(hook pre "$(deprecate_json "$v2" $'status: deprecated\ndeprecated: 2026-10-25' "- 2026-10-25: Deprecated: not needed.")")"
[[ "$out" == *'"ask"'* && "$out" == *"Deprecated specs that name GetAlbumV2 as their replacement will keep pointing at it: GetAlbum."* ]] \
  && pass "pre: deprecating a replacement names the specs that point at it" || fail "pre: deprecate a replacement" "$out"
echo "export const x = 1" > "$repo/src/gone.ts"
v3="$repo/specs/apis/GetAlbumV3.md"
sed 's/GetAlbumV2/GetAlbumV3/g' "$v2" > "$v3"
sed -i 's/^status: approved$/status: deprecated\ndeprecated: 2026-10-25\nreplaced_by: GetAlbumV3/' "$v2"
out="$(lint --fix)"; code=$?
[[ $code -eq 0 && "$out" == *"[[api:GetAlbum]] points at GetAlbum, which is deprecated on 2026-10-24; use GetAlbumV3 instead"* && "$out" != *"use GetAlbumV2"* && "$out" != *"chain"* ]] \
  && pass "a chain of replacements is followed to its live end, without a warning" || fail "replacement chain" "$out"
out="$(hook post "$(edit_json "$repo/src/gone.ts" x y)")"
[[ "$out" == *"source of GetAlbum, which is deprecated on 2026-10-24; use GetAlbumV3 instead"* ]] && pass "  ...in the source reminder too" || fail "chain in post hook" "$out"
out="$(lint --summary)"; [[ "$out" == *"Deprecated (frozen):"*"GetAlbum "*"2026-10-24  → GetAlbumV3"* ]] && pass "  ...and in the summary" || fail "chain in summary" "$out"
rm "$v3"; sed -i '/^replaced_by: GetAlbumV3$/d' "$v2"
out="$(lint --fix)"; code=$?
[[ $code -eq 0 && "$out" == *"GetAlbum, which is deprecated on 2026-10-24; nothing live replaces it"* && "$out" != *"chain"* ]] \
  && pass "a chain that ends with no replacement says nothing live replaces it" || fail "chain to nothing" "$out"
sed -i 's/^deprecated: 2026-10-25$/deprecated: 2026-10-25\nreplaced_by: GetAlbum/' "$v2"
out="$(lint --fix)"; code=$?
[[ $code -eq 0 && "$out" == *"chain of replacements is broken: GetAlbum → GetAlbumV2 → GetAlbum goes round in a loop"* ]] \
  && pass "a loop in the chain only warns" || fail "chain loop" "$out"
rm "$v2"; out="$(lint --fix)"; code=$?
[[ $code -eq 0 && "$out" == *"chain of replacements is broken: GetAlbumV2 has no spec"* ]] && pass "  ...and so does a replacement that's been deleted" || fail "replacement deleted later" "$out"
mv "$v2.bak" "$v2"; lint --fix >/dev/null
badge="$repo/specs/components/ArtistBadge.md"
cp "$badge" "$badge.bak"; cp "$screen" "$screen.bak"
sed -i 's/^status: .*/status: deprecated\ndeprecated: 2026-10-24/' "$badge"; sed -i 's/variant=compact/variant=tiny/' "$screen"
expect_err "a deprecated component's variants are still checked" 'ArtistBadge has no variant "tiny"'
sed -i 's/\[\[ArtistBadge variant=tiny\]\]/[[~ArtistBadge]]/; /^uses:/d; /^local:/d' "$screen"
expect_err "a one-off can't take a deprecated component's name" "[[~ArtistBadge]] has the name of a shared component that's deprecated on 2026-10-24"
expect_warn "a source importing a deprecated component is told it's deprecated, not to add it to uses" "source imports ArtistBadge, which is deprecated on 2026-10-24"
mv "$badge.bak" "$badge"; mv "$screen.bak" "$screen"
mutate_in "$repo/specs/apis/GetAlbumV2.md" "replaced_by only on a deprecated spec" expect_err '"replaced_by" belongs only on a deprecated spec' 's/^status: approved$/status: approved\nreplaced_by: GetAlbum/'
mutate_in "$api" "a hand-deprecated spec can't be replaced by another kind" expect_err "replaced_by names Album, which is a model spec; it must be another api spec" 's/^replaced_by: GetAlbumV2$/replaced_by: Album/'
mutate_in "$api" "a hand-deprecated spec can't replace itself" expect_err "it can't be replaced by itself" 's/^replaced_by: GetAlbumV2$/replaced_by: GetAlbum/'
mutate_in "$api" "quoted deprecation values are read without their quotes" expect_ok "" 's/^deprecated: 2026-10-24$/deprecated: "2026-10-24"/; s/^replaced_by: GetAlbumV2$/replaced_by: "GetAlbumV2"/'
out="$(node "$repo/scripts/spec-lint.mjs" --root "$repo" --new api GetAlbum 2>&1)"; code=$?
[[ $code -eq 1 && "$out" == *"which is deprecated; a deprecated spec keeps its name for good"* ]] && pass "--new refuses a name a deprecated spec holds" || fail "--new deprecated name" "$out"
cp "$repo/specs/outline.md" "$repo/specs/outline.md.keep"; echo $'## APIs\n- GetAlbum' > "$repo/specs/outline.md"
out="$(node "$repo/scripts/spec-lint.mjs" --root "$repo" --scaffold 2>&1)"; code=$?
[[ $code -eq 1 && "$out" == *"which is deprecated; a deprecated spec keeps its name for good"* ]] && pass "  ...and so does --scaffold" || fail "--scaffold deprecated name" "$out"
mv "$repo/specs/outline.md.keep" "$repo/specs/outline.md"
mutate_in "$repo/specs/apis/GetAlbumV2.md" "a hand-deprecated spec can't be replaced by a draft" expect_err "GetAlbumV2, which is still a draft" 's/^status: approved$/status: draft/'
cp "$api" "$api.bak"; sed -i 's/^status: deprecated$/status: "deprecated"/' "$api"
out="$(hook pre "$(edit_json "$api" $'## Rules\n' $'## Rules\n\n')")"
[[ "$out" == *'"deny"'* && "$out" == *"frozen"* ]] && pass "a quoted status still freezes the spec" || fail "quoted status" "$out"
mv "$api.bak" "$api"
echo 'it("[GetAlbum.R1] unlisted is not_found", () => {})' > "$repo/src/GetAlbum.test.ts"
out="$(lint --summary)"
[[ "$out" == *"Deprecated (frozen):"*"GetAlbum "*"2026-10-24  → GetAlbumV2  ⚠ tests still tagged: GetAlbum.R1"* ]] && pass "summary lists deprecated specs and tests still tagged with their rules" || fail "summary deprecated" "$out"
echo "export const x = 1" > "$repo/src/gone.ts"
out="$(hook post "$(edit_json "$repo/src/gone.ts" x y)")"; code=$?
[[ $code -eq 0 && "$out" == *additionalContext*"source of GetAlbum, which is deprecated on 2026-10-24; use GetAlbumV2 instead"* ]] && pass "post: editing a deprecated spec's source reminds Claude" || fail "post: deprecated source" "$out"
rm "$repo/src/gone.ts" "$repo/src/GetAlbum.test.ts" "$repo/specs/apis/GetAlbumV2.md"
mv "$api.orig" "$api"; lint --fix >/dev/null
expect_ok "back to clean after deprecation tests"

echo "shell hook"
bash_asks() { local out; out="$(hook bash "$(bash_json "$2")")"; [[ "$out" == *'"ask"'* ]] && pass "$1" || fail "$1" "$out"; }
bash_quiet() { local out; out="$(hook bash "$(bash_json "$2")")"; [[ -z "$out" ]] && pass "$1" || fail "$1" "$out"; }
bash_asks  "sed -i on a spec asks"       "sed -i 's/a/b/' specs/screens/AlbumDetail.md"
bash_asks  "redirect into a spec asks"   "echo hi >> specs/screens/AlbumDetail.md"
bash_asks  "rm -rf specs asks"           "rm -rf specs"
bash_asks  "inline script near specs asks" "node -e 'require(\"fs\").writeFileSync(\"specs/x.md\", \"\")'"
bash_quiet "reading specs is quiet"      "cat specs/screens/AlbumDetail.md | head -5"
bash_quiet "grep with 2>/dev/null is quiet" "grep -rn R1 specs/ 2>/dev/null"
bash_quiet "spec-lint --fix is quiet"    "node scripts/spec-lint.mjs --fix"
bash_quiet "writing a report is quiet"   "cat tmp.md > specs/_reports/AlbumDetail.md"
bash_quiet "unrelated rm is quiet"       "rm -rf build/out"

echo "scaffolding"
[[ -f "$repo/specs/outline.md" ]] && pass "install adds an outline" || fail "outline installed" "$(ls "$repo/specs")"
new_spec() { node "$repo/scripts/spec-lint.mjs" --root "$repo" --new "$@" 2>&1; }
out="$(new_spec screen Library)"
grep -q "^screen: Library$" "$repo/specs/screens/Library.md" && grep -q "^status: draft$" "$repo/specs/screens/Library.md" && grep -q "^## Rules$" "$repo/specs/screens/Library.md" \
  && pass "--new creates a named draft from the template" || fail "--new" "$out"
expect_ok "  ...which lints clean"
out="$(new_spec screen Library)"; code=$?
[[ $code -eq 0 && "$out" == *keep* ]] && pass "--new keeps an existing spec" || fail "--new existing" "$out"
out="$(new_spec model AlbumDetail)"; code=$?
[[ $code -eq 1 && "$out" == *"already taken by specs/screens/AlbumDetail.md"* ]] && pass "--new refuses a name taken by another kind" || fail "--new taken" "$out"
out="$(new_spec widget Thing)"; [[ $? -eq 1 && "$out" == *'unknown kind "widget"'* ]] && pass "--new rejects an unknown kind" || fail "--new kind" "$out"
out="$(new_spec screen 9Lives)"; [[ $? -eq 1 && "$out" == *"isn't a valid spec name"* ]] && pass "--new rejects an invalid name" || fail "--new name" "$out"
rm "$repo/specs/screens/Library.md"

cp "$repo/specs/outline.md" "$repo/specs/outline.md.orig"
cat > "$repo/specs/outline.md" <<'EOF'
# Outline
## Screens
- AlbumDetail
- ArtistPage: let a listener browse everything by one artist
  - maybe a "follow" button? (my own note)
## Components
- ArtistBadge
- TrackRow
## Flows
- Onboarding
## Models
- Artist
## APIs
- GetArtist: GET /artists/{id} — fetch one artist
## Policies
- CanFollow: whether a listener can follow an artist
## Screens
- NowPlaying
EOF
scaffold() { node "$repo/scripts/spec-lint.mjs" --root "$repo" --scaffold 2>&1; }
out="$(scaffold)"; code=$?
[[ $code -eq 0 && "$out" == *"7 spec(s) created, 2 already existed"* ]] && pass "--scaffold creates a draft per new entry" || fail "--scaffold" "$out"
grep -q "^let a listener browse everything by one artist$" "$repo/specs/screens/ArtistPage.md" && ! grep -q "follow" "$repo/specs/screens/ArtistPage.md" \
  && pass "  ...the entry's note becomes the Goal; nested notes stay in the outline" || fail "scaffold note" "$(cat "$repo/specs/screens/ArtistPage.md")"
[[ -f "$repo/specs/screens/NowPlaying.md" ]] && pass "  ...including entries under a repeated heading" || fail "repeated heading" "$out"
grep -q "^endpoint: GET /artists/{id}$" "$repo/specs/apis/GetArtist.md" && grep -q "^fetch one artist$" "$repo/specs/apis/GetArtist.md" \
  && pass "  ...an API's leading endpoint fills in endpoint" || fail "scaffold endpoint" "$(cat "$repo/specs/apis/GetArtist.md")"
grep -q "^policy: CanFollow$" "$repo/specs/policies/CanFollow.md" && grep -q "^whether a listener can follow an artist$" "$repo/specs/policies/CanFollow.md" \
  && pass "  ...a ## Policies entry becomes a policy draft" || fail "scaffold policy" "$(cat "$repo/specs/policies/CanFollow.md" 2>&1)"
grep -q "^The ArtistBadge.$" "$repo/specs/components/ArtistBadge.md" && ! grep -q "^## Props" "$repo/specs/components/ArtistBadge.md" \
  && pass "  ...and existing specs are left alone" || fail "scaffold existing" "$(cat "$repo/specs/components/ArtistBadge.md")"
expect_ok "scaffolded drafts lint clean"
out="$(scaffold)"; [[ "$out" == *"0 spec(s) created, 9 already existed"* ]] && pass "--scaffold is idempotent" || fail "--scaffold idempotent" "$out"
echo "- Settings" >> "$repo/specs/outline.md"
expect_warn "an outline entry without a spec warns" "Settings has no spec yet"
outline="$repo/specs/outline.md"
mutate_in "$outline" "outline entry under the wrong section" expect_err "listed under ## APIs but specs/models/Artist.md is a model spec" 's/^- Artist$/- Placeholder/; s/^- GetArtist:.*/- Artist/'
mutate_in "$outline" "outline entry that isn't a name"      expect_err "isn't a spec name"                 's/^- TrackRow$/- Track row in a list/'
mutate_in "$outline" "outline section that isn't a kind"    expect_err 'unknown section "## Widgets"'     's/^## Flows$/## Widgets/'
mutate_in "$outline" "outline entry listed twice"           expect_err "TrackRow is listed more than once" 's/^- Onboarding$/- TrackRow/'
bash_quiet "--scaffold is quiet to the shell hook" "node scripts/spec-lint.mjs --scaffold"
rm "$repo"/specs/screens/ArtistPage.md "$repo"/specs/components/TrackRow.md "$repo"/specs/flows/Onboarding.md "$repo"/specs/models/Artist.md "$repo"/specs/apis/GetArtist.md "$repo"/specs/screens/NowPlaying.md "$repo"/specs/policies/CanFollow.md
mv "$repo/specs/outline.md.orig" "$repo/specs/outline.md"

echo "post hook"
out="$(hook post "$(edit_json "$screen" x y)")"; code=$?
[[ $code -eq 0 && -z "$out" ]] && pass "post: clean tree is silent" || fail "post: clean" "$out"
sed -i 's/{copy.buy}/{copy.nope}/' "$screen"
out="$(hook post "$(edit_json "$screen" x y)")"; code=$?
[[ $code -eq 2 && "$out" == *"{copy.nope}"* ]] && pass "post: lint errors exit 2 with details" || fail "post: errors (exit $code)" "$out"
out="$(hook post "$(edit_json "$repo/src/AlbumDetail.tsx" x y)")"; code=$?
[[ $code -eq 2 ]] && pass "post: editing a spec's source file also lints" || fail "post: source" "$out"
out="$(hook post "$(edit_json "$repo/README.md" x y)")"; code=$?
[[ $code -eq 0 ]] && pass "post: unrelated files ignored" || fail "post: unrelated" "$out"

echo "noticing changes"
seen_json() { node -e 'console.log(JSON.stringify({ hook_event_name: process.argv[1], prompt: "hi" }))' "$1"; }
seen() { hook seen "$(seen_json "${1:-UserPromptSubmit}")"; }
grep -q '"SessionStart"' "$repo/.claude/settings.json" && grep -q '"UserPromptSubmit"' "$repo/.claude/settings.json" \
  && pass "install adds the SessionStart and UserPromptSubmit hooks" || fail "seen hooks installed" "$(cat "$repo/.claude/settings.json")"
rm -f "$repo/specs/.last-seen.json"
out="$(seen SessionStart)"; [[ -z "$out" && -f "$repo/specs/.last-seen.json" ]] && pass "seen: the first run only records what's there" || fail "seen: baseline" "$out"
out="$(seen)"; [[ -z "$out" ]] && pass "seen: nothing changed, nothing said" || fail "seen: quiet" "$out"
lib="$repo/specs/screens/Library.md"
node "$repo/scripts/spec-lint.mjs" --root "$repo" --new screen Library >/dev/null
out="$(seen)"; [[ -z "$out" ]] && pass "seen: a new draft isn't news" || fail "seen: new draft" "$out"
sed -i 's/^status: draft$/status: approved/' "$lib"
out="$(seen)"
[[ "$out" == *'"hookEventName":"UserPromptSubmit"'* && "$out" == *"Library was approved. Offer to build it; don't start until the user says so."* ]] \
  && pass "seen: an approval by hand is noticed, and Claude offers to build" || fail "seen: approval" "$out"
out="$(seen)"; [[ -z "$out" ]] && pass "  ...once" || fail "seen: once" "$out"
cp "$screen" "$screen.bak"; sed -i 's/Timeline is newest first./Timeline is oldest first./' "$screen"
out="$(seen SessionStart)"
[[ "$out" == *'"hookEventName":"SessionStart"'* && "$out" == *"AlbumDetail changed after it was built"*"set it to implemented"* ]] \
  && pass "seen: a hand edit to a verified spec sends it back to be re-verified" || fail "seen: hand edit" "$out"
mv "$screen.bak" "$screen"; seen >/dev/null
own_edit() { # own_edit <file> <sed expr> [id]: what Claude's Edit does, hooks and all
  local json; json="$(node -e 'console.log(JSON.stringify({ tool_name: "Edit", tool_use_id: process.argv[3] || undefined, tool_input: { file_path: process.argv[1], old_string: "x", new_string: "y" } }))' "$1" "$2" "${3:-}")"
  hook pre "$json" >/dev/null; sed -i "$2" "$1"; hook post "$json" >/dev/null
}
own_edit "$lib" 's/^## Goal$/## Goal\nBrowse everything you own./'
out="$(seen)"; [[ -z "$out" ]] && pass "seen: Claude's own edits aren't reported back to it" || fail "seen: own edit" "$out"
sed -i 's/^status: approved$/status: implemented/' "$lib"; seen >/dev/null
sed -i 's/^Browse everything you own.$/Browse every album you own./' "$lib"
own_edit "$lib" 's/^status: implemented$/status: implemented\nsource: [src\/AlbumDetail.tsx]/'
out="$(seen)"; [[ "$out" == *"Library changed after it was built"* ]] && pass "seen: a change made before Claude's own edit is still reported" || fail "seen: absorbed" "$out"
cp "$lib" "$lib.bak"; sed -i 's/^status: implemented$/status: approved/; s/^Browse every album you own.$/Browse all your albums./' "$lib"
out="$(seen)"; [[ "$out" == *"Library went from implemented to approved: it needs building again."*"Library changed since you last read it"* ]] \
  && pass "seen: a status change doesn't hide a content change" || fail "seen: both" "$out"
mv "$lib.bak" "$lib"; seen >/dev/null
lib2="$repo/specs/screens/Library2.md"; sed 's/^screen: Library$/screen: Library2/' "$lib" > "$lib2"; seen >/dev/null
own_edit "$lib" 's/^Browse every album you own.$/Browse it all./' a & own_edit "$lib2" 's/^Browse every album you own.$/Browse it all./' b & wait
out="$(seen)"; [[ -z "$out" ]] && pass "seen: two of Claude's edits at once are both recorded" || fail "seen: parallel" "$out"
cmd="sed -i 's/Browse it all./Browse everything./' specs/screens/Library2.md"
hook bash "$(bash_json "$cmd")" >/dev/null; (cd "$repo" && eval "$cmd"); hook bash-post "$(bash_json "$cmd")" >/dev/null
out="$(seen)"; [[ -z "$out" ]] && pass "seen: a shell command of Claude's that changes specs is recorded too" || fail "seen: bash" "$out"
rm "$lib2"; seen >/dev/null
echo "- Library" >> "$repo/specs/outline.md"
sed -i 's/^status: implemented$/status: deprecated\ndeprecated: 2026-10-25/' "$lib"
out="$(seen)"; [[ "$out" == *"Library was deprecated. Take it off specs/outline.md, and don't build on it from now on."* ]] && pass "seen: a deprecation by hand is noticed" || fail "seen: deprecated" "$out"
sed -i 's/^status: deprecated$/status: approved/' "$lib"
out="$(seen)"
[[ "$out" == *"Library was brought back (deprecated → approved). Finish reviving it: remove its \`deprecated\`"*"add a dated line under ## Decisions"* && "$out" != *"put it back in specs/outline.md"* ]] \
  && pass "seen: bringing a spec back is noticed, with only the clean-up still to do" || fail "seen: revived" "$out"
expect_err "  ...and lint says what to do with the leftover fields" '"deprecated" belongs only on a deprecated spec (status is approved); if it'"'"'s been brought back, remove it'
out="$(hook pre "$(edit_json "$lib" $'deprecated: 2026-10-25\n' '')")"
[[ -z "$out" ]] && pass "pre: clearing a revived spec's deprecation fields doesn't ask" || fail "pre: revive clean-up" "$out"
out="$(hook pre "$(edit_json "$lib" "status: approved" $'status: approved\nreplaced_by: AlbumDetail')")"
[[ "$out" == *'"ask"'* ]] && pass "  ...but adding one still does" || fail "pre: add deprecation field" "$out"
sed -i '/^- Library$/d' "$repo/specs/outline.md"
rm "$lib"; out="$(seen)"; [[ "$out" == *"Library was deleted."* ]] && pass "seen: a deleted spec is noticed" || fail "seen: deleted" "$out"
echo "{ not json" > "$repo/specs/.last-seen.json"
out="$(seen)"; [[ "$out" == *"couldn't be read, so changes since then can't be listed"* ]] && pass "seen: an unreadable record is said, not silently replaced" || fail "seen: corrupt" "$out"
out="$(seen)"; [[ -z "$out" ]] && pass "  ...and it starts afresh" || fail "seen: corrupt restart" "$out"
gi="$(mktemp -d)"; printf 'node_modules\r\n/specs/.last-seen.json \r\n' > "$gi/.gitignore"; "$kit/install.sh" "$gi" >/dev/null
[[ "$(grep -c "last-seen" "$gi/.gitignore")" == 1 ]] && pass "install recognises an existing .gitignore entry, CRLF and all" || fail "gitignore dup" "$(cat -A "$gi/.gitignore")"
{ echo "specs/.last-seen.json"; for i in $(seq 1 1000); do echo "build/output-directory-number-$i/"; done; } > "$gi/.gitignore"
for i in 1 2 3; do "$kit/install.sh" "$gi" >/dev/null; done
[[ "$(grep -c "last-seen" "$gi/.gitignore")" == 1 ]] && pass "  ...in a large .gitignore too" || fail "gitignore dup, large file" "$(grep -c last-seen "$gi/.gitignore") entries"
rm -rf "$gi"

echo "example"
example="$kit/examples/music-store"
out="$(node "$kit/template/scripts/spec-lint.mjs" --root "$example" 2>&1)" && pass "examples/music-store lints clean" || fail "example lint" "$out"
out="$(node --test "$example/src/album.test.mjs" 2>&1)" && pass "examples/music-store tests pass" || fail "example tests" "$out"

echo
[[ $fails -eq 0 ]] && echo "all passed" || { echo "$fails failed"; exit 1; }
