<!-- rdd:start -->
## Specs (`specs/`): Recipe-Driven Development

`specs/` is the source of truth for every screen, component, flow, data model and API that has a
spec. The user is the head chef and writes the recipe (the spec); Claude is the cook and follows
it; the user tastes the result before it's called done. The format is defined in `specs/README.md`;
read it before writing or changing a spec.

- **Before any work a spec covers**, read that spec, every spec it references (`uses`,
  `[[screen:…]]`, `[[flow:…]]`, `[[model:…]]`, `[[api:…]]`), and `specs/tokens.md` for UI.
  Cite rule IDs (e.g. `AlbumDetail.R1`) in plans, commits and test names.
- **Never change an approved spec silently.** If implementation shows the spec is wrong,
  incomplete or impossible, add an entry under `## Open amendments` (Finding / Change / Affects /
  Shared/one-off impact), tell the user, and pause the work that depends on it. Don't build the
  amended behaviour until the user accepts it. A PreToolUse hook asks the user before protected
  spec content changes. That prompt is a backstop, not permission. Never change spec files
  through Bash; a second hook asks the user if a shell command looks like it does.
- **Accepting / rejecting:** on accept, merge the change, remove the amendment and add a dated
  line under `## Decisions`. On reject, remove the amendment and record the reason under `## Decisions`.
- **Status:** only the user moves a spec to `approved`. Claude may set `implemented` once it's
  built. Claude may propose `verified` only after `/spec-verify` writes a report with every rule
  ✅; the hook refuses it otherwise, and asks the user to confirm (the taste test) when the report
  passes. Before setting it, tell the user in 2–5 bullets what to try so they can taste it.
- **Shared vs one-off:** before creating a component, check `specs/components/`. Reuse a shared
  component (adding a variant if only props or appearance differ) rather than forking it. A new
  one-off must appear as `[[~Name]]` in the spec, which for an approved spec means an amendment.
  Never quietly copy a shared component into a screen. Likewise, reuse an existing
  `specs/models/` entity rather than redefining its fields inline.
- **Tests** that check a rule include its ID in brackets: `it("[AlbumDetail.R1] ...")`.
- **Verification** checks the spec as written. Never weaken a test or reinterpret a rule to make
  it pass; a mismatch is either a bug or an amendment.
- spec-lint runs automatically after edits. Run `node scripts/spec-lint.mjs --fix` to regenerate
  `Used by`, and `--summary` for an overview.
<!-- rdd:end -->
