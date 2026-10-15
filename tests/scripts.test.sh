#!/bin/bash
# End-to-end test of the bin/ scripts on a throwaway repository with an origin.
# shellcheck disable=SC2015,SC2016  # `cond && ok || bad` is safe: ok always returns 0; backticks in patterns are literal Markdown
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
head=$(git -C "$wt" rev-parse HEAD)
expect "red-proof refuses a test that fails at HEAD" 2 cutter-red-proof T1
grep -q 'src/mul.test.mjs: fails' "$tmp/out" && ok "red-proof names the file failing at HEAD" || bad "red-proof names the file failing at HEAD"
[ -z "$(git -C "$wt" status --porcelain)" ] && [ "$(git -C "$wt" rev-parse HEAD)" = "$head" ] && ok "tree untouched after the HEAD refusal" || bad "tree untouched after the HEAD refusal"

# a runner red-proof does not detect (mocha globals) falls through to node --test and cannot pass at HEAD
expect "worktree add T5" 0 cutter-worktree add T5 --no-setup
wt5="$tmp/repo/.worktrees/T5"
echo 'export const div = (a, b) => a / b' >"$wt5/src/div.mjs"
cat >"$wt5/src/div.test.mjs" <<'EOF'
import assert from 'node:assert'
import { div } from './div.mjs'
describe('div', () => { it('divides', () => assert.equal(div(6, 3), 2)) })
EOF
git -C "$wt5" add -A && git -C "$wt5" commit -qm "feat: add div"
expect "red-proof refuses an unsupported runner" 2 cutter-red-proof T5
grep -q 'src/div.test.mjs: fails' "$tmp/out" && ok "red-proof names the unsupported file" || bad "red-proof names the unsupported file"
[ -z "$(git -C "$wt5" status --porcelain)" ] && [ -f "$wt5/src/div.mjs" ] && ok "tree untouched for an unsupported runner" || bad "tree untouched for an unsupported runner"
expect "rm T5" 0 cutter-worktree rm T5

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
[ "$(cat .cutter/T1/review-head)" = "$(git -C "$wt" rev-parse HEAD)" ] && ok "packet records the reviewed head" || bad "packet records the reviewed head"

# fixes packet: only the commits since the reviewed head, with round 1's findings
expect "fixes packet refuses without review.md" 2 cutter-review-packet T1 --fixes
printf '# T1 — review\n\n- [minor] round-one-finding\n\n## Fixes applied\n\n- implementer-account\n' >.cutter/T1/review.md
expect "fixes packet with no fix commits" 3 cutter-review-packet T1 --fixes
[ ! -e .cutter/T1/fixes-packet.md ] && ok "no fixes packet without fix commits" || bad "no fixes packet without fix commits"
echo 'export const sq = (a) => a * a' >"$wt/src/sq.mjs"
git -C "$wt" add src/sq.mjs && git -C "$wt" commit -qm "fix: add sq"
expect "fixes packet" 0 cutter-review-packet T1 --fixes
grep -q 'src/sq.mjs' .cutter/T1/fixes.diff && ! grep -q 'src/mul.mjs' .cutter/T1/fixes.diff && ok "fixes diff holds only the fix commits" || bad "fixes diff holds only the fix commits"
grep -q 'round-one-finding' .cutter/T1/fixes-packet.md && ok "fixes packet carries round 1's findings" || bad "fixes packet carries round 1's findings"
! grep -q 'implementer-account' .cutter/T1/fixes-packet.md && ok "fixes packet leaves out Fixes applied" || bad "fixes packet leaves out Fixes applied"
grep -q 'src/mul.mjs' .cutter/T1/review.diff && ok "round 1 diff kept" || bad "round 1 diff kept"
expect "packet rejects an unknown flag" 2 cutter-review-packet T1 --nope
git -C "$wt" rev-parse HEAD >.cutter/T1/review-head
git -C "$wt" commit -q --amend -m "fix: add sq (amended)"
expect "fixes packet off a rewritten history" 2 cutter-review-packet T1 --fixes

# lock
mkdir .cutter/T1/lock
expect "lock blocks a concurrent run" 2 cutter-verify T1
rmdir .cutter/T1/lock

# gates come from the ticket's worktree; changes against the base's list are reported
echo '{ "gates": ["echo gate-base", "echo gate-kept"] }' >.claude/cutter.json
git add .claude/cutter.json && git commit -qm "chore: gates" && git push -q origin main
expect "worktree add T7" 0 cutter-worktree add T7 --no-setup
wt7="$tmp/repo/.worktrees/T7"
echo '{ "base": "nope", "gates": ["echo gate-kept", "echo gate-added"] }' >"$wt7/.claude/cutter.json"
git -C "$wt7" commit -qam "chore: change gates"
expect "verify with the worktree's gates" 0 cutter-verify T7
s7=.cutter/T7/verify/summary.txt
grep -q '^echo gate-added ' "$s7" && ok "gate added in the worktree runs" || bad "gate added in the worktree runs"
! grep -q '^echo gate-base ' "$s7" && ok "gate removed in the worktree does not run" || bad "gate removed in the worktree does not run"
grep -qxF 'gates differ from origin/main:' "$s7" && ok "difference reported against the main checkout's base" || bad "difference reported against the main checkout's base"
grep -qxF '  + echo gate-added' "$s7" && grep -qxF '  - echo gate-base' "$s7" && ok "added and removed gates listed" || bad "added and removed gates listed"
! grep -q 'gate-kept' <(grep '^  [+-] ' "$s7") && ok "kept gate not listed" || bad "kept gate not listed"
echo '{ "gates": ["echo gate-base", "echo gate-kept", "echo gate-later"] }' >.claude/cutter.json
git commit -qam "chore: base gains a gate" && git push -q origin main
expect "verify after the base gained a gate" 0 cutter-verify T7
! grep -q 'gate-later' "$s7" && ok "gate added on the base after the cut not listed" || bad "gate added on the base after the cut not listed"
echo '{ "gates": ["echo gate-kept", "echo gate-base"] }' >"$wt7/.claude/cutter.json"
git -C "$wt7" commit -qam "chore: reorder gates"
expect "verify with reordered gates" 0 cutter-verify T7
! grep -q '^gates differ' "$s7" && ok "same gates in another order: no report" || bad "same gates in another order: no report"
expect "rm T7" 0 cutter-worktree rm T7
git rm -q .claude/cutter.json && git commit -qm "chore: drop gates" && git push -q origin main

