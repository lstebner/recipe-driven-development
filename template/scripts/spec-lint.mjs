#!/usr/bin/env node
// Recipe-Driven Development: validates specs/ against the format defined in specs/README.md.
//   (no flag)      lint everything; exit 1 on errors
//   --fix          regenerate the "Used by" section of component, model, API and policy specs, then lint
//   --summary      status dashboard: specs, rules, tagged tests, open amendments, shared vs one-off
//   --hash <Name>  print the fingerprint of a spec's protected content (goes in its /spec-verify report)
//   --refs <Name>[#member]  list every live spec that relies on a spec (or on one model field / API error code),
//                  directly or through other specs, with its status and where it makes the link
//   --components <Name>  print the fingerprint of each shared component a spec is built from (goes in its report too)
//   --new <kind> <Name>  create a draft spec from specs/_templates/<kind>.md
//   --scaffold     create a draft spec for every entry in specs/outline.md that doesn't have one yet
//   --hook-pre     Claude Code PreToolUse hook (Edit/Write): ask the user before protected spec content
//                  changes; only allow `verified` with a passing report, and then only after the user confirms;
//                  ask before a spec is deprecated, and refuse any edit to one that already is
//   --hook-bash    Claude Code PreToolUse hook (Bash): ask the user before a shell command that looks like it writes to specs/
//   --hook-post    Claude Code PostToolUse hook: report lint errors back to Claude after a relevant edit, and
//                  remind it when the file it edited is the source of a deprecated spec
//   --hook-bash-post  Claude Code PostToolUse hook (Bash): record how a command the Bash hook asked about left the specs
//   --hook-seen    Claude Code SessionStart / UserPromptSubmit hook: tell Claude which specs changed since it last
//                  looked (an approval, a hand edit, a git pull), and what that means it should offer to do next
//   --version      print the kit version
//   --root <dir>   repo root (default: $CLAUDE_PROJECT_DIR, else the parent of this script's directory)
import { createHash } from "node:crypto"
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmdirSync, statSync, writeFileSync } from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

// The kit's version, shared by this script, the skills and the CLAUDE.md rules. Bump it with an entry in CHANGELOG.md.
const VERSION = "0.2.0"

const args = process.argv.slice(2)
const has = (flag) => args.includes(flag)
const argOf = (flag) => (has(flag) ? args[args.indexOf(flag) + 1] : null)
const root = path.resolve(argOf("--root") || process.env.CLAUDE_PROJECT_DIR || path.join(path.dirname(fileURLToPath(import.meta.url)), ".."))
const specsDir = path.join(root, "specs")

// One entry per kind of spec: its folder under specs/, required sections, whether it gets a generated "Used by",
// tables whose first column must be unique (beyond the Fields, Errors and Copy every kind checks), and which of
// its sections count toward the fingerprint of specs that reference it. Only a policy's do: its decision is part
// of what a referencing spec asks for, while a model or API is a contract with its own report. Purpose and
// Examples explain the decision rather than make it, so editing them doesn't send anyone back to re-verify.
const KINDS = {
  screen: { dir: "screens", required: ["Goal", "Rules"] },
  component: { dir: "components", required: ["Purpose"], usedBy: true },
  flow: { dir: "flows", required: ["Goal", "Steps", "Rules"] },
  model: { dir: "models", required: ["Purpose", "Fields"], usedBy: true },
  api: { dir: "apis", required: ["Purpose", "Rules"], usedBy: true },
  policy: { dir: "policies", required: ["Purpose", "Rules"], usedBy: true, keyed: ["inputs"], fingerprinted: ["inputs", "output", "rules", "must not"] },
}
// The table a States section holds, column by column: one row per state, a plain lowercase name, what puts it there
// and what it looks like, all in plain words. What must or must never happen is a rule, not a state. Specs give
// direction, so a component's props, types and defaults are left to its code.
const STATES_COLUMNS = ["state", "when", "looks like"]
const TABLES = { component: { states: STATES_COLUMNS }, screen: { states: STATES_COLUMNS } }
const RULE_WORDS = /\b(must|never|always|should|cannot|can't|won't)\b/i
const STATUSES = ["draft", "approved", "implemented", "verified", "deprecated"]
// A spec with no status is treated as a draft everywhere: the least that's been agreed.
const statusOf = (spec) => spec.fm.status ?? "draft"
// Claude may move a spec between these on evidence; anything else (e.g. → approved) is the user's call.
// Moving into `verified` additionally needs a passing report and the user's confirmation (see hookPre).
const CLAUDE_STATUSES = ["approved", "implemented", "verified"]
// Everything outside these sections (plus frontmatter) is protected once a spec leaves draft.
const UNPROTECTED_SECTIONS = ["used by", "open amendments", "decisions"]
// A deprecated spec is frozen: kept as a record of what was meant, never built against or edited again.
const DEPRECATION_KEYS = ["deprecated", "replaced_by"]
const USED_BY_MARK = "<!-- generated by spec-lint --fix; do not edit -->"
const TEST_FILE = /(\.(test|spec|e2e)\.[cm]?[jt]sx?$)|(\/(e2e|maestro|tests?|__tests__)\/.*\.([cm]?[jt]sx?|ya?ml|py)$)/
const SKIP_DIRS = new Set(["node_modules", ".git", "dist", "build", ".next", ".turbo", ".expo", "coverage", "Pods", "android", "ios", "specs"])

const rel = (file) => path.relative(root, file)
const normalize = (text) => text.replace(/\r\n/g, "\n")

// ---------- parsing ----------

// Blank out comments and fenced code but keep line numbers stable.
const blank = (s) => s.replace(/[^\n]/g, "")
const stripNoise = (text) =>
  text.replace(/<!--[\s\S]*?-->/g, blank).replace(/^```[\s\S]*?^```/gm, blank)

