#!/bin/bash
# End-to-end test of the bin/ scripts on a throwaway repository with an origin.
# shellcheck disable=SC2015  # `cond && ok || bad` is safe: ok always returns 0
set -uo pipefail
BIN="$(cd "$(dirname "$0")/.." && pwd)/bin"
export PATH="$BIN:$PATH"
fail=0
ok()   { echo "ok    $1"; }
bad()  { echo "FAIL  $1"; fail=1; }
expect() { # <description> <expected-exit> <command...>
  local d=$1 want=$2; shift 2
  "$@" >"$tmp/out" 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then ok "$d"; else bad "$d (want exit $want, got $got)"; sed 's/^/      /' "$tmp/out"; fi
}

tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT
git -c init.defaultBranch=main init -q --bare "$tmp/origin.git"
git -c init.defaultBranch=main init -q "$tmp/repo"
cd "$tmp/repo" || exit 2
git config user.email t@t; git config user.name t
cat >package.json <<'EOF'
{ "name": "fixture", "private": true, "scripts": { "test": "node --test" } }
EOF
mkdir src
echo 'export const add = (a, b) => a + b' >src/math.mjs
git add -A && git commit -qm "init"
git remote add origin "$tmp/origin.git" && git push -q -u origin main

# init: .cutter/ is excluded before anything is written there
expect "init with an id" 0 cutter-worktree init T0
[ "$(cat "$tmp/out")" = "$tmp/repo/.cutter/T0" ] || [ "$(cat "$tmp/out")" = "$(cd "$tmp/repo" && pwd -P)/.cutter/T0" ] && ok "init prints the ticket dir" || bad "init prints the ticket dir"
echo plan >.cutter/T0/plan.md
[ -z "$(git status --porcelain)" ] && ok "ticket files stay out of git before any worktree" || bad "ticket files stay out of git before any worktree"
[ ! -e .cutter/drafts ] && ok "init <id> does not create drafts/" || bad "init <id> does not create drafts/"
expect "init without an id" 0 cutter-worktree init
[ -d .cutter/drafts ] && ok "init creates drafts/" || bad "init creates drafts/"
[ "$(cat "$tmp/out")" = "$tmp/repo/.cutter" ] || [ "$(cat "$tmp/out")" = "$(cd "$tmp/repo" && pwd -P)/.cutter" ] && ok "init prints .cutter" || bad "init prints .cutter"

# worktree
expect "worktree add" 0 cutter-worktree add T1 --slug mul
wt="$tmp/repo/.worktrees/T1"
[ -e "$wt/.git" ] && ok "worktree exists" || bad "worktree exists"
[ "$(git -C "$wt" rev-parse --abbrev-ref HEAD)" = feat/T1-mul ] && ok "branch name" || bad "branch name"
grep -qxF '/.cutter/' .git/info/exclude && grep -qxF '/.worktrees/' .git/info/exclude && ok "excluded locally" || bad "excluded locally"
[ -z "$(git status --porcelain)" ] && ok "main checkout stays clean" || bad "main checkout stays clean"
[ -z "$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" ] && ok "new branch has no upstream" || bad "new branch has no upstream"
expect "worktree add is re-runnable" 0 cutter-worktree add T1
expect "worktree path" 0 cutter-worktree path T1
expect "bad id rejected" 2 cutter-worktree add "../x"

# a change with a real test
echo 'export const mul = (a, b) => a * b' >"$wt/src/mul.mjs"
cat >"$wt/src/mul.test.mjs" <<'EOF'
import { test } from 'node:test'
import assert from 'node:assert'
import { mul } from './mul.mjs'
test('mul', () => assert.equal(mul(2, 3), 6))
EOF
git -C "$wt" add -A && git -C "$wt" commit -qm "feat: add mul"

expect "verify passes" 0 cutter-verify T1
grep -q '^test ' .cutter/T1/verify/summary.txt && ok "verify ran package.json test" || bad "verify ran package.json test"
expect "red-proof: real test goes red" 0 cutter-red-proof T1
grep -q '^RED ' "$tmp/out" && ok "red-proof reports RED" || bad "red-proof reports RED"
[ -z "$(git -C "$wt" status --porcelain)" ] && [ -f "$wt/src/mul.mjs" ] && ok "red-proof restored the tree" || bad "red-proof restored the tree"

# a test that does not test the change
cat >"$wt/src/noop.test.mjs" <<'EOF'
import { test } from 'node:test'
import assert from 'node:assert'
test('noop', () => assert.equal(1, 1))
EOF
echo 'export const sub = (a, b) => a - b' >"$wt/src/sub.mjs"
git -C "$wt" add -A && git -C "$wt" commit -qm "feat: add sub"
expect "red-proof: unrelated test stays green" 1 cutter-red-proof T1
grep -q '^GREEN  src/noop.test.mjs' "$tmp/out" && ok "red-proof names the green file" || bad "red-proof names the green file"

