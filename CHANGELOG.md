# Changelog

What changed in each version of the kit: `spec-lint.mjs`, the skills, the CLAUDE.md rules, the
templates and `install.sh`. Check your installed version with `node scripts/spec-lint.mjs --version`;
`./install.sh <repo> --update` says which version it's updating from.

Before 1.0, the minor version goes up for new features and for anything **breaking**, and the
patch version for fixes. Breaking means a repo's existing specs can fail lint after
`--update`, or reports that were valid go stale (anything that changes how fingerprints are
computed). Breaking entries say so and say what to do.

Every PR adds a line under **Unreleased**. A release turns Unreleased into a version heading and
bumps `VERSION` in `template/scripts/spec-lint.mjs` to match.

## Unreleased

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
