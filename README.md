# Recipe-Driven Development

A workflow for building with AI coding tools, borrowed from the kitchen:

- **You're the head chef.** You write the recipe: a spec in constrained markdown that says what
  a screen, component, flow, data model or API should be, with rules that can be checked.
- **The AI is the cook.** Claude Code reviews the recipe, builds against it and checks its own
  work against it. It can't change an approved recipe without your sign-off: if it finds a
  problem, it proposes an amendment and waits for you.
- **You taste it.** Nothing is done until you say so. Claude can only mark a spec `verified`
  with a report showing every rule passing, and even then you're asked to confirm right in the
  session. You never have to leave your flow to edit a file.

```
./install.sh <repo>            # adds specs/, scripts/spec-lint.mjs, two skills, hooks, CLAUDE.md rules
./install.sh <repo> --update   # also refreshes spec-lint.mjs, the skills and the CLAUDE.md rules
./test/run.sh                  # end-to-end check in a throwaway repo
```

What gets installed into the repo:

| path | what it is |
|---|---|
| `specs/README.md` | the spec format: lifecycle, tasting, each kind of spec, references, layout grammar, rules, amendments |
| `specs/_templates/` | `screen.md`, `component.md`, `flow.md`, `model.md`, `api.md` |
| `specs/tokens.md` | design tokens, referenced as `$name` |
| `scripts/spec-lint.mjs` | lint (`--fix` regenerates Used by, `--summary` prints a dashboard, `--hash` fingerprints a spec); also the hook entry point. Node ≥ 18, no dependencies |
| `.claude/settings.json` | **PreToolUse** hooks ask you before protected content in a non-draft spec changes, before a shell command that looks like it writes to `specs/`, and before anything is marked `verified` (which is refused outright without a passing report). A **PostToolUse** hook sends lint errors back to Claude |
| `.claude/skills/spec-review`, `spec-verify` | `/spec-review <Name>`, `/spec-verify <Name>` |
| `CLAUDE.md` | rules block between `rdd:start` and `rdd:end` markers |

Limits: the shell-command hook is a heuristic. It catches the usual ways of writing files
(`sed -i`, redirects, `mv`, `cp`, `rm`, `tee`, inline scripts and so on), but a determined command
can still get past it. Under permission modes that skip prompts, the "ask" may not reach you.
