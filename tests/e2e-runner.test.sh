#!/bin/bash
# Self-test for tests/e2e/run.sh with a stub `claude` (CUTTER_E2E_CLAUDE): no model is called.
# The stub writes $STUB_STREAM (canned stream-json) to stdout and, when $STUB_RUN is set, runs that script first
# (to call the fake gh or not). Real scenario ids drive the runner: 3 is the one-turn duplicate-issue flow.
# Cases: unknown ids exit 2 before any claude run; a permission denial is reported with its command; a gh call in the
# tool log that the fake never saw fails the flow; a plugin without bin/cutter-land fails before claude runs; a
# failing scenario makes the exit code non-zero.
# shellcheck disable=SC2015,SC2016  # `cond && ok || bad` is safe: ok always returns 0; $HOME is literal command text
set -uo pipefail
RUN_SH="$(cd "$(dirname "$0")" && pwd)/e2e/run.sh"
fail=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=1; }

tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT

cat >"$tmp/claude" <<'STUB'
#!/bin/bash
echo run >>"$STUB_MARK"
if [ -n "${STUB_RUN:-}" ]; then bash "$STUB_RUN" >/dev/null 2>&1; fi
cat "$STUB_STREAM"
STUB
chmod +x "$tmp/claude"

# A stream whose one Bash call is `gh issue list`, with an optional denial of another command.
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"gh issue list --state open --search greet"}}]}}' \
  '{"type":"result","subtype":"success","permission_denials":[],"total_cost_usd":0.01,"duration_ms":10}' >"$tmp/stream-ok"
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"echo $HOME"}}]}}' \
  '{"type":"result","subtype":"success","permission_denials":[{"tool_name":"Bash","tool_use_id":"t2","tool_input":{"command":"echo $HOME"}}],"total_cost_usd":0.01,"duration_ms":10}' >"$tmp/stream-denied"
printf '%s\n' '#!/bin/bash' 'gh issue list --state open --search greet' >"$tmp/calls-gh"
mkdir -p "$tmp/plugin/bin"

# runner <expected exit> <description> <env...> -- <args...>; leaves the output in $tmp/out and the stub's runs in $tmp/mark.
runner() {
  local want="$1" what="$2" got
  shift 2
  local envs=()
  while [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  : >"$tmp/mark"
  env "CUTTER_E2E_CLAUDE=$tmp/claude" "STUB_MARK=$tmp/mark" ${envs[@]+"${envs[@]}"} bash "$RUN_SH" "$@" >"$tmp/out" 2>"$tmp/err"
  got=$?
  if [ "$got" -ne "$want" ]; then bad "$what (want exit $want, got $got)"; sed 's/^/      /' "$tmp/out" "$tmp/err"; return 1; fi
}
line_matches() { grep -Eq -- "$1" "$tmp/out"; }

# unknown ids
if runner 2 "unknown scenario id exits 2" -- 99; then
  [ ! -s "$tmp/mark" ] && grep -q "unknown scenario id '99'" "$tmp/err" && ok "unknown scenario id exits 2" || bad "unknown scenario id exits 2 (claude ran or no message)"
fi
if runner 2 "ids are case-sensitive" -- o1; then
  [ ! -s "$tmp/mark" ] && ok "ids are case-sensitive: o1 exits 2" || bad "ids are case-sensitive: o1 exits 2 (claude ran)"
fi
if runner 2 "one unknown id among known ones" -- 3 W9; then
  [ ! -s "$tmp/out" ] && [ ! -s "$tmp/mark" ] && ok "an unknown id exits 2 before any scenario runs" || bad "an unknown id exits 2 before any scenario runs"
fi

# control: the gh call is in the fake's log, no denial
if runner 0 "a clean run exits 0" "STUB_STREAM=$tmp/stream-ok" "STUB_RUN=$tmp/calls-gh" -- 3; then
  [ "$(grep -c . "$tmp/out")" = 2 ] && line_matches '^pass  3  [0-9]+s$' && line_matches '^total [0-9]+s$' && ok "a clean run prints one pass line and the total, exit 0" || { bad "a clean run prints one pass line and the total"; sed 's/^/      /' "$tmp/out"; }
fi

# denial
if runner 1 "a permission denial fails the flow" "STUB_STREAM=$tmp/stream-denied" "STUB_RUN=$tmp/calls-gh" -- 3; then
  line_matches '^FAIL  3  [0-9]+s  .*permission denied: echo \$HOME' && ok "a permission denial fails the flow and names the command; a failing scenario makes the exit code non-zero" || { bad "a permission denial fails the flow and names the command"; sed 's/^/      /' "$tmp/out"; }
fi

# a gh call the fake never saw
if runner 1 "a gh call missing from the fake log fails" "STUB_STREAM=$tmp/stream-ok" -- 3; then
  line_matches "^FAIL  3  [0-9]+s  .*tool log has 1 'gh issue list' calls, the fake gh saw 0" && ok "a gh call missing from the fake log fails the flow" || { bad "a gh call missing from the fake log fails the flow"; sed 's/^/      /' "$tmp/out"; }
fi

# the plugin under test has no bin/cutter-land
if runner 1 "a plugin without cutter-land fails" "STUB_STREAM=$tmp/stream-ok" "STUB_RUN=$tmp/calls-gh" "CUTTER_E2E_PLUGIN=$tmp/plugin" -- 3; then
  line_matches '^FAIL  3  [0-9]+s  .*cutter-land resolves to' && [ ! -s "$tmp/mark" ] && ok "cutter-land outside the plugin under test fails the flow before claude runs" || { bad "cutter-land outside the plugin under test fails the flow before claude runs"; sed 's/^/      /' "$tmp/out"; }
fi

[ "$fail" -eq 0 ] && echo "e2e-runner: all cases pass"
exit "$fail"
