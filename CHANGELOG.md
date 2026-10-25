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