# on cutter itself, verify lists the worktree's bin/ and scripts/ files that differ from the running copy
git -c init.defaultBranch=main init -q --bare "$tmp/self-origin.git"
git -c init.defaultBranch=main init -q "$tmp/self"
cd "$tmp/self" || exit 2
git config user.email t@t; git config user.name t
mkdir -p .claude-plugin .claude
echo '{ "name": "cutter" }' >.claude-plugin/plugin.json
echo '{ "gates": ["echo gate-self"] }' >.claude/cutter.json
cp -R "$BIN" bin && cp -R "$BIN/../scripts" scripts
git add -A && git commit -qm "init" && git remote add origin "$tmp/self-origin.git" && git push -q -u origin main
expect "worktree add on cutter itself" 0 cutter-worktree add S1 --no-setup
wts="$tmp/self/.worktrees/S1"
ss=.cutter/S1/verify/summary.txt
expect "verify with identical scripts" 0 cutter-verify S1
! grep -q '^scripts differ' "$ss" && ok "identical scripts: no report" || bad "identical scripts: no report"
echo '# changed' >>"$wts/bin/cutter-verify"; echo '# changed' >>"$wts/scripts/lib.sh"; echo '#!/bin/bash' >"$wts/bin/cutter-extra"
git -C "$wts" add -A && git -C "$wts" commit -qm "feat: change scripts"
expect "verify with changed scripts" 0 cutter-verify S1
grep -q '^scripts differ from the running copy (.*):$' "$ss" && ok "changed scripts reported" || bad "changed scripts reported"
[ "$(grep '^  [a-z]' "$ss")" = "$(printf '  bin/cutter-extra\n  bin/cutter-verify\n  scripts/lib.sh')" ] &&
  ok "changed, added and lib files listed, sorted" || { bad "changed, added and lib files listed, sorted"; cat "$ss"; }
grep -q '^echo gate-self .*pass' "$ss" && ok "gates still run with the report" || bad "gates still run with the report"
echo '{ "name": "other" }' >"$wts/.claude-plugin/plugin.json"
git -C "$wts" commit -qam "chore: another plugin"
expect "verify on another plugin" 0 cutter-verify S1
! grep -q '^scripts differ' "$ss" && ok "another plugin's name: no report" || bad "another plugin's name: no report"
echo '{ broken' >"$wts/.claude-plugin/plugin.json"
git -C "$wts" commit -qam "chore: broken plugin.json"
expect "verify with a broken plugin.json" 0 cutter-verify S1
! grep -q '^scripts differ' "$ss" && ok "broken plugin.json: no report" || bad "broken plugin.json: no report"
cd "$tmp/repo" || exit 2

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

# rm never forces: a worktree with uncommitted changes stays
expect "worktree add T6" 0 cutter-worktree add T6 --no-setup
echo wip >"$tmp/repo/.worktrees/T6/wip.txt"
expect "rm refuses uncommitted changes" 2 cutter-worktree rm T6
expect "rm --force is refused" 2 cutter-worktree rm T6 --force
[ -e "$tmp/repo/.worktrees/T6/wip.txt" ] && ok "rm keeps the dirty worktree" || bad "rm keeps the dirty worktree"
rm "$tmp/repo/.worktrees/T6/wip.txt"
expect "rm T6" 0 cutter-worktree rm T6

# cutter-land, on its own repo (origin path contains github.com so the host is detected)
mkdir -p "$tmp/github.com" "$tmp/stub"
git -c init.defaultBranch=main init -q --bare "$tmp/github.com/land.git"
git -c init.defaultBranch=main init -q "$tmp/land"
cd "$tmp/land" || exit 2
git config user.email t@t; git config user.name t
echo base >f.txt; echo one >g.txt
git add -A && git commit -qm "init"
git remote add origin "$tmp/github.com/land.git" && git push -q -u origin main
cat >"$tmp/stub/gh" <<'STUB'
#!/bin/bash
echo "$*" >>"$STUB_LOG"
case "$*" in *headRefOid*) echo "${STUB_CHECKS-}"; exit 0 ;; esac
case "$1 $2" in
  "pr view"|"mr view") echo "${STUB_VIEW-}"; exit "${STUB_VIEW_RC:-0}" ;;
  "label list") printf '%s\n' "${STUB_LABELS-}" ;;
  "issue view") echo '{"number":7,"title":"T","body":"b","url":"https://github.com/acme/land/issues/7","state":"OPEN","labels":[],"issueType":null,"comments":[]}' ;;
esac
exit 0
STUB
cp "$tmp/stub/gh" "$tmp/stub/glab"; chmod +x "$tmp/stub/gh" "$tmp/stub/glab"
export STUB_LOG="$tmp/stub.log"
cutter-worktree add L1 --no-setup >/dev/null
lw="$tmp/land/.worktrees/L1"

expect "check on a clean worktree" 0 cutter-land check L1
echo dirty >"$lw/new.txt"
expect "check on a dirty worktree" 1 cutter-land check L1
grep -q 'new.txt' "$tmp/out" && ok "check lists the files" || bad "check lists the files"
rm "$lw/new.txt"
expect "land rejects extra arguments" 2 cutter-land push L1 --force
expect "land rejects unknown subcommand" 2 cutter-land nuke L1

echo feature >"$lw/feature.txt"; git -C "$lw" add -A; git -C "$lw" commit -qm "feat: feature"
expect "push first time" 0 cutter-land push L1
[ -n "$(git ls-remote --heads origin feat/L1)" ] && ok "branch on origin" || bad "branch on origin"
# a conflicting rebase is left in progress and lists the file
cutter-worktree add LC --no-setup >/dev/null
lc="$tmp/land/.worktrees/LC"
echo ticket >"$lc/f.txt"; git -C "$lc" commit -qam "feat: ticket edits f"
echo upstream >f.txt; git commit -qam "chore: upstream edits f"; git push -q origin main
expect "rebase conflict" 1 cutter-land rebase LC
grep -q 'f.txt' "$tmp/out" && ok "conflict lists the file" || bad "conflict lists the file"
[ -e "$(git -C "$lc" rev-parse --git-path rebase-merge)" ] && ok "rebase left in progress" || bad "rebase left in progress"
git -C "$lc" rebase --abort
# the base moves, then the branch is rebased and pushed again
echo moved >>f.txt; git commit -qam "chore: move base"; git push -q origin main
expect "rebase onto the moved base" 0 cutter-land rebase L1
git -C "$lw" merge-base --is-ancestor origin/main HEAD && ok "branch contains the new base" || bad "branch contains the new base"
expect "push after a rebase (lease)" 0 cutter-land push L1
[ "$(git ls-remote --heads origin feat/L1 | cut -f1)" = "$(git -C "$lw" rev-parse HEAD)" ] && ok "origin has the rebased branch" || bad "origin has the rebased branch"
# a push URL naming another repo is refused before anything is pushed; the same repo in another form is not
git init -q --bare "$tmp/other.git"
echo more >"$lw/more.txt"; git -C "$lw" add -A; git -C "$lw" commit -qm "feat: more"
o_before="$(git ls-remote origin)"
git config remote.origin.pushurl "$tmp/other.git"
expect "push refuses a push URL to another repo" 2 cutter-land push L1
grep -qF "$tmp/other.git" "$tmp/out" && grep -qF "$tmp/github.com/land.git" "$tmp/out" && ok "refusal names both URLs" || bad "refusal names both URLs"
[ "$(git ls-remote origin)" = "$o_before" ] && [ -z "$(git ls-remote "$tmp/other.git")" ] && ok "mismatched push URL left both repos untouched" || bad "mismatched push URL left both repos untouched"
git config remote.origin.pushurl "file://$tmp/github.com/land.git/"
expect "push allows the same repo in another form" 0 cutter-land push L1
[ "$(git ls-remote --heads origin feat/L1 | cut -f1)" = "$(git -C "$lw" rev-parse HEAD)" ] && ok "pushed through the equivalent push URL" || bad "pushed through the equivalent push URL"
git config --unset remote.origin.pushurl
mkdir -p .claude && echo '{"base":"feat/L1"}' >.claude/cutter.json
expect "push refuses the base branch" 2 cutter-land push L1
rm -r .claude

