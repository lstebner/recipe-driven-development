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
expect_ok() { local out; out="$(lint)" && pass "$1" || fail "$1" "$out"; }
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

echo "install"
out="$("$kit/install.sh" "$repo")" || fail "install" "$out"
out2="$("$kit/install.sh" "$repo")"
[[ "$(grep -c spec-lint.mjs "$repo/.claude/settings.json")" == 3 && "$(grep -c rdd:start "$repo/CLAUDE.md")" == 1 ]] \
  && pass "install is idempotent" || fail "install is idempotent" "$out2"
old="$(mktemp -d)"
printf '# Mine\n\n<!-- spec-kit:start -->\nold rules\n<!-- spec-kit:end -->\n\nafter\n' > "$old/CLAUDE.md"
mkdir -p "$old/.claude"
echo '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"node \"$CLAUDE_PROJECT_DIR/scripts/spec-lint.mjs\" --hook-pre"}]}]}}' > "$old/.claude/settings.json"
"$kit/install.sh" "$old" --update >/dev/null
[[ "$(grep -c rdd:start "$old/CLAUDE.md")" == 1 && "$(grep -c spec-kit "$old/CLAUDE.md")" == 0 && "$(grep -c '^after$' "$old/CLAUDE.md")" == 1 ]] \
  && pass "--update replaces an old spec-kit rules block in place" || fail "--update rules block" "$(cat "$old/CLAUDE.md")"
[[ "$(grep -c spec-lint.mjs "$old/.claude/settings.json")" == 3 ]] && pass "re-install adds the missing hooks" || fail "hook merge" "$(cat "$old/.claude/settings.json")"
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
out="$(lint --summary)"; [[ "$out" == *"Models & APIs"*"Album"*"← Checkout, GetAlbum"* ]] && pass "summary lists model and API users" || fail "summary models" "$out"
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

echo "hooks"
out="$(hook pre "$(edit_json "$screen" "Buy is hidden when owned." "Buy is always shown.")")"
[[ "$out" == *'"permissionDecision":"ask"'* && "$out" == *"Rules"* ]] && pass "pre: editing Rules of approved spec asks" || fail "pre: Rules" "$out"
out="$(hook pre "$(edit_json "$screen" $'## Open amendments\n' $'## Open amendments\n### A1: thing\n- Finding: x\n')")"
[[ -z "$out" ]] && pass "pre: adding an amendment doesn't ask" || fail "pre: amendment" "$out"
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
[[ "$out" == *'"deny"'* && "$out" == *"no ✅ row for AlbumDetail.R2"* && "$out" == *"Layout as ⚠️"* ]] && pass "pre: missing rule row and ⚠️ are refused" || fail "pre: missing row" "$out"
write_report "000000000000" "| AlbumDetail.R1 | ✅ | test |" "| AlbumDetail.R2 | ✅ | test |"
out="$(to_verified)"
[[ "$out" == *'"deny"'* && "$out" == *"older version"* ]] && pass "pre: a stale report is refused" || fail "pre: stale" "$out"
write_report "$hash" "| AlbumDetail.R1 | ✅ | test |" "| AlbumDetail.R2 | ✅ | test |"
out="$(to_verified)"
[[ "$out" == *'"ask"'* && "$out" == *"Taste test"* && "$out" == *"2/2"* ]] && pass "pre: a passing report asks you to taste it" || fail "pre: taste" "$out"
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

echo
[[ $fails -eq 0 ]] && echo "all passed" || { echo "$fails failed"; exit 1; }
