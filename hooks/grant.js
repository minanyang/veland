#!/usr/bin/env node
// UserPromptSubmit and PreToolUse (Bash) hook: a flow skill's Bash grants hold for the rest of the
// session in which the user typed it. Claude Code applies a skill's `allowed-tools` only to the turn
// the skill was invoked in, not to a background wake-up, a later approval turn or a `--resume` turn.
//
// UserPromptSubmit: a prompt that starts with `/cutter:open`, `/cutter:work` or `/cutter:close`
// records that skill's `Bash(...)` grants, as its SKILL.md lists them now, as pending, in
//   ${CLAUDE_PLUGIN_DATA}/sessions/<session_id>.json
//   { "skills": { "<skill>": { "confirmed": { "prompt_id", "grants" }, "pending": { "prompt_id", "grants" } } } }
// outside the working directory, so the agent cannot write itself a record without being asked.
// The hook input does not say who sent the prompt (a scheduled prompt looks the same), so a pending
// entry is confirmed only when the transcript line of that prompt_id is the user's typed skill.
//
// PreToolUse: allows a single command (no shell metacharacters) matching a confirmed grant, or a
// pending one that the transcript confirms, outside a subagent. Anything else, and any error of its
// own, prints nothing: Claude Code decides as usual.

const fs = require('node:fs')
const path = require('node:path')

