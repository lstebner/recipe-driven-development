---
name: spec-new
description: Create new draft specs in specs/: one from a name and a line about it ("/spec-new AlbumDetail: let a listener buy an album", "/spec-new model Album"), or one for every outline entry that has no spec yet ("/spec-new" with no arguments). Adds the entry to specs/outline.md and drafts the content from what the user has said. Use when asked to "add a spec", "start a spec for …", or "draft the specs from the outline".
argument-hint: "[kind] <Name>[: what it's for]  (no arguments: everything in the outline)"
---

# New spec

A shortcut for starting recipes. The user names the dish and says a line about it; you set up
the draft and fill in what they've told you. It's always a `draft`: only the user approves it.

## Arguments

- `/spec-new [kind] <Name>[: what it's for]`, e.g. `/spec-new AlbumDetail: let a listener see an
  album and buy it`, or `/spec-new api GetAlbum: GET /albums/{id} — fetch one album`.
  - `kind` is `screen`, `component`, `flow`, `model` or `api`. If it's left out, infer it from the
    name and the line (a page or view is a screen, an entity is a model, an endpoint is an api).
    If you can't tell, ask in one short question.
  - Several at once is fine: `/spec-new Library, ArtistBadge, model Artist`.
- `/spec-new` with no arguments: every entry in `specs/outline.md` that doesn't have a spec yet.

## Steps

1. **Outline first.** For each named spec that isn't in `specs/outline.md`, add it under the
   right heading as `- Name: the line` (create the heading if it's missing). The outline stays
   the one list of everything planned.
2. **Create the files** with `node scripts/spec-lint.mjs --scaffold`. It creates a draft for
   every outline entry without a spec, fills in the line as the Goal or Purpose (and an API's
   leading `GET /path` as its endpoint), and never touches existing specs. If a name is already
   taken, tell the user which spec has it and skip it. A deprecated spec keeps its name for good,
   so a replacement needs a new one (`GetAlbumV2`, or a name that says what changed).
3. **Draft the content**, following the drafting rule in `CLAUDE.md`: write only what the user
   said or clearly implied, using this conversation and the outline (including the notes
   indented under each entry). That usually means a Goal or Purpose, a few checkable Rules, and
   sections the intent clearly covers. Leave the rest empty. If all you have is a name, leave
   the draft as scaffolded.
4. **Lint** with `node scripts/spec-lint.mjs` and fix any errors in what you wrote.
5. **Report** in a few lines: which specs you created (as paths), what you guessed, and the next
   step, `/spec-review <Name>`. Don't paste the specs back.
