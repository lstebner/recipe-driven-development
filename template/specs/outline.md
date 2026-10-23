# Outline

Everything you know you'll need, listed quickly. Then run:

    node scripts/spec-lint.mjs --scaffold

That creates a draft spec for every entry that doesn't have one yet, from `specs/_templates/`.
Existing specs are never touched, so you can keep adding to this list and run it again.
Or, in Claude Code, run `/spec-new` and Claude fills the drafts in from these lines and your
conversation, then lists what it guessed. `/spec-new Name: a line about it` adds one entry here
and drafts it in one go.

Write each entry as `- Name`, or `- Name: a line about it`. The line becomes the draft's Goal or
Purpose. For an API, start the line with its endpoint: `- GetAlbum: GET /albums/{id} — fetch one album`.
Anything indented under an entry is your own notes and isn't copied anywhere.

## Screens

## Components

## Flows

## Models

## APIs