const SID = /^[A-Za-z0-9-]+$/
const TYPED = /^\s*\/cutter:(open|work|close)(?=\s|$)/
const META = /[;&|<>$`\n\r]/
const CHUNK = 1 << 20
const MAX_SCAN = 16 << 20

const pass = () => process.exit(0)

try {
  main()
} catch {
  pass()
}

function main() {
  const input = JSON.parse(fs.readFileSync(0, 'utf8'))
  if (!input || typeof input !== 'object') pass()
  const sid = typeof input.session_id === 'string' && SID.test(input.session_id) ? input.session_id : null
  const data = process.env.CLAUDE_PLUGIN_DATA
  if (!sid || !data || !path.isAbsolute(data)) pass()
  const file = path.join(data, 'sessions', `${sid}.json`)

  if (input.hook_event_name === 'UserPromptSubmit') {
    const typed = TYPED.exec(typeof input.prompt === 'string' ? input.prompt : '')
    if (typed && typeof input.prompt_id === 'string' && input.prompt_id) record(file, typed[1], input.prompt_id)
    pass()
  }
  if (input.hook_event_name !== 'PreToolUse' || input.tool_name !== 'Bash') pass()
  if (input.agent_id !== undefined) pass()
  const raw = input.tool_input && typeof input.tool_input.command === 'string' ? input.tool_input.command : ''
  const command = raw.trim()
  if (!command || META.test(command)) pass()
  const skills = readSkills(file)
  for (const [skill, entry] of Object.entries(skills)) {
    if (granting(entry && entry.confirmed, command)) allow(skill)
  }
  for (const [skill, entry] of Object.entries(skills)) {
    const pending = entry && entry.pending
    if (!granting(pending, command) || !typedBy(input.transcript_path, pending.prompt_id, skill)) continue
    skills[skill] = { confirmed: pending }
    write(file, skills)
    allow(skill)
  }
  pass()
}

function allow(skill) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'allow',
        permissionDecisionReason: `cutter: granted by /cutter:${skill}`,
      },
    }),
  )
  pass()
}

function granting(part, command) {
  return !!part && Array.isArray(part.grants) && part.grants.some((g) => typeof g === 'string' && matches(g, command))
}

// Reads the transcript backwards, at most MAX_SCAN bytes, for the line of prompt `id`: the user's
// typed expansion of the skill. A scheduled prompt's line is not `origin.kind: "human"` and keeps its
// raw text; a tool result has array content.
function typedBy(transcript, id, skill) {
  if (typeof transcript !== 'string' || !path.isAbsolute(transcript) || typeof id !== 'string' || !id) return false
  const fd = fs.openSync(transcript, 'r')
  try {
    let pos = fs.fstatSync(fd).size
    let rest = Buffer.alloc(0)
    let scanned = 0
    while (pos > 0 && scanned < MAX_SCAN) {
      const n = Math.min(CHUNK, pos)
      pos -= n
      scanned += n
      const buf = Buffer.alloc(n)
      fs.readSync(fd, buf, 0, n, pos)
      const data = Buffer.concat([buf, rest])
      const nl = data.indexOf(10)
      if (pos > 0 && nl === -1) {
        rest = data
        continue
      }
      const start = pos > 0 ? nl + 1 : 0
      rest = data.subarray(0, start)
      const lines = data.subarray(start).toString('utf8').split('\n')
      for (let i = lines.length - 1; i >= 0; i--) {
        if (lines[i].includes(id) && typedLine(lines[i], id, skill)) return true
      }
    }
  } finally {
    fs.closeSync(fd)
  }
  return false
}

function typedLine(line, id, skill) {
  let l
  try {
    l = JSON.parse(line)
  } catch {
    return false
  }
  return (
    !!l &&
    l.type === 'user' &&
    l.promptId === id &&
    !!l.origin &&
    l.origin.kind === 'human' &&
    !!l.message &&
    typeof l.message.content === 'string' &&
    l.message.content.includes(`<command-name>/cutter:${skill}</command-name>`)
  )
}

function readSkills(file) {
  try {
    const r = JSON.parse(fs.readFileSync(file, 'utf8'))
    if (r && typeof r === 'object' && r.skills && typeof r.skills === 'object' && !Array.isArray(r.skills)) return r.skills
  } catch {}
  return {}
}

function skillGrants(skill) {
  let text
  try {
    text = fs.readFileSync(path.join(__dirname, '..', 'skills', skill, 'SKILL.md'), 'utf8').replace(/\r/g, '')
  } catch {
    return []
  }
  const fm = /^---\n([\s\S]*?)\n---/.exec(text)
  if (!fm) return []
  const m = /^allowed-tools:\n((?:  - .*\n?)+)/m.exec(fm[1] + '\n')
  if (!m) return []
  return m[1]
    .split('\n')
    .filter(Boolean)
    .map((l) => /^Bash\((.*)\)$/.exec(l.replace(/^  - /, '').trim()))
    .filter(Boolean)
    .map((b) => b[1].trim())
    .filter(Boolean)
}

// Typing a skill again replaces only its pending entry: its confirmed grants stay until a new
// prompt is confirmed, so a prompt the user did not type neither adds grants nor takes them away.
function record(file, skill, promptId) {
  const skills = readSkills(file)
  const entry = skills[skill] && typeof skills[skill] === 'object' ? skills[skill] : {}
  skills[skill] = { ...entry, pending: { prompt_id: promptId, grants: skillGrants(skill) } }
  write(file, skills)
}

function write(file, skills) {
  const dir = path.dirname(file)
  fs.mkdirSync(dir, { recursive: true })
  const tmp = path.join(dir, `.${path.basename(file)}.${process.pid}.tmp`)
  fs.writeFileSync(tmp, JSON.stringify({ skills }) + '\n', { mode: 0o600 })
  fs.renameSync(tmp, file)
}

// `<prefix> *` matches the prefix alone or followed by a space and anything; any other `*` matches
// any run of characters; the rest is literal and the whole command must match.
function matches(grant, command) {
  if (grant.endsWith(' *')) {
    const prefix = grant.slice(0, -2)
    if (command === prefix) return true
    return glob(prefix + ' *', command)
  }
  return glob(grant, command)
}

function glob(pattern, command) {
  const re = pattern
    .split('*')
    .map((s) => s.replace(/[.+?^${}()|[\]\\]/g, '\\$&'))
    .join('.*')
  return new RegExp(`^${re}$`, 's').test(command)
}
