---
name: spec-migrate
description: Convert specs written before the Props and States tables to the current format. A component's "## Props / States" list becomes a Props table, a States table and, for any behaviour it described, Rules; a screen's States list becomes a States table. Fills prop types, required and defaults from the source code. Use when lint warns that a spec uses the old format, or when asked to "migrate the specs", "/spec-migrate", or "/spec-migrate PrimaryButton".
argument-hint: "[Name, …]  (no arguments: every spec lint warns about)"
---

# Spec migrate

The recipe isn't changing, only how it's written down. Convert each spec so that nothing it
asked for is lost and nothing new is slipped in. The user should be able to read the old and
new versions side by side and see the same recipe. The format is in `specs/README.md`
(Component spec, and Migrating to the tables). Read it first.

## Steps

1. **Find the specs.** Run `node scripts/spec-lint.mjs` and collect the specs it warns about:
   `"## Props / States" is the old format`, or `States is a list`. With names given, take just
   those. Skip `deprecated` specs: they're frozen and stay as they are.
2. **Ask about what converting costs.** Converting a spec changes its fingerprint, and two
   kinds of spec pay for that:
   - **A verified spec:** its report goes stale, so it goes back to `implemented` and needs
     `/spec-verify` again.
   - **The verified specs built from a component:** converting the component flags each of them
     for an audit, and clearing that means re-running `/spec-verify` on it. Run
     `node scripts/spec-lint.mjs --refs <Component>` for each component you'd convert; the specs
     it marks `(will need an audit)` are the ones.

   List both and ask which, if any, to include. A component whose conversion would flag verified
   specs counts as one to ask about, even if it isn't verified itself. Leave the rest alone. They
   keep working, with a lint warning, until they next change for another reason. Everything
   else (drafts, and approved or implemented specs that flag nothing) is migrated without asking.
3. **Convert each spec**, reading its `source` files for a component:
   - **Props:** one row per prop, named in backticks exactly as in code. Take the type,
     whether it's required, and the default from the code. Where the code doesn't say, or there's
     no code yet, write your best reading of the old spec and add it to your list of guesses.
     A prop the code has but the old spec never mentioned is a guess too. List it, don't add it.
   - **States:** one row per state, named in plain lowercase. "when" names the prop in backticks
     (`` `loading` is true``) or the event ("while held"). A prop that drives a state gets
     `→ state <name>` in its notes.
   - **Rules:** behaviour in the old list ("not pressable", "never shows two at once") becomes
     a rule in `## Rules` with the next unused ID (add the section if there isn't one). Something
     it must never do in general may belong in `## Must not` instead. Keep the wording. Don't
     sharpen it into something the user didn't say.
   - **Keep everything else as it is**, and remove the old section.
4. **Write it** in a single edit per spec:
   - **draft:** edit it directly.
   - **approved or implemented:** as an amendment (see `specs/README.md`). Finding: "written
     before the Props and States tables". Change: the conversion, naming any new Rules.
     Affects: what `--refs` lists, saying which of those specs will need an audit. The rest only
     relied on the spec; a change in format doesn't change what they build on. Then apply it: merge the change, remove the entry, and add a dated line under
     `## Decisions` ("Moved Props / States into the Props and States tables; 'not pressable'
     became R1"). The user accepts it at the prompt.
   - **verified, if the user included it:** first set `status: implemented`, which needs no
     prompt. Then convert it as for implemented.
5. **Check.** Run `node scripts/spec-lint.mjs`. The old-format warnings for what you converted
   should be gone, and there should be no new errors.
6. **Report** in a few lines:
   - what you converted;
   - **your guesses** (types, defaults, anything you read into the old wording), so the user can
     correct them;
   - new Rules that have no tagged test yet;
   - the specs that need `/spec-verify` again, because they were verified or are now flagged
     for an audit, which you can offer to run.

Never edit a report, and never set `verified`: re-verifying is `/spec-verify`'s job, and the
taste test is the user's.