# a branch name with a leading + (a forced refspec) is refused by push and squash, origin and base untouched
git -C "$tmp/land" branch '+feat/EVIL' main
git -C "$tmp/land" worktree add -q "$tmp/land/.worktrees/EVIL" '+feat/EVIL'
o_before="$(git ls-remote origin)"; b_before="$(git rev-parse main)"
expect "push refuses a +branch" 2 cutter-land push EVIL
expect "squash refuses a +branch" 2 cutter-land squash EVIL
[ "$(git ls-remote origin)" = "$o_before" ] && [ "$(git rev-parse main)" = "$b_before" ] && ok "+branch left origin and base untouched" || bad "+branch left origin and base untouched"
expect "add refuses a bad --type" 2 cutter-worktree add L9 --type '+feat' --no-setup
expect "add refuses a bad --slug" 2 cutter-worktree add L9 --slug 'a:b' --no-setup
expect "add refuses a slug with a slash" 2 cutter-worktree add L9 --slug 'a/b' --no-setup

# merge: only `pr merge <branch> --squash`, only into the configured base, pinned to origin's repo, never a fork's PR
: >"$tmp/stub.log"
export PATH="$tmp/stub:$PATH"
git remote set-url origin git@github.com:acme/land.git
STUB_VIEW="develop OPEN false" expect "merge refuses a PR into another base" 2 cutter-land merge L1
! grep -q 'pr merge' "$tmp/stub.log" && ok "no merge call for a wrong base" || bad "no merge call for a wrong base"
STUB_VIEW="main OPEN true" expect "merge refuses a fork's PR" 2 cutter-land merge L1
! grep -q 'pr merge' "$tmp/stub.log" && ok "no merge call for a fork's PR" || bad "no merge call for a fork's PR"
lwsha="$(git -C "$lw" rev-parse HEAD)"
checks() { printf '{"headRefOid":"%s","statusCheckRollup":%s}' "$lwsha" "$1"; }
STUB_CHECKS="$(checks '[]')"; export STUB_CHECKS
STUB_VIEW="main OPEN false" expect "merge" 0 cutter-land merge L1
grep -qxF 'pr view feat/L1 --repo github.com/acme/land --json baseRefName,state,isCrossRepository --jq .baseRefName + " " + .state + " " + (.isCrossRepository | tostring)' "$tmp/stub.log" && ok "gh pr view pinned to origin's repo" || bad "gh pr view pinned to origin's repo"
grep -qxF 'pr merge feat/L1 --repo github.com/acme/land --squash --match-head-commit '"$lwsha" "$tmp/stub.log" && ok "gh called with pr merge <branch> --repo <o/r> --squash --match-head-commit <sha>" || bad "gh called with pr merge <branch> --repo <o/r> --squash --match-head-commit <sha>"
# merge: the PR's checks on the verified head must be green
merge_checks() { # <description> <exit> <rollup json> — the merge call is made only on exit 0
  : >"$tmp/stub.log"
  STUB_VIEW="main OPEN false" STUB_CHECKS="$(checks "$3")" expect "merge: $1" "$2" cutter-land merge L1
  if [ "$2" -eq 0 ]; then grep -q 'pr merge' "$tmp/stub.log" && ok "merge: $1: merge called" || bad "merge: $1: merge called"
  else ! grep -q 'pr merge' "$tmp/stub.log" && ok "merge: $1: no merge call" || bad "merge: $1: no merge call"; fi
}
merge_checks "all checks green" 0 '[{"__typename":"CheckRun","name":"gates (ubuntu-latest)","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"legacy","state":"SUCCESS"}]'
merge_checks "a failed check" 2 '[{"__typename":"CheckRun","name":"gates (ubuntu-latest)","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"gates (macos-latest)","status":"COMPLETED","conclusion":"FAILURE"}]'
grep -q 'gates (macos-latest): FAILURE' "$tmp/out" && ok "merge: names the failed check" || bad "merge: names the failed check"
merge_checks "a check in progress" 2 '[{"__typename":"CheckRun","name":"gates (macos-latest)","status":"IN_PROGRESS","conclusion":""}]'
grep -q 'gates (macos-latest): IN_PROGRESS' "$tmp/out" && ok "merge: names the pending check" || bad "merge: names the pending check"
merge_checks "a pending status context" 2 '[{"__typename":"StatusContext","context":"legacy","state":"PENDING"}]'
grep -q 'legacy: PENDING' "$tmp/out" && ok "merge: names the pending context" || bad "merge: names the pending context"
merge_checks "a failed status context" 2 '[{"__typename":"StatusContext","context":"legacy","state":"ERROR"}]'
merge_checks "neutral and skipped checks" 0 '[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"NEUTRAL"},{"__typename":"CheckRun","name":"b","status":"COMPLETED","conclusion":"SKIPPED"}]'
: >"$tmp/stub.log"
STUB_VIEW="main OPEN false" STUB_CHECKS='{"headRefOid":"0000000000000000000000000000000000000000","statusCheckRollup":[]}' expect "merge: PR head is not the worktree's HEAD" 2 cutter-land merge L1
grep -q 'push first' "$tmp/out" && ! grep -q 'pr merge' "$tmp/stub.log" && ok "merge: says push first, no merge call" || bad "merge: says push first, no merge call"
merge_checks "no checks, no workflow file" 0 '[]'
mkdir -p "$lw/.github/workflows"
printf 'on:\n  pull_request:\n' >"$lw/.github/workflows/ci.yml"
git -C "$lw" add -A && git -C "$lw" commit -qm "ci: workflow"
lwsha="$(git -C "$lw" rev-parse HEAD)"
merge_checks "no checks, a pull_request workflow on the branch" 2 '[]'
grep -q 'still pending' "$tmp/out" && ok "merge: no checks yet is still pending" || bad "merge: no checks yet is still pending"
printf 'on:\n  push:\n' >"$lw/.github/workflows/ci.yml"
git -C "$lw" commit -qam "ci: push only"
lwsha="$(git -C "$lw" rev-parse HEAD)"
merge_checks "no checks, a workflow without pull_request" 0 '[]'
# a branch that drops the base's pull_request trigger is still pending
om="$(git -C "$lw" rev-parse origin/main)"
wf="$(printf 'on:\n  pull_request:\n' | git -C "$lw" hash-object -w --stdin)"
gh_tree="$(printf '100644 blob %s\tci.yml\n' "$wf" | git -C "$lw" mktree)"
gh_tree="$(printf '040000 tree %s\tworkflows\n' "$gh_tree" | git -C "$lw" mktree)"
base_tree="$( { git -C "$lw" ls-tree "$om"; printf '040000 tree %s\t.github\n' "$gh_tree"; } | git -C "$lw" mktree)"
git -C "$lw" update-ref refs/remotes/origin/main "$(git -C "$lw" commit-tree "$base_tree" -p "$om" -m "ci: base workflow")"
merge_checks "no checks, the base's pull_request workflow dropped on the branch" 2 '[]'
git -C "$lw" update-ref refs/remotes/origin/main "$om"
STUB_CHECKS="$(checks '[]')"; export STUB_CHECKS

