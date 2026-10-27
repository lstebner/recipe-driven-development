# Changelog

What changed in each version of the kit: `spec-lint.mjs`, the skills, the CLAUDE.md rules, the
templates and `install.sh`. Check your installed version with `node scripts/spec-lint.mjs --version`;
`./install.sh <repo> --update` says which version it's updating from.

Before 1.0, the minor version goes up for new features and for anything **breaking**, and the
patch version for fixes. Breaking means a repo's existing specs can fail lint after
`--update`, or reports that were valid go stale (anything that changes how fingerprints are
computed). Breaking entries say so and say what to do.

Every PR adds a line under **Unreleased**. To release, run the **Create a release** workflow from
the Actions tab. It opens a PR that turns Unreleased into a version heading and bumps `VERSION`
in `template/scripts/spec-lint.mjs` to match. Squash-merging that PR tags the merge commit
`vX.Y.Z` and publishes a GitHub release with its entries.

## Unreleased

- The spec templates leave a blank line after the closing `---` of the frontmatter, so the
  first heading renders as its own block in editors such as Mark Text. New specs get it from
  the templates; existing specs don't need it, and lint accepts both.

- `node scripts/spec-lint.mjs --refs <Name>` lists every live spec that relies on a spec. That
  includes specs relying on it through others (a flow that steps through a screen that uses the
  component), each with its status and where the link is. `--refs Album#price` or
  `--refs GetAlbum#not_found` narrows it to one field or error code, plus the specs that link to the
  whole model or API. Claude runs it to fill in an amendment's Affects line, and the prompt for a
  change to a protected spec now lists who relies on it. For a change to a policy's decision, that
  includes specs built on the ones that rely on it. Run `install.sh --update` for the new script
  and rules.

- Decisions can record trade-offs: a good-enough solution, why, and when to revisit it.
  `specs/README.md` describes the convention and the CLAUDE.md rules have Claude add these lines
  while building and say when a revisit condition has been met. Run `install.sh --update` to get
  both.

- A change to a shared component flags every spec made from it for an audit. `/spec-verify`
  records the fingerprint of each component a spec uses on a new `Components:` line in its report
  (`node scripts/spec-lint.mjs --components <Name>`), and lint warns, without failing, when one
  has changed since. Claude names the specs to audit when it changes a component, and when the
  change-tracking hook sees you change one, including when a component reworked as a draft is
  approved again. Before a change, `--refs` and the prompt for it mark the verified specs it will
  flag ("AlbumDetail (verified, will need an audit)"). Marking a spec verified now needs the line to
  record every component the spec uses. Existing
  reports don't have it and aren't audited until they're re-verified. `specs/README.md` has a new
  section, "Changing a spec", on how to evolve something that's already approved or built.
  Run `install.sh --update` for the new skill and rules.

- Components keep **Props** and **States** as separate tables, and can have **Rules**: props are
  named in backticks as in code, with a type, required and default; states are plain lowercase
  names, with what puts the component in them and what it looks like; behaviour ("not pressable")
  is a rule, with an ID and a test. A prop that drives a state says `→ state <name>`, and lint
  checks both ends. It also checks that a screen's `[[Component prop=…]]` only sets props the
  component has. A screen's States section is the same table. Write a `|` inside a cell as `\|`
  (for a union type). Specs in the old format, or with a Props or States table in another layout,
  still lint, with a warning, and the new `/spec-migrate` skill converts them. It converts verified
  specs, and components with verified specs built from them, only if you say so, since converting
  sends those back to be re-verified or flags them for an audit. Run `install.sh --update` for
  the new templates, skill and rules.

## 0.2.0 (2026-10-26)

- Releases are made with two workflows: **Create a release** opens the release PR, and merging
  it tags the version and publishes a GitHub release.

- Claude notices spec changes made outside its session. A hook at session start and on each
  prompt compares the specs with `specs/.last-seen.json` (per checkout; install adds it to
  `.gitignore`) and tells Claude what changed: an approval to offer building, a hand edit to a
  built spec to re-check, a revived spec to finish bringing back, and so on. Bringing a
  deprecated spec back is now just setting its status yourself. Run `install.sh --update` to add
  the hooks.

- New spec kind: **policy**, in `specs/policies/`, for a business decision that several specs
  depend on but can't share as a component (whether a listener can buy an album, what an
  order costs). Specs reference it as `[[policy:Name]]`, its Used by lists them, and a spec's
  fingerprint includes the decision (Inputs, Output, Rules, Must not) of every policy it relies
  on, through other policies too, so changing one makes the reports of verified specs that rely
  on it stale. Specs that don't reference a policy keep their fingerprint. Outlines take a
  `## Policies` heading, and `--new policy` uses the new template.
- `install.sh --update` now also refreshes `specs/README.md`, the format definition, so new kinds
  and syntax reach Claude. A copy that differs from the kit's is kept as `specs/README.md.old`;
  carry any notes of your own over from it.
- Specs can be deprecated: `status: deprecated` with a `deprecated:` date and an optional
  `replaced_by:` (a live spec of the same kind, past draft). A deprecated spec is frozen, drops
  out of Used by, is skipped by the content checks, and is listed in `--summary` with any tests
  still tagged with its rules. Replacements that are deprecated in turn form a chain, and
  messages name the live spec at its end. **Breaking** (narrowly): `deprecated` and
  `replaced_by` are now reserved frontmatter keys, so a live spec that already uses either one
  fails lint. Rename the key.
- Text between a spec's frontmatter and its first heading (a title or intro) is now protected
  and part of the fingerprint. **Breaking** for specs that have such text: a verified one's
  report goes stale, so re-run `/spec-verify`. Specs that start with a `##` heading are unaffected.
- Quotes around frontmatter values are no longer kept as part of the value, so `status:
  "approved"` and `api: "GetAlbum"` work as expected. **Breaking** for specs with quoted values
  other than `status` and `source`: their fingerprint changes, so a verified one's report goes
  stale. Re-run `/spec-verify`.
- `install.sh --update` refuses to downgrade a repo that has a newer kit than the one you're
  running it from.

## 0.1.0 (2026-10-25)

The first versioned release: everything up to this point.

- Spec kinds: screen, component, flow, model and API, each with a template in `specs/_templates/`.
- Lifecycle: `draft` → `approved` (yours only) → `implemented` → `verified` (a passing report plus
  your confirmation, the taste test).
- Hooks ask before protected content in a non-draft spec changes, name the amendment being
  accepted, refuse `verified` without a report matching the spec's fingerprint, and ask before a
  shell command that looks like it writes to `specs/`. Lint errors go back to Claude after each edit.
- `spec-lint.mjs`: lint, `--fix` (Used by), `--summary`, `--hash`, `--new` and `--scaffold` from
  `specs/outline.md`.
- Skills: `/spec-new`, `/spec-review` and `/spec-verify`.
- `install.sh`, with `--update` to refresh the script, skills and CLAUDE.md rules; kitchen
  spinner verbs.
- `examples/music-store`, with specs at each stage of the lifecycle.
