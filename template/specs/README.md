# Specs

This folder holds the recipes. You're the head chef: you decide what each screen, component,
flow, data model and API should be. Claude can draft the recipe from what you've told it, but it
only becomes binding when you approve it. Claude is the cook: it plans, implements and checks its
work against the recipe, and **never changes a recipe silently**. Any change to an approved spec
is proposed as an amendment that you accept or reject. And nothing is done until you've tasted
it: a spec only becomes `verified` when you confirm the result is what you meant.

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
    the name filled in. Kinds: `screen`, `component`, `flow`, `model`, `api`.
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

Once a spec leaves `draft`, its frontmatter and every section except **Used by**,
**Open amendments** and **Decisions** are protected. Claude Code will ask your permission
before any edit touches them.

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
report no longer matches the fingerprint and lint fails until it's re-verified.

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

## References between specs

Any protected section can point at another spec. Lint checks that the target exists, and models
and APIs get a generated **Used by** listing everyone who points at them.

| syntax | meaning |
|---|---|
| `[[screen:AlbumDetail]]` | a screen spec |
| `[[flow:Checkout]]` | a flow spec |
| `[[model:Album]]` / `[[model:Album#price]]` | a model, or one of its fields |
| `[[api:GetAlbum]]` / `[[api:GetAlbum#not_found]]` | an API, or one of its error codes |

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

Then it applies the amendment straight away: merges the change, removes the entry and adds a
line to Decisions, all in one edit. That edit triggers a prompt naming the amendment
("Accept amendment A1 (…)?"), and the prompt is your decision:

- **Accept** by approving it. Nothing else to do.
- **Deny** to leave the amendment open. Tell Claude to reject it and it removes the entry and
  records your reason in Decisions, so the question doesn't come back.

```markdown
## Decisions
- 2026-10-23: Rejected A2 (make ReleaseTimeline shared): only AlbumDetail needs it; revisit if a second screen does.
```

## Tools

- `node scripts/spec-lint.mjs`: validate everything (also runs automatically after Claude edits).
- `node scripts/spec-lint.mjs --fix`: regenerate `Used by`.
- `node scripts/spec-lint.mjs --summary`: dashboard of status, rule/test coverage, open amendments, and what's shared vs one-off.
- `node scripts/spec-lint.mjs --new <kind> <Name>`: create one draft spec from its template.
- `node scripts/spec-lint.mjs --scaffold`: create a draft for every outline entry without a spec.
- `node scripts/spec-lint.mjs --hash <Name>`: the spec's fingerprint, which `/spec-verify` stamps into its report.
- `node scripts/spec-lint.mjs --version`: the version of the kit this repo has; see the kit's CHANGELOG.md for what each one changed.
- `/spec-new [kind] <Name>[: what it's for]`: add a spec to the outline and draft it; with no arguments, draft everything in the outline that has no spec.
- `/spec-review <Name>`: Claude critiques a spec before it's built.
- `/spec-verify <Name>`: Claude checks the implementation rule by rule, writes `_reports/<Name>.md`, and then asks you to taste it.