git remote set-url origin https://notgithub.com/acme/land.git
: >"$tmp/stub.log"
STUB_VIEW="main OPEN false" expect "merge refuses a host that only contains github.com" 2 cutter-land merge L1
[ ! -s "$tmp/stub.log" ] && ok "no gh call for a look-alike host on merge" || bad "no gh call for a look-alike host on merge"
git remote set-url origin https://evil.example/x@github.com/acme/land.git
: >"$tmp/stub.log"
STUB_VIEW="main OPEN false" expect "merge refuses an @ in the path posing as the host" 2 cutter-land merge L1
[ ! -s "$tmp/stub.log" ] && ok "no gh call for an @-spoofed host" || bad "no gh call for an @-spoofed host"
git remote set-url origin https://gitlab.example.com/grp/land.git
: >"$tmp/stub.log"
expect "merge via glab refuses an MR without project ids" 2 env STUB_VIEW='{"target_branch":"main","state":"opened"}' cutter-land merge L1
expect "merge via glab refuses a fork's MR" 2 env STUB_VIEW='{"target_branch":"main","state":"opened","source_project_id":2,"target_project_id":1}' cutter-land merge L1
! grep -q 'mr merge' "$tmp/stub.log" && ok "no glab merge call for a fork's MR" || bad "no glab merge call for a fork's MR"
expect "merge via glab" 0 env STUB_VIEW='{"target_branch":"main","state":"opened","source_project_id":1,"target_project_id":1}' cutter-land merge L1
grep -qxF 'mr view feat/L1 -R https://gitlab.example.com/grp/land --output json' "$tmp/stub.log" && ok "glab mr view pinned to origin's project" || bad "glab mr view pinned to origin's project"
grep -qxF 'mr merge feat/L1 -R https://gitlab.example.com/grp/land --squash --yes --sha '"$lwsha" "$tmp/stub.log" && ok "glab called with mr merge <branch> -R <url> --squash --yes --sha <sha>" || bad "glab called with mr merge <branch> -R <url> --squash --yes --sha <sha>"
git remote set-url origin "$tmp/github.com/land.git"

# pr / issue: argv is built from files under .cutter/ and origin alone
land_log() { grep -qxF -- "$1" "$tmp/stub.log" && ok "$2" || { bad "$2"; cat "$tmp/stub.log"; }; }
mkdir -p "$tmp/land/.cutter/L1" "$tmp/land/.cutter/drafts"
td="$(cd "$tmp/land/.cutter/L1" && pwd -P)"
git remote set-url origin git@github.com:acme/land.git
expect "pr refuses a missing title and body" 2 cutter-land pr L1
printf 'feat: the feature\nignored second line\n' >"$td/pr-title"
expect "pr refuses a missing body" 2 cutter-land pr L1
printf 'Closes #1\n' >"$td/pr-body.md"
: >"$tmp/stub.log"
STUB_VIEW_RC=1 expect "pr creates via gh" 0 cutter-land pr L1
land_log "pr create --repo github.com/acme/land --base main --head feat/L1 --title feat: the feature --body-file $td/pr-body.md" "gh pr create argv"
: >"$tmp/stub.log"
STUB_VIEW="main OPEN false" expect "pr updates via gh" 0 cutter-land pr L1
land_log "pr edit feat/L1 --repo github.com/acme/land --body-file $td/pr-body.md" "gh pr edit argv"
: >"$tmp/stub.log"
STUB_VIEW="develop OPEN false" expect "pr refuses an open PR into another base" 2 cutter-land pr L1
! grep -qE 'pr (edit|create)' "$tmp/stub.log" && ok "no edit or create for a wrong base" || bad "no edit or create for a wrong base"
STUB_VIEW="main OPEN true" expect "pr refuses a fork's open PR" 2 cutter-land pr L1
! grep -qE 'pr (edit|create)' "$tmp/stub.log" && ok "no edit or create for a fork's PR" || bad "no edit or create for a fork's PR"
# pr and merge refuse a push URL naming another repo; the same repo over https is allowed
git config remote.origin.pushurl https://github.com/evil/land.git
: >"$tmp/stub.log"
STUB_VIEW_RC=1 expect "pr refuses a push URL to another repo" 2 cutter-land pr L1
STUB_VIEW="main OPEN false" expect "merge refuses a push URL to another repo" 2 cutter-land merge L1
[ ! -s "$tmp/stub.log" ] && ok "no gh call with a mismatched push URL" || bad "no gh call with a mismatched push URL"
git config remote.origin.pushurl https://github.com/acme/land.git
STUB_VIEW_RC=1 expect "pr allows the same repo over https" 0 cutter-land pr L1
land_log "pr create --repo github.com/acme/land --base main --head feat/L1 --title feat: the feature --body-file $td/pr-body.md" "gh pr create argv with an equivalent push URL"
git config --unset remote.origin.pushurl
git remote set-url origin https://gitlab.example.com/grp/sub/land.git
: >"$tmp/stub.log"
STUB_VIEW_RC=1 expect "pr creates via glab" 0 cutter-land pr L1
land_log "mr create -R https://gitlab.example.com/grp/sub/land --target-branch main --source-branch feat/L1 --title feat: the feature --description Closes #1 --yes" "glab mr create argv"
: >"$tmp/stub.log"
STUB_VIEW='{"target_branch":"main","state":"opened","source_project_id":2,"target_project_id":1}' expect "pr refuses a fork's open MR" 2 cutter-land pr L1
! grep -qE 'mr (update|create)' "$tmp/stub.log" && ok "no update or create for a fork's MR" || bad "no update or create for a fork's MR"
STUB_VIEW='{"target_branch":"main","state":"opened","source_project_id":1,"target_project_id":1}' expect "pr updates via glab" 0 cutter-land pr L1
land_log "mr update feat/L1 -R https://gitlab.example.com/grp/sub/land --description Closes #1" "glab mr update argv"
git remote set-url origin git@github.com:acme/land.git
: >"$tmp/stub.log"
expect "pr rejects extra arguments" 2 cutter-land pr L1 --fill
expect "pr rejects a bad id" 2 cutter-land pr '../x'
: >"$td/pr-title"
expect "pr refuses an empty title" 2 cutter-land pr L1
printf 'feat: the feature\n' >"$td/pr-title"
mv "$td/pr-body.md" "$tmp/real-body.md"; ln -s "$tmp/real-body.md" "$td/pr-body.md"
expect "pr refuses a symlinked body" 2 cutter-land pr L1
[ ! -s "$tmp/stub.log" ] && ok "no call for refused pr" || bad "no call for refused pr"
rm "$td/pr-body.md"

