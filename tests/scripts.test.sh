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
echo '{ "gates": ["echo gate-kept", "echo gate-base"] }' >"$wt7/.claude/cutter.json"
git -C "$wt7" commit -qam "chore: reorder gates"
expect "verify with reordered gates" 0 cutter-verify T7
! grep -q '^gates differ' "$s7" && ok "same gates in another order: no report" || bad "same gates in another order: no report"
expect "rm T7" 0 cutter-worktree rm T7
git rm -q .claude/cutter.json && git commit -qm "chore: drop gates" && git push -q origin main

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
case "$1 $2" in "pr view"|"mr view") echo "$STUB_VIEW" ;; esac
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
mkdir -p .claude && echo '{"base":"feat/L1"}' >.claude/cutter.json
expect "push refuses the base branch" 2 cutter-land push L1
rm -r .claude

# a branch name with a leading + (a forced refspec) is refused by push and ff, origin and base untouched
git -C "$tmp/land" branch '+feat/EVIL' main
git -C "$tmp/land" worktree add -q "$tmp/land/.worktrees/EVIL" '+feat/EVIL'
o_before="$(git ls-remote origin)"; b_before="$(git rev-parse main)"
expect "push refuses a +branch" 2 cutter-land push EVIL
expect "ff refuses a +branch" 2 cutter-land ff EVIL
[ "$(git ls-remote origin)" = "$o_before" ] && [ "$(git rev-parse main)" = "$b_before" ] && ok "+branch left origin and base untouched" || bad "+branch left origin and base untouched"
expect "add refuses a bad --type" 2 cutter-worktree add L9 --type '+feat' --no-setup
expect "add refuses a bad --slug" 2 cutter-worktree add L9 --slug 'a:b' --no-setup
expect "add refuses a slug with a slash" 2 cutter-worktree add L9 --slug 'a/b' --no-setup

# merge: only `pr merge <branch> --squash`, and only into the configured base
: >"$tmp/stub.log"
export PATH="$tmp/stub:$PATH"
STUB_VIEW="develop OPEN" expect "merge refuses a PR into another base" 2 cutter-land merge L1
! grep -q 'pr merge' "$tmp/stub.log" && ok "no merge call for a wrong base" || bad "no merge call for a wrong base"
lwsha="$(git -C "$lw" rev-parse HEAD)"
STUB_VIEW="main OPEN" expect "merge" 0 cutter-land merge L1
grep -qxF 'pr merge feat/L1 --squash --match-head-commit '"$lwsha" "$tmp/stub.log" && ok "gh called with pr merge <branch> --squash --match-head-commit <sha>" || bad "gh called with pr merge <branch> --squash --match-head-commit <sha>"
git remote set-url origin "$tmp/gitlab.com/land.git"
: >"$tmp/stub.log"
expect "merge via glab" 0 env STUB_VIEW='{"target_branch":"main","state":"opened"}' cutter-land merge L1
grep -qxF 'mr merge feat/L1 --squash --yes --sha '"$lwsha" "$tmp/stub.log" && ok "glab called with mr merge <branch> --squash --yes --sha <sha>" || bad "glab called with mr merge <branch> --squash --yes --sha <sha>"
git remote set-url origin "$tmp/github.com/land.git"

# ff: local mode
expect "ff fast-forwards the base" 0 cutter-land ff L1
[ "$(git rev-parse main)" = "$(git rev-parse feat/L1)" ] && ok "base is at the ticket branch" || bad "base is at the ticket branch"
cutter-worktree add L2 --no-setup >/dev/null
echo two >"$tmp/land/.worktrees/L2/two.txt"; git -C "$tmp/land/.worktrees/L2" add -A; git -C "$tmp/land/.worktrees/L2" commit -qm "feat: two"
echo more >g.txt; git commit -qam "chore: base moves"
expect "ff refuses when the base moved" 2 cutter-land ff L2
git checkout -q -b elsewhere
echo again >g.txt; git commit -qam "chore: base moves on"
expect "ff refuses (off the base) when the base moved" 2 cutter-land ff L2
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

[ "$fail" -eq 0 ] && echo "scripts: all cases pass"
exit "$fail"
