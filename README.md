# Recipe-Driven Development

A workflow for building with AI coding tools, borrowed from the kitchen:

- **You're the head chef.** You decide what goes on the menu. Each recipe is a spec in
  constrained markdown that says what a screen, component, flow, data model, API or policy should
  be, with rules that can be checked. Claude can draft them for you, but nothing is built until
  you approve the recipe.
- **The AI is the cook.** Claude Code reviews the recipe, builds against it and checks its own
  work against it. It can't change an approved recipe without your sign-off: if it finds a
  problem, it proposes an amendment and you accept or reject it with one click.
- **You taste it.** Nothing is done until you say so. Claude can only mark a spec `verified`
  with a report showing every rule passing, and even then you're asked to confirm right in the
  session. You never have to leave your flow to edit a file.

## Why does this exist?

Since I started working closely with Claude at the beginning of 2026, my role as a developer has
shifted. I no longer write every line of code, and as a result I've started to lose track of
everything my app does. That's mostly fine: the code should be written and organized however
Claude can best work with it. But I still need to stay in control of the architecture and the
core functionality.

Losing track shows up as two closely related problems:

1. **Claude makes assumptions faster than I can keep up with**, especially in auto mode.
2. **Claude changes existing behaviour to get a task done** when my request is too vague.

Recipe-driven development is my answer to both. It's sort of an evolution of test-driven
development for AI coding: you write specs first, Claude builds against them, and the same specs
are used to check the result afterwards.

That said, specs are not a replacement for testing your code. You still need tests to make sure
the code works. Specs are for you as the developer, to make sure everything is working towards
your vision.

In this framework, a spec (or recipe) is a short markdown file describing how a model, API,
policy, component, screen or flow should behave. It describes behaviour, not implementation, so
Claude keeps its freedom over how the code is written. Specs start as drafts, which Claude can
help you write. Once you approve one, it's the source of truth:

- **Fewer assumptions.** You settle the behaviour up front, and `/spec-review` flags anything
  vague before it's built, so there's less left for Claude to guess.
- **No quiet changes.** Claude can't edit an approved spec. If it thinks one needs to change, it
  proposes an amendment and you accept it or tell it to stick to the recipe.

Because the specs describe how everything is supposed to work, you can audit the codebase
against them at any time. You stay in touch with how your app behaves without reading every
line, and you and Claude can each do what you do best.

## A day in the kitchen

1. **List the menu.** Jot what you need in `specs/outline.md`, one line each, or tell Claude.
2. **Draft the recipes.** `/spec-new AlbumDetail: let a listener buy an album` adds it to the
   outline and drafts it from what you've said. `/spec-new` on its own drafts everything in the
   outline that has no spec yet.
3. **Review.** `/spec-review AlbumDetail` lists what's vague or missing, with wording to fix it.
   Reply "apply 1, 3" or edit the spec yourself.
4. **Approve.** Say "approve AlbumDetail". Claude sets the status and you confirm the prompt.
   From here the spec is locked.
5. **Cook.** "Build AlbumDetail." If Claude finds the spec is wrong, it writes an amendment and
   asks you to accept it. That prompt is your one decision.
6. **Check.** `/spec-verify AlbumDetail` checks every rule and writes a report. Rules only a
   person can judge are left for you.
7. **Taste.** Claude tells you what to try, then asks you to confirm. Yes: `verified`. No: say
   what's off and it goes back on the stove.

When a recipe comes off the menu, say "deprecate BuyButton, PrimaryButton replaces it". The spec
stays as a frozen record with the date and the reason, so Claude knows not to build on it even
while old code still references it, and it points Claude at the replacement.

See [`examples/music-store`](examples/music-store) for a small set of specs partway through a
project: one verified, a few approved (one with an open amendment), a couple of drafts, and one
deprecated.

## Installing