printf '# Add the thing\nLabels: bug, ui\nType: Bug\n\n## Context\nbody\n' >"$tmp/land/.cutter/drafts/thing.md"
STUB_LABELS=$'bug\nui\nother'
export STUB_LABELS
: >"$tmp/stub.log"
expect "issue create" 0 cutter-land issue thing
grep -qE -- '^issue create --repo github.com/acme/land --title Add the thing --body-file .+ --label bug --label ui --type Bug$' "$tmp/stub.log" && ok "gh issue create argv" || bad "gh issue create argv"
expect "issue rejects a path slug" 2 cutter-land issue ../x
expect "issue rejects a slash slug" 2 cutter-land issue a/b
expect "issue rejects extra arguments" 2 cutter-land issue thing --label x
printf '# T\nLabels: bug, nope\n\nb\n' >"$tmp/land/.cutter/drafts/bad.md"
: >"$tmp/stub.log"
expect "issue refuses an unknown label" 2 cutter-land issue bad
! grep -q 'issue create' "$tmp/stub.log" && ok "no create call for an unknown label" || bad "no create call for an unknown label"
ln -s "$tmp/land/.cutter/drafts/thing.md" "$tmp/land/.cutter/drafts/link.md"
expect "issue refuses a symlinked draft" 2 cutter-land issue link
printf '# T\nLabels:\n\nb\n' >"$tmp/land/.cutter/drafts/nolabel.md"
: >"$tmp/stub.log"
expect "issue with an empty Labels: line" 0 cutter-land issue nolabel
! grep -q -- '--label' "$tmp/stub.log" && ok "no --label for an empty Labels: line" || bad "no --label for an empty Labels: line"
mv "$tmp/land/.cutter/drafts" "$tmp/drafts-elsewhere"; ln -s "$tmp/drafts-elsewhere" "$tmp/land/.cutter/drafts"
expect "issue refuses a draft under a symlinked drafts dir" 2 cutter-land issue thing
rm "$tmp/land/.cutter/drafts"; mv "$tmp/drafts-elsewhere" "$tmp/land/.cutter/drafts"
ln "$tmp/real-body.md" "$td/pr-body.md"
expect "pr refuses a hard-linked body" 2 cutter-land pr L1
rm "$td/pr-body.md"; printf 'Closes #1\n' >"$td/pr-body.md"

# comment: posts .cutter/gh-<n>/comment.md on issue <n> of origin's repo, without a worktree
mkdir -p "$tmp/land/.cutter/gh-7"
gd="$(cd "$tmp/land/.cutter/gh-7" && pwd -P)"
: >"$tmp/stub.log"
expect "comment refuses a missing comment.md" 2 cutter-land comment gh-7
: >"$gd/comment.md"
expect "comment refuses an empty comment.md" 2 cutter-land comment gh-7
printf 'Decisions from planning:\n' >"$tmp/real-comment.md"; rm "$gd/comment.md"; ln -s "$tmp/real-comment.md" "$gd/comment.md"
expect "comment refuses a symlinked comment.md" 2 cutter-land comment gh-7
rm "$gd/comment.md"; printf 'Decisions from planning:\n' >"$gd/comment.md"
expect "comment rejects a non-gh id" 2 cutter-land comment L1
expect "comment rejects gh-0" 2 cutter-land comment gh-0
expect "comment rejects extra arguments" 2 cutter-land comment gh-7 --repo evil/land
expect "comment refuses without ticket.md" 2 cutter-land comment gh-7
printf '# T\n\n- source: GitHub issue #7 (open)\n- url: https://github.com/other/land/issues/7\n' >"$gd/ticket.md"
expect "comment refuses a ticket read from another repo" 2 cutter-land comment gh-7
printf '# T\n\n- source: GitHub issue #7 (open)\n- url: https://github.com/acme/land/issues/77\n' >"$gd/ticket.md"
expect "comment refuses a ticket of another issue" 2 cutter-land comment gh-7
printf '# T\n\n- source: GitHub issue #77 (open)\n- url: https://github.com/acme/land/issues/77\n\n- url: https://github.com/acme/land/issues/7\n' >"$gd/ticket.md"
expect "comment refuses an issue url planted below the header" 2 cutter-land comment gh-7
[ ! -s "$tmp/stub.log" ] && ok "no gh call for a refused comment" || bad "no gh call for a refused comment"
printf '# T\n\n- source: GitHub issue #7 (open)\n- url: https://github.com/Acme/Land/issues/7\n' >"$gd/ticket.md"
expect "comment posts without a worktree" 0 cutter-land comment gh-7
land_log "issue comment 7 --repo github.com/acme/land --body-file $gd/comment.md" "gh issue comment argv"
[ ! -e "$gd/comment.md" ] && [ -s "$gd/comment.posted.md" ] && ok "a posted comment.md becomes comment.posted.md" || bad "a posted comment.md becomes comment.posted.md"
: >"$tmp/stub.log"
expect "comment refuses to post a second time" 2 cutter-land comment gh-7
[ ! -s "$tmp/stub.log" ] && ok "no gh call for a second comment" || bad "no gh call for a second comment"
printf 'Decisions from planning:\n' >"$gd/comment.md"
git remote set-url origin https://gitlab.example.com/grp/land.git
: >"$tmp/stub.log"
expect "comment refuses a GitLab origin" 2 cutter-land comment gh-7
git remote set-url origin git@github.com:acme/land.git

