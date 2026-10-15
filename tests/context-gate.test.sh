#!/bin/bash
# Self-test for hooks/context-gate.js.
set -uo pipefail
GATE="$(cd "$(dirname "$0")/.." && pwd)/hooks/context-gate.js"
tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT
fail=0

transcript() { # <file> <tokens> [compact-after]
  printf '{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s}}}\n' "$2" >"$1"
  [ -n "${3:-}" ] && printf '{"type":"user","isCompactSummary":true}\n' >>"$1"
  return 0
}
run() { # <prompt> <transcript> [cwd]
  node -e 'process.stdout.write(JSON.stringify({prompt:process.argv[1],transcript_path:process.argv[2],cwd:process.argv[3]}))' "$1" "$2" "${3:-$tmp}" | node "$GATE"
}
check() { # <description> <want: block|pass|warn|warn+block> <prompt> <transcript> [cwd]
  local out got; out="$(run "$3" "$4" "${5:-$tmp}")"
  case "$out" in
    '') got=pass ;;
    *'"decision":"block"'*'"systemMessage":"cutter: '*) got=warn+block ;;
    *'"decision":"block"'*) got=block ;;
    '{"systemMessage":"cutter: '*) got=warn ;;
    *) got=other ;;
  esac
  if [ "$got" = "$2" ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1 (want $2, got: ${out:-nothing})"; fail=1
  fi
}

transcript "$tmp/big.jsonl" 250000
transcript "$tmp/mid.jsonl" 150000
transcript "$tmp/small.jsonl" 50000
transcript "$tmp/compacted.jsonl" 250000 yes

check "blocks /cutter:work on a big context" block "/cutter:work gh-12" "$tmp/big.jsonl"
check "blocks /cutter:close on a big context" block "/cutter:close gh-12" "$tmp/big.jsonl"
check "passes on a small context" pass "/cutter:work gh-12" "$tmp/small.jsonl"
check "default limit is 200k" pass "/cutter:work gh-12" "$tmp/mid.jsonl"
check "passes right after a compaction" pass "/cutter:work gh-12" "$tmp/compacted.jsonl"
check "ignores other prompts" pass "fix the bug" "$tmp/big.jsonl"
check "ignores other skills" pass "/work TASK-1" "$tmp/big.jsonl"
check "passes with no transcript" pass "/cutter:work x" "$tmp/missing.jsonl"
check "passes on a malformed payload" pass "" ""
mkdir -p "$tmp/proj/.claude"
echo '{ "contextGate": { "maxTokens": 300000 } }' >"$tmp/proj/.claude/cutter.json"
check "honours a raised limit" pass "/cutter:work x" "$tmp/big.jsonl" "$tmp/proj"
mkdir -p "$tmp/proj/a/b"
check "honours a raised limit from a subdirectory" pass "/cutter:work x" "$tmp/big.jsonl" "$tmp/proj/a/b"
mkdir -p "$tmp/proj/wt/.claude" "$tmp/proj/wt/sub"
echo '{ "contextGate": { "maxTokens": 100000 } }' >"$tmp/proj/wt/.claude/cutter.json"
transcript "$tmp/110k.jsonl" 110000
check "nearest config wins" block "/cutter:work x" "$tmp/110k.jsonl" "$tmp/proj/wt/sub"
echo '{ "base": "main" }' >"$tmp/proj/wt/.claude/cutter.json"
check "a config without contextGate is final and silent" block "/cutter:work x" "$tmp/big.jsonl" "$tmp/proj/wt/sub"
echo '{ nope' >"$tmp/proj/wt/.claude/cutter.json"
check "warns on a broken config and passes" warn "/cutter:work x" "$tmp/small.jsonl" "$tmp/proj/wt/sub"
echo '{ "contextGate": { "maxTokens": "lots" } }' >"$tmp/proj/wt/.claude/cutter.json"
check "warns on a non-numeric maxTokens and blocks" warn+block "/cutter:close x" "$tmp/big.jsonl" "$tmp/proj/wt/sub"
check "does not warn on other prompts" pass "fix the bug" "$tmp/big.jsonl" "$tmp/proj/wt/sub"
echo '{ "contextGate": { "maxTokens": 0 } }' >"$tmp/proj/.claude/cutter.json"
check "maxTokens 0 turns it off" pass "/cutter:work x" "$tmp/big.jsonl" "$tmp/proj"
if printf 'garbage' | node "$GATE" | grep -q block; then echo "FAIL  garbage input blocked"; fail=1; else echo "ok    garbage input passes"; fi

[ "$fail" -eq 0 ] && echo "context-gate: all cases pass"
exit "$fail"
