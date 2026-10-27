# Specs

This folder holds the recipes. You're the head chef: you decide what each screen, component,
flow, data model, API and policy should be. Claude can draft the recipe from what you've told
it, but it only becomes binding when you approve it. Claude is the cook: it plans, implements and
checks its work against the recipe, and **never changes a recipe silently**. Any change to an
approved spec is proposed as an amendment that you accept or reject. And nothing is done until
you've tasted it: a spec only becomes `verified` when you confirm the result is what you meant.

The loop: outline → draft → `/spec-review` → you approve → Claude builds (amendments if needed)
→ `/spec-verify` → you taste → `verified`.

```
specs/
  README.md        this file: the spec format
  outline.md       a quick list of everything planned; --scaffold turns it into draft specs
  tokens.md        design tokens (colors, spacing, type)
  screens/         one file per screen             e.g. screens/AlbumDetail.md
  components/      one file per shared component   e.g. components/PrimaryButton.md
  flows/           multi-step journeys             e.g. flows/Checkout.md
  models/          data entities                   e.g. models/Album.md
  apis/            one file per endpoint           e.g. apis/GetAlbum.md
  policies/        business decisions, shared      e.g. policies/CanBuyAlbum.md
  _templates/      copy these to start a new spec
  _reports/        verification reports written by /spec-verify
```

Only new work gets specs. Code without a spec isn't checked. Spec names must be unique across
all of `specs/` (a screen and a model can't both be called `Album`), because rule IDs and reports
are keyed by name.

## Starting specs

Deciding what goes in the recipe is your job; typing it up doesn't have to be. Either:

- **Ask Claude to draft it** with `/spec-new`:
  - `/spec-new AlbumDetail: let a listener see an album and buy it`: one spec. Add the kind
    (`/spec-new model Album`) if the name doesn't make it obvious; list several with commas.
  - `/spec-new`: every entry in `outline.md` that doesn't have a spec yet.

  Claude adds the entry to the outline, writes a `draft` from what you've said, keeps it short,
  and lists anything it had to guess so you can confirm or correct it. Then run `/spec-review`.
- **Or start from an empty draft** with one of two commands:

  - `node scripts/spec-lint.mjs --new screen AlbumDetail`: one draft spec from its template, with
    the name filled in. Kinds: `screen`, `component`, `flow`, `model`, `api`, `policy`.
  - `node scripts/spec-lint.mjs --scaffold`: one draft for every entry in `outline.md` that
    doesn't have a spec yet. Existing specs are never touched, so run it as often as you like.

Either way, a draft is just a draft. What makes it a rule is your approval.

The outline is for sketching the whole project quickly:

```markdown
## Screens
- AlbumDetail: let a listener see an album and buy it
- Library
## Components
- ArtistBadge
## Models
- Album
- Artist
## APIs
- GetAlbum: GET /albums/{id} — fetch one album
## Policies
- CanBuyAlbum: whether a listener can buy an album, already owns it, or can't get it
```

The text after the colon is yours, so it goes into the draft's Goal or Purpose (and for an API, a
leading `GET /path` becomes its `endpoint`). Everything else in the draft is left for you to write.
Lint warns about outline entries that don't have a spec yet, and errors if an entry's section
doesn't match the kind of spec it became.

## Lifecycle

| status | meaning | who sets it |
|---|---|---|
| `draft` | being written; anyone can edit freely | you, or Claude drafting for you |
| `approved` | intent is settled; ready to build | **you only**: say "approve AlbumDetail" and confirm the prompt, or edit the status yourself |
| `implemented` | built; not yet fully verified | Claude |
| `verified` | every rule passed `/spec-verify`, and you tasted it | Claude proposes it; **you confirm** |
| `deprecated` | off the menu: kept as a record, never built against or edited again | Claude proposes it; **you confirm** |

Once a spec leaves `draft`, its frontmatter, anything before its first heading, and every
section except **Used by**, **Open amendments** and **Decisions** are protected. Claude Code will
ask your permission before any edit touches them.