echo dirty >"$wt/scratch.txt"
expect "red-proof refuses a dirty tree" 2 cutter-red-proof T1
expect "verify passes on a dirty tree that stands still" 0 cutter-verify T1
rm "$wt/scratch.txt"

# a failing gate
echo 'export const mul = (a, b) => a + b' >"$wt/src/mul.mjs"
git -C "$wt" commit -qam "break mul"
expect "verify fails on a red test" 1 cutter-verify T1
grep -q FAIL .cutter/T1/verify/summary.txt && ok "summary shows FAIL" || bad "summary shows FAIL"

# config gates
mkdir -p .claude
echo '{ "gates": ["true", "echo gate-two"] }' >.claude/cutter.json
expect "verify uses configured gates" 0 cutter-verify T1
grep -q 'gate-two' .cutter/T1/verify/summary.txt && ok "configured gate listed" || bad "configured gate listed"
echo '{ "gates": ["touch moved.txt"] }' >.claude/cutter.json
expect "verify fails when a gate moves the tree" 1 cutter-verify T1
grep -q '^MOVED' .cutter/T1/verify/summary.txt && ok "summary says MOVED" || bad "summary says MOVED"
rm "$wt/moved.txt"

# review packet
expect "review packet" 0 cutter-review-packet T1
grep -q 'src/mul.mjs' .cutter/T1/review-packet.md && [ -s .cutter/T1/review.diff ] && ok "packet lists changes" || bad "packet lists changes"
grep -q 'gates already ran' .cutter/T1/review-packet.md && ok "packet carries the verify summary" || bad "packet carries the verify summary"

# lock
mkdir .cutter/T1/lock
expect "lock blocks a concurrent run" 2 cutter-verify T1
rmdir .cutter/T1/lock

# remove
expect "rm keeps an unmerged branch" 0 cutter-worktree rm T1
grep -q 'kept branch feat/T1-mul' "$tmp/out" && ok "unmerged branch kept" || bad "unmerged branch kept"
[ ! -e "$wt" ] && ok "worktree gone" || bad "worktree gone"

# a merged branch is deleted on rm (local fast-forward, base not pushed)
expect "worktree add T2" 0 cutter-worktree add T2 --slug T2
[ "$(git -C "$tmp/repo/.worktrees/T2" rev-parse --abbrev-ref HEAD)" = feat/T2 ] && ok "slug equal to id is dropped" || bad "slug equal to id is dropped"
expect "worktree add T4" 0 cutter-worktree add T4 --slug T4-helper --no-setup
[ "$(git -C "$tmp/repo/.worktrees/T4" rev-parse --abbrev-ref HEAD)" = feat/T4-helper ] && ok "slug starting with the id is not doubled" || bad "slug starting with the id is not doubled"
expect "rm T4" 0 cutter-worktree rm T4
echo 'export const one = 1' >"$tmp/repo/.worktrees/T2/src/one.mjs"
git -C "$tmp/repo/.worktrees/T2" add -A && git -C "$tmp/repo/.worktrees/T2" commit -qm "feat: one"
git merge -q --ff-only feat/T2
expect "rm after a local merge" 0 cutter-worktree rm T2
grep -q 'deleted branch feat/T2' "$tmp/out" && ok "merged branch deleted" || bad "merged branch deleted"

# a squash-merged PR: git does not call the branch merged, but its changes are on origin/main
expect "worktree add T3" 0 cutter-worktree add T3
wt3="$tmp/repo/.worktrees/T3"
printf 'export const two = 2\n' >"$wt3/src/two.mjs"
git -C "$wt3" add -A && git -C "$wt3" commit -qm "feat: two (1/2)"
printf 'export const two = 2\nexport const three = 3\n' >"$wt3/src/two.mjs"
git -C "$wt3" commit -qam "feat: two (2/2)"
git -C "$wt3" push -q origin feat/T3
git push -q origin main
git merge -q --squash feat/T3 && git commit -qm "feat: two (#3)" && git push -q origin main
expect "rm after a squash merge" 0 cutter-worktree rm T3
grep -q 'deleted branch feat/T3 (its changes are on origin/main)' "$tmp/out" && ok "squash-merged branch deleted" || bad "squash-merged branch deleted"
[ -z "$(git ls-remote --heads origin feat/T3)" ] && ok "merged remote branch deleted" || bad "merged remote branch deleted"

[ "$fail" -eq 0 ] && echo "scripts: all cases pass"
exit "$fail"
