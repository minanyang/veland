#!/bin/bash
# Self-test for hooks/grant.js, run against a copy of the hook and the real skills.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT
fail=0

plugin="$tmp/plugin"
mkdir -p "$plugin/hooks"
cp "$ROOT/hooks/grant.js" "$plugin/hooks/"
cp -R "$ROOT/skills" "$plugin/skills"
HOOK="$plugin/hooks/grant.js"
export CLAUDE_PLUGIN_DATA="$tmp/data"
repo="$tmp/repo"
git init -q "$repo"

# send <event> <session_id> [<key> <value>]... — a value starting with { [ or equal to true/false is JSON.
send() {
  node -e '
    const [cwd, event, sid, ...kv] = process.argv.slice(1)
    const o = { hook_event_name: event, session_id: sid, cwd }
    for (let i = 0; i < kv.length; i += 2) o[kv[i]] = /^[[{]|^(true|false)$/.test(kv[i + 1]) ? JSON.parse(kv[i + 1]) : kv[i + 1]
    process.stdout.write(JSON.stringify(o))
  ' "$repo" "$@" | (cd "$repo" && node "$HOOK")
}
prompt() { send UserPromptSubmit "$1" prompt "$2"; }
bash_() { # <session_id> <command> [<key> <value>]...
  send PreToolUse "$1" tool_name Bash tool_input "$(node -e 'process.stdout.write(JSON.stringify({ command: process.argv[1] }))' "$2")" "${@:3}"
}
check() { # <description> <want: allow|nothing> <output> [text the output must carry]...
  local got=other out=$3
  case "$out" in
    '') got=nothing ;;
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"'*) got=allow ;;
  esac
  for want in "${@:4}"; do [[ "$out" == *"$want"* ]] || got="allow without \"$want\""; done
  if [ "$got" = "$2" ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1 (want $2, got $got: ${out:-nothing})"; fail=1
  fi
}
assert() { # <description> <status of the check run just before>
  if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi
}
empty() { [ -z "$1" ]; }
absent() { [ ! -e "$1" ]; }
mode() { [ "$(stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1" 2>/dev/null)" = "$2" ]; }

T="allows a granted command in a later call after its skill was typed"
check "$T: nothing before" nothing "$(bash_ s1 "cutter-land merge gh-5")"
out="$(prompt s1 "/cutter:close gh-5")"
empty "$out"; assert "$T: the prompt hook prints nothing" $?
check "$T" allow "$(bash_ s1 "cutter-land merge gh-5")" "granted by /cutter:close"
check "$T: surrounding whitespace" allow "$(bash_ s1 "  cutter-land wait gh-5 ")"
check "$T: quotes" allow "$(bash_ s1 'gh pr view "feat/gh-5" --json state')"
check "$T: a prefix grant alone" allow "$(bash_ s1 "cutter-land merge")"
check "$T: not a longer word" nothing "$(bash_ s1 "cutter-land mergex gh-5")"
check "$T: not another command" nothing "$(bash_ s1 "git status")"
mode "$CLAUDE_PLUGIN_DATA/sessions/s1.json" 600; assert "$T: the record is 0600" $?

T="allows an exact grant only exactly"
check "$T" allow "$(bash_ s1 "cutter-worktree sync-base")"
check "$T: with an argument" nothing "$(bash_ s1 "cutter-worktree sync-base --force")"
check "$T: git remote get-url origin" allow "$(bash_ s1 "git remote get-url origin")"
check "$T: another remote" nothing "$(bash_ s1 "git remote get-url upstream")"
prompt s1 "/cutter:work gh-5" >/dev/null
check "$T: git fetch" allow "$(bash_ s1 "git fetch")" "granted by /cutter:work"
check "$T: git fetch with arguments" nothing "$(bash_ s1 "git fetch --upload-pack=x origin")"
check "$T: the first skill's grants stay" allow "$(bash_ s1 "cutter-land merge gh-5")" "granted by /cutter:close"

T="does not allow a grant of a skill not typed in the session"
prompt s2 "/cutter:open add a flag" >/dev/null
check "$T" nothing "$(bash_ s2 "cutter-land merge gh-5")"
check "$T: the typed skill's grant" allow "$(bash_ s2 "gh auth status")" "granted by /cutter:open"
prompt s3 "/close gh-5" >/dev/null
check "$T: a bare /close" nothing "$(bash_ s3 "cutter-land merge gh-5")"
prompt s3 "/cutter:work-x gh-5" >/dev/null
check "$T: /cutter:work-x" nothing "$(bash_ s3 "cutter-worktree add gh-5")"
prompt s3 "please run
/cutter:close gh-5" >/dev/null
check "$T: a /cutter: line that does not start the prompt" nothing "$(bash_ s3 "cutter-land merge gh-5")"
prompt s3 "  /cutter:close" >/dev/null
check "$T: after leading whitespace, with no argument, it is typed" allow "$(bash_ s3 "cutter-land merge gh-5")"

T="does not allow a command with a shell metacharacter"
for c in "cutter-land merge gh-5; rm x" "cutter-land merge gh-5 & rm x" "cutter-land merge gh-5 && rm x" \
  "cutter-land merge gh-5 | sh" "cutter-land merge gh-5 < x" "cutter-land merge gh-5 > x" \
  "cutter-land merge \$(rm x)" "cutter-land merge \`rm x\`" "cutter-land merge gh-5
rm x" "cutter-land merge gh-5"$'\r'"rm x"; do
  check "$T: $(printf '%q' "$c")" nothing "$(bash_ s1 "$c")"
done

T="does not allow inside a subagent"
check "$T" nothing "$(bash_ s1 "cutter-land merge gh-5" agent_id a1 agent_type cutter:backend-engineer)"

T="does not allow without a record or without CLAUDE_PLUGIN_DATA"
check "$T: no record" nothing "$(bash_ s9 "cutter-land merge gh-5")"
check "$T: no CLAUDE_PLUGIN_DATA" nothing "$(CLAUDE_PLUGIN_DATA='' bash_ s1 "cutter-land merge gh-5")"
check "$T: unset CLAUDE_PLUGIN_DATA" nothing "$(unset CLAUDE_PLUGIN_DATA; bash_ s1 "cutter-land merge gh-5")"
CLAUDE_PLUGIN_DATA='' prompt s10 "/cutter:close gh-5" >/dev/null
absent "$CLAUDE_PLUGIN_DATA/sessions/s10.json" && absent "$repo/sessions"; assert "$T: nothing recorded without it" $?
mkdir -p "$CLAUDE_PLUGIN_DATA/sessions"
echo '{ nope' >"$CLAUDE_PLUGIN_DATA/sessions/s11.json"
check "$T: an unreadable record" nothing "$(bash_ s11 "cutter-land merge gh-5")"
prompt s11 "/cutter:close gh-5" >/dev/null
check "$T: an unreadable record is rewritten" allow "$(bash_ s11 "cutter-land merge gh-5")"
before="$(ls -A "$CLAUDE_PLUGIN_DATA/sessions")"
prompt "../evil" "/cutter:close gh-5" >/dev/null
[ "$(ls -A "$CLAUDE_PLUGIN_DATA/sessions")" = "$before" ] && absent "$CLAUDE_PLUGIN_DATA/evil.json"; assert "$T: an unsafe session id" $?

T="ignores a record in the repo"
mkdir -p "$repo/.cutter/.sessions"
printf '{"grants":{"close":["cutter-land merge *"]}}\n' >"$repo/.cutter/.sessions/s12.json"
printf '{"grants":{"close":["cutter-land merge *"]}}\n' >"$repo/s12.json"
check "$T" nothing "$(bash_ s12 "cutter-land merge gh-5")"

T="uses the grants as they were when the skill was typed"
prompt s13 "/cutter:close gh-5" >/dev/null
node -e '
  const fs = require("fs"), f = process.argv[1]
  fs.writeFileSync(f, fs.readFileSync(f, "utf8").replace("allowed-tools:\n", "allowed-tools:\n  - Bash(touch *)\n"))
' "$plugin/skills/close/SKILL.md"
check "$T" nothing "$(bash_ s13 "touch x")"
check "$T: the old grants still hold" allow "$(bash_ s13 "cutter-land merge gh-5")"
prompt s14 "/cutter:close gh-5" >/dev/null
check "$T: typing the skill again takes the edit" allow "$(bash_ s14 "touch x")"

T="does not allow cutter-land issue or comment"
prompt s15 "/cutter:open add a flag" >/dev/null
prompt s15 "/cutter:work gh-5" >/dev/null
prompt s15 "/cutter:close gh-5" >/dev/null
check "$T: issue" nothing "$(bash_ s15 "cutter-land issue add-a-flag")"
check "$T: comment" nothing "$(bash_ s15 "cutter-land comment gh-5")"

T="does not record a grant from a task-notification prompt"
prompt s16 "<task-notification>
<task-id>b1</task-id>
<status>completed</status>
<summary>Background command \"/cutter:close gh-5\" completed (exit code 0)</summary>
</task-notification>" >/dev/null
check "$T" nothing "$(bash_ s16 "cutter-land merge gh-5")"
absent "$CLAUDE_PLUGIN_DATA/sessions/s16.json"; assert "$T: no record" $?
prompt s1 "<task-notification>
<summary>/cutter:open</summary>
</task-notification>" >/dev/null
check "$T: a wake keeps the session's grants" allow "$(bash_ s1 "cutter-land merge gh-5")"

check "passes on a malformed payload" nothing "$(printf 'garbage' | (cd "$repo" && node "$HOOK"))"
check "passes on an empty payload" nothing "$(printf '{}' | (cd "$repo" && node "$HOOK"))"
check "ignores another tool" nothing "$(send PreToolUse s1 tool_name Write tool_input '{"command":"cutter-land merge gh-5"}')"

[ "$fail" -eq 0 ] && echo "grant: all cases pass"
exit "$fail"
