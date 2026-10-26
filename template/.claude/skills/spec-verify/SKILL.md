---
name: spec-verify
description: Verify an implemented screen, component, flow, data model, API or policy against its spec in specs/, rule by rule, write a pass/fail report to specs/_reports/<Name>.md, and hand it to the user to taste. Checks lint, imports, copy, rule-tagged tests, schema and contract, and visual layout via screenshots. Use when asked to "verify against the spec", "/spec-verify AlbumDetail", or at the end of implementing a spec.
---

# Spec verify

You're the cook checking the dish against the recipe before the head chef tastes it. Check the
implementation against the spec **as written**, not against your memory of what was built or
what was discussed along the way. The output is a report the user can read in 30 seconds, so
they don't need to read the code.

## Ground rules

- The spec is the authority. If the code and the spec disagree, it's a ❌. Don't reinterpret
  the rule so it passes, and don't change a test to make it pass.
- If a ❌ suggests the spec itself is wrong, say so in the report and propose an amendment
  (under `## Open amendments`, per `specs/README.md`). Don't edit the spec's protected sections.
- ✅ needs evidence: a file:line, a passing test name, a screenshot, or a request and its response.
- 👤 is for what only a person can judge: whether it looks right, how it feels on a real device,
  whether the copy reads well. Say what to look at. It doesn't block `verified`; it goes on the
  user's list of things to try.
- ⚠️ is for something you could check but didn't (a simulator wouldn't start, a service was
  down). Give the reason. It blocks `verified` until it's checked. Never use 👤 to get past one.
- Only the user can say it tastes right. A clean report earns the right to *ask*; see step 7.

## Steps

If the spec is `deprecated`, stop: there's nothing to verify, and its report stays as it was.
Offer to verify its `replaced_by` instead.

1. `node scripts/spec-lint.mjs`: any errors go at the top of the report.
2. Read the spec, every spec it references, and `specs/tokens.md` (for UI).
3. **Static checks** against the `source` files:
   - **component:** every row in Props matches the code (name, type, required, default), and
     the code has no props the table doesn't list; each state in States can actually be reached
     the way its "when" says.
   - **screen / component:** every `uses` component is imported and actually rendered; no
     shared component has been copied in; every `{copy.key}` text appears verbatim
     (placeholders aside); tokens are used rather than raw values wherever Style names them.
   - **model:** the schema, type or migration has every field with the stated type and
     required-ness, and no extra fields the spec doesn't mention; relationships and delete
     behaviour match.
   - **api:** the route matches `endpoint`; request and response shapes match (including the
     referenced models); every row in Errors is produced with that status and code; Auth is enforced.
   - **flow:** each step's screen or API exists and links to the next as written, including every branch.
   - **policy:** the decision is made in one place, and every spec in Used by gets its answer
     from there rather than working it out again or adjusting it (filtering, reordering, adding
     cases). A second copy of the logic is a ❌, even if it currently gives the same answer.
4. **Tests:** find tests tagged `[<RuleID>]` (`grep -rn "\[AlbumDetail.R"`), run them, and record
   pass or fail. If a rule has no tagged test, say so. Offer to write one, but don't block the report on it.
5. **Run it:**
   - **screen / component / flow:** run the app using the project's own run or verify skill if
     there is one (e.g. a simulator or e2e skill), otherwise the built-in `run` skill. Screenshot
     every breakpoint and state the spec mentions and compare each against the Layout tree, node
     by node and in order. For a flow, walk every path through Steps, branches included.
   - **api:** call it for the happy path and for each error code; record request and response.
   - **model:** exercise each Rule (invariant) against the real storage layer if you can.
   - **policy:** run the decision for each Examples row and each rule, and record what you
     gave it and what came back. Then check that each spec in Used by shows the same answer for
     the same input (e.g. AlbumDetail, GetAlbum and CreateOrder agree for a listener who owns the
     album, one who doesn't, and one whose order was refunded).
6. Get the fingerprint with `node scripts/spec-lint.mjs --hash <Name>` and the components line with
   `node scripts/spec-lint.mjs --components <Name>`, then write `specs/_reports/<Name>.md`
   (overwrite it) and show the user the summary table. The fingerprint covers the decision of
   every policy the spec relies on, through other policies too, so a verified spec whose policy
   has changed since its report goes stale: re-verify it against the policy as it is now. The
   components line records each shared component the spec is built from as you checked it. When
   one changes later, lint warns that the spec needs auditing. If you're here because of that
   warning, check what the component's change means for this spec in particular.
7. **Status.** If the spec was `approved`, you may set `implemented` once it's built. If every
   rule is ✅ or 👤, no row is ❌ or ⚠️ and lint is clean, propose the taste test:
   - Tell the user in 2–5 bullets **what to try** to taste it themselves: every 👤 row first,
     then the screens, inputs or calls that exercise the rules most likely to be subtly wrong.
   - Then set `status: verified`. The hook re-checks the report and asks the user to confirm. If
     they deny it, ask what's off: it's either a bug to fix or an amendment to the spec.
   - Never set `approved`, and never edit the report to make the hook accept it.

## Report format

```markdown
# <Name>: verification report
Date: YYYY-MM-DD · Spec: 3f9a1c0b7e2d · Status: implemented · Lint: clean
Components: ArtistBadge 8c41d07e9a2f, PrimaryButton 5e0b3a9d1c76

| rule | result | evidence |
|---|---|---|
| AlbumDetail.R1 | ✅ | test "[AlbumDetail.R1] hides buy when owned" passes; page.tsx:42 |
| AlbumDetail.R2 | ❌ | timeline renders oldest first (screenshot md-default.png) |
| AlbumDetail.R3 | 👤 | spinner timing: tap Buy on a slow connection and check it feels immediate |
| Layout | ⚠️ | <md breakpoint not checked: simulator unavailable |
| Copy | ✅ | 4/4 keys found verbatim |
| Shared components | ✅ | ArtistBadge, PrimaryButton imported from packages/ui |

## Failures
- AlbumDetail.R2: <what's wrong, where, and the suggested fix>

## Proposed amendments
- (none)
```

Use one row per rule, with the rule ID alone in the first column, plus rows for the other checks
that apply (Layout, Copy, Shared components, Schema, Contract, Errors, Paths). The hook reads this
table: every rule needs a ✅ or 👤 row, and any ❌ or ⚠️ row blocks `verified`. It also reads the
`Components:` line, exactly as `--components` prints it (`none` if the spec uses no components),
and refuses `verified` if the line leaves out a component the spec uses or records an older one.
For a spec with no components the line is just a record: if it starts using one later, its own
fingerprint changes and the report goes stale anyway.