// YAML lets any value be quoted (status: "approved"); the quotes aren't part of it.
const unquote = (s) => s.replace(/^(["'])(.*)\1$/, "$2")

const parseFrontmatter = (text) => {
  const match = /^---\n([\s\S]*?)\n---\n/.exec(text)
  if (!match) return { data: null, lines: 0 }
  const data = {}
  for (const raw of match[1].split("\n")) {
    const line = raw.replace(/\s+#.*$/, "").trim()
    const kv = /^([\w-]+):\s*(.*)$/.exec(line)
    if (!kv) continue
    const value = kv[2].trim()
    data[kv[1]] = value.startsWith("[")
      ? value.replace(/^\[|\]$/g, "").split(",").map((s) => unquote(s.trim())).filter(Boolean)
      : unquote(value)
  }
  return { data, lines: match[0].split("\n").length - 1 }
}

const parseSections = (text) => {
  const sections = {}
  let current = null
  text.split("\n").forEach((line, index) => {
    const heading = /^## (.+?)\s*$/.exec(line)
    if (heading) {
      current = { name: heading[1], line: index + 1, lines: [] }
      sections[heading[1].toLowerCase()] = current
    } else if (current) {
      current.lines.push({ n: index + 1, text: line })
    }
  })
  return sections
}

const asList = (value) => (Array.isArray(value) ? value : value ? [value] : [])
const isTableRow = (text) => /^\s*\|/.test(text ?? "")
const isSeparator = (text) => /^\s*\|\s*:?-{2,}/.test(text ?? "")
// A row's cells. "\|" is a pipe inside a cell, as GitHub renders it, so a union type can be written `"a" \| "b"`.
const cellsOf = (text) =>
  text
    .trim()
    .replace(/^\|/, "")
    .replace(/(?<!\\)\|$/, "")
    .split(/(?<!\\)\|/)
    .map((c) => c.trim().replace(/\\\|/g, "|"))
// Body rows of every table in a section: skips each header row (the one right above a |---| line) and the separator.
const tableRows = (section) => {
  const lines = section?.lines ?? []
  return lines
    .filter((l, i) => isTableRow(l.text) && !isSeparator(l.text) && !isSeparator(lines[i + 1]?.text))
    .map((l) => ({ n: l.n, cells: cellsOf(l.text) }))
}
const tableKeys = (section) =>
  tableRows(section)
    .map((row) => ({ n: row.n, key: row.cells[0].replace(/^`|`$/g, "").replace(/^\$/, "") }))
    .filter((row) => row.key)

// Header row of each table in a section: the one right above a |---| line.
const tableHeaders = (section) => {
  const lines = section?.lines ?? []
  return lines.filter((l, i) => isTableRow(l.text) && isSeparator(lines[i + 1]?.text)).map((l) => ({ n: l.n, cells: cellsOf(l.text).map((c) => c.toLowerCase()) }))
}
// A States section in the current format is a table whose header is exactly the kind's columns (see TABLES).
// Anything else under that heading (a list, or a table from before the format with other columns) gets one warning
// and isn't checked row by row, so a spec that linted clean before the table existed still does.
// { section, columns, headers, current }, or null when the kind doesn't have the section or the spec leaves it out.
const formats = new WeakMap()
const formatOf = (spec, key) => {
  if (!formats.has(spec)) formats.set(spec, {})
  const cache = formats.get(spec)
  if (!(key in cache)) {
    const columns = TABLES[spec.kind]?.[key]
    const section = spec.sections[key]
    const headers = columns && section ? tableHeaders(section) : []
    cache[key] = columns && section ? { section, columns, headers, current: headers.length > 0 && headers.every((h) => h.cells.join("|") === columns.join("|")) } : null
  }
  return cache[key]
}

const parseSpec = (raw, file, kind) => {
  const text = normalize(raw)
  const { data } = parseFrontmatter(text)
  return { file, kind, name: path.basename(file, ".md"), raw: text, fm: data ?? {}, hasFrontmatter: !!data, sections: parseSections(stripNoise(text)) }
}
const loadSpec = (file, kind) => parseSpec(readFileSync(file, "utf8"), file, kind)

const listSpecs = (dir, kind) =>
  existsSync(dir)
    ? readdirSync(dir).filter((f) => f.endsWith(".md")).sort().map((f) => loadSpec(path.join(dir, f), kind))
    : []

const loadAll = () => {
  const all = Object.entries(KINDS).flatMap(([kind, { dir }]) => listSpecs(path.join(specsDir, dir), kind))
  const tokensFile = path.join(specsDir, "tokens.md")
  const tokens = existsSync(tokensFile) ? loadSpec(tokensFile, "tokens") : null
  const live = all.filter((s) => !isDeprecated(s))
  const deprecated = all.filter(isDeprecated)
  return { all, live, deprecated, tokens, outline: parseOutline() }
}

// specs/outline.md: a quick list of everything planned, under ## Screens, ## Components, ## Flows,
// ## Models, ## APIs and ## Policies. Each top-level bullet is "- Name" or "- Name: a line about it".
const outlineFile = path.join(specsDir, "outline.md")
const OUTLINE_HEADINGS = "## Screens, ## Components, ## Flows, ## Models, ## APIs or ## Policies"
const parseOutline = () => {
  if (!existsSync(outlineFile)) return null
  const entries = []
  const problems = []
  // Read sections in order rather than by name, so a heading that appears twice keeps both lists.
  const sections = []
  stripNoise(normalize(readFileSync(outlineFile, "utf8"))).split("\n").forEach((text, index) => {
    const heading = /^## (.+?)\s*$/.exec(text)
    if (heading) sections.push({ name: heading[1], line: index + 1, lines: [] })
    else sections.at(-1)?.lines.push({ n: index + 1, text })
  })
  for (const section of sections) {
    // A heading is the kind's folder name ("Policies") or the kind itself ("Policy").
    const heading = section.name.toLowerCase()
    const kind = Object.keys(KINDS).find((k) => k === heading || KINDS[k].dir === heading)
    if (!kind) {
      problems.push({ n: section.line, message: `unknown section "## ${section.name}" (expected ${OUTLINE_HEADINGS})` })
      continue
    }
    for (const line of section.lines.filter((l) => /^[-*]\s+/.test(l.text))) {
      const match = /^[-*]\s+[*`]*([A-Za-z]\w*)[*`]*\s*(?:(?::|—|–|\s-\s)\s*(.*))?$/.exec(line.text.trim())
      if (match) entries.push({ n: line.n, kind, heading: section.name, name: match[1], note: (match[2] ?? "").trim() })
      else problems.push({ n: line.n, message: `"${line.text.trim().replace(/^[-*]\s+/, "")}" isn't a spec name — write one word like AlbumDetail, optionally followed by ": a line about it"` })
    }
  }
  return { entries, problems }
}

// Scan a set of sections line by line with a global regex.
const scan = (spec, sectionNames, regex) => {
  const hits = []
  for (const name of sectionNames) {
    for (const line of spec.sections[name]?.lines ?? []) {
      const text = line.text.replace(/`[^`]*`/g, (m) => " ".repeat(m.length))
      for (const match of text.matchAll(regex)) hits.push({ n: line.n, match })
    }
  }
  return hits
}
const protectedSections = (spec) => Object.keys(spec.sections).filter((s) => !UNPROTECTED_SECTIONS.includes(s))

const refsOf = (spec) =>
  scan(spec, ["layout", "states"], /\[\[(~?)([A-Za-z]\w*)((?:\s+[\w-]+=[^\]\s]+)*)\s*\]\]/g).map(({ n, match }) => ({
    n,
    local: match[1] === "~",
    name: match[2],
    variant: /variant=([^\s\]]+)/.exec(match[3] ?? "")?.[1],
  }))

// [[screen:Name]], [[flow:Name]], [[model:Name]], [[model:Name#field]], [[api:Name]], [[api:Name#error_code]], [[policy:Name]]
const typedRefsOf = (spec) =>
  scan(spec, protectedSections(spec), /\[\[(screen|flow|model|api|policy):([A-Za-z]\w*)(?:#([\w.-]+))?\]\]/g).map(({ n, match }) => ({
    n,
    kind: match[1],
    name: match[2],
    member: match[3],
  }))

// What a #member can name: a model's fields, or an API's error codes.
const membersOf = (spec) =>
  spec.kind === "model" ? tableKeys(spec.sections.fields).map((k) => k.key) : spec.kind === "api" ? tableKeys(spec.sections.errors).map((k) => k.key) : []

const isDeprecated = (spec) => spec.fm.status === "deprecated"
const replacementsOf = (spec) => asList(spec.fm.replaced_by)

// Follow replaced_by through specs that were deprecated in turn, to the live specs at the end of each chain
// (A → B → C gives C). A chain that ends at a spec with no replacement adds nothing: that behaviour is going
// away. A name with no spec, or a chain that comes back on itself, is broken.
const resolveReplacements = (spec, byName, trail = [spec.name]) => {
  const live = []
  const broken = []
  for (const name of replacementsOf(spec)) {
    const target = byName.get(name)
    if (trail.includes(name)) broken.push(`${[...trail, name].join(" → ")} goes round in a loop`)
    else if (!target) broken.push(`${name} has no spec`)
    else if (!isDeprecated(target)) live.push(name)
    else {
      const next = resolveReplacements(target, byName, [...trail, name])
      live.push(...next.live)
      broken.push(...next.broken)
    }
  }
  return { live: [...new Set(live)], broken: [...new Set(broken)] }
}

// "deprecated on 2026-10-24; use NewThing instead", for messages that point Claude away from a deprecated spec.
// It names the live end of the replacement chain, not the next step, which may itself be deprecated.
const deprecationNote = (spec, byName) => {
  const { live } = resolveReplacements(spec, byName)
  const what = live.length ? `; use ${live.join(", ")} instead` : replacementsOf(spec).length ? `; nothing live replaces it` : ""
  return `deprecated on ${spec.fm.deprecated || "?"}${what}`
}
const byNameOf = (all) => new Map(all.map((s) => [s.name, s]))

// A real calendar date as YYYY-MM-DD. Date.parse alone rolls 2026-02-30 over into March, so round-trip it.
const isDate = (text) => /^\d{4}-\d{2}-\d{2}$/.test(text) && !Number.isNaN(Date.parse(text)) && new Date(text).toISOString().slice(0, 10) === text

const dateProblems = (fm) => (isDate(fm.deprecated ?? "") ? [] : [`"deprecated" must be the date it was deprecated, as YYYY-MM-DD (got "${fm.deprecated ?? ""}")`])

// What's wrong with a deprecated spec's replacements. Each must be a spec of the same kind, other than itself and
// past draft (a draft can be deleted, leaving the frozen spec pointing at nothing). Lint checks these on every
// deprecated spec, including one deprecated by hand, since each can be put right without editing the frozen
// spec (approve the draft) or never comes right at all. At the moment of deprecating, the hook also wants each
// replacement to exist and be live. Afterwards a replacement may be deprecated in turn, which just makes the chain
// longer, or be deleted, which lint can only warn about (see resolveReplacements).
const replacementProblems = (fm, name, kind, byName, { deprecating = false } = {}) => {
  const problems = []
  for (const replacement of replacementsOf({ fm })) {
    const target = byName.get(replacement)
    if (replacement === name) problems.push(`it can't be replaced by itself`)
    else if (!target) deprecating && problems.push(`replaced_by names ${replacement}, which has no spec`)
    else if (target.kind !== kind) problems.push(`replaced_by names ${replacement}, which is a ${target.kind} spec; it must be another ${kind} spec`)
    else if (isDeprecated(target)) deprecating && problems.push(`replaced_by names ${replacement}, which is itself ${deprecationNote(target, byName)}`)
    else if ((target.fm.status ?? "draft") === "draft") problems.push(`replaced_by names ${replacement}, which is still a draft; approve it first, or leave replaced_by out and say what's coming under Decisions`)
  }
  return problems
}

// A rule is "- R1: ..." or "- AlbumDetail.R1: ..."; either way its full ID is AlbumDetail.R1.
const rulesOf = (spec) =>
  (spec.sections.rules?.lines ?? [])
    .filter((l) => /^[-*]\s+/.test(l.text))
    .map((l) => {
      const match = /^[-*]\s+\**(?:([A-Za-z]\w*)\.)?R(\d+)\**\s*:/.exec(l.text)
      return { n: l.n, text: l.text, prefix: match?.[1], id: match ? `${spec.name}.R${match[2]}` : null, short: match ? `R${match[2]}` : null }
    })

const stepsOf = (spec) =>
  (spec.sections.steps?.lines ?? []).filter((l) => /^\d+\.\s/.test(l.text)).map((l) => ({ n: l.n, num: Number(/^\d+/.exec(l.text)[0]) }))

const variantsOf = (spec) =>
  (spec.sections.variants?.lines ?? [])
    .map((l) => /^[-*]\s+[*`]*([\w-]+)[*`]*\s*(?::|—|–|\s-\s)/.exec(l.text)?.[1])
    .filter(Boolean)

const amendmentsOf = (spec) => (stripNoise(spec.raw).match(/^## Open amendments\s*\n([\s\S]*?)(?=^## |$(?![\s\S]))/m)?.[1].match(/^### /gm) ?? []).length

// Open amendments as { id, title, change }, from "### A1: title" blocks and their "- Change:" line.
const openAmendments = (text) =>
  (stripNoise(normalize(text)).match(/^## Open amendments\s*\n([\s\S]*?)(?=^## |$(?![\s\S]))/m)?.[1] ?? "")
    .split(/^(?=### )/m)
    .map((block) => {
      const head = /^### (A\d+)\s*:?\s*(.*)$/m.exec(block)
      return head && { id: head[1], title: head[2].trim(), change: /^[-*]\s*Change:\s*(.*)$/m.exec(block)?.[1].trim() }
    })
    .filter(Boolean)

// ---------- fingerprint & reports ----------

// Each section's text by its lowercase name, trimmed so whitespace-only edits don't count as changes. Anything
// between the frontmatter and the first heading (a title, an intro) is a part of its own.
const INTRO = "intro (before the first heading)"
const sectionTexts = (text) => {
  const normal = normalize(text)
  const clean = (lines) => lines.map((l) => l.trimEnd()).join("\n").trim()
  const texts = {}
  const intro = clean(normal.replace(/^---\n[\s\S]*?\n---\n/, "").split(/^## /m)[0].split("\n"))
  if (intro) texts[INTRO.toLowerCase()] = { name: INTRO, text: intro }
  for (const [key, section] of Object.entries(parseSections(normal))) texts[key] = { name: section.name, text: clean(section.lines.map((l) => l.text)) }
  return texts
}

// Everything a non-draft spec protects: frontmatter plus every section except the unprotected ones.
const protectedParts = (text, texts = sectionTexts(text)) => {
  const parts = { frontmatter: JSON.stringify(parseFrontmatter(normalize(text)).data ?? {}) }
  for (const [key, { name, text: body }] of Object.entries(texts)) if (!UNPROTECTED_SECTIONS.includes(key)) parts[name] = body
  return parts
}

// The policies a spec relies on, following references all the way down: a screen that references policy A,
// where A references policy B, relies on both. Each comes with the trail that reaches it (["A", "B"]). They're
// looked up among the specs already loaded, by exact name, so this always agrees with lint about what exists.
const reliesOn = (spec, byName) => {
  const found = new Map()
  const walk = (from, trail) => {
    for (const ref of typedRefsOf(from)) {
      const target = byName.get(ref.name)
      if (!KINDS[ref.kind].fingerprinted || target?.kind !== ref.kind || target.name === spec.name || found.has(target.name)) continue
      found.set(target.name, { spec: target, trail: [...trail, target.name] })
      walk(target, [...trail, target.name])
    }
  }
  walk(spec, [])
  return [...found.values()].sort((a, b) => a.spec.name.localeCompare(b.spec.name))
}
// "CanBuyAlbum", or "AlbumPricing (through CanBuyAlbum)" for one reached through another.
const trailNote = ({ spec, trail }) => (trail.length > 1 ? `${spec.name} (through ${trail.slice(0, -1).join(" → ")})` : spec.name)

// Fingerprint of what a spec asks for. Status, source and the deprecation fields are lifecycle, not intent, so
// they're left out: marking a spec verified, or deprecating a policy it uses, doesn't make its report stale, but
// changing a rule does. The decision of every policy it relies on (see KINDS) is part of what it asks for too.
// A policy's decision, as it counts toward the fingerprints of specs that rely on it. Worked out once per loaded
// spec, since a snapshot fingerprints every spec and many can rely on the same policy.
const decisions = new WeakMap()
const decisionOf = (policy) => {
  if (!decisions.has(policy)) {
    const texts = sectionTexts(policy.raw)
    decisions.set(policy, JSON.stringify(KINDS[policy.kind].fingerprinted.map((key) => texts[key]?.text ?? "")))
  }
  return decisions.get(policy)
}
const hashOf = (spec, byName) => {
  const { status, source, deprecated, replaced_by, ...intent } = spec.fm
  const parts = { ...protectedParts(spec.raw), frontmatter: JSON.stringify(intent) }
  for (const { spec: policy } of reliesOn(spec, byName)) parts[`[[${policy.kind}:${policy.name}]]`] = decisionOf(policy)
  return createHash("sha256").update(JSON.stringify(parts)).digest("hex").slice(0, 12)
}

// Who points at each spec that has a Used by: the components a spec lays out (or lists in "uses"), and its typed
// references. Only live specs count. Lint builds Used by from this, and the hooks use it to say who a change reaches.
const usersOfAll = (live, byName) => {
  const users = new Map()
  const add = (name, spec) => {
    if (!(users.get(name) ?? []).includes(spec)) users.set(name, [...(users.get(name) ?? []), spec])
  }
  for (const spec of live) {
    const shared = refsOf(spec).filter((r) => !r.local).map((r) => r.name)
    for (const name of spec.fm.uses === undefined ? shared : asList(spec.fm.uses)) add(name, spec)
    for (const ref of typedRefsOf(spec)) {
      const target = byName.get(ref.name)
      if (target?.kind === ref.kind && target !== spec && KINDS[target.kind].usedBy) add(target.name, spec)
    }
  }
  return users
}

// The shared components a spec is built from: those it lays out (or lists in "uses"), and those they're built from
// in turn. They aren't part of its fingerprint: most component changes (a new variant) don't touch most of the
// specs that use it, and sending every one back to be re-verified would teach people to wave it through. Instead
// its report records each one's fingerprint, and lint asks for an audit when one has changed since (see checkReport).
// It follows the same links as --refs (see linksOf), keeping only those to components.
const componentsOf = (spec, byName) => {
  const found = new Map()
  const walk = (from) => {
    for (const { target } of linksOf(from, byName)) {
      if (target.kind !== "component" || target.name === spec.name || found.has(target.name)) continue
      found.set(target.name, target)
      walk(target)
    }
  }
  walk(spec)
  return [...found.values()].sort((a, b) => a.name.localeCompare(b.name))
}
// Whether changing `component` will flag `spec` for an audit: it's verified, built from the component, and its report
// records the component's fingerprint. A report from before components were recorded, or no report, isn't audited.
const flagsForAudit = (spec, component, byName) => {
  if (statusOf(spec) !== "verified" || !componentsOf(spec, byName).includes(component)) return false
  const { hasStamps, unstamped } = checkReport(spec, byName)
  return hasStamps && !unstamped.includes(component.name)
}
// The verified specs whose reports recorded an older `component` than there is now: the ones lint asks to audit.
const behindOn = (component, specs, byName) =>
  specs.live.filter((s) => statusOf(s) === "verified" && checkReport(s, byName).audit.includes(component.name)).map((s) => s.name)
// The report's "Components:" line: "ArtistBadge 1a2b3c4d5e6f, PrimaryButton 9f8e7d6c5b4a", or "none".
const componentStamps = (spec, byName) => componentsOf(spec, byName).map((c) => `${c.name} ${hashOf(c, byName)}`).join(", ") || "none"

// A report passes when it's stamped with the spec's current fingerprint, has a ✅ or 👤 row for every rule,
// and no row anywhere is ❌ or ⚠️. 👤 means "only a human can check this": it's left for the taste test.
// It also says which components have changed since it was written (`audit`) and which it doesn't record
// (`unstamped`). Neither fails the report: lint warns about the first, and the hook wants both cleared before
// a spec is marked verified. A report from before components were recorded has no line, so it's never audited.
const checkReport = (spec, byName) => {
  const file = path.join(specsDir, "_reports", `${spec.name}.md`)
  if (!existsSync(file)) return { file, problems: [`there's no report at ${rel(file)}; run /spec-verify ${spec.name}`], passed: 0, total: 0, taste: [], audit: [], unstamped: [], hasStamps: false }
  const lines = normalize(readFileSync(file, "utf8")).split("\n")
  const problems = []
  const hash = hashOf(spec, byName)
  const stamp = lines.map((l) => /\bSpec:\s*`?([0-9a-f]{12})\b/.exec(l)?.[1]).find(Boolean)
  if (!stamp) problems.push(`${rel(file)} has no "Spec: <hash>" line`)
  else if (stamp !== hash) {
    const policies = reliesOn(spec, byName).map(trailNote)
    const what = policies.length ? `the spec or a policy it relies on (${policies.join(", ")})` : "the spec"
    problems.push(`${rel(file)} was written for an older version of ${what} (Spec: ${stamp}, now ${hash}); set status: implemented and re-run /spec-verify ${spec.name}`)
  }
  const rows = lines.filter((l) => isTableRow(l) && !isSeparator(l)).map(cellsOf)
  for (const row of rows) if (/❌|⚠/.test(row[1] ?? "")) problems.push(`${rel(file)} marks ${row[0]} as ${row[1]}`)
  const rules = rulesOf(spec).filter((r) => r.id)
  const rowFor = (rule, mark) => rows.some((r) => [rule.id, rule.short].includes(r[0].replace(/`/g, "")) && (r[1] ?? "").includes(mark))
  const passed = rules.filter((rule) => rowFor(rule, "✅"))
  for (const rule of rules) if (!passed.includes(rule) && !rowFor(rule, "👤")) problems.push(`${rel(file)} has no ✅ or 👤 row for ${rule.id}`)
  const taste = rows.filter((r) => (r[1] ?? "").includes("👤")).map((r) => r[0].replace(/`/g, ""))
  const stampLine = lines.find((l) => /^\s*Components:/.test(l))
  const recorded = new Map([...(stampLine ?? "").matchAll(/([A-Za-z]\w*)\s+`?([0-9a-f]{12})\b/g)].map((m) => [m[1], m[2]]))
  const components = componentsOf(spec, byName)
  const audit = components.filter((c) => recorded.has(c.name) && recorded.get(c.name) !== hashOf(c, byName)).map((c) => c.name)
  const unstamped = components.filter((c) => !recorded.has(c.name)).map((c) => c.name)
  return { file, problems, passed: passed.length, total: rules.length, taste, audit, unstamped, hasStamps: stampLine !== undefined }
}

// ---------- linting ----------

const lint = ({ all, live, tokens, outline }) => {
  const problems = []
  const report = (level, spec, n, message) => problems.push({ level, file: rel(spec.file), n, message })
  const byName = new Map()
  for (const spec of all) {
    const other = byName.get(spec.name)
    if (other) report("error", spec, 1, `the name ${spec.name} is already taken by ${rel(other.file)}; names must be unique across specs/ so rule IDs and reports don't collide`)
    else byName.set(spec.name, spec)
  }
  const componentNames = new Map(all.filter((s) => s.kind === "component").map((c) => [c.name, c]))
  const tokenNames = new Set(tokens ? Object.values(tokens.sections).flatMap(tableKeys).map((t) => t.key) : [])
  const usersOf = usersOfAll(live, byName)
  const localOwners = new Map()
  const endpoints = new Map()

  for (const spec of all) {
    const { fm, kind } = spec
    if (!spec.hasFrontmatter) report("error", spec, 1, "missing frontmatter (--- ... ---)")
    if (fm[kind] !== spec.name) report("error", spec, 1, `frontmatter "${kind}: ${fm[kind] ?? ""}" must match the filename "${spec.name}"`)
    // An unfinished draft gets warnings, not errors, for missing content.
    const incomplete = fm.status === "draft" ? "warning" : "error"
    if (!STATUSES.includes(fm.status)) report("error", spec, 1, `status must be one of ${STATUSES.join(" | ")} (got "${fm.status ?? ""}")`)
    // A deprecated spec is a frozen record: only its deprecation is checked, and it no longer counts as using
    // anything or claiming an endpoint. A bad date is its own error. A replacement deprecated in turn is fine (the
    // chain is followed); one that's gone is only a warning, since fixing it would mean editing the frozen spec.
    if (isDeprecated(spec)) {
      for (const problem of [...dateProblems(fm), ...replacementProblems(fm, spec.name, kind, byName)]) report("error", spec, 1, `status is deprecated but ${problem}`)
      for (const problem of resolveReplacements(spec, byName).broken) report("warning", spec, 1, `deprecated, but its chain of replacements is broken: ${problem}`)
      continue
    }
    for (const key of DEPRECATION_KEYS) if (fm[key] !== undefined) report("error", spec, 1, `"${key}" belongs only on a deprecated spec (status is ${fm.status ?? "missing"}); if it's been brought back, remove it`)
    for (const section of KINDS[kind].required) {
      const found = spec.sections[section.toLowerCase()]
      if (!found) report(incomplete, spec, 1, `missing required section "## ${section}"`)
      else if (!found.lines.some((l) => l.text.trim())) report(incomplete, spec, found.line, `section "## ${section}" is empty`)
    }

    // Rules: every top-level bullet needs a unique ID; a prefix, if given, must be the spec's own name.
    const rules = rulesOf(spec)
    const seen = new Set()
    for (const rule of rules) {
      if (!rule.id) report("error", spec, rule.n, `rule has no ID — write it as "- R<n>: ..."`)
      else if (rule.prefix && rule.prefix !== spec.name) report("error", spec, rule.n, `rule ${rule.prefix}.${rule.short} belongs to another spec — write it as "- ${rule.short}: ..."`)
      else if (seen.has(rule.short)) report("error", spec, rule.n, `duplicate rule ID ${rule.id}`)
      seen.add(rule.short)
    }
    if (KINDS[kind].required.includes("Rules") && spec.sections.rules && rules.length === 0) report(incomplete, spec, spec.sections.rules.line, "Rules needs at least one rule")
    for (const { n, match } of scan(spec, ["layout", "states", "steps"], /(?:→|->)\s*(R\d+(?:\s*,\s*R\d+)*)/g)) {
      for (const short of match[1].split(/\s*,\s*/)) {
        if (!seen.has(short)) report("error", spec, n, `links to ${spec.name}.${short}, which isn't in Rules`)
      }
    }

    // Flow steps: numbered, and every "→ step N" lands on one.
    if (kind === "flow") {
      const steps = stepsOf(spec)
      const nums = new Set()
      for (const step of steps) {
        if (nums.has(step.num)) report("error", spec, step.n, `duplicate step ${step.num}`)
        nums.add(step.num)
      }
      if (spec.sections.steps && steps.length === 0) report(incomplete, spec, spec.sections.steps.line, `Steps needs at least one numbered step ("1. [[screen:Name]]")`)
      for (const { n, match } of scan(spec, ["steps"], /(?:→|->)\s*step\s+(\d+)/gi)) {
        if (!nums.has(Number(match[1]))) report("error", spec, n, `goes to step ${match[1]}, which doesn't exist`)
      }
    }

    // APIs: an endpoint, and no two specs claiming the same one.
    if (kind === "api") {
      const endpoint = (fm.endpoint ?? "").replace(/\s+/g, " ").trim()
      if (!endpoint) report(incomplete, spec, 1, `missing "endpoint" in frontmatter (e.g. endpoint: GET /albums/{id})`)
      else if (endpoints.has(endpoint)) report("error", spec, 1, `endpoint "${endpoint}" is also specced by ${endpoints.get(endpoint).name}`)
      else endpoints.set(endpoint, spec)
    }

    // Component refs vs uses/local.
    const refs = refsOf(spec)
    const shared = new Set(refs.filter((r) => !r.local).map((r) => r.name))
    const local = new Set(refs.filter((r) => r.local).map((r) => r.name))
    // "uses" and "local" are optional: left out, the layout is the list. Written out, they must match it.
    const uses = new Set(fm.uses === undefined ? shared : asList(fm.uses))
    const declaredLocal = new Set(fm.local === undefined ? local : asList(fm.local))
    for (const ref of refs) {
      if (ref.local) {
        const namesake = componentNames.get(ref.name)
        // A deprecated component's name stays taken, but pointing at it would mean building on it.
        if (namesake && isDeprecated(namesake)) report("error", spec, ref.n, `[[~${ref.name}]] has the name of a shared component that's ${deprecationNote(namesake, byName)} — give the one-off another name`)
        else if (namesake) report("error", spec, ref.n, `[[~${ref.name}]] is marked one-off but a shared spec exists — use [[${ref.name}]] or rename the one-off`)
        if (shared.has(ref.name)) report("error", spec, ref.n, `${ref.name} is used both as shared and as a one-off`)
        continue
      }
      if (ref.name === spec.name) report("error", spec, ref.n, `${ref.name} references itself`)
      const target = componentNames.get(ref.name)
      if (!target) report("error", spec, ref.n, `[[${ref.name}]] has no spec — create specs/components/${ref.name}.md, or mark it one-off as [[~${ref.name}]]`)
      if (!target) continue
      if (isDeprecated(target)) report("warning", spec, ref.n, `[[${ref.name}]] is ${deprecationNote(target, byName)}`)
      if (ref.variant && ref.variant !== "default" && !variantsOf(target).includes(ref.variant)) {
        report("error", spec, ref.n, `${ref.name} has no variant "${ref.variant}" (known: ${variantsOf(target).join(", ") || "none"})`)
      }
    }
    for (const name of shared) if (!uses.has(name)) report("error", spec, 1, `[[${name}]] is in the layout but not in "uses"`)
    for (const name of uses) if (!shared.has(name)) report("error", spec, 1, `"uses" lists ${name} but the layout never references [[${name}]]`)
    for (const name of local) if (!declaredLocal.has(name)) report("error", spec, 1, `[[~${name}]] is in the layout but not in "local"`)
    for (const name of declaredLocal) if (!local.has(name)) report("error", spec, 1, `"local" lists ${name} but the layout never references [[~${name}]]`)
    for (const name of local) localOwners.set(name, [...(localOwners.get(name) ?? []), spec])

    // Typed refs to screens, flows, models, APIs and policies.
    for (const ref of typedRefsOf(spec)) {
      const label = `[[${ref.kind}:${ref.name}${ref.member ? `#${ref.member}` : ""}]]`
      const target = byName.get(ref.name)
      if (!target || target.kind !== ref.kind) {
        report("error", spec, ref.n, `${label} has no spec — create specs/${KINDS[ref.kind].dir}/${ref.name}.md`)
        continue
      }
      if (isDeprecated(target)) report("warning", spec, ref.n, `${label} points at ${target.name}, which is ${deprecationNote(target, byName)}`)
      if (!ref.member) continue
      if (!["model", "api"].includes(target.kind)) report("error", spec, ref.n, `${label}: only models (#field) and APIs (#error_code) have members`)
      else if (!membersOf(target).includes(ref.member)) {
        const what = target.kind === "model" ? "field" : "error code"
        report("error", spec, ref.n, `${target.name} has no ${what} "${ref.member}" (known: ${membersOf(target).join(", ") || "none"})`)
      }
    }

    // A draft can change without anyone being asked, which would quietly change what this spec asks for. That
    // holds for a policy reached through another one too.
    if (statusOf(spec) !== "draft") {
      for (const relied of reliesOn(spec, byName).filter((r) => statusOf(r.spec) === "draft")) {
        const level = ["implemented", "verified"].includes(statusOf(spec)) ? "error" : "warning"
        const n = typedRefsOf(spec).find((ref) => ref.name === relied.trail[0])?.n ?? 1
        report(level, spec, n, `[[policy:${relied.spec.name}]]${relied.trail.length > 1 ? ` (through ${relied.trail.slice(0, -1).join(" → ")})` : ""} is still a draft, and its rules are part of what ${spec.name} asks for — approve ${relied.spec.name} before building on it`)
      }
    }

    // Table keys must be unique: model fields, API error codes, copy keys, and any a kind adds (policy inputs).
    for (const section of ["fields", "errors", "copy", ...(KINDS[kind].keyed ?? [])]) {
      const keys = new Set()
      for (const row of tableKeys(spec.sections[section])) {
        if (keys.has(row.key)) report("error", spec, row.n, `duplicate key "${row.key}" in ${spec.sections[section].name}`)
        keys.add(row.key)
      }
    }

    // The States table (see TABLES).
    const migrate = `/spec-migrate ${spec.name} converts it`
    if (kind === "component" && spec.sections["props / states"]) {
      report("warning", spec, spec.sections["props / states"].line, `"## Props / States" is the old format: put its states in a ## States table and its guidelines in ## Rules, and leave props to the code (${migrate})`)
    }
    for (const key of Object.keys(TABLES[kind] ?? {})) {
      const format = formatOf(spec, key)
      if (!format) continue
      const { section, columns, headers, current } = format
      const layout = `| ${columns.join(" | ")} |`
      const loose = section.lines.filter((l) => l.text.trim() && !isTableRow(l.text))
      if (!headers.length) {
        if (loose.length) report("warning", spec, section.line, `${section.name} is a list: write it as a table, ${layout} (${migrate})`)
        continue
      }
      if (!current) {
        const got = headers.find((h) => h.cells.join("|") !== columns.join("|"))
        report("warning", spec, got.n, `${section.name}'s table isn't in the current format, ${layout} (got | ${got.cells.join(" | ")} |), so its rows aren't checked (${migrate})`)
        continue
      }
      for (const l of loose) report("warning", spec, l.n, `${section.name} has a line outside its table; if it's a guideline, make it a rule in ## Rules`)
      const names = new Set()
      for (const row of tableKeys(section)) {
        if (names.has(row.key)) report("error", spec, row.n, `duplicate key "${row.key}" in ${section.name}`)
        names.add(row.key)
      }
    }
    if (formatOf(spec, "states")?.current) {
      for (const { n, cells } of tableRows(spec.sections.states)) {
        // More cells than columns almost always means a | in a cell; say so rather than read the row a column off.
        if (cells.length > STATES_COLUMNS.length) {
          report("error", spec, n, `state ${cells[0]} has ${cells.length} cells for ${STATES_COLUMNS.length} columns; write a | inside a cell as \\|`)
          continue
        }
        const [name = "", when = "", looks = ""] = cells
        if (!/^[a-z][a-z0-9-]*$/.test(name)) report("error", spec, n, `state "${name}" should be a plain lowercase name, like loading or not-found`)
        if (/`/.test(when)) report("warning", spec, n, `state ${name}'s "when" is written as code; say what's happening in plain words, like "while a purchase is in flight"`)
        if (RULE_WORDS.test(looks)) report("warning", spec, n, `state ${name}'s "looks like" reads like a rule; put it in ## Rules so it gets an ID and a test`)
      }
    }

    // Copy keys.
    const copyRows = tableKeys(spec.sections.copy)
    const copyKeys = new Set(copyRows.map((r) => r.key))
    const usedKeys = new Set()
    for (const { n, match } of scan(spec, ["layout", "states", "rules", "steps"], /\{copy\.([\w.-]+)\}/g)) {
      usedKeys.add(match[1])
      if (!copyKeys.has(match[1])) report("error", spec, n, `{copy.${match[1]}} isn't in the Copy table`)
    }
    for (const row of copyRows) if (!usedKeys.has(row.key)) report("warning", spec, row.n, `copy key "${row.key}" is never placed in Layout/States/Rules`)

    // Style: tokens, not raw values.
    for (const { n, match } of scan(spec, ["layout", "states", "style", "variants", "props / states"], /\$([a-z][\w-]*(?:\.[\w-]+)+)/gi)) {
      if (!tokens) report("error", spec, n, `$${match[1]} used but specs/tokens.md doesn't exist`)
      else if (!tokenNames.has(match[1])) report("error", spec, n, `unknown token $${match[1]}`)
    }
    for (const { n, match } of scan(spec, ["style"], /#[0-9a-f]{3,8}\b|\b\d+px\b/gi)) {
      report("warning", spec, n, `raw value "${match[0]}" in Style — use a token from specs/tokens.md`)
    }

    // Source files: must exist, and should import what the spec says it uses.
    const sources = asList(fm.source)
    if (["implemented", "verified"].includes(fm.status) && sources.length === 0) report("warning", spec, 1, `status is ${fm.status} but no "source" is listed`)
    const sourceText = sources
      .map((s) => {
        const file = path.join(root, s)
        if (!existsSync(file)) report("error", spec, 1, `source "${s}" doesn't exist`)
        return existsSync(file) ? readFileSync(file, "utf8") : ""
      })
      .join("\n")
    if (sourceText) {
      // An import clause can't contain quotes, so this can't run past the end of one import statement.
      const clauses = [...sourceText.matchAll(/import\s+([^'"]*?)\s+from\s*['"]/g)].map((m) => m[1])
      const imports = (name) => clauses.some((c) => new RegExp(`\\b${name}\\b`).test(c))
      const built = ["implemented", "verified"].includes(fm.status)
      for (const name of uses) if (!imports(name)) report(built ? "error" : "warning", spec, 1, `uses ${name} but its source never imports it`)
      for (const [name, component] of componentNames) {
        if (name === spec.name || uses.has(name) || !imports(name)) continue
        // Code lags behind its specs: a deprecated component may still be imported, but the fix is to move off it.
        if (isDeprecated(component)) report("warning", spec, 1, `source imports ${name}, which is ${deprecationNote(component, byName)}`)
        else report("warning", spec, 1, `source imports shared component ${name}, which isn't in "uses"`)
      }
    }

    // Verified means a passing report for exactly this version of the spec.
    if (fm.status === "verified") {
      const { problems: failures, audit } = checkReport(spec, byName)
      for (const problem of failures) report("error", spec, 1, `status is verified but ${problem}`)
      if (audit.length) {
        report(
          "warning",
          spec,
          1,
          `verified against an older ${audit.join(", ")} than there is now; audit whether the change affects ${spec.name}, then re-run /spec-verify ${spec.name} to record it`,
        )
      }
    }
  }

  // The outline: well-formed, no duplicates, and each entry matches the kind of spec it became.
  if (outline) {
    const note = (level, n, message) => problems.push({ level, file: rel(outlineFile), n, message })
    for (const p of outline.problems) note("error", p.n, p.message)
    const listed = new Set()
    for (const entry of outline.entries) {
      if (listed.has(entry.name)) note("error", entry.n, `${entry.name} is listed more than once`)
      listed.add(entry.name)
      const spec = byName.get(entry.name)
      if (!spec) note("warning", entry.n, `${entry.name} has no spec yet — run: node scripts/spec-lint.mjs --scaffold`)
      else if (isDeprecated(spec)) note("error", entry.n, `${entry.name} is ${deprecationNote(spec, byName)} — take it off the outline, which lists only what's current`)
      else if (spec.kind !== entry.kind) note("error", entry.n, `${entry.name} is listed under ## ${entry.heading} but ${rel(spec.file)} is a ${spec.kind} spec`)
    }
  }

  // Used by must match what's generated.
  for (const spec of live.filter((s) => KINDS[s.kind].usedBy)) {
    const expected = usedByLines(spec, usersOf)
    const actual = (spec.sections["used by"]?.lines ?? []).map((l) => l.text.trim()).filter((t) => t.startsWith("-"))
    if (expected.join("\n") !== actual.join("\n")) report("error", spec, spec.sections["used by"]?.line ?? 1, `"Used by" is stale — run: node scripts/spec-lint.mjs --fix`)
    if (spec.kind === "component" && !usersOf.has(spec.name)) report("warning", spec, 1, `shared component isn't used by any spec yet`)
  }
  for (const [name, owners] of localOwners) {
    if (owners.length > 1) {
      for (const owner of owners) report("warning", owner, 1, `one-off [[~${name}]] also appears in ${owners.filter((o) => o !== owner).map((o) => o.name).join(", ")} — should it be shared?`)
    }
  }
  return { problems, usersOf, localOwners }
}

const usedByLines = (spec, usersOf) => {
  const users = (usersOf.get(spec.name) ?? []).map((s) => `- ${s.name} (${s.kind})`).sort()
  return users.length ? users : ["- _(none yet)_"]
}

const fixUsedBy = (specs) => {
  const { usersOf } = lint(specs)
  const changed = []
  for (const spec of specs.live.filter((s) => KINDS[s.kind].usedBy)) {
    const block = `## Used by\n${USED_BY_MARK}\n${usedByLines(spec, usersOf).join("\n")}\n`
    const existing = /^## Used by\s*\n[\s\S]*?(?=^## |$(?![\s\S]))/m
    let next
    if (existing.test(spec.raw)) next = spec.raw.replace(existing, `${block}\n`)
    else if (/^## Open amendments/m.test(spec.raw)) next = spec.raw.replace(/^## Open amendments/m, `${block}\n## Open amendments`)
    else next = `${spec.raw.trimEnd()}\n\n${block}`
    next = `${next.trimEnd()}\n`
    if (next !== spec.raw) {
      writeFileSync(spec.file, next)
      changed.push(rel(spec.file))
    }
  }
  return changed
}

const format = (problems) =>
  problems.map((p) => `${p.file}:${p.n}  ${p.level === "error" ? "error  " : "warning"}  ${p.message}`).join("\n")

// ---------- reverse lookup ----------

// Every link a spec makes to another: { from, target, member, where }. `where` is the section it's in, or for a
// flow the step ("step 2"), or "uses" for a component that's listed in the frontmatter but not laid out.
const SHARED_REF = /\[\[([A-Za-z]\w*)((?:\s+[\w-]+=[^\]\s]+)*)\s*\]\]/g
const TYPED_REF = /\[\[(screen|flow|model|api|policy):([A-Za-z]\w*)(?:#([\w.-]+))?\]\]/g
const linksOf = (spec, byName) => {
  const links = []
  const add = (name, kind, member, where) => {
    const target = byName.get(name)
    if (target && target !== spec && target.kind === kind) links.push({ from: spec, target, member, where })
  }
  for (const key of protectedSections(spec)) {
    let step = null
    for (const line of spec.sections[key].lines) {
      if (key === "steps" && /^\d+\.\s/.test(line.text)) step = /^\d+/.exec(line.text)[0]
      const where = step ? `step ${step}` : key
      const text = line.text.replace(/`[^`]*`/g, (m) => " ".repeat(m.length))
      // [[Name]] is a component only in a layout or a state (see refsOf); [[kind:Name]] counts anywhere.
      if (["layout", "states"].includes(key)) for (const m of text.matchAll(SHARED_REF)) add(m[1], "component", undefined, where)
      for (const m of text.matchAll(TYPED_REF)) add(m[2], m[1], m[3], where)
    }
  }
  for (const name of asList(spec.fm.uses)) if (!links.some((l) => l.target.name === name)) add(name, "component", undefined, "uses")
  return links
}

// The live specs that rely on `target`: those that link to it, then those that link to them, and so on, each
// listed once at the shortest distance, as { spec, parent, where }. With a member (a model field or API error code),
// the first step counts links to that member and links to the whole target, which take in every member (an API
// that returns [[model:Album]] returns its price too), but not links to its other members. Those whole-target
// links are marked in `where`. Deprecated specs are frozen, so they're returned apart.
const reliedOnBy = (target, specs, member) => {
  const byName = byNameOf(specs.all)
  const links = specs.live.flatMap((s) => linksOf(s, byName))
  const reaches = (l) => !member || l.member === member || l.member === undefined
  const whereOf = (l) => (member && l.target === target && l.member === undefined ? `${l.where} (all of ${target.name})` : l.where)
  const found = []
  const seen = new Set([target])
  let frontier = [target]
  while (frontier.length) {
    const next = []
    for (const node of frontier) {
      const into = links.filter((l) => l.target === node && !seen.has(l.from) && (node !== target || reaches(l)))
      for (const from of [...new Set(into.map((l) => l.from))].sort((a, b) => a.name.localeCompare(b.name))) {
        seen.add(from)
        found.push({ spec: from, parent: node === target ? null : node, where: [...new Set(into.filter((l) => l.from === from).map(whereOf))] })
        next.push(from)
      }
    }
    frontier = next
  }
  const frozen = specs.deprecated.filter((s) => linksOf(s, byName).some((l) => l.target === target && reaches(l)))
  return { found, frozen }
}

// "AlbumDetail (verified), Shelf (implemented, through Card)": for a hook prompt, so the user sees what a change reaches.
// For a component, it also marks the verified specs built from it whose reports record it: the change will flag
// those for an audit (see componentsOf). A report from before components were recorded isn't audited, so isn't marked.
const reachNote = (target, specs, limit = 8) => {
  const { found } = reliedOnBy(target, specs)
  if (!found.length) return ""
  const byName = byNameOf(specs.all)
  const audited = (spec) => target.kind === "component" && flagsForAudit(spec, target, byName)
  const names = found.map(({ spec, parent }) => `${spec.name} (${statusOf(spec)}${parent ? `, through ${parent.name}` : ""}${audited(spec) ? ", will need an audit" : ""})`)
  const shown = names.length > limit ? [...names.slice(0, limit), `and ${names.length - limit} more`] : names
  return ` Relied on by ${shown.join(", ")}; see node scripts/spec-lint.mjs --refs ${target.name}.`
}

const refsReport = (query, specs) => {
  const [name, member] = query.split("#")
  const target = specs.all.find((s) => s.name === name)
  if (!target) return { error: `no spec named "${name ?? ""}"` }
  if (member && !membersOf(target).includes(member)) {
    const what = target.kind === "model" ? "field" : target.kind === "api" ? "error code" : "members"
    return { error: ["model", "api"].includes(target.kind) ? `${name} has no ${what} "${member}" (known: ${membersOf(target).join(", ") || "none"})` : `${name} is a ${target.kind} spec; only models (#field) and APIs (#error_code) have members` }
  }
  const { found, frozen } = reliedOnBy(target, specs, member)
  const label = `${query} (${target.kind}, ${statusOf(target)})`
  const out = []
  if (!found.length) out.push(`Nothing live relies on ${label}.`)
  else {
    out.push(`${label} is relied on by:`)
    const depth = new Map([[target, 0]])
    for (const row of found) depth.set(row.spec, depth.get(row.parent ?? target) + 1)
    const width = Math.max(...found.map((r) => 2 * depth.get(r.spec) + r.spec.name.length))
    const kindWidth = Math.max(...found.map((r) => r.spec.kind.length))
    const statusWidth = Math.max(...found.map((r) => statusOf(r.spec).length))
    // For a component, the verified specs a change to it will flag for an audit (see flagsForAudit).
    const byName = byNameOf(specs.all)
    const audited = (spec) => target.kind === "component" && flagsForAudit(spec, target, byName)
    // Print as a tree: each spec under the one it relies on through.
    const print = (parent) => {
      for (const row of found.filter((r) => (r.parent ?? target) === parent)) {
        const indent = "  ".repeat(depth.get(row.spec))
        out.push(
          `${(indent + row.spec.name).padEnd(width)}  ${row.spec.kind.padEnd(kindWidth)}  ${statusOf(row.spec).padEnd(statusWidth)}  ` +
            `${row.where.join(", ")}${audited(row.spec) ? "  (will need an audit)" : ""}`,
        )
        print(row.spec)
      }
    }
    print(target)
  }
  if (frozen.length) out.push(`Also referenced by deprecated ${frozen.length === 1 ? "spec" : "specs"} ${frozen.map((s) => s.name).join(", ")}, which won't change.`)
  return { text: out.join("\n") }
}

// ---------- summary ----------

const walk = (dir, out = []) => {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".") && entry.name !== ".maestro") continue
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      if (!SKIP_DIRS.has(entry.name)) walk(full, out)
    } else if (TEST_FILE.test(full) && statSync(full).size < 2_000_000) out.push(full)
  }
  return out
}

const summary = (specs) => {
  const { problems, usersOf, localOwners } = lint(specs)
  const tests = walk(root).map((f) => readFileSync(f, "utf8"))
  const { live, deprecated } = specs
  const rows = live.map((spec) => {
    const ids = rulesOf(spec).map((r) => r.id).filter(Boolean)
    const tagged = ids.filter((id) => tests.some((t) => t.includes(`[${id}]`))).length
    const errors = problems.filter((p) => p.file === rel(spec.file) && p.level === "error").length
    return [spec.name, spec.kind, spec.fm.status ?? "?", ids.length ? `${tagged}/${ids.length}` : "-", String(amendmentsOf(spec) || "-"), String(errors || "-")]
  })
  const table = [["spec", "kind", "status", "tagged tests", "amendments", "lint errors"], ...rows]
  const widths = table[0].map((_, i) => Math.max(...table.map((r) => r[i].length)))
  // Deprecated specs are listed below the table, lined up with it, so their names count towards its first column.
  widths[0] = Math.max(widths[0], ...deprecated.map((s) => s.name.length))
  const line = (r) => r.map((c, i) => c.padEnd(widths[i])).join("  ")
  const out = [line(table[0]), widths.map((w) => "-".repeat(w)).join("  "), ...rows.map(line), ""]
  const usedBy = (kind) => live.filter((s) => s.kind === kind).map((s) => `  ${s.name.padEnd(widths[0])}  ← ${(usersOf.get(s.name) ?? []).map((u) => u.name).join(", ") || "(unused)"}`)
  out.push("Shared components:", ...usedBy("component"))
  const contracts = [...usedBy("model"), ...usedBy("api"), ...usedBy("policy")]
  if (contracts.length) out.push("", "Models, APIs & policies:", ...contracts)
  out.push("", "One-offs (deliberately not shared):")
  if (localOwners.size === 0) out.push("  (none)")
  for (const [name, owners] of localOwners) out.push(`  ~${name.padEnd(widths[0] - 1)}  in ${owners.map((s) => s.name).join(", ")}${owners.length > 1 ? "  ⚠ in more than one spec" : ""}`)
  // Deprecated specs, with any tests still tagged with their rules: those are code that hasn't caught up yet.
  if (deprecated.length) out.push("", "Deprecated (frozen):")
  const byName = byNameOf(specs.all)
  for (const spec of deprecated) {
    const tagged = rulesOf(spec).map((r) => r.id).filter((id) => id && tests.some((t) => t.includes(`[${id}]`)))
    const { live: replacements } = resolveReplacements(spec, byName)
    const replaced = replacements.length ? `  → ${replacements.join(", ")}` : replacementsOf(spec).length ? "  → nothing live" : ""
    out.push(`  ${spec.name.padEnd(widths[0])}  ${spec.kind.padEnd(9)}  ${spec.fm.deprecated || "?"}${replaced}${tagged.length ? `  ⚠ tests still tagged: ${tagged.join(", ")}` : ""}`)
  }
  return out.join("\n")
}

// ---------- scaffolding ----------

const PLACEHOLDERS = { screen: "ScreenName", component: "ComponentName", flow: "FlowName", model: "ModelName", api: "ApiName", policy: "PolicyName" }
const HTTP_ENDPOINT = /^((?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s+\S+)\s*(?:(?:—|–|-|:)\s*)?(.*)$/i

// Create a draft spec from its template. `note` is the user's own one-liner from the outline: it becomes
// the Goal or Purpose (for an API, a leading "GET /path" becomes the endpoint). Nothing else is filled in.
const newSpec = (kind, name, note = "") => {
  if (!KINDS[kind]) return { error: `unknown kind "${kind ?? ""}" (expected ${Object.keys(KINDS).join(" | ")})` }
  if (!/^[A-Za-z]\w*$/.test(name ?? "")) return { error: `"${name ?? ""}" isn't a valid spec name — use one word like AlbumDetail` }
  const file = path.join(specsDir, KINDS[kind].dir, `${name}.md`)
  const taken = loadAll().all.find((s) => s.name === name)
  if (taken && isDeprecated(taken)) return { error: `the name ${name} belongs to ${rel(taken.file)}, which is deprecated; a deprecated spec keeps its name for good, so pick a new one` }
  if (taken) return taken.kind === kind ? { kept: file } : { error: `the name ${name} is already taken by ${rel(taken.file)}` }
  const template = path.join(specsDir, "_templates", `${kind}.md`)
  if (!existsSync(template)) return { error: `there's no template at ${rel(template)}` }
  let text = normalize(readFileSync(template, "utf8")).split(PLACEHOLDERS[kind]).join(name)
  let summary = note
  const http = kind === "api" ? HTTP_ENDPOINT.exec(note) : null
  if (http) {
    text = text.replace(/^endpoint:.*$/m, `endpoint: ${http[1].replace(/^\S+/, (method) => method.toUpperCase())}`)
    summary = http[2].trim()
  }
  if (summary) {
    const heading = KINDS[kind].required[0]
    text = text.replace(new RegExp(`^## ${heading}\\n(?:<!--[\\s\\S]*?-->\\n)?`, "m"), () => `## ${heading}\n${summary}\n`)
  }
  mkdirSync(path.dirname(file), { recursive: true })
  writeFileSync(file, text)
  return { created: file }
}

const printResult = (result) => {
  if (result.created) console.log(`  create  ${rel(result.created)}`)
  else if (result.kept) console.log(`  keep    ${rel(result.kept)}`)
  else console.error(`  error   ${result.error}`)
}

const scaffold = () => {
  const outline = parseOutline()
  if (!outline) {
    console.error(`no outline at ${rel(outlineFile)}`)
    return 1
  }
  for (const p of outline.problems) console.error(`  error   ${rel(outlineFile)}:${p.n}  ${p.message}`)
  const results = outline.entries.map((entry) => newSpec(entry.kind, entry.name, entry.note))
  results.forEach(printResult)
  const created = results.filter((r) => r.created).length
  console.log(`${created} spec(s) created, ${results.filter((r) => r.kept).length} already existed`)
  return outline.problems.length || results.some((r) => r.error) ? 1 : 0
}

// ---------- hooks ----------

const readStdin = () => {
  try {
    return JSON.parse(readFileSync(0, "utf8"))
  } catch {
    return {}
  }
}

const decide = (decision, reason) =>
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: decision, permissionDecisionReason: reason } }))

const specKind = (file) => {
  if (!file || !path.resolve(file).startsWith(specsDir + path.sep)) return null
  const relative = path.relative(specsDir, path.resolve(file))
  if (relative === "tokens.md") return "tokens"
  const match = /^([\w-]+)\/[^/]+\.md$/.exec(relative)
  return Object.keys(KINDS).find((kind) => KINDS[kind].dir === match?.[1]) ?? null
}

const applyEdit = (text, input) => {
  const edits = input.edits ?? [input]
  let next = text
  for (const edit of edits) {
    if (edit.old_string == null || !next.includes(edit.old_string)) return null
    next = edit.replace_all ? next.split(edit.old_string).join(edit.new_string) : next.replace(edit.old_string, () => edit.new_string)
  }
  return next
}

const hookPre = () => {
  const { tool_name: tool, tool_input: input = {}, tool_use_id: id } = readStdin()
  const file = input.file_path && path.resolve(input.file_path)
  const kind = specKind(file)
  if (!kind) return
  if (kind !== "tokens") {
    const specs = loadAll()
    beginOwnChange(id ?? `file:${file}`, specs, reachOf(file, kind, specs))
  }
  // A spec that doesn't exist yet counts as an empty draft, so creating one straight into approved still asks.
  const before = existsSync(file) ? readFileSync(file, "utf8") : ""
  const after = tool === "Write" ? input.content : applyEdit(before, input)
  if (after == null) return
  const oldFm = parseFrontmatter(normalize(before)).data ?? {}
  const newFm = parseFrontmatter(normalize(after)).data ?? {}
  const from = oldFm.status ?? "draft"
  const to = newFm.status ?? "draft"
  const name = path.basename(file, ".md")
  // Parse each version's sections once; the checks below all read from these.
  const oldTexts = sectionTexts(before)
  const newTexts = sectionTexts(after)
  const oldParts = protectedParts(before, oldTexts)
  const newParts = protectedParts(after, newTexts)
  const changed = [...new Set([...Object.keys(oldParts), ...Object.keys(newParts)])].filter((k) => oldParts[k] !== newParts[k])
  // The specs on disk, loaded the first time a check below needs them, and only once.
  let loaded
  const specs = () => (loaded ??= { ...loadAll(), byName: byNameOf(loadAll().all) })
  // The live specs that point at this one directly, from the same map lint builds Used by from.
  const pointingAt = () => (KINDS[kind]?.usedBy ? (usersOfAll(specs().live, specs().byName).get(name) ?? []) : [])

  // tokens.md has no lifecycle beyond being protected once it leaves draft.
  if (kind !== "tokens") {
    // A deprecated spec is frozen for good. Only the user can bring one back, by editing it themselves.
    if (from === "deprecated") {
      return decide(
        "deny",
        `${name} is frozen (${deprecationNote({ name, fm: oldFm }, byNameOf(loadAll().all))}): deprecated specs are never edited. ` +
          `If the user wants it back, they change its status themselves; otherwise write a new spec.`,
      )
    }
    // Deprecating is the user's call, like approving. It has to be complete and stand on its own, since the
    // spec is frozen from then on: a date, live replacements of the same kind, a dated line under Decisions saying
    // why (it can't be added later), and nothing else changed.
    if (to === "deprecated") {
      // A draft was never agreed on, so there's nothing to keep a record of.
      if (from === "draft") return decide("deny", `${name} is a draft, so there's nothing to keep a record of: delete it instead of deprecating it (and take it off the outline).`)
      const { all, deprecated } = loadAll()
      const problems = [...dateProblems(newFm), ...replacementProblems(newFm, name, kind, byNameOf(all), { deprecating: true })]
      const strip = (fm) => JSON.stringify(Object.fromEntries(Object.entries(fm).filter(([k]) => !["status", ...DEPRECATION_KEYS].includes(k))))
      const also = [
        ...(strip(oldFm) !== strip(newFm) ? ["frontmatter"] : []),
        ...changed.filter((k) => k !== "frontmatter"),
        ...["used by", "open amendments"].filter((key) => (oldTexts[key]?.text ?? "") !== (newTexts[key]?.text ?? "")).map((key) => newTexts[key]?.name ?? oldTexts[key].name),
      ]
      const dated = (texts) => (texts.decisions?.text ?? "").split("\n").filter((l) => /^[-*]\s+\d{4}-\d{2}-\d{2}\b/.test(l))
      const oldDecisions = new Set(dated(oldTexts))
      if (!dated(newTexts).some((l) => !oldDecisions.has(l))) problems.push(`add a dated line under ## Decisions saying why ("- ${newFm.deprecated || "YYYY-MM-DD"}: Deprecated: …"), in the same edit, since it can't be added once the spec is frozen. One Edit can't change both the frontmatter and Decisions: use a single Write of the whole file, or a MultiEdit with both changes`)
      if (also.length) problems.push(`deprecate it in an edit of its own; this one also changes ${also.join(", ")}`)
      if (problems.length) return decide("deny", `${name} can't be deprecated like this: ${problems.join("; ")}.`)
      const replaced = replacementsOf({ fm: newFm })
      // Specs already deprecated in favour of this one will point at a deprecated spec from now on.
      const pointing = deprecated.filter((s) => replacementsOf(s).includes(name)).map((s) => s.name)
      const users = pointingAt().map((s) => s.name)
      return decide(
        "ask",
        `Deprecate ${name} (${from} → deprecated)${replaced.length ? `, replaced by ${replaced.join(", ")}` : ", with no replacement"}? ` +
          `From here it's frozen: Claude won't build against it or edit it again, and specs that still point at it get a lint warning` +
          `${users.length ? ` (${users.join(", ")})` : ""}. ` +
          `${pointing.length ? `Deprecated specs that name ${name} as their replacement will keep pointing at it: ${pointing.join(", ")}. ` : ""}` +
          `Approve if that's your decision; deny if not.`,
      )
    }
    // Marking verified is the taste test: Claude needs a passing report, and then the user has the final say.
    if (to === "verified" && from !== "verified") {
      const { file: reportFile, problems, passed, total, taste, audit, unstamped, hasStamps } = checkReport(parseSpec(after, file, kind), specs().byName)
      const stamps = `node scripts/spec-lint.mjs --components ${name}`
      if (unstamped.length) problems.push(`${rel(reportFile)} ${hasStamps ? `doesn't record ${unstamped.join(", ")}` : `has no "Components:" line`} (get it with ${stamps})`)
      if (audit.length) problems.push(`${rel(reportFile)} was written against an older ${audit.join(", ")}; check ${name} against it as it is now, and update the "Components:" line (${stamps})`)
      if (problems.length) return decide("deny", `${name} can't be marked verified yet: ${problems.join("; ")}.`)
      return decide(
        "ask",
        `Taste test: ${rel(reportFile)} shows ${passed}/${total} rules of ${name} passing` +
          `${taste.length ? `, and leaves ${taste.join(", ")} for you to check by hand` : ""}. ` +
          `Approve if you've tried it and it's what you meant; deny and tell Claude what's off if not.`,
      )
    }
  }
  if (from === "draft" && to === "draft") return
  if (changed.length === 0) return
  // Claude may record implementation progress (status approved ↔ implemented, verified → implemented, source paths) without asking.
  // It may also clear `deprecated` and `replaced_by` from a live spec, which is what a revived one still carries:
  // bringing it back was the user's call (they set its status), the fields are a lint error on a live spec anyway,
  // and they aren't part of what it asks for. (A deprecated spec never gets this far: it's frozen above.)
  if (changed.length === 1 && changed[0] === "frontmatter") {
    const { status: s1, source: src1, ...rest1 } = oldFm
    const { status: s2, source: src2, ...rest2 } = newFm
    for (const key of DEPRECATION_KEYS) if (rest2[key] === undefined) delete rest1[key]
    const progressOnly = JSON.stringify(rest1) === JSON.stringify(rest2) && (s1 === s2 || (CLAUDE_STATUSES.includes(s1) && CLAUDE_STATUSES.includes(s2) && s2 !== "approved"))
    if (progressOnly) return
  }
  // A policy's decision is part of every spec that relies on it, directly or through another policy, so say which
  // specs a change to it reaches: verified ones will need re-verifying. Edits that leave the decision alone
  // (Purpose, Examples) don't reach anyone.
  const decision = KINDS[kind]?.fingerprinted ?? []
  const users = changed.some((k) => decision.includes(k.toLowerCase()))
    ? specs().live.filter((s) => s.name !== name && reliesOn(s, specs().byName).some((r) => r.spec.name === name))
    : []
  const verified = users.filter((s) => statusOf(s) === "verified").map((s) => s.name)
  const reach = verified.length ? ` ${verified.join(", ")} will need re-verifying.` : ""
  // Name everyone who relies on the spec, directly or through other specs, so the user sees what the change can
  // reach without taking Claude's word for it. For a policy that includes specs that don't rely on its decision
  // themselves but are built on ones that do (a flow through a screen that uses it).
  const target = kind !== "tokens" && specs().all.find((s) => s.file === file)
  const relied = target ? reachNote(target, specs()) : ""
  // Applying an amendment removes it from Open amendments; this prompt is where the user accepts it.
  const stillOpen = new Set(openAmendments(after).map((a) => a.id))
  const applied = openAmendments(before).filter((a) => !stillOpen.has(a.id))
  if (applied.length) {
    return decide(
      "ask",
      `Accept ${applied.map((a) => `amendment ${a.id} (${a.title})${a.change ? `: ${a.change}` : ""}`).join("; ")}? ` +
        `This changes ${rel(file)}, touching: ${changed.join(", ")}.${relied}${reach} Approve to accept; deny to leave it open, and tell Claude if you'd rather reject it.`,
    )
  }
  decide(
    "ask",
    `Spec change in ${rel(file)} (status: ${from} → ${to}), touching: ${changed.join(", ")}.${relied}${reach} ` +
      `Approve only if you agreed to this exact change; otherwise deny and ask Claude to propose it under "## Open amendments".`,
  )
}

// The Edit/Write hook can't see shell commands, so catch the obvious ways a command could change a spec.
const SHELL_WRITE = /\b(sed|perl)\b[^|;&]*\s-[a-z]*i|\b(tee|mv|cp|rm|truncate|touch|ln|dd)\b|\bgit\s+(checkout|restore|reset|apply|stash|mv|rm)\b|\b(node|python3?|ruby|bun|deno)\s+(-e|-c|--eval)\b/
const hookBash = () => {
  const { tool_input: input = {}, tool_use_id: id } = readStdin()
  // Reports are Claude's own output; only the specs themselves are protected.
  const command = (input.command ?? "").replace(/\bspecs\/_reports\b\S*/g, "")
  const mentionsSpecs = /(^|[\s'"=(/])specs(\/|['"\s;|&)]|$)/.test(command)
  const redirectsIntoSpecs = /\d?>>?\s*['"]?[^\s'"&|;]*\bspecs\//.test(command)
  if (!redirectsIntoSpecs && !(mentionsSpecs && SHELL_WRITE.test(command))) return
  if (existsSync(specsDir)) {
    const specs = loadAll()
    beginOwnChange(id ?? `bash:${input.command}`, specs, specs.all.map(keyOf))
  }
  decide(
    "ask",
    `This shell command looks like it changes files in specs/, which skips the spec protection on Edit/Write. ` +
      `Approve only if you expected it; otherwise deny and ask Claude to make the change with Edit or Write.`,
  )
}

// After a shell command the Bash hook asked about has run, record how it left the specs (see beginOwnChange).
const hookBashPost = () => {
  const { tool_input: input = {}, tool_use_id: id } = readStdin()
  if (existsSync(specsDir)) endOwnChange(id ?? `bash:${input.command}`, loadAll, { anyNew: true })
}

// ---------- noticing changes ----------

// What Claude last saw of each spec: its status and fingerprint, keyed by "kind/Name". It's local to this checkout
// and ignored by git, so a teammate's approval shows up here after a pull. Claude's own changes are recorded as it
// makes them (see beginOwnChange), so what's reported is only what changed somewhere else.
const seenFile = path.join(specsDir, ".last-seen.json")
const seenLock = `${seenFile}.lock`
const keyOf = (spec) => `${spec.kind}/${spec.name}`

// Hooks for tool calls made in parallel run at the same time, so every read-modify-write of the record holds a lock.
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms)
const withSeenLock = (fn) => {
  for (let tries = 0; tries < 200; tries++) {
    try {
      mkdirSync(seenLock)
      break
    } catch {
      // A lock left behind by a hook that crashed goes stale after a few seconds. After ~4s of waiting, go ahead
      // without it rather than hold up the session.
      try {
        if (Date.now() - statSync(seenLock).mtimeMs > 5000) rmdirSync(seenLock)
      } catch {}
      sleep(20)
    }
  }
  try {
    return fn()
  } finally {
    try {
      rmdirSync(seenLock)
    } catch {}
  }
}

// { record } when there's a readable record, { unreadable: true } when the file is there but can't be parsed.
const readSeen = () => {
  if (!existsSync(seenFile)) return {}
  try {
    const record = JSON.parse(readFileSync(seenFile, "utf8"))
    return record?.specs ? { record: { pending: {}, ...record } } : { unreadable: true }
  } catch {
    return { unreadable: true }
  }
}
// Written to a temporary file and renamed into place, so a reader never sees half a record. Notes about changes
// Claude started but never finished (an edit the user denied) are dropped after an hour.
const writeSeen = (record) => {
  const pending = Object.fromEntries(Object.entries(record.pending ?? {}).filter(([, p]) => Date.now() - p.at < 3_600_000))
  const tmp = `${seenFile}.${process.pid}.tmp`
  writeFileSync(tmp, `${JSON.stringify({ specs: record.specs, pending }, null, 2)}\n`)
  renameSync(tmp, seenFile)
}

const glimpse = (spec, byName) => ({ status: statusOf(spec), hash: hashOf(spec, byName) })
const snapshot = (specs) => {
  const byName = byNameOf(specs.all)
  return Object.fromEntries(specs.all.map((spec) => [keyOf(spec), glimpse(spec, byName)]))
}
const same = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null)

// What a changed spec means for Claude, one line each. Claude offers the next step; it never starts building or
// verifying on its own because a status moved. A spec whose status and content both changed gets a line for each.
const BUILT = ["implemented", "verified"]
const statusNote = (spec, from, to, outlined) => {
  const name = spec.name
  if (from === "deprecated") {
    // Only the clean-up that's still to do, so Claude doesn't repeat what the user already did.
    const todo = []
    if (DEPRECATION_KEYS.some((key) => spec.fm[key] !== undefined)) todo.push("remove its `deprecated` and `replaced_by` lines")
    if (!/reviv|brought back/i.test(sectionTexts(spec.raw).decisions?.text ?? "")) todo.push("add a dated line under ## Decisions saying why it's back")
    if (!outlined.has(name)) todo.push("put it back in specs/outline.md")
    return `${name} was brought back (deprecated → ${to}).${todo.length ? ` Finish reviving it: ${todo.join(", ")}.` : ""} Then offer to build it.`
  }
  if (to === "deprecated") return `${name} was deprecated. ${outlined.has(name) ? "Take it off specs/outline.md, and don't" : "Don't"} build on it from now on.`
  if (to === "approved" && from === "draft") return `${name} was approved. Offer to build it; don't start until the user says so.`
  if (to === "verified") return `${name} was marked verified by hand. Lint checks it has a passing report; if it doesn't, say so.`
  if (to === "draft") return `${name} went back to draft (from ${from}): it's being reworked, so don't build on it until it's approved again.`
  return `${name} went from ${from} to ${to}${BUILT.includes(from) && !BUILT.includes(to) ? ": it needs building again" : ""}.`
}
// A component's change can reach every built spec made from it. Those aren't sent back to be re-verified (see
// componentsOf), so name them, and Claude offers to audit each.
const auditNote = (component, specs, byName) => {
  const built = specs.live.filter((s) => BUILT.includes(statusOf(s)) && componentsOf(s, byName).includes(component))
  return built.length
    ? ` It's part of ${built.map((s) => `${s.name} (${statusOf(s)})`).join(", ")}: offer to audit each for whether the change affects it.` +
        `${built.some((s) => statusOf(s) === "verified") ? " Lint warns about the verified ones until they're re-verified." : ""}` +
        ` node scripts/spec-lint.mjs --refs ${component.name} shows everything else that relies on it.`
    : ""
}
const contentNote = (name, status) =>
  BUILT.includes(status)
    ? `${name} changed after it was built (its own text, or a policy it relies on). Check the code still matches it` +
      `${status === "verified" ? `, and set it to implemented: its report no longer matches, so it needs /spec-verify again` : ", and offer to re-verify it"}.`
    : `${name} changed since you last read it. Re-read it before building on it.`

const changeNotes = (seen, now, specs) => {
  const byKey = new Map(specs.all.map((s) => [keyOf(s), s]))
  const outlined = new Set((specs.outline?.entries ?? []).map((e) => e.name))
  const byName = byNameOf(specs.all)
  const notes = []
  for (const [key, { status, hash }] of Object.entries(now)) {
    const spec = byKey.get(key)
    const was = seen[key]
    if (!was) {
      if (status !== "draft") notes.push(`${spec.name} (${spec.kind}) is new, and already ${status}: read it before working on anything it covers.`)
      continue
    }
    const changed = was.hash !== hash && status !== "draft" && status !== "deprecated"
    // Edits to a draft aren't news, so a component reworked as a draft shows no content change when it's approved
    // again. Its verified specs' reports say whether it changed, so name the ones it has left behind.
    const behind = spec.kind === "component" && !changed && was.status === "draft" && !["draft", "deprecated"].includes(status) ? behindOn(spec, specs, byName) : []
    if (was.status !== status) {
      notes.push(
        `${statusNote(spec, was.status, status, outlined)}` +
          `${behind.length ? ` It changed while it was a draft, so ${behind.join(", ")} ${behind.length === 1 ? "was" : "were"} verified against an older version: offer to audit each for whether the change affects it.` : ""}`,
      )
    }
    if (changed) notes.push(`${contentNote(spec.name, status)}${spec.kind === "component" ? auditNote(spec, specs, byName) : ""}`)
  }
  for (const key of Object.keys(seen)) if (!now[key]) notes.push(`${key.split("/")[1]} was deleted.`)
  return notes
}

const hookSeen = () => {
  const { hook_event_name: event = "UserPromptSubmit" } = readStdin()
  if (!existsSync(specsDir)) return
  const specs = loadAll()
  const now = snapshot(specs)
  const notes = withSeenLock(() => {
    const { record, unreadable } = readSeen()
    if (!record || !same(record.specs, now)) writeSeen({ ...record, specs: now })
    if (unreadable) {
      return [
        `The record of what you last saw of the specs (specs/.last-seen.json) couldn't be read, so changes since then can't be listed. ` +
          `It's been started afresh; run node scripts/spec-lint.mjs --summary if you need to see where everything stands.`,
      ]
    }
    // The first run only records what's there.
    return record ? changeNotes(record.specs, now, specs) : []
  })
  if (notes.length === 0) return
  const context =
    `Spec changes since you last looked, made outside your own edits (by the user, or a git pull):\n` +
    `${notes.map((n) => `- ${n}`).join("\n")}\n` +
    `Tell the user briefly what you noticed and offer the next step for each. Don't start building or verifying unasked.`
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: event, additionalContext: context } }))
}

// Claude's own changes to specs are recorded as it makes them, so they aren't reported back to it. Before a change
// (an Edit or Write to a spec, or a shell command that looks like it writes to specs/), note how the specs it can
// touch look. Afterwards, each one whose record still matches that note moves on to how Claude left it. One whose
// record doesn't match had already changed somewhere else, unreported, so it keeps its old record and that change
// is still reported. `id` pairs the two halves: the tool call's ID, or failing that the file or command.
const beginOwnChange = (id, specs, keys) => {
  const now = snapshot(specs)
  withSeenLock(() => {
    const { record } = readSeen()
    if (!record) return
    record.pending[id] = { at: Date.now(), specs: Object.fromEntries(keys.map((key) => [key, now[key] ?? null])) }
    writeSeen(record)
  })
}
const endOwnChange = (id, loadSpecs, { anyNew = false } = {}) => {
  // Most tool calls have nothing to record (the Bash hook runs after every command), so check before fingerprinting.
  if (!readSeen().record?.pending[id]) return
  const now = snapshot(loadSpecs())
  withSeenLock(() => {
    const { record } = readSeen()
    const before = record?.pending[id]
    if (!before) return
    // A shell command can create specs nobody named beforehand; a spec that's new to both counts as Claude's.
    const keys = new Set([...Object.keys(before.specs), ...(anyNew ? Object.keys(now).filter((key) => !record.specs[key]) : [])])
    for (const key of keys) {
      if (!same(record.specs[key], before.specs[key])) continue
      if (now[key]) record.specs[key] = now[key]
      else delete record.specs[key]
    }
    delete record.pending[id]
    writeSeen(record)
  })
}
// The specs an edit to `file` can change the fingerprint of: the spec itself, and any that rely on it as a policy.
const reachOf = (file, kind, specs) => {
  const name = path.basename(file, ".md")
  const byName = byNameOf(specs.all)
  const reached = specs.live.filter((s) => reliesOn(s, byName).some((r) => r.spec.name === name)).map(keyOf)
  return [`${kind}/${name}`, ...reached]
}

const hookPost = () => {
  const { tool_input: input = {}, tool_use_id: id } = readStdin()
  const file = input.file_path && path.resolve(input.file_path)
  if (!file || !existsSync(specsDir)) return
  const specs = loadAll()
  // How the specs this edit could touch looked before it (see beginOwnChange), read before endOwnChange clears it.
  const before = readSeen().record?.pending[id ?? `file:${file}`]?.specs
  if (specKind(file) && specKind(file) !== "tokens") endOwnChange(id ?? `file:${file}`, () => specs)
  const sourcesOf = (spec) => asList(spec.fm.source).map((src) => path.join(root, src))
  const sources = new Set(specs.all.flatMap(sourcesOf))
  if (!file.startsWith(specsDir + path.sep) && !sources.has(file)) return
  // Code often outlives its spec. Remind Claude, so it moves the code toward the replacement rather than extending it.
  const frozen = specs.deprecated.filter((s) => sourcesOf(s).includes(file))
  const byName = byNameOf(specs.all)
  const frozenNotes = frozen.map((s) => `${rel(file)} is a source of ${s.name}, which is ${deprecationNote(s, byName)}. Don't build on what ${s.name} describes.`)
  // An edit of Claude's to a component: name the verified specs whose reports it has left behind, so they get audited.
  // Only when this edit changed the component's fingerprint: an edit to its Decisions, say, isn't to blame for drift
  // from an earlier change. With no record of how it looked before, say what's behind without saying why.
  const edited = specs.live.find((s) => s.file === file && s.kind === "component")
  const was = edited && before ? before[keyOf(edited)] : undefined
  const changedNow = edited && (!before || was?.hash !== hashOf(edited, byName))
  const behind = changedNow ? behindOn(edited, specs, byName) : []
  const audit = `Tell the user, and offer to audit each for whether the change affects it; lint warns until each is re-verified with /spec-verify.`
  const auditNotes = !behind.length
    ? []
    : before
      ? [`Your change to ${edited.name} reaches ${behind.join(", ")}, verified against the old version. ${audit}`]
      : [`${behind.join(", ")} ${behind.length === 1 ? "was" : "were"} verified against an older ${edited.name} than there is now. ${audit}`]
  const note = [...frozenNotes, ...auditNotes].join("\n")
  const errors = lint(specs).problems.filter((p) => p.level === "error")
  if (errors.length === 0) {
    if (note) process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: note } }))
    return
  }
  process.stderr.write(`spec-lint found ${errors.length} error(s) after editing ${rel(file)}:\n${format(errors)}\n${note ? `${note}\n` : ""}`)
  process.exit(2)
}

// ---------- main ----------

if (has("--version")) console.log(VERSION)
else if (has("--hook-pre")) hookPre()
else if (has("--hook-bash-post")) hookBashPost()
else if (has("--hook-bash")) hookBash()
else if (has("--hook-post")) hookPost()
else if (has("--hook-seen")) hookSeen()
else if (!existsSync(specsDir)) console.log(`no specs/ directory under ${root}`)
else if (has("--new")) {
  const result = newSpec(argOf("--new"), args[args.indexOf("--new") + 2])
  printResult(result)
  process.exit(result.error ? 1 : 0)
} else if (has("--scaffold")) process.exit(scaffold())
else if (has("--refs")) {
  const { text, error } = refsReport(argOf("--refs") ?? "", loadAll())
  if (error) {
    console.error(error)
    process.exit(1)
  }
  console.log(text)
} else if (has("--hash")) {
  const spec = loadAll().all.find((s) => s.name === argOf("--hash"))
  if (!spec) {
    console.error(`no spec named "${argOf("--hash") ?? ""}"`)
    process.exit(1)
  }
  console.log(hashOf(spec, byNameOf(loadAll().all)))
} else if (has("--components")) {
  const { all } = loadAll()
  const spec = all.find((s) => s.name === argOf("--components"))
  if (!spec) {
    console.error(`no spec named "${argOf("--components") ?? ""}"`)
    process.exit(1)
  }
  console.log(componentStamps(spec, byNameOf(all)))
} else {
  let specs = loadAll()
  if (has("--fix")) {
    const changed = fixUsedBy(specs)
    if (changed.length) console.log(`updated "Used by" in: ${changed.join(", ")}`)
    specs = loadAll()
  }
  if (has("--summary")) console.log(summary(specs))
  const { problems } = lint(specs)
  if (problems.length) console.log(`${has("--summary") ? "\n" : ""}${format(problems)}`)
  const errors = problems.filter((p) => p.level === "error").length
  if (!has("--summary")) console.log(errors ? `\n${errors} error(s), ${problems.length - errors} warning(s)` : `specs OK${problems.length ? ` (${problems.length} warning(s))` : ""}`)
  process.exit(errors ? 1 : 0)
}
