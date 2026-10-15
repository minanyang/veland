#!/usr/bin/env node
// UserPromptSubmit hook: refuse /cutter:work and /cutter:close on a session that is
// already carrying a large context, and say to /clear first.
//
// A flow skill run on top of an unrelated conversation re-reads all of it on every turn:
// slower turns and a bigger bill, for context the ticket does not need. The ticket's files
// in .cutter/<id>/ are the memory; a fresh session loses nothing.
//
// Context = input + cache_creation + cache_read tokens of the last assistant message in
// the transcript. A compaction after that message means the context was just reset.
//
// .claude/cutter.json: { "contextGate": { "maxTokens": 120000 } }; maxTokens 0 turns it off.

const fs = require('node:fs')
const path = require('node:path')

let input
try {
  input = JSON.parse(fs.readFileSync(0, 'utf8'))
} catch {
  process.exit(0) // never block a prompt on a malformed payload
}

const cmd = /^\s*\/cutter:(work|close)\b(.*)$/.exec(input.prompt || '')
if (!cmd) process.exit(0)

let limit = 120_000
try {
  const cfg = JSON.parse(fs.readFileSync(path.join(input.cwd || process.cwd(), '.claude', 'cutter.json'), 'utf8'))
  if (cfg.contextGate && Number.isFinite(cfg.contextGate.maxTokens)) limit = cfg.contextGate.maxTokens
} catch {}
if (limit <= 0) process.exit(0)

let lines
try {
  lines = fs.readFileSync(input.transcript_path, 'utf8').split('\n')
} catch {
  process.exit(0) // no transcript yet: a fresh session
}

let ctx = 0
for (let i = lines.length - 1; i >= 0 && !ctx; i--) {
  const line = lines[i]
  if (!line) continue
  if (line.includes('"isCompactSummary":true')) process.exit(0)
  if (!line.includes('"usage"')) continue
  let e
  try {
    e = JSON.parse(line)
  } catch {
    continue
  }
  const u = e.type === 'assistant' && e.message && e.message.usage
  if (u) ctx = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0)
}
if (ctx < limit) process.exit(0)

const again = `/cutter:${cmd[1]}${cmd[2].trim() ? ' ' + cmd[2].trim() : ''}`
process.stdout.write(
  JSON.stringify({
    decision: 'block',
    reason:
      `Context is ${Math.round(ctx / 1000)}k tokens, over cutter's ${Math.round(limit / 1000)}k limit for a flow skill. ` +
      `Run /clear, then ${again} — the ticket's files in .cutter/ carry everything the next session needs.`,
  }),
)
