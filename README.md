# Recipe-Driven Development

A workflow for building with AI coding tools, borrowed from the kitchen:

- **You're the head chef.** You decide what goes on the menu. Each recipe is a spec in
  constrained markdown that says what a screen, component, flow, data model or API should be,
  with rules that can be checked. Claude can draft them for you, but nothing is built until you
  approve the recipe.
- **The AI is the cook.** Claude Code reviews the recipe, builds against it and checks its own
  work against it. It can't change an approved recipe without your sign-off: if it finds a
  problem, it proposes an amendment and you accept or reject it with one click.
- **You taste it.** Nothing is done until you say so. Claude can only mark a spec `verified`
  with a report showing every rule passing, and even then you're asked to confirm right in the
  session. You never have to leave your flow to edit a file.

## Why does this exist?

While working closely with Claude since the beginning of 2026 I've found that my role as a
developer has shifted. I no longer have to read every single line of code, or worry about having
to find specific functions or components for debugging, so I really don't need to worry about
how every little thing is organized as much as I used to. In fact, I don't think I should
anymore. Claude (in my case) is going to be the one that has to read the code, so the code
should be written in the way that makes it most efficient.

However, this has led to two core problems that are closely related. The first one being that it
will make assumptions as it goes that I can't keep up with (especially with auto mode now in
existence) and the second being that it will sometimes change existing functionality to
accomplish what I asked if I'm too vague with my request.

Recipe-driven development is my solution to both problems. It's sort of an evolution of
test-driven development for an AI coding world.

The basic idea is that you write specs as markdown and then Claude is instructed to treat these
as the source of truth for how things are supposed to work. You can spec models, APIs,
components, layouts, and page flows. These documents start as drafts and you can have Claude
help you scaffold the initial pass. You then update them to being "approved" at which point
Claude is no longer free to edit them and will instead ask you if it can make amendments to them
whenever it thinks it needs to make a change. You then have the ability to approve or tell it to
stick to how things are spec'd.

So the spec files both guide the development process, and also the verification after things are
built. They can be used to audit the codebase at any time, and also to help you as the developer
stay in touch with how everything works _without_ being overly specific which means you and
Claude can both do what you do best.

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

## Installing

```
./install.sh <repo>            # adds specs/, scripts/spec-lint.mjs, three skills, hooks, CLAUDE.md rules
./install.sh <repo> --update   # also refreshes spec-lint.mjs, the skills and the CLAUDE.md rules
./test/run.sh                  # end-to-end check in a throwaway repo
```

You may need to **keep permission prompts on.** Your sign-off is a Claude Code permission prompt.
Under modes that skip prompts, the "ask" may never reach you, and the locks quietly stop working.

The spec kinds (screen, component, flow, model, API) are shaped for apps with a UI and a
backend. CLIs, libraries and background jobs fit less well; a model or API spec usually comes
closest. If you're interested in using this repo for those things, feel free to file issues or
make a fork and improve it.

What gets installed into the repo:

| path | what it is |
|---|---|
| `specs/README.md` | the spec format: lifecycle, tasting, each kind of spec, references, layout grammar, rules, amendments |
| `specs/outline.md` | a quick list of every screen, component, flow, model and API you know you'll need; `--scaffold` turns it into draft specs |
| `specs/_templates/` | `screen.md`, `component.md`, `flow.md`, `model.md`, `api.md` |
| `specs/tokens.md` | design tokens, referenced as `$name` |
| `scripts/spec-lint.mjs` | lint (`--fix` regenerates Used by, `--summary` prints a dashboard, `--hash` fingerprints a spec), scaffolding (`--new <kind> <Name>`, `--scaffold` from the outline); also the hook entry point. Node ≥ 18, no dependencies |
| `.claude/settings.json` | **PreToolUse** hooks ask you before protected content in a non-draft spec changes (naming the amendment when Claude applies one), before a shell command that looks like it writes to `specs/`, and before anything is marked `verified` (which is refused outright without a passing report). A **PostToolUse** hook sends lint errors back to Claude. Also kitchen-themed `spinnerVerbs` ("Checking the pantry", "Mincing", "Deglazing"…), unless the repo already sets its own |
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

## Issues/suggestions

Feel free to open issues here in this repo if you run into problems or have ideas that can
improve the way this works.

## License

[MIT](LICENSE)