```
./install.sh <repo>            # adds specs/, scripts/spec-lint.mjs, three skills, hooks, CLAUDE.md rules
./install.sh <repo> --update   # also refreshes spec-lint.mjs, specs/README.md, the skills and the CLAUDE.md rules
./test/run.sh                  # end-to-end check in a throwaway repo
```

The kit is versioned: `node scripts/spec-lint.mjs --version` prints the version a repo has, and
`--update` says which version it's updating from. [`CHANGELOG.md`](CHANGELOG.md) lists what
changed in each one, and flags anything that could make your existing specs fail lint after an update.

You may need to **keep permission prompts on.** Your sign-off is a Claude Code permission prompt.
Under modes that skip prompts, the "ask" may never reach you, and the locks quietly stop working.

The spec kinds (screen, component, flow, model, API, policy) are shaped for apps with a UI and a
backend. CLIs, libraries and background jobs fit less well; a model, API or policy spec usually
comes closest. If you're interested in using this repo for those things, feel free to file issues or
make a fork and improve it.

What gets installed into the repo:

| path | what it is |
|---|---|
| `specs/README.md` | the spec format: lifecycle, tasting, deprecating, each kind of spec, references, layout grammar, rules, amendments |
| `specs/outline.md` | a quick list of every screen, component, flow, model, API and policy you know you'll need; `--scaffold` turns it into draft specs |
| `specs/_templates/` | `screen.md`, `component.md`, `flow.md`, `model.md`, `api.md`, `policy.md` |
| `specs/tokens.md` | design tokens, referenced as `$name` |
| `scripts/spec-lint.mjs` | lint (`--fix` regenerates Used by, `--summary` prints a dashboard, `--hash` fingerprints a spec, `--refs` lists every spec that relies on one), scaffolding (`--new <kind> <Name>`, `--scaffold` from the outline); also the hook entry point. Node ≥ 18, no dependencies |
| `.claude/settings.json` | **PreToolUse** hooks ask you before protected content in a non-draft spec changes (naming the amendment when Claude applies one), before a shell command that looks like it writes to `specs/`, before anything is marked `verified` (which is refused outright without a passing report), and before a spec is deprecated (any later edit to a deprecated spec is refused). **PostToolUse** hooks send lint errors back to Claude, remind it when it edits the source of a deprecated spec, and record its own changes to specs. **SessionStart** and **UserPromptSubmit** hooks tell Claude which specs changed outside its own edits (your approvals and edits, or a teammate's after a pull), using `specs/.last-seen.json`, which install adds to `.gitignore`. Also kitchen-themed `spinnerVerbs` ("Checking the pantry", "Mincing", "Deglazing"…), unless the repo already sets its own |
| `.claude/skills/spec-new`, `spec-review`, `spec-verify` | `/spec-new [kind] <Name>[: what it's for]`, `/spec-review <Name>`, `/spec-verify <Name>` |
| `CLAUDE.md` | rules block between `rdd:start` and `rdd:end` markers |

Limits: the shell-command hook is a heuristic. It catches the usual ways of writing files
(`sed -i`, redirects, `mv`, `cp`, `rm`, `tee`, inline scripts and so on), but a determined command
can still get past it.

## Using in an established codebase

You can install this in an established codebase and ask Claude to create draft specs based on
how everything is currently working. This will naturally act as an audit and can help you find
issues. You can also install it and simply use it going forward as you make changes or build new
features.

## Releasing

For maintainers: run **Create a release** from the Actions tab, choosing `minor` or `patch` (or
an exact version). It opens a `chore: release X.Y.Z` PR with the changelog and `VERSION` updated
and starts the tests on it. Squash-merge it and **Tag a release** tags the merge commit and
publishes a GitHub release with that version's changelog entries.

## Issues/suggestions

Feel free to open issues here in this repo if you run into problems or have ideas that can
improve the way this works. Pull requests should add a line under **Unreleased** in
[`CHANGELOG.md`](CHANGELOG.md).

## License

[MIT](LICENSE)
