<!-- rdd:start -->
## Specs (`specs/`): Recipe-Driven Development

`specs/` is the source of truth for every screen, component, flow, data model, API and policy
that has a spec. The user is the head chef and decides the recipe (the spec); Claude is the cook
and follows it; the user tastes the result before it's called done. The format is defined in
`specs/README.md`; read it before writing or changing a spec.

- **Before any work a spec covers**, read that spec, every spec it references (`[[Name]]`,
  `[[screen:…]]`, `[[flow:…]]`, `[[model:…]]`, `[[api:…]]`, `[[policy:…]]`), and
  `specs/tokens.md` for UI.
  Cite full rule IDs (e.g. `AlbumDetail.R1`) in plans, commits and test names.
- **Drafting:** when asked to draft specs (`/spec-new`, from `specs/outline.md`, or from a
  conversation), add each to the outline and write it as `draft`, starting the files with
  `node scripts/spec-lint.mjs --scaffold`. Write only what the user said or clearly implied: Goal
  or Purpose, Rules, and the sections their intent covers. Leave the other sections empty rather
  than inventing detail. End your message with a short list of what you guessed, so the user can
  confirm or correct it, and suggest `/spec-review`.
- **Never change an approved spec silently.** If implementation shows the spec is wrong,
  incomplete or impossible, add an entry under `## Open amendments` (Finding / Change / Affects /
  Shared/one-off impact), tell the user in a sentence, and pause the work that depends on it.
  Before writing Affects, or changing any spec others build on, run
  `node scripts/spec-lint.mjs --refs <Name>` (or `<Name>#member` for one field or error code). Name
  the specs it lists that the change really touches, and say which of them are verified. Then
  apply it in a single edit: merge the change, remove the entry, and add a dated line under
  `## Decisions`. The hook asks the user to accept it by name, and that prompt is their decision.
  If they deny it, leave the amendment open and ask whether to reject it; on reject, remove the
  entry and record their reason under `## Decisions`. Any other prompt about protected spec content
  is a backstop, not permission. Never change spec files through Bash; a second hook asks the user
  if a shell command looks like it does.
- **Status:** only the user moves a spec to `approved` (they say so, you set it, and they confirm
  the prompt). Claude may set `implemented` once it's built. Claude may propose `verified` only
  after `/spec-verify` writes a report with every rule ✅ or 👤; the hook refuses it otherwise, and
  asks the user to confirm (the taste test) when the report passes. Before setting it, tell the
  user in 2–5 bullets what to try, including every 👤 row.
- **Deprecated specs** (`status: deprecated`) are frozen records of something that's off the menu.
  Never edit one, never build new work against it, and don't extend code that only exists for it.
  Use its `replaced_by` spec instead, following the chain if that one was deprecated too (lint
  messages name the live end); if nothing live replaces it, the behaviour is meant to go away, so
  ask before relying on it. Code and tests may still reference it: when you're working in that
  code, move it to the replacement (or point it out) rather than following the old spec. A live
  spec that still points at it needs an amendment.
- **Deprecating** is the user's decision, like approving. When they ask, set `status: deprecated`,
  `deprecated: <today's date, YYYY-MM-DD>` and `replaced_by: <Name>` (a live spec of the same
  kind, past draft) if something replaces it, and add a dated line under `## Decisions` saying
  why, all in one edit and changing nothing else (a Write of the whole file, or a MultiEdit, since
  one Edit can't reach both); the hook asks them to confirm. Then remove it from
  `specs/outline.md`. A draft isn't deprecated: delete it (and its outline entry) instead. You
  may suggest deprecating, but never do it unasked.
- **Trade-offs:** when you settle on a good-enough way of meeting a spec and a better one would
  only be worth it later, add a dated line under `## Decisions` saying what you chose, why, and
  when to revisit it (a condition someone would notice, not "someday"), and mention it to the
  user. Don't act on a revisit line unasked, but tell the user when you see its condition has been
  met. A trade-off that changes what the spec says is an amendment, not a decision.
- **Shared vs one-off:** before creating a component, check `specs/components/`. Reuse a shared
  component (adding a variant if only props or appearance differ) rather than forking it. A new
  one-off must appear as `[[~Name]]` in the spec, which for an approved spec means an amendment.
  Never quietly copy a shared component into a screen. Likewise, reuse an existing
  `specs/models/` entity rather than redefining its fields inline, and get a decision from its
  `specs/policies/` spec rather than working it out again where it's used. When a decision that
  more than one spec needs isn't in a policy yet, suggest one rather than restating it in each.
- **Changing a component** can reach every spec made from it, but doesn't send them back to be
  re-verified. Instead, when a hook or lint names specs to audit after a component change, tell
  the user and offer to check each: whether the change affects it, which is an amendment or a bug
  if so. Re-running `/spec-verify` on a spec records the components as they are now. A component
  amendment's Affects line comes from `--refs`, like any other; say which of those specs will need an
  audit.
- **Props, States and Rules** are separate tables and sections (see `specs/README.md`, Component
  spec): props in backticks as in code, states in plain lowercase, behaviour as Rules. Don't mix
  them. A spec still in the old `## Props / States` format can be converted with `/spec-migrate`.
  Mention it when you're working on one, but don't convert it unasked.
- **Tests** that check a rule include its full ID in brackets: `it("[AlbumDetail.R1] ...")`.
- **Verification** checks the spec as written. Never weaken a test or reinterpret a rule to make
  it pass; a mismatch is either a bug or an amendment. Mark a rule 👤 only when a person genuinely
  has to judge it, never to get past a check you could have run.
- **Changes made outside this session** (the user editing a spec, or a git pull) are listed by a
  hook at the start of a session and with the user's messages: approvals, hand edits, revivals,
  deprecations. Tell the user briefly what you noticed and offer the next step it calls for, per
  `specs/README.md` ("Noticing your changes"). Don't start building or verifying unasked.
- spec-lint runs automatically after edits. Run `node scripts/spec-lint.mjs --fix` to regenerate
  `Used by`, and `--summary` for an overview.
<!-- rdd:end -->
