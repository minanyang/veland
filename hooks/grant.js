#!/usr/bin/env node
// UserPromptSubmit and PreToolUse (Bash) hook: a flow skill's Bash grants hold for the rest of the
// session in which the user typed it. Claude Code applies a skill's `allowed-tools` only to the turn
// the skill was invoked in, not to a background wake-up, a later approval turn or a `--resume` turn.
//
// UserPromptSubmit: a prompt that starts with `/cutter:open`, `/cutter:work` or `/cutter:close`
// records that skill's `Bash(...)` grants, as its SKILL.md lists them now, in
//   ${CLAUDE_PLUGIN_DATA}/sessions/<session_id>.json   { "grants": { "<skill>": ["<grant>", …] } }
// outside the working directory, so the agent cannot write itself a record without being asked.
//
// PreToolUse: allows a single command (no shell metacharacters) matching a recorded grant, outside a
// subagent. Anything else, and any error of its own, prints nothing: Claude Code decides as usual.

const fs = require('node:fs')
const path = require('node:path')

const SID = /^[A-Za-z0-9-]+$/
const TYPED = /^\s*\/cutter:(open|work|close)(?=\s|$)/
const META = /[;&|<>$`\n\r]/

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
    if (typed) record(file, typed[1])
    pass()
  }
  if (input.hook_event_name !== 'PreToolUse' || input.tool_name !== 'Bash') pass()
  if (input.agent_id !== undefined) pass()
  const raw = input.tool_input && typeof input.tool_input.command === 'string' ? input.tool_input.command : ''
  const command = raw.trim()
  if (!command || META.test(command)) pass()
  const grants = readGrants(file)
  for (const [skill, list] of Object.entries(grants)) {
    if (!Array.isArray(list)) continue
    if (list.some((g) => typeof g === 'string' && matches(g, command))) {
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
  }
  pass()
}

function readGrants(file) {
  try {
    const r = JSON.parse(fs.readFileSync(file, 'utf8'))
    if (r && typeof r === 'object' && r.grants && typeof r.grants === 'object' && !Array.isArray(r.grants)) return r.grants
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

function record(file, skill) {
  const grants = readGrants(file)
  grants[skill] = skillGrants(skill)
  const dir = path.dirname(file)
  fs.mkdirSync(dir, { recursive: true })
  const tmp = path.join(dir, `.${path.basename(file)}.${process.pid}.tmp`)
  fs.writeFileSync(tmp, JSON.stringify({ grants }) + '\n', { mode: 0o600 })
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
