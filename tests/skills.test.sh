#!/bin/bash
# The skills' `allowed-tools` must cover every command their fenced bash blocks run and every command their prose names in inline code (unless Claude Code allows it as read-only, it is left to the user, or it is named but never run), and must not
# grant anything that can destroy work, force-push, bypass branch protection or run arbitrary code.
# Creating an issue and posting a comment are public writes: never granted, so they always prompt.
# open and work must load the shared references/grill.md (beside the skills directory) through a granted `veland-grill`.
# The grill must always ask a ticket's own open questions, and work must post their answers through comment.md.
# The skills and review agents that report on work must carry the verify-first rule.
# work and close must resolve .veland/<id>/ paths against the printed `ticket dir:` and take the base from `base:`.
# open, work, close and batch must each have a `## Replies` section.
# SKILLS_DIR overrides the skills directory (used to show the test red against another tree).
set -uo pipefail
SKILLS_DIR="${SKILLS_DIR:-$(cd "$(dirname "$0")/.." && pwd)/skills}"
exec node - "$SKILLS_DIR" <<'JS'
const fs = require("fs")
const dir = process.argv[2]
let fail = 0
const ok = (m) => console.log(`ok    ${m}`)
const bad = (m) => { console.log(`FAIL  ${m}`); fail = 1 }

// Commands left to the user's own permissions, per skill (prefix of the placeholder-normalised line).
const userOwn = {
  close: [],
  work: ["git -C X add ", "git -C X commit ", "veland-land comment "],
  open: ["veland-land issue "],
  batch: ["veland-land comment ", "veland-batch approve "],
}
const ownedBy = (skill, line) => userOwn[skill].some((p) => line === p.trimEnd() || line.startsWith(p))
// Exact prose commands Claude Code runs without a grant (checked with `claude -p` in default mode). Granting
// `git log *` or `git diff *` instead would also allow `--output=<file>`.
const readOnly = ["git log --name-only HEAD..origin/X", "git log -n 5 --oneline", "git worktree list",
  "git diff --name-only X...X", "git diff origin/X...X -- .claude/agent-memory"]
// Commands a skill's prose names for the user or as an explanation, never runs itself.
const notRun = {
  close: ["gh auth login", "glab auth login", "git rebase --skip", "git merge --ff-only"],
  work: [],
  open: ["gh auth login"],
  batch: [],
}
const forbidden = ["git push", "git rebase", "git merge", "git log", "gh pr merge", "glab mr merge", "gh api",
  "gh issue create", "gh pr create", "gh pr edit", "glab mr create", "glab mr update"]
const bareGrants = ["veland-worktree *", "veland-land *", "git *"]
// Commands that must always ask: the public writes, and a batch's plan approval, which text a worker wrote must
// never be able to give.
const publicWrites = ["veland-land issue", "veland-land comment", "veland-batch approve"]

const norm = (s) => s.replace(/<[^>]*>/g, "X")

