---
name: spec-review
description: Critique a screen, component, flow, data model, API or policy spec in specs/ before it is built. Finds ambiguity, untestable rules, missing states and branches, copy gaps, contract gaps, conflicts with shared components and models, and shared-vs-one-off problems, and proposes concrete wording for each. Use when asked to "review this spec", "/spec-review AlbumDetail", or before implementing a draft spec.
---

# Spec review

The user is the head chef and the spec is their recipe. Give them feedback on it **before**
it's cooked, so that what gets built matches what they meant. This skill only advises. It never edits the spec unless the user then asks for
specific changes (and for a non-draft spec, those changes go in as amendments; see `specs/README.md`).

## Steps

1. Run `node scripts/spec-lint.mjs`. Lint errors are findings too; include them. If the spec is
   `deprecated`, don't review it: it's frozen. Say so, and offer to review its `replaced_by` instead.
2. Read `specs/README.md` (the format), the target spec, every spec it references (`uses`,
   `[[screen:…]]`, `[[flow:…]]`, `[[model:…]]`, `[[api:…]]`, `[[policy:…]]`), `specs/tokens.md`
   for UI, and any other specs that reference the same components, models, APIs or policies.
3. Go through the checklist below. For each problem, write the **exact text** you'd add or change.
   A finding with no proposed wording isn't useful.

## Checklist

**Goal**
- Is it clear who the user is and what they're trying to get done? Does every Layout node serve the goal?

**Rules**
- Can each rule be checked as pass or fail? Flag vague words: "nice", "fast", "clean", "appropriate", "intuitive", "should feel".
- Every `?condition` in Layout is explained by a rule, and every rule shows up somewhere in Layout or States.
- Look for rules that conflict with each other or with a component's `Must not`.

**States**: which are missing? Check: loading, empty, error, offline, permission or auth,
partial data, very long text or names, zero / one / many items, first-time use.

**Layout**
- Responsive behaviour is stated for every region that has more than one column.
- Each node is clear enough to build without guessing. Flag gaps like "Details: what's in it, and in what order?"

**Copy**
- Every user-visible string has a key, including errors, empty states, buttons and accessibility labels.
- Placeholders (`{price}`) say where their value comes from.

**Shared vs one-off**
- A `[[~OneOff]]` that resembles an existing shared component: should it be a variant?
- A shared component asked to do something structurally different here: should that be a new component, or a variant?
- Something described inline in Layout that clearly exists elsewhere: should it be `[[Shared]]`?
- Variants referenced that the component spec doesn't define.
- References to a deprecated spec: propose pointing at its `replaced_by` instead.

**Style**
- Raw values instead of tokens; tokens that are missing from `tokens.md`.

**Flows**
- Every step has a way forward and a way out; no step is a dead end unless it's an exit.
- Every branch condition is explained by a rule, and every API error a step can hit has a branch.
- Exits say what happens to partial state (a half-filled cart, an unpaid order).
- Back, refresh, deep-linking into the middle and resuming later: what happens?

**Models**
- Every field has a type and says whether it's required; constraints (length, range, format, uniqueness) are stated.
- Relationships say what happens on delete.
- Fields that duplicate another model's: should this reference `[[model:Other]]` instead?

**APIs**
- Request and response shapes reference models rather than redefining their fields.
- Every way it can fail has a row in Errors, including auth, validation, not found, conflict and rate limits.
- Auth says who can call it and what error everyone else gets.
- Side effects, idempotency, ordering and pagination are stated where they apply.
- Every screen that calls it handles each of its error codes in States.

**Policies**
- The rules decide every combination of inputs: no case where two rules disagree or none applies.
  An Examples row for each tricky case (boundaries, missing inputs, overlapping roles) makes gaps
  easy to spot.
- Inputs are only what the decision needs. An input that's really about presentation (screen
  size, platform) usually means part of it belongs in the specs that use it instead.
- Every spec in Used by takes the answer as given. Flag any that restate, filter or reorder it.
- Two or more specs that work out the same decision themselves (the same conditions in their
  Rules or `?condition`s): propose pulling it into a policy.

## Output

Match the review to the spec's stage. A first draft needs a clear goal and checkable rules, not
every edge case: keep **Blocking** to what would make it impossible to build or verify, and list
at most five **Consider** items, the ones most likely to matter. Go deeper (every state, every
copy key, accessibility labels) when the spec is about to be approved or the user asks for a
thorough pass.

Group findings as **Blocking** (it can't be built or verified as written), **Should fix**, and
**Consider**. Number them so the user can reply "apply 1, 3, 4". Each finding is one line
naming the problem, followed by the proposed text. End with a one-line verdict: ready to
approve, or not yet.