# cutter-ticket reads the issue from origin's repo only
: >"$tmp/stub.log"
expect "ticket by number" 0 cutter-ticket github 7
land_log "issue view 7 --repo github.com/acme/land --json number,title,body,url,state,labels,issueType,comments" "gh issue view pinned to origin's repo"
: >"$tmp/stub.log"
expect "ticket by origin's URL" 0 cutter-ticket github https://github.com/Acme/land/issues/7
land_log "issue view 7 --repo github.com/acme/land --json number,title,body,url,state,labels,issueType,comments" "a URL is read as its number in origin's repo"
cp "$tmp/out" "$tmp/ticket.stdout"
expect "ticket --out" 0 cutter-ticket github 7 --out .cutter/gh-7/ticket.md
[ ! -s "$tmp/out" ] && ok "ticket --out prints nothing" || bad "ticket --out prints nothing"
cmp -s "$gd/ticket.md" "$tmp/ticket.stdout" && ok "ticket --out writes what it would print" || bad "ticket --out writes what it would print"
echo keep >"$tmp/victim"
ln -sf "$tmp/victim" "$gd/ticket.md"
expect "ticket --out over a symlinked ticket.md" 0 cutter-ticket github 7 --out "$gd/ticket.md"
[ "$(cat "$tmp/victim")" = keep ] && [ ! -L "$gd/ticket.md" ] && ok "symlink replaced, its target untouched" || bad "symlink replaced, its target untouched"
: >"$tmp/stub.log"
expect "ticket refuses an unknown trailing argument" 2 cutter-ticket github 7 --web
expect "ticket refuses --out without a path" 2 cutter-ticket github 7 --out
expect "ticket refuses an argument after --out <path>" 2 cutter-ticket github 7 --out "$gd/ticket.md" extra
expect "ticket refuses --out outside .cutter/" 2 cutter-ticket github 7 --out "$tmp/x.md"
expect "ticket refuses --out into another issue's dir" 2 cutter-ticket github 8 --out "$gd/ticket.md"
expect "ticket refuses --out to another file name" 2 cutter-ticket github 7 --out "$gd/plan.md"
mv "$gd" "$tmp/gh-7.real"
ln -s "$tmp/gh-7.real" .cutter/gh-7
expect "ticket refuses a symlinked gh-<n> dir" 2 cutter-ticket github 7 --out .cutter/gh-7/ticket.md
rm .cutter/gh-7
mv "$tmp/gh-7.real" "$gd"
[ ! -e "$tmp/x.md" ] && ok "nothing written outside .cutter/" || bad "nothing written outside .cutter/"
expect "ticket refuses another repo's URL" 2 cutter-ticket github https://github.com/other/land/issues/7
expect "ticket refuses a URL on a look-alike host" 2 cutter-ticket github https://github.com.evil/acme/land/issues/7
expect "ticket refuses a flag" 2 cutter-ticket github --web
expect "ticket refuses a repo-qualified ref" 2 cutter-ticket github other/land#7
git remote set-url origin https://notgithub.com/acme/land.git
expect "ticket refuses a non-github.com origin" 2 cutter-ticket github 7
git remote set-url origin git@github.com:acme/land.git
[ ! -s "$tmp/stub.log" ] && ok "no gh call for a refused ticket" || bad "no gh call for a refused ticket"
git remote set-url origin https://notgithub.com/acme/land.git
: >"$tmp/stub.log"
expect "pr refuses a host that only contains github.com" 2 cutter-land pr L1
expect "issue refuses a host that only contains github.com" 2 cutter-land issue thing
expect "comment refuses a host that only contains github.com" 2 cutter-land comment gh-7
[ ! -s "$tmp/stub.log" ] && ok "no gh call for a look-alike host" || bad "no gh call for a look-alike host"
unset STUB_LABELS
git remote set-url origin "$tmp/github.com/land.git"

