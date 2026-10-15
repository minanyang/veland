#!/bin/bash
# cutter guard — PreToolUse hook for Bash that blocks destructive commands.
# Registered by the plugin's hooks/hooks.json with matcher "Bash".
#
# Receives the Claude Code hook JSON on stdin; the bash command is at
# `.tool_input.command`.
#
#   exit 0  → allow the command
#   exit 2  → block the command and surface the stderr message to Claude
#
# Best-effort, not a sandbox: it matches command text, so an indirect form
# (a script, an alias, eval) gets past it.
#
# To run a blocked command anyway, run it yourself in chat with the
# `!<command>` prefix.

set -uo pipefail

INPUT=$(cat)
# node, not jq: a missing jq would make COMMAND empty and silently allow everything.
COMMAND=$(printf '%s' "$INPUT" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{process.stdout.write(JSON.parse(d).tool_input?.command??"")}catch{process.exit(3)}})') || {
  echo "guard-bash.sh: could not read the hook input — blocking to be safe" >&2
  exit 2
}

# No command → nothing to validate.
[ -z "$COMMAND" ] && exit 0

# cutter's scripts are pre-approved by the skills' allowed-tools (`Bash(cutter-ticket *)` …) and write
# only their own files. A redirection, pipe, chain or substitution would stretch that grant into a write
# or command the user never approved, so a cutter script runs alone. Checked before deferring to a
# project's guard: that guard does not know cutter's grants.
# Claude Code matches a rule against each subcommand of a chain, after stripping `VAR=` assignments and
# wrappers such as `timeout 60`, so a cutter script counts wherever it is in command position.
# shellcheck disable=SC2016  # a literal $( and ` are what is matched
CUTTER_AT_CMD='(^|[;&|({`]|\$\(|'$'\n'')[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|(timeout|time|nice|nohup|stdbuf|command|builtin|noglob|xargs|env|exec)([[:space:]]+(-[^[:space:]]*|[0-9][^[:space:]]*|[A-Z]+))*)[[:space:]]+)*([^[:space:]]*/)?cutter-[a-z]'
# shellcheck disable=SC2016
if [[ "$COMMAND" =~ $CUTTER_AT_CMD ]] &&
  [[ "$COMMAND" == *[\<\>\|\;\&\`]* || "$COMMAND" == *'$('* || "$COMMAND" == *$'\n'* ]]; then
  cat >&2 <<EOF
Blocked by cutter's guard — a cutter script runs alone, one per call, with no redirection,
pipe, chaining or command substitution:
  $COMMAND

The scripts write their own files (cutter-ticket --out writes ticket.md); run the command bare.
EOF
  exit 2
fi

# A project that ships its own guard at .claude/scripts/guard-bash.sh registers it
# in its own settings; defer to it so the two lists cannot disagree.
[ -n "${CLAUDE_PROJECT_DIR-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.claude/scripts/guard-bash.sh" ] && exit 0

# Denylist of regex patterns.
# Each entry is a POSIX extended regex matched case-insensitively.
PATTERNS=(
  # Filesystem destruction
  '\brm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)'
  # Git history rewriting / force pushing
  # --force-with-lease is allowed: it refuses to overwrite work it has not seen.
  '\bgit[[:space:]]+push[[:space:]]+.*(-f\b|--force([[:space:]]|$))'
  '\bgit[[:space:]]+reset[[:space:]]+--hard\b'
  '\bgit[[:space:]]+clean[[:space:]]+.*-[a-zA-Z]*f'
  '\bgit[[:space:]]+checkout[[:space:]]+--[[:space:]]+\.'
  # Package publishing
  '\b(npm|yarn|pnpm|bun)[[:space:]]+publish\b'
  # Disk-level danger
  '>[[:space:]]*/dev/(sda|nvme|disk)'
  '\bdd[[:space:]]+if=.*[[:space:]]+of=/dev/'
)

# Matched case-sensitively: here the case of a flag changes its meaning
# (`git branch -d` deletes a merged branch, `-D` deletes regardless).
CASE_SENSITIVE_PATTERNS=(
  '\bgit[[:space:]]+branch[[:space:]]+(.*[[:space:]])?-[a-zA-Z]*D\b'
)

block() {
  cat >&2 <<EOF
Blocked by cutter's guard — command matches a destructive pattern:
  $COMMAND

Pattern matched: $1

If you genuinely need to run this, ask the user to run it themselves
in chat with the !<command> prefix.
EOF
  exit 2
}

for pat in "${PATTERNS[@]}"; do
  echo "$COMMAND" | grep -iEq -- "$pat" && block "$pat"
done
for pat in "${CASE_SENSITIVE_PATTERNS[@]}"; do
  echo "$COMMAND" | grep -Eq -- "$pat" && block "$pat"
done

exit 0