for (const skill of Object.keys(userOwn)) {
  const text = fs.readFileSync(`${dir}/${skill}/SKILL.md`, "utf8")
  const fm = /^---\n([\s\S]*?)\n---/.exec(text)[1]
  const m = /^allowed-tools:\n((?:  - .*\n?)+)/m.exec(fm + "\n")
  const entries = m ? m[1].split("\n").filter(Boolean).map((l) => l.replace(/^  - /, "").trim()) : []
  entries.length ? ok(`${skill}: allowed-tools declared`) : bad(`${skill}: no allowed-tools list`)

  const bodies = []
  for (const e of entries) {
    const b = /^Bash\((.*)\)$/.exec(e)
    if (!b) { bad(`${skill}: entry ${e} is not Bash(...)`); continue }
    const body = b[1]
    const toks = body.split(" ")
    if (toks.slice(0, -1).some((t) => t.includes("*")) || (toks.at(-1).includes("*") && toks.at(-1) !== "*"))
      bad(`${skill}: ${e} has a * that is not the last token`)
    if (bareGrants.includes(body) || forbidden.some((f) => body === f || body.startsWith(f + " "))) bad(`${skill}: ${e} is a forbidden grant`)
    // Only the exact `git fetch`: with arguments, `--upload-pack=<cmd>` runs arbitrary code.
    if (/^git( -[cC] \S+)* fetch /.test(body)) bad(`${skill}: ${e} grants git fetch with arguments`)
    bodies.push(body)
  }
  if (entries.length) ok(`${skill}: entries are well-formed and safe`)
  const covered = (line) => bodies.some((b) => b.endsWith(" *") ? line === b.slice(0, -2) || line.startsWith(b.slice(0, -1)) : line === b)

  const lines = []
  for (const blk of text.matchAll(/```bash\n([\s\S]*?)```/g))
    lines.push(...blk[1].replace(/\\\n\s*/g, " ").split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#")))

  for (const raw of lines) {
    const line = norm(raw)
    if (/&&|\|\||;|\|/.test(line)) { bad(`${skill}: chained command: ${raw}`); continue }
    if (covered(line)) ok(`${skill}: covered: ${raw}`)
    else if (ownedBy(skill, line)) ok(`${skill}: left to the user: ${raw}`)
    else bad(`${skill}: not covered by allowed-tools: ${raw}`)
  }

  // Prose: fenced blocks of every kind are removed first, then each inline-code span that is a command.
  const prose = []
  let fence = 0
  for (const l of text.split("\n")) {
    const f = /^\s*(`{3,})/.exec(l)
    if (!fence && f) fence = f[1].length
    else if (fence && f && f[1].length >= fence && /^\s*`+\s*$/.test(l)) fence = 0
    else if (!fence) prose.push(l)
  }
  const spans = new Set()
  const p = prose.join("\n")
  for (let i = 0; i < p.length;) {
    const run = /^`+/.exec(p.slice(i))
    if (!run) { i++; continue }
    const n = run[0].length
    const close = new RegExp(`(?<!\`)\`{${n}}(?!\`)`, "g")
    close.lastIndex = i + n
    const c = close.exec(p)
    if (!c) { i += n; continue }
    spans.add(p.slice(i + n, c.index).replace(/\n/g, " ").trim())
    i = c.index + n
  }
  for (const raw of spans) {
    const line = norm(raw)
    if (!/^(git|gh|glab|veland-[a-z-]+) /.test(line)) continue
    if (/&&|\|\||;|\|/.test(line)) bad(`${skill}: chained command in prose: ${raw}`)
    else if (covered(line)) ok(`${skill}: covered (prose): ${raw}`)
    else if (ownedBy(skill, line)) ok(`${skill}: left to the user: ${raw}`)
    else if (readOnly.includes(line)) ok(`${skill}: left to Claude Code's read-only rules: ${raw}`)
    else if (notRun[skill].includes(line)) ok(`${skill}: named, not run: ${raw}`)
    else bad(`${skill}: prose command not covered by allowed-tools: ${raw}`)
  }
}

// No skill may grant one of them, by any pattern that covers it: `*`, `veland-land *`, `veland-land i*`,
// the legacy `veland-land issue:*`, or the command itself.
for (const skill of fs.readdirSync(dir).filter((d) => fs.existsSync(`${dir}/${d}/SKILL.md`))) {
  const fm = (/^---\n([\s\S]*?)\n---/.exec(fs.readFileSync(`${dir}/${skill}/SKILL.md`, "utf8")) || ["", ""])[1]
  const covers = (body, w) => {
    body = body.replace(/:\*$/, " *")
    return body.endsWith("*") ? (w + " ").startsWith(body.slice(0, -1)) : body === w || body.startsWith(w + " ")
  }
  const hits = [...fm.matchAll(/Bash\(([^)]*)\)/g)].filter((b) => publicWrites.some((w) => covers(b[1].trim(), w)))
  // A bare `Bash` (or `Bash()`) grants every command.
  const tools = (/^allowed-tools:(.*(?:\n  - .*)*)/m.exec(fm) || ["", ""])[1]
  hits.push(...[...tools.matchAll(/(?:^|[\s,-])(Bash(?:\(\s*\))?)(?=[\s,]|$)/g)].map((b) => [b[1]]))
  hits.length ? hits.forEach((b) => bad(`${skill}: ${b[0]} grants ${b[1] ?? b[0]}, which must always prompt`))
    : ok(`${skill}: grants no public write or batch approval`)
}

