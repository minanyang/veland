---
name: portable-shell-in-tests
description: tests/*.sh run in CI on ubuntu-latest and macos-latest; BSD-first `stat -f ... || stat -c ...` fallbacks break on GNU
metadata:
  type: project
---

CI (`.github/workflows/ci.yml`) runs the gates on both ubuntu-latest and macos-latest, but local runs (and `cutter-verify` in the packet) are macOS only, so a GNU/BSD flag difference in a test passes locally and fails CI.

**Why:** gh-53's `tests/grant.test.sh` used `stat -f %Lp f || stat -c %a f`. On GNU, `-f` is `--file-system` (no argument), so `%Lp` becomes a missing operand, the fs status of `f` is still printed to stdout, exit is 1, and the fallback's output is appended — the comparison fails. Confirmed from coreutils `src/stat.c` (long option `file-system`, `no_argument`).

**How to apply:** in any test diff, check `stat`, `sed -i`, `date`, `readlink -f`, `mktemp` flags for BSD/GNU portability; the GNU-first order (`stat -c ... || stat -f ...`) is safe because BSD `stat -c` fails with no stdout. A test that breaks Linux CI blocks `cutter-land merge` — rate it `blocker`.
