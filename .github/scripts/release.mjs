#!/usr/bin/env node
// Release helpers for the kit, used by .github/workflows/release.yml and tag-release.yml. Runnable by hand too.
//   prepare <patch|minor|major|X.Y.Z> [--date YYYY-MM-DD]
//                  turn Unreleased in CHANGELOG.md into a version heading, start a new empty Unreleased above it,
//                  and set VERSION in template/scripts/spec-lint.mjs to match; prints the new version
//   notes <X.Y.Z>  print that version's entries from CHANGELOG.md, for the GitHub release
//   current        print VERSION from template/scripts/spec-lint.mjs
//   --root <dir>   the kit's root (default: two directories up from this script)
import { readFileSync, writeFileSync } from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const args = process.argv.slice(2)
const argOf = (flag) => (args.includes(flag) ? args[args.indexOf(flag) + 1] : null)
const root = path.resolve(argOf("--root") || path.join(path.dirname(fileURLToPath(import.meta.url)), "..", ".."))
const changelogFile = path.join(root, "CHANGELOG.md")
const lintFile = path.join(root, "template", "scripts", "spec-lint.mjs")

const fail = (message) => {
  console.error(`release: ${message}`)
  process.exit(1)
}
const SEMVER = /^(\d+)\.(\d+)\.(\d+)$/
const parse = (version) => SEMVER.exec(version)?.slice(1).map(Number)
const newer = (a, b) => {
  const [x, y] = [parse(a), parse(b)]
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] > y[i]
  return false
}

const current = () => /^const VERSION = "(.*)"$/m.exec(readFileSync(lintFile, "utf8"))?.[1] ?? fail(`no VERSION in ${lintFile}`)

// The body of a "## heading" section of the changelog: everything up to the next "## " heading.
const section = (text, heading) => {
  const start = text.indexOf(`\n${heading}\n`)
  if (start === -1) return null
  const from = start + heading.length + 2
  const next = text.indexOf("\n## ", from)
  return { from: start + 1, to: next === -1 ? text.length : next + 1, body: text.slice(from, next === -1 ? text.length : next).trim() }
}

const prepare = (target, date) => {
  const was = current()
  const [major, minor, patch] = parse(was) ?? fail(`VERSION "${was}" isn't X.Y.Z`)
  const bumps = { major: `${major + 1}.0.0`, minor: `${major}.${minor + 1}.0`, patch: `${major}.${minor}.${patch + 1}` }
  const version = bumps[target] ?? (parse(target ?? "") ? target : fail(`expected patch, minor, major or X.Y.Z (got "${target ?? ""}")`))
  if (!newer(version, was)) fail(`${version} isn't newer than the current version, ${was}`)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) fail(`--date must be YYYY-MM-DD (got "${date}")`)

  const text = readFileSync(changelogFile, "utf8")
  const unreleased = section(text, "## Unreleased") ?? fail(`CHANGELOG.md has no "## Unreleased" section`)
  if (!unreleased.body) fail("Unreleased in CHANGELOG.md is empty, so there's nothing to release")
  if (text.includes(`\n## ${version} `)) fail(`CHANGELOG.md already has a section for ${version}`)
  const released = `## Unreleased\n\n## ${version} (${date})\n\n${unreleased.body}\n\n`
  writeFileSync(changelogFile, text.slice(0, unreleased.from) + released + text.slice(unreleased.to))
  writeFileSync(lintFile, readFileSync(lintFile, "utf8").replace(/^const VERSION = ".*"$/m, `const VERSION = "${version}"`))
  console.log(version)
}

const notes = (version) => {
  const text = readFileSync(changelogFile, "utf8")
  const heading = text.split("\n").find((line) => line.startsWith(`## ${version} `))
  const found = heading && section(text, heading)
  if (!found?.body) fail(`CHANGELOG.md has no entries for ${version}`)
  console.log(found.body)
}

const [command, value] = args.filter((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1].startsWith("--")))
if (command === "prepare") prepare(value, argOf("--date") ?? new Date().toISOString().slice(0, 10))
else if (command === "notes") notes(value)
else if (command === "current") console.log(current())
else fail("usage: release.mjs prepare <patch|minor|major|X.Y.Z> [--date YYYY-MM-DD] | notes <X.Y.Z> | current")