// open and work load the one shared grill rather than each carrying a copy. A Read of it would prompt (the plugin
// root is outside the workspace and a Read rule takes only an absolute path), so they run the granted veland-grill.
const grill = `${dir}/../references/grill.md`
fs.existsSync(grill) ? ok("references/grill.md exists") : bad("references/grill.md is missing")
for (const skill of ["open", "work"]) {
  const text = fs.readFileSync(`${dir}/${skill}/SKILL.md`, "utf8")
  text.includes("run `veland-grill`") && /^  - Bash\(veland-grill\)$/m.test(text)
    ? ok(`${skill}: loads the grill through a granted veland-grill`) : bad(`${skill}: does not load the grill through a granted veland-grill`)
}

// open reads the issue types through its granted script: Claude Code refuses the raw GraphQL query for its braces.
{
  const text = fs.readFileSync(`${dir}/open/SKILL.md`, "utf8")
  const fm = /^---\n([\s\S]*?)\n---/.exec(text)[1]
  const step2 = (/^## Step 2\b[\s\S]*?(?=^## )/m.exec(text) || [""])[0]
  const runs = [...step2.matchAll(/```bash\n([\s\S]*?)```/g)].some((b) => b[1].split("\n").some((l) => l.trim() === "veland-ticket issue-types"))
  fm.split("\n").some((l) => l.trim() === "- Bash(veland-ticket issue-types)") && runs
    ? ok("open: looks up issue types through a granted veland-ticket issue-types")
    : bad("open: does not look up issue types through a granted veland-ticket issue-types")
}

// open runs veland-worktree init before anything else: its tickets: line decides whether origin and gh are checked at
// all, and its listing — not reading the forms or the banned file itself — is what the draft is built from.
{
  const text = fs.readFileSync(`${dir}/open/SKILL.md`, "utf8")
  // Up to the next step: Step 3's draft layout has `## ` headings of its own.
  const step = (n) => (new RegExp(`^## Step ${n}\\b[\\s\\S]*?(?=^## Step )`, "m").exec(text) || [""])[0]
  const blocks = (s) => [...s.matchAll(/```bash\n([\s\S]*?)```/g)].map((b) => b[1].split("\n").map((l) => l.trim()))
  const s1 = text.search(/^## Step 1\b/m)
  const pre = s1 === -1 ? "" : text.slice(0, s1), steps = s1 === -1 ? text : text.slice(s1)
  const initAt = blocks(pre).findIndex((b) => b.includes("veland-worktree init"))
  const originAt = blocks(pre).findIndex((b) => b.includes("git remote get-url origin"))
  const s2 = step(2), s3 = step(3)
  initAt !== -1 && originAt > initAt && !blocks(steps).some((b) => b.includes("veland-worktree init")) &&
    pre.includes("`tickets: github`") && pre.includes("`tickets: files`") &&
    ["`form:`", "`drafts:`", "`banned:`"].every((l) => (s2 + s3).includes(l)) &&
    s3.includes("`<drafts>/<short-slug>.md`") && !text.includes("Read it whole") && !text.includes("`references/banned-phrases.txt`")
    ? ok("open: reads the tickets mode from veland-worktree init before checking origin")
    : bad("open: reads the tickets mode from veland-worktree init before checking origin")
}

const rule = "Never reply that something is unverified, unchecked or not yet confirmed: check it first. " +
  "Only when a check is impossible, say so, naming what was tried and why it cannot be checked."
for (const f of ["skills/open/SKILL.md", "skills/work/SKILL.md", "skills/close/SKILL.md", "skills/batch/SKILL.md", "skills/code-review/SKILL.md",
  "skills/code-review-branch/SKILL.md", "agents/code-reviewer.md", "agents/security-reviewer.md"]) {
  const file = `${dir}/../${f}`
  fs.existsSync(file) && fs.readFileSync(file, "utf8").includes(rule)
    ? ok(`${f}: carries the verify-first rule`) : bad(`${f}: lost the verify-first rule`)
}

// work's cold read is driven by plan-check's line and saved, and a draft is checked before it is shown.
{
  const text = fs.readFileSync(`${dir}/work/SKILL.md`, "utf8")
  const step = (n) => (new RegExp(`^## Step ${n}\\b[\\s\\S]*?(?=^## Step )`, "m").exec(text) || [""])[0]
  step(1).includes("cold read required") && step(1).includes("`.veland/<id>/cold-read.md`")
    ? ok("work: acts on plan-check's cold read line") : bad("work: does not act on plan-check's cold read line")
  const draft = step(0).slice(step(0).indexOf("exists as a draft"))
  draft.indexOf("`veland-plan-check <id>`") !== -1 && draft.indexOf("`veland-plan-check <id>`") < draft.indexOf("show the draft once")
    ? ok("work: checks a draft plan before showing it") : bad("work: does not check a draft plan before showing it")
}

// A question the ticket itself asks is never settled silently: the grill always asks it, an accepted recommendation
// counts as its answer, and work posts that answer to the issue through comment.md.
{
  const text = fs.readFileSync(grill, "utf8")
  text.includes("An open question the ticket itself states — its own words ask it — is always asked, whatever the ticket's size.")
    ? ok("grill: always asks the ticket's own open questions") : bad("grill: does not always ask the ticket's own open questions")
  text.includes("Accepting the recommendations (\"go with your recommendations\") answers every question asked in that round")
    ? ok("grill: an accepted recommendation is an answer") : bad("grill: an accepted recommendation is not an answer")
  const step1 = (/^## Step 1\b[\s\S]*?(?=^## Step )/m.exec(fs.readFileSync(`${dir}/work/SKILL.md`, "utf8")) || [""])[0]
  step1.includes("`.veland/<id>/comment.md` — every open question the ticket itself states among them, whether the user answered it or accepted the recommendation")
    ? ok("work: posts the answers to the ticket's own questions through comment.md")
    : bad("work: does not post the answers to the ticket's own questions through comment.md")
}

// close takes its mode from check's mode: line, never from reading the config itself.
{
  const text = fs.readFileSync(`${dir}/close/SKILL.md`, "utf8")
  const step0 = (/^## Step 0\b[\s\S]*?(?=^## Step )/m.exec(text) || [""])[0]
  step0.includes("`mode: <close>`") && step0.includes("never read `.claude/veland.json`") &&
    !text.includes("comes from `.claude/veland.json`")
    ? ok("close: takes the mode from check's mode: line") : bad("close: does not take the mode from check's mode: line")
}

// close fills the template check names, and answers pr's refusal by adding the missing sections.
{
  const text = fs.readFileSync(`${dir}/close/SKILL.md`, "utf8")
  const step0 = (/^## Step 0\b[\s\S]*?(?=^## Step )/m.exec(text) || [""])[0]
  const step3 = (/^## Step 3\b[\s\S]*?(?=^## Step )/m.exec(text) || [""])[0]
  step0.includes("`pr template: <path>`") && step3.includes("`pr template: <path>`") &&
    step3.includes("with the Read tool") && step3.includes("add them to `pr-body.md`")
    ? ok("close: fills the template check names and adds the sections pr names")
    : bad("close: does not fill the template check names or add the sections pr names")
}

// .veland/<id>/ paths resolve against the printed ticket dir, never the worktree, and the base comes from base:.
{
  const text = fs.readFileSync(`${dir}/work/SKILL.md`, "utf8")
  const step0 = (/^## Step 0\b[\s\S]*?(?=^## Step )/m.exec(text) || [""])[0]
  text.includes("`ticket dir: <path>`") && text.includes("`base: <branch> (<ref>)`") && text.includes("never under the worktree") &&
    step0.includes("run `veland-worktree init <id>` on every invocation, before anything reads or writes under `.veland/`") &&
    !text.includes(".worktrees/<id>")
    ? ok("work: resolves .veland paths against ticket dir: and takes the base from base:")
    : bad("work: resolves .veland paths against ticket dir: and takes the base from base:")
}
{
  const text = fs.readFileSync(`${dir}/close/SKILL.md`, "utf8")
  const step0 = (/^## Step 0\b[\s\S]*?(?=^## Step )/m.exec(text) || [""])[0]
  const first = (/```bash\n([\s\S]*?)```/.exec(step0) || ["", ""])[1].split("\n").filter(Boolean)
  first[0] === "veland-land check <id>" && first[1] === "veland-worktree path <id>" &&
    step0.includes("`ticket dir: <path>`") && step0.includes("`review: missing`") && step0.includes("never under the worktree") &&
    !text.includes("`.veland/<id>/review.md` is missing")
    ? ok("close: runs check first and resolves .veland paths against ticket dir:")
    : bad("close: runs check first and resolves .veland paths against ticket dir:")
}

for (const skill of ["open", "work", "close", "batch"])
  /^## Replies$/m.test(fs.readFileSync(`${dir}/${skill}/SKILL.md`, "utf8"))
    ? ok(`${skill}: has a ## Replies section`) : bad(`${skill}: lacks a ## Replies section`)
process.exit(fail)
JS