# squash: local mode, several tickets in a row without pushing the base
mkdir -p .claude && echo '{ "close": "local" }' >.claude/cutter.json
git add .claude/cutter.json && git commit -qm "chore: local mode" && git push -q origin main
echo extra >"$lw/extra.txt"; git -C "$lw" add -A; git -C "$lw" commit -qm "feat: extra"
expect "rebase L1 in local mode" 0 cutter-land rebase L1
expect "squash refuses without a commit message" 2 cutter-land squash L1
: >"$td/commit-msg"
expect "squash refuses an empty commit message" 2 cutter-land squash L1
rm "$td/commit-msg"; echo outside >"$tmp/outside-msg"; ln -s "$tmp/outside-msg" "$td/commit-msg"
expect "squash refuses a symlinked commit message" 2 cutter-land squash L1
rm "$td/commit-msg"
printf 'feat: land L1\n\nBody line.\n' >"$td/commit-msg"
before="$(git rev-parse main)"
expect "squash lands the branch" 0 cutter-land squash L1
[ "$(git rev-parse main^)" = "$before" ] && ok "one commit on the base" || bad "one commit on the base"
[ "$(git rev-parse 'main^{tree}')" = "$(git rev-parse 'feat/L1^{tree}')" ] && ok "base has the branch's tree" || bad "base has the branch's tree"
[ "$(git log -1 --format=%B main)" = "$(printf 'feat: land L1\n\nBody line.')" ] && ok "squash commit uses commit-msg" || bad "squash commit uses commit-msg"
[ -z "$(git status --porcelain)" ] && ok "main checkout updated with the base" || bad "main checkout updated with the base"
expect "squash refuses a branch not rebased onto the base" 2 cutter-land squash L1
expect "rm after a local squash" 0 cutter-worktree rm L1
grep -q 'deleted branch feat/L1 (its changes are on main)' "$tmp/out" && ok "locally squashed branch deleted" || bad "locally squashed branch deleted"
cutter-worktree add L0 --no-setup >/dev/null
mkdir -p .cutter/L0 && echo "feat: nothing" >.cutter/L0/commit-msg
expect "squash refuses a branch with nothing beyond the base" 2 cutter-land squash L0
grep -q 'no commits beyond main' "$tmp/out" && ok "empty branch: reason given" || bad "empty branch: reason given"
cutter-worktree rm L0 >/dev/null
expect "add starts from the unpushed local base" 0 cutter-worktree add L2 --no-setup
grep -q 'from main (' "$tmp/out" && ok "L2 starts from main" || bad "L2 starts from main"
echo two >"$tmp/land/.worktrees/L2/two.txt"; git -C "$tmp/land/.worktrees/L2" add -A; git -C "$tmp/land/.worktrees/L2" commit -qm "feat: two"
mkdir -p .cutter/L2 && echo "feat: two" >.cutter/L2/commit-msg
git checkout -q -b elsewhere
expect "rebase onto the unpushed local base" 0 cutter-land rebase L2
grep -q 'onto main$' "$tmp/out" && ok "L2 rebased onto main" || bad "L2 rebased onto main"
expect "squash off the base" 0 cutter-land squash L2
[ "$(git rev-parse 'main^{tree}')" = "$(git rev-parse 'feat/L2^{tree}')" ] && [ "$(git rev-parse --abbrev-ref HEAD)" = elsewhere ] && ok "base ref updated, checkout untouched" || bad "base ref updated, checkout untouched"
[ "$(git rev-list --count origin/main..main)" = 2 ] && ok "two tickets squashed in a row without a push" || bad "two tickets squashed in a row without a push"
cutter-worktree add L3 --no-setup >/dev/null
echo three >"$tmp/land/.worktrees/L3/three.txt"; git -C "$tmp/land/.worktrees/L3" add -A; git -C "$tmp/land/.worktrees/L3" commit -qm "feat: three"
mkdir -p .cutter/L3 && echo "feat: three" >.cutter/L3/commit-msg
git checkout -q main
echo more >g.txt; git commit -qam "chore: base moves"
expect "squash refuses when the base moved" 2 cutter-land squash L3
git checkout -q elsewhere
expect "squash refuses (off the base) when the base moved" 2 cutter-land squash L3
git checkout -q main
# the local base behind origin: start from origin/main; diverged: refuse
git push -q origin main
git clone -q "$tmp/github.com/land.git" "$tmp/land-other"
echo upstream >"$tmp/land-other/up.txt"
git -C "$tmp/land-other" add -A && git -C "$tmp/land-other" -c user.email=t@t -c user.name=t commit -qm "feat: upstream" && git -C "$tmp/land-other" push -q origin main
expect "add with the local base behind origin" 0 cutter-worktree add L4 --no-setup
grep -q 'from origin/main (' "$tmp/out" && ok "behind: starts from origin/main" || bad "behind: starts from origin/main"
echo four >"$tmp/land/.worktrees/L4/four.txt"; git -C "$tmp/land/.worktrees/L4" add -A; git -C "$tmp/land/.worktrees/L4" commit -qm "feat: four"
mkdir -p .cutter/L4 && echo "feat: four" >.cutter/L4/commit-msg
expect "rebase with the local base behind origin" 0 cutter-land rebase L4
grep -q 'onto origin/main$' "$tmp/out" && ok "behind: rebased onto origin/main" || bad "behind: rebased onto origin/main"
expect "squash with the local base behind origin" 0 cutter-land squash L4
[ "$(git rev-parse main^)" = "$(git rev-parse origin/main)" ] && [ -z "$(git rev-list main..origin/main)" ] && ok "behind: squash lands on origin/main, not diverged" || bad "behind: squash lands on origin/main, not diverged"
[ -z "$(git status --porcelain)" ] && [ -f up.txt ] && ok "behind: checkout has the upstream file" || bad "behind: checkout has the upstream file"
# a dirty main checkout on the base: unrelated changes kept, a change to a file the ticket touches refused
cutter-worktree add L7 --no-setup >/dev/null
echo seven >"$tmp/land/.worktrees/L7/seven.txt"; echo ticket-g >"$tmp/land/.worktrees/L7/g.txt"
git -C "$tmp/land/.worktrees/L7" add -A; git -C "$tmp/land/.worktrees/L7" commit -qm "feat: seven"
mkdir -p .cutter/L7 && echo "feat: seven" >.cutter/L7/commit-msg
echo mine >g.txt
before="$(git rev-parse main)"
expect "squash refuses over an uncommitted change to a touched file" 2 cutter-land squash L7
grep -q 'uncommitted changes to files the ticket touches' "$tmp/out" && ! grep -q 'moved since' "$tmp/out" && ok "dirty checkout: reason given" || bad "dirty checkout: reason given"
[ "$(git rev-parse main)" = "$before" ] && [ "$(cat g.txt)" = mine ] && ok "dirty checkout: base and change untouched" || bad "dirty checkout: base and change untouched"
git checkout -q -- g.txt
echo mine >>f.txt; echo staged >s.txt; git add s.txt
expect "squash with unrelated uncommitted changes" 0 cutter-land squash L7
[ "$(git rev-parse main^)" = "$before" ] && [ -f seven.txt ] && ok "dirty checkout: squash applied" || bad "dirty checkout: squash applied"
[ "$(git diff --name-only)" = f.txt ] && [ "$(git diff --cached --name-only)" = s.txt ] && ok "dirty checkout: unrelated changes kept" || bad "dirty checkout: unrelated changes kept"
git checkout -q -- f.txt; git rm -q --cached s.txt; rm s.txt
echo upstream2 >"$tmp/land-other/up.txt"
git -C "$tmp/land-other" pull -q && git -C "$tmp/land-other" -c user.email=t@t -c user.name=t commit -qam "feat: upstream again" && git -C "$tmp/land-other" push -q origin main
git fetch -q origin
echo local >h.txt; git add h.txt && git commit -qm "chore: local only"
expect "add refuses a diverged base" 2 cutter-worktree add L5 --no-setup
[ ! -e "$tmp/land/.worktrees/L5" ] && ok "no worktree for a diverged base" || bad "no worktree for a diverged base"
expect "rebase refuses a diverged base" 2 cutter-land rebase L4
# pr mode ignores the local base
git rm -q .claude/cutter.json && git commit -qm "chore: pr mode"
expect "add in pr mode with an unpushed local base" 0 cutter-worktree add L6 --no-setup
grep -q 'from origin/main (' "$tmp/out" && ok "pr mode starts from origin/main" || bad "pr mode starts from origin/main"
cd "$tmp/repo" || exit 2

