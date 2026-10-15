#!/bin/bash
# The skills' `allowed-tools` must cover every command their fenced bash blocks run, and must not
# grant anything that can destroy work, force-push, bypass branch protection or run arbitrary code.
# Creating an issue and posting a comment are public writes: never granted, so they always prompt.
# open and work must load the shared references/grill.md (beside the skills directory).
# The skills and review agents that report on work must carry the verify-first rule.
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
  work: ["git -C X add ", "git -C X commit ", "cutter-land comment "],
  open: ["gh api graphql ", "cutter-land issue "],
}
const forbidden = ["git push", "git rebase", "git merge", "git log", "gh pr merge", "glab mr merge", "gh api",
  "gh issue create", "gh pr create", "gh pr edit", "glab mr create", "glab mr update"]
const bareGrants = ["cutter-worktree *", "cutter-land *"]
const publicWrites = ["cutter-land issue", "cutter-land comment"]

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
    bodies.push(body)
  }
  if (entries.length) ok(`${skill}: entries are well-formed and safe`)

  const lines = []
  for (const blk of text.matchAll(/```bash\n([\s\S]*?)```/g))
    lines.push(...blk[1].replace(/\\\n\s*/g, " ").split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#")))

  for (const raw of lines) {
    const line = norm(raw)
    if (/&&|\|\||;|\|/.test(line)) { bad(`${skill}: chained command: ${raw}`); continue }
    const covered = bodies.some((b) => b.endsWith(" *") ? line === b.slice(0, -2) || line.startsWith(b.slice(0, -1)) : line === b)
    if (covered) ok(`${skill}: covered: ${raw}`)
    else if (userOwn[skill].some((p) => line.startsWith(p))) ok(`${skill}: left to the user: ${raw}`)
    else bad(`${skill}: not covered by allowed-tools: ${raw}`)
  }
}

// No skill may grant a public write, by any pattern that covers it: `*`, `cutter-land *`, `cutter-land i*`,
// the legacy `cutter-land issue:*`, or the command itself.
for (const skill of fs.readdirSync(dir).filter((d) => fs.existsSync(`${dir}/${d}/SKILL.md`))) {
  const fm = (/^---\n([\s\S]*?)\n---/.exec(fs.readFileSync(`${dir}/${skill}/SKILL.md`, "utf8")) || ["", ""])[1]
  const covers = (body, w) => {
    body = body.replace(/:\*$/, " *")
    return body.endsWith("*") ? (w + " ").startsWith(body.slice(0, -1)) : body === w || body.startsWith(w + " ")
  }
  const hits = [...fm.matchAll(/Bash\(([^)]*)\)/g)].filter((b) => publicWrites.some((w) => covers(b[1].trim(), w)))
  hits.length ? hits.forEach((b) => bad(`${skill}: ${b[0]} grants a public write, which must always prompt`))
    : ok(`${skill}: grants no public write`)
}

// open and work load the one shared grill rather than each carrying a copy.
const grill = `${dir}/../references/grill.md`
fs.existsSync(grill) ? ok("references/grill.md exists") : bad("references/grill.md is missing")
for (const skill of ["open", "work"])
  fs.readFileSync(`${dir}/${skill}/SKILL.md`, "utf8").includes("`references/grill.md`")
    ? ok(`${skill}: loads references/grill.md`) : bad(`${skill}: does not load references/grill.md`)

const rule = "Never reply that something is unverified, unchecked or not yet confirmed: check it first. " +
  "Only when a check is impossible, say so, naming what was tried and why it cannot be checked."
for (const f of ["skills/open/SKILL.md", "skills/work/SKILL.md", "skills/close/SKILL.md", "skills/code-review/SKILL.md",
  "skills/code-review-branch/SKILL.md", "agents/code-reviewer.md", "agents/security-reviewer.md"]) {
  const file = `${dir}/../${f}`
  fs.existsSync(file) && fs.readFileSync(file, "utf8").includes(rule)
    ? ok(`${f}: carries the verify-first rule`) : bad(`${f}: lost the verify-first rule`)
}
process.exit(fail)
JS