### Tasting (`verified`)

Claude can't just declare something done. When it sets `status: verified`:

1. The hook checks `_reports/<Name>.md`. The report must be stamped with the spec's current
   fingerprint (`Spec: <hash>`, from `node scripts/spec-lint.mjs --hash <Name>`), have a ✅ or
   👤 row for every rule, and have no ❌ or ⚠️ rows. If any of that fails, the change is refused.
2. If the report passes, you're asked to confirm, right in the session. Claude tells you
   beforehand what to try. Approve if it tastes right; deny and say what's off if it doesn't.

👤 means "only a person can check this": how something looks, how it feels on a real device. It
doesn't block `verified`; it lands on your list of things to try, and the prompt names it. That
way Claude never has to choose between leaving a rule unchecked and claiming a ✅ it can't back up.

Lint holds the line afterwards: if a verified spec changes (say you accept an amendment), its
report no longer matches the fingerprint and lint fails until it's re-verified. The fingerprint
also covers the decision of every [policy](#policy-spec) the spec relies on, so changing a
policy's Inputs, Output, Rules or Must not sends every verified spec that relies on it back to be
re-verified too. Rewording its Purpose or adding Examples doesn't.

Components work differently: the report records the fingerprint of each shared component the
spec is built from (a `Components:` line, from `node scripts/spec-lint.mjs --components <Name>`),
and a change to one asks for an audit rather than sending the spec back. See
[Changing a spec](#changing-a-spec).

### Deprecating (`deprecated`)

Recipes come off the menu: a feature is dropped, or something newer replaces it. Deleting the
spec would lose the record of what was meant, and the code usually lags behind: old components
stay imported, old endpoints keep their callers for a while. So the spec stays, marked so Claude
knows not to use it:

```markdown
---
api: GetAlbumPrice
status: deprecated
deprecated: 2026-10-22          # the date it came off the menu, for digging through history later
replaced_by: GetAlbum           # optional: what to use instead (a list if it was split up)
endpoint: GET /albums/{id}/price
---
```

Say "deprecate GetAlbumPrice, GetAlbum replaces it" and Claude sets these fields, adding a dated
line under Decisions saying why, in one edit that changes nothing else. The hook checks that the
date is real, that each replacement is a live spec of the same kind and past draft (a draft
could be deleted, leaving the frozen spec pointing at nothing), and that the Decisions line is
there, since it can't be added once the spec is frozen. Then it asks you to confirm. Claude
also takes it off `outline.md`, which lists only what's current; lint fails until it does. A
draft was never agreed on, so there's nothing to keep: delete it instead.

From then on the spec is **frozen**:

- **Never edited.** The hook refuses every edit Claude tries, Decisions included. If you change
  your mind, set its status back yourself (to `approved`, say). Claude notices on your next
  message (see [Noticing your changes](#noticing-your-changes)) and finishes the job: it removes
  the `deprecated` and `replaced_by` lines, adds a dated line under Decisions and puts the spec
  back in `outline.md`. From then on it's checked in full again, so anything that went stale while
  it was frozen, such as a `source` file that has since moved, shows up in lint. Or write a new
  spec.
- **Never built against.** Claude follows `replaced_by` instead, and doesn't extend code that only
  exists for the deprecated spec. If the replacement has been deprecated in turn, the chain is
  followed to its end: when BuyButton was replaced by PrimaryButton, and PrimaryButton later by
  ActionButton, everything that still uses BuyButton is told to use ActionButton. When Claude
  edits a file listed in its `source`, a hook reminds it that the spec is deprecated.
- **Still visible.** Lint warns wherever a live spec still points at it (fix those with an
  amendment), and `--summary` lists every deprecated spec with any tests still tagged with its
  rules: that's code that hasn't caught up yet.
- **Out of the way.** Lint checks only its deprecation fields, so missing source files or renamed
  references can't break it. Its replacement being deprecated in turn is fine; if the chain breaks
  (a replacement is deleted, or the chain loops back on itself), lint warns rather than fails,
  since the frozen spec can't be fixed. It drops out of everyone's Used by, and a
  replacement can claim the same endpoint. Its name and rule IDs stay taken, so old commits and
  test names still point at exactly one thing.

### Noticing your changes

You don't have to tell Claude when you change a spec yourself. `specs/.last-seen.json` records
what Claude last saw of each spec (its status and fingerprint). It's ignored by git, so it's
per checkout. At the start of a session and on each message you send, a hook compares the specs
with it and tells Claude what changed somewhere else: your own edits, or a teammate's after a
`git pull`. Claude's own changes, through its edit tools or a shell command it ran, are recorded
as it makes them, so it isn't told about those. If you'd already changed the same spec, your
change is still reported.

| what changed | what Claude does |
|---|---|
| draft → `approved` | offers to build it |
| the content of an `implemented` or `verified` spec, or a policy it relies on | checks the code still matches and offers to re-verify (a `verified` one goes back to `implemented`, since its report no longer matches) |
| the content of an `approved` spec | re-reads it before building on it |
| `deprecated` → anything else | finishes bringing it back (above), then offers to build it |
| anything → `deprecated` | takes it off the outline and stops building on it |
| anything → `verified`, by hand | leaves it to lint to check the report, and says so if it fails |
| back to `draft` | stops building on it until it's approved again |
| the content of a component | as above, and names the built specs made from it so they can be audited ([below](#changing-a-spec)) |

A spec whose status and content both changed gets a note for each. Claude only offers: it doesn't
start building or verifying because a status moved. The first run just records what's there, and
if the record can't be read, Claude says so and starts it afresh. If you run two sessions at
once, whichever sees a change first is the one that's told.

### Changing a spec

When something that's already approved or built needs to change (a new feature for a
component, a rule that turned out wrong), change the recipe first, then the dish:

1. **Decide what kind of change it is.** For a component, see [Shared vs one-off](#shared-vs-one-off):
   if only props or appearance differ, it's a variant of the existing component; if the
   structure differs, it's a new component. If the change is to a decision several specs share,
   it belongs in a [policy](#policy-spec).
2. **Change the spec.** Any of these works:
   - **Ask Claude** ("add a destructive variant to PrimaryButton"). The spec is protected, so
     Claude writes it up as an [amendment](#amendments) and applies it, and you accept it at the
     prompt. Its Affects line lists the specs the change reaches, from
     `node scripts/spec-lint.mjs --refs <Name>`, and the prompt lists them too.
   - **Edit it yourself.** Claude is told about it on your next message ([above](#noticing-your-changes)).
   - **Set it back to `draft`** for a bigger rework, edit freely (`/spec-review` helps), and
     approve it again.

   New rules get the next number. Don't renumber: tests and reports refer to rules by ID.
3. **Build it.** A `verified` spec whose content changed goes back to `implemented`, since its
   report no longer matches. Claude builds the change and tags new tests with the new rule IDs.
4. **Taste it** with `/spec-verify`, as for anything new.

**Changing a component.** A component's change can reach every spec made from it, directly or
through another component, but most changes (a new variant, a new prop) don't affect most of
those specs. So they aren't sent back to be re-verified; they're flagged for an audit instead:

- Each report records the fingerprint of every component its spec is built from (the
  `Components:` line). Lint **warns** on a verified spec when one of those components has
  changed since: "verified against an older PrimaryButton than there is now". A component's
  Used by, Open amendments and Decisions aren't part of its fingerprint, so they don't count.
- Before a change, `--refs <Name>` and the prompt for it mark the verified specs that will need an
  audit: "AlbumDetail (verified, will need an audit)".
- When the change is yours, the hook tells Claude which built specs use the component. When it's
  Claude's, it's told which verified specs it has left behind. Either way, Claude tells you and
  offers to audit each one.
- **Auditing** means checking whether the change affects that spec. Where it does, that's an
  amendment to the spec, or a bug to fix. Either way, re-running `/spec-verify` on it records the
  component as it is now and clears the warning.

Reports written before the `Components:` line existed aren't audited. They get the line the next
time the spec is verified.

## Screen spec

````markdown
---
screen: AlbumDetail             # must match the filename
status: approved
source: [apps/web/src/app/albums/[id]/page.tsx]   # optional until implemented
---

## Goal
Let a listener see an album's details and release history, and buy it.

## Layout
- Header: [[ArtistBadge variant=compact]] · {copy.title}
- Body (≥md: row · <md: stack)
  - Artwork
  - Details
    - [[~ReleaseTimeline]]                     → R2
    - Price ($type.heading)
    - ?!owned [[PrimaryButton]] {copy.buy}     → R1
    - ?owned {copy.owned}                      → R1

## States
- loading: skeleton of Body; no [[PrimaryButton]]
- not-found: when [[api:GetAlbum#not_found]], show {copy.notFound}

## Rules
- R1: The buy button is hidden when the listener already owns the album; show {copy.owned} instead.
- R2: The release timeline shows the newest release first.

## Copy
| key | text |
|---|---|
| title | {album.title} |
| buy | Buy for {price} |
| owned | In your library |
| notFound | We couldn't find that album. |

## Style
- Artwork has $radius.md corners and $shadow.card.

## Open amendments

## Decisions
````

Required sections: **Goal**, **Rules**. Everything else is optional: write only what matters.

## Component spec

````markdown
---
component: PrimaryButton
status: approved
source: packages/ui/src/PrimaryButton.tsx
---

## Purpose
The single call-to-action on a screen.

## Variants
- default: filled $color.accent
- quiet: outline only, for secondary placement

## Props / States
- label (required), onPress, loading, disabled
- loading: spinner replaces label; not pressable

## Must not
- Never fetch data or navigate on its own; the screen decides what a press does.

## Used by
<!-- generated by spec-lint --fix; do not edit -->
- AlbumDetail (screen)

## Open amendments

## Decisions
````

Required section: **Purpose**. A component can compose other shared components: give it a
`## Layout` section, the same as a screen.

## Flow spec

A journey across screens and API calls: checkout, onboarding, password reset.

````markdown
---
flow: Checkout
status: approved
---

## Goal
A listener who has chosen an album ends up owning it, or knows exactly why not.

## Entry
Buy on [[screen:AlbumDetail]]; the listener is signed in.

## Steps
1. [[screen:Cart]]
   - ?empty → end                                      → R1
2. [[screen:Payment]] calls [[api:CreateOrder]]
   - ?[[api:CreateOrder#card_declined]] → step 2       → R2
3. [[screen:OrderConfirmation]]

## Exits
- done: the album is in the library
- cancelled at any step: the cart is kept

## Rules
- R1: An empty cart never reaches Payment.
- R2: A declined card returns to Payment with the card fields kept and {copy.declined} shown.

## Copy
| key | text |
|---|---|
| declined | Your card was declined. Try another one. |

## Open amendments

## Decisions
````

Required sections: **Goal**, **Steps**, **Rules**. Steps are a numbered list; branches are
sub-bullets ending in `→ step N`, `→ end`, or `→ [[flow:Other]]`.

## Model spec

A data entity. Screens and APIs reference it rather than redefining its fields.

````markdown
---
model: Album
status: approved
source: [packages/db/schema/album.ts]
---

## Purpose
An album listed for sale.

## Fields
| field | type | required | notes |
|---|---|---|---|
| id | uuid | yes | |
| title | string | yes | 1–200 chars |
| artist | [[model:Artist]] | yes | |
| price | money | yes | |

## Relationships
- artist: many Albums → one [[model:Artist]]; an Artist with albums can't be deleted

## Rules
- R1: price is never negative.
- R2: title is trimmed before it's saved.

## Used by
<!-- generated by spec-lint --fix; do not edit -->
- GetAlbum (api)

## Open amendments

## Decisions
````

Required sections: **Purpose**, **Fields**.

## API spec

One endpoint (or RPC, or webhook). The contract the frontend and backend both build to.

````markdown
---
api: GetAlbum
status: approved
endpoint: GET /albums/{id}
source: [apps/api/src/routes/albums.ts]
---

## Purpose
Fetch one album for its detail page.

## Auth
Public. Signed-in callers also get `owned`.

## Request
| field | type | required | notes |
|---|---|---|---|
| id | uuid | yes | path |

## Response
200: [[model:Album]] plus `owned: boolean`

## Errors
| code | status | when |
|---|---|---|
| not_found | 404 | no album with that id, or it's unlisted |

## Rules
- R1: An unlisted album returns not_found, never 403, so its existence isn't revealed.

## Used by
<!-- generated by spec-lint --fix; do not edit -->
- AlbumDetail (screen)

## Open amendments

## Decisions
````

Required sections: **Purpose**, **Rules**, plus `endpoint` in the frontmatter. No two API specs
may claim the same endpoint.

## Policy spec

A business decision that more than one spec depends on: whether a listener can buy an album, what
an order costs, who may cancel it. It isn't a data entity (no fields), an endpoint, or something
on screen. It's the logic between them, written down once so every spec that needs the answer
gets the same one.

Reach for a policy when several specs must agree on a decision but can't share a component.
Whether a listener can buy an album decides what AlbumDetail shows (Buy, or "In your library"),
what GetAlbum reports as `owned`, and when CreateOrder refuses a second purchase. Written into each
spec, the conditions drift apart; in a policy there's one place to change them, and **Used by**
lists everything a change affects. The same goes for components that show the same thing in
different ways, like a mobile and a desktop menu that must always list the same links.

````markdown
---
policy: CanBuyAlbum
status: approved
source: [apps/api/src/policies/canBuyAlbum.ts]
---

## Purpose
Whether a listener can buy an album, already owns it, or can't get it at all.

## Inputs
| input | type | notes |
|---|---|---|
| album | [[model:Album]] | |
| listener | signed-in listener | absent when signed out |

## Output
One of `buy`, `owned` or `unavailable`.

## Rules
- R1: `unavailable` when the album isn't listed, whoever is asking.
- R2: Otherwise `owned` when the listener has a completed order for the album. A refunded order doesn't count.
- R3: Otherwise `buy`, including for signed-out visitors: they sign in when they press Buy.

## Examples
| case | inputs | output |
|---|---|---|
| signed out | listed album, no listener | buy |
| refunded | listed album, only a refunded order | buy |
| delisted after buying | unlisted album, a completed order | unavailable |

## Must not
- Never trust what the client says about ownership: it comes from the listener's orders.

## Used by
<!-- generated by spec-lint --fix; do not edit -->
- AlbumDetail (screen)
- CreateOrder (api)
- GetAlbum (api)

## Open amendments

## Decisions
````

Required sections: **Purpose**, **Rules**. Inputs and Output say what the decision takes and
gives back, not how it's computed. Examples are optional: they're the cases worth pinning down,
and each one makes a good test.

The specs that depend on it reference it and say how they use the answer, without restating it.
In AlbumDetail:

```markdown
## Layout
- ?buy [[PrimaryButton]] {copy.buy}   → R1
- ?owned {copy.owned}                 → R1

## Rules
- R1: The buy button shows only when [[policy:CanBuyAlbum]] gives `buy`, and {copy.owned} only when it gives `owned`.
```

And in CreateOrder's Errors table, `| already_owned | 409 | [[policy:CanBuyAlbum]] gives owned |`.

How the code shares the decision (a function, a hook, a server field) is up to Claude. What the
policy pins down is that there's one answer: no spec that uses it works the answer out again on
its own.

A policy's decision (its Inputs, Output, Rules and Must not) counts as part of every spec that
relies on it, directly or through another policy: if AlbumDetail references CanBuyAlbum, and
CanBuyAlbum references a RefundWindow policy, AlbumDetail relies on both. When you're asked to
approve a change to the decision, the prompt names every spec it reaches. Once accepted, any of
them that were `verified` fail lint until they're re-verified against the new rules. Purpose and
Examples explain the decision rather than make it, so editing them reaches no one. A spec that's
past draft can't rely on a draft policy, since a draft can change without anyone being asked.

## References between specs

Any protected section can point at another spec. Lint checks that the target exists, and models,
APIs and policies get a generated **Used by** listing everyone who points at them.

| syntax | meaning |
|---|---|
| `[[screen:AlbumDetail]]` | a screen spec |
| `[[flow:Checkout]]` | a flow spec |
| `[[model:Album]]` / `[[model:Album#price]]` | a model, or one of its fields |
| `[[api:GetAlbum]]` / `[[api:GetAlbum#not_found]]` | an API, or one of its error codes |
| `[[policy:CanBuyAlbum]]` | a policy spec |

So a screen can say `- not-found: when [[api:GetAlbum#not_found]], show {copy.notFound}`, and lint
will catch it if that error code is renamed.

## Layout tree grammar

The Layout section is an indented bullet tree. It's the authoritative structure. Lint reads the
shared components and one-offs straight from it, so there's no separate list to keep in sync.
(Older specs may list them in `uses:` / `local:` frontmatter; if those lists are there, they must
match the tree.)

| syntax | meaning |
|---|---|
| `Header:` | a named region (just a label) |
| `[[Name]]` | a **shared** component; needs `components/Name.md` |
| `[[~Name]]` | a **deliberate one-off**; must *not* have a shared spec |
| `[[Name variant=quiet]]` | a variant listed in that component's `## Variants` |
| `{copy.key}` | text from this spec's Copy table |
| `$color.accent` | a design token from `tokens.md` |
| `(≥md: row · <md: stack)` | responsive behaviour |
| `?owned` / `?!owned` | shown only when the condition is true / false; explain it in a rule |
| `→ R1` / `→ R1, R3` | this node is governed by those rules |

The symbols are optional niceties. Type `>=`, `->` and `,` instead of `≥`, `→` and `·` if that's easier.

## Shared vs one-off

- If something appears in more than one screen, or should look identical everywhere, make it **shared**.
- **Variant or new component?** If only props or appearance differ, it's a variant of the
  existing component. If the structure differs, it's a new component, and its Purpose must
  say why it isn't a variant.
- **Same decision, different rendering?** If two components show the same thing in structurally
  different ways, they're separate components, and the decision they share is a
  [policy](#policy-spec) that both reference.
- Mark one-offs with `~` on purpose. spec-lint warns when the same one-off appears in two specs.
- `Used by` is generated. Run `node scripts/spec-lint.mjs --fix`; never edit it by hand.

## Rules

- Every top-level bullet in `## Rules` is one checkable rule: `- R1: …`. Its full ID is
  `SpecName.R1` (e.g. `AlbumDetail.R1`), which is what tests, reports and commits use. Writing
  the full ID in the spec (`- AlbumDetail.R1: …`) also works.
- Don't renumber IDs. If a rule is removed, its number retires.
- Write rules so they can be checked as pass or fail. "Feels fast" can't be checked; "shows a skeleton within 100 ms" can.
- Tag tests with the rule ID in brackets so verification can find them:
  `it("[AlbumDetail.R1] hides buy when owned", ...)`.

## Amendments

When Claude finds something during implementation that would change an approved spec, it adds
an entry under `## Open amendments`, tells you in a sentence, and pauses any work that depends on it:

```markdown
### A1: Buy button needs a disabled state while purchase is pending
- Finding: double-taps create two orders in testing.
- Change: Rules + `R3: Buy button is disabled and shows a spinner while a purchase is in flight.`
- Affects: AlbumDetail.R1, PrimaryButton (needs `loading` state)
- Shared/one-off impact: none
```

**Affects** comes from `node scripts/spec-lint.mjs --refs <Name>`, not from memory. It lists every
live spec that relies on the one being changed, including specs that rely on it through another
spec, with its status and where each link is:

```
$ node scripts/spec-lint.mjs --refs PrimaryButton
PrimaryButton (component, approved) is relied on by:
  AlbumDetail  screen  approved  layout, states
    Checkout   flow    approved  step 1
```

`--refs GetAlbum#not_found` or `--refs Album#price` narrows it to the specs that use that one
error code or field. That includes the specs that link to the whole API or model, marked
`(all of Album)`: an API that returns `[[model:Album]]` returns its price too.

Then it applies the amendment straight away: merges the change, removes the entry and adds a
line to Decisions, all in one edit. That edit triggers a prompt naming the amendment
("Accept amendment A1 (…)?"). The prompt also lists who relies on the spec, so you can see what
the change can reach for yourself. The prompt is your decision:

- **Accept** by approving it. Nothing else to do.
- **Deny** to leave the amendment open. Tell Claude to reject it and it removes the entry and
  records your reason in Decisions, so the question doesn't come back.

```markdown
## Decisions
- 2026-10-23: Rejected A2 (make ReleaseTimeline shared): only AlbumDetail needs it; revisit if a second screen does.
```

## Decisions

Decisions is the spec's history: one dated line per choice, saying what was decided and why.
Accepted and rejected amendments, deprecations and revivals all land here, and so do trade-offs:
a solution that's good enough for now when there's a better one you'd reach for later. Recording
a trade-off stops anyone "fixing" something that was deliberate, and tells them when the fix is
due. So say when to come back to it:

```markdown
## Decisions
- 2026-10-26: Validation lives in makeAlbum, not the database; every write goes through it for now. Revisit when something else writes albums.
```

The revisit condition is what makes the line worth keeping. Give it something you'd notice
(another screen needs it, a list passes 100 items, a second caller appears), not "someday". An
idea with no condition is a wish: put it under the entry in `outline.md` or in your issue tracker
instead.

A revisit line isn't a task. Claude doesn't act on it until you ask, but if it sees the condition
has been met while working, it tells you. Trade-offs only cover *how* the spec is met. One that
changes what the spec says (a rule, a state, an error) is an amendment.

Decisions isn't protected and isn't part of the fingerprint, so Claude can add lines without a
prompt and a verified spec stays verified.

## Tools

- `node scripts/spec-lint.mjs`: validate everything (also runs automatically after Claude edits).
- `node scripts/spec-lint.mjs --fix`: regenerate `Used by`.
- `node scripts/spec-lint.mjs --summary`: dashboard of status, rule/test coverage, open amendments, and what's shared vs one-off.
- `node scripts/spec-lint.mjs --new <kind> <Name>`: create one draft spec from its template.
- `node scripts/spec-lint.mjs --scaffold`: create a draft for every outline entry without a spec.
- `node scripts/spec-lint.mjs --hash <Name>`: the spec's fingerprint, which `/spec-verify` stamps into its report.
- `node scripts/spec-lint.mjs --refs <Name>[#member]`: every live spec that relies on it, directly or through other specs, with its status and where the link is.
- `node scripts/spec-lint.mjs --components <Name>`: the fingerprint of each component the spec is built from, for the report's `Components:` line.
- `node scripts/spec-lint.mjs --version`: the version of the kit this repo has; see the kit's CHANGELOG.md for what each one changed.
- `/spec-new [kind] <Name>[: what it's for]`: add a spec to the outline and draft it; with no arguments, draft everything in the outline that has no spec.
- `/spec-review <Name>`: Claude critiques a spec before it's built.
- `/spec-verify <Name>`: Claude checks the implementation rule by rule, writes `_reports/<Name>.md`, and then asks you to taste it.
- "deprecate <Name>, <Other> replaces it": Claude marks it `deprecated`, and you confirm the prompt.