# sync-base: after a merged PR, fast-forward the main checkout's base only when that is safe
expect "sync-base when level" 0 cutter-worktree sync-base
grep -q 'main is up to date' "$tmp/out" && ok "level base reported up to date" || bad "level base reported up to date"
git clone -q "$tmp/origin.git" "$tmp/other"
merged() { # land a commit on origin/main from elsewhere, as a merged PR would
  echo "$1" >"$tmp/other/$1.txt"
  git -C "$tmp/other" add -A && git -C "$tmp/other" -c user.email=t@t -c user.name=t commit -qm "feat: $1" && git -C "$tmp/other" push -q origin main
}
merged pr1
before=$(git rev-parse main)
git switch -q -c side
expect "sync-base off the base" 0 cutter-worktree sync-base
grep -q 'main is behind origin/main, not updated: the main checkout is on side' "$tmp/out" && ok "off the base: left behind" || bad "off the base: left behind"
git switch -q main && git branch -q -D side
[ "$(git rev-parse main)" = "$before" ] && ok "base untouched off the base" || bad "base untouched off the base"
echo 'export const add = (a, b) => b + a' >src/math.mjs
expect "sync-base with an unrelated unstaged change" 0 cutter-worktree sync-base
grep -q "fast-forwarded main to $(git rev-parse --short origin/main)" "$tmp/out" && ok "unrelated unstaged change: fast-forwarded" || bad "unrelated unstaged change: fast-forwarded"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok "base equals origin/main" || bad "base equals origin/main"
[ "$(git diff --name-only)" = src/math.mjs ] && ok "unstaged change kept" || bad "unstaged change kept"
merged pr2
git add src/math.mjs
expect "sync-base with an unrelated staged change" 0 cutter-worktree sync-base
grep -q "fast-forwarded main to $(git rev-parse --short origin/main)" "$tmp/out" && ok "unrelated staged change: fast-forwarded" || bad "unrelated staged change: fast-forwarded"
[ "$(git diff --cached --name-only)" = src/math.mjs ] && ok "staged change kept staged" || bad "staged change kept staged"
git reset -q -- src/math.mjs
echo 'export const add = (a, b) => a + b + 0' >"$tmp/other/src/math.mjs"
git -C "$tmp/other" -c user.email=t@t -c user.name=t commit -qam "fix: math" && git -C "$tmp/other" push -q origin main
before=$(git rev-parse main)
expect "sync-base with a change to an incoming file" 0 cutter-worktree sync-base
grep -q 'not updated: git merge --ff-only refused' "$tmp/out" && grep -q 'src/math.mjs' "$tmp/out" && ok "conflicting change: refused, file named" || bad "conflicting change: refused, file named"
[ "$(git rev-parse main)" = "$before" ] && ok "base untouched when git refuses" || bad "base untouched when git refuses"
git checkout -q -- src/math.mjs
expect "sync-base on a clean base" 0 cutter-worktree sync-base
grep -q "fast-forwarded main to $(git rev-parse --short origin/main)" "$tmp/out" && ok "clean base fast-forwarded" || bad "clean base fast-forwarded"
merged pr3
echo local >local.txt && git add local.txt && git commit -qm "chore: local only"
before=$(git rev-parse main)
expect "sync-base with local commits" 0 cutter-worktree sync-base
grep -q 'not updated: main has commits origin/main does not' "$tmp/out" && ok "diverged base: left behind" || bad "diverged base: left behind"
[ "$(git rev-parse main)" = "$before" ] && ok "diverged base untouched" || bad "diverged base untouched"

# ci-gates.sh: every gate runs, a table lands in the summary, gate changes against a base are listed
cig="$(cd "$BIN/.." && pwd)/scripts/ci-gates.sh"
cg="$tmp/cig"
git -c init.defaultBranch=main init -q "$cg"
mkdir "$cg/.claude"
cat >"$cg/.claude/cutter.json" <<'EOF'
{ "gates": ["echo gate-one", "echo gate-bad >&2; exit 3", "echo gate-three"] }
EOF
git -C "$cg" add -A && git -C "$cg" -c user.email=t@t -c user.name=t commit -qm "init"
cgbase="$(git -C "$cg" rev-parse HEAD)"
cd "$cg" || exit 2
GITHUB_STEP_SUMMARY="$tmp/cig-summary" expect "ci-gates: a failing gate fails the run" 1 "$cig"
grep -q 'gate-three' "$tmp/out" && ok "ci-gates: runs the gates after a failed one" || bad "ci-gates: runs the gates after a failed one"
grep -c '^::group::' "$tmp/out" | grep -qx 3 && grep -c '^::endgroup::' "$tmp/out" | grep -qx 3 && ok "ci-gates: one group per gate" || bad "ci-gates: one group per gate"
grep -q '^| `echo gate-one` | pass |' "$tmp/cig-summary" && grep -q 'exit 3` | FAIL |' "$tmp/cig-summary" && grep -q '`echo gate-three` | pass |' "$tmp/cig-summary" && ok "ci-gates: summary has pass and FAIL rows" || bad "ci-gates: summary has pass and FAIL rows"
[ "$(grep -n 'gate-one' "$tmp/cig-summary" | cut -d: -f1)" -lt "$(grep -n 'gate-three' "$tmp/cig-summary" | cut -d: -f1)" ] && ok "ci-gates: gate order kept" || bad "ci-gates: gate order kept"
expect "ci-gates: writes the table to stdout without GITHUB_STEP_SUMMARY" 1 env -u GITHUB_STEP_SUMMARY "$cig"
grep -q '^| gate | result | secs |' "$tmp/out" && ok "ci-gates: table on stdout" || bad "ci-gates: table on stdout"
echo '{ "gates": ["echo gate-one", "echo gate-added"] }' >.claude/cutter.json
git add -A && git -c user.email=t@t -c user.name=t commit -qm "chore: gates"
: >"$tmp/cig-summary"
GITHUB_STEP_SUMMARY="$tmp/cig-summary" expect "ci-gates: only passing gates" 0 "$cig"
! grep -q 'gates differ' "$tmp/cig-summary" && ok "ci-gates: no base, no gate changes" || bad "ci-gates: no base, no gate changes"
GITHUB_STEP_SUMMARY="$tmp/cig-summary" expect "ci-gates: with a base" 0 "$cig" "$cgbase"
grep -qxF '  - echo gate-bad >&2; exit 3' "$tmp/cig-summary" && grep -qxF '  + echo gate-added' "$tmp/cig-summary" && grep -qxF '  - echo gate-three' "$tmp/cig-summary" && ok "ci-gates: lists added and removed gates" || bad "ci-gates: lists added and removed gates"
! grep -qF 'gate-one' <(grep '^  [+-] ' "$tmp/cig-summary") && ok "ci-gates: kept gates not listed" || bad "ci-gates: kept gates not listed"
echo '{}' >.claude/cutter.json
expect "ci-gates: no gates" 2 "$cig"

[ "$fail" -eq 0 ] && echo "scripts: all cases pass"
exit "$fail"
