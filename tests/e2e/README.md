# End-to-end scenarios

`run.sh` drives `/cutter:open`, `/cutter:work` and `/cutter:close` through real `claude -p` runs against throwaway repos,
a github.com origin backed by a local bare repo, and a fake `gh`. Each scenario passes or fails on state alone: files
under `.cutter/`, git state (main checkout, worktree, branches), origin's heads, the fake `gh` call log, and the tool
calls of the stream-json log (tool name, Bash command, `subagent_type`, `run_in_background`) — never the model's text.

## Run

```bash
bash tests/e2e/run.sh              # all 27 scenarios
bash tests/e2e/run.sh 7 O2 C3      # only these (ids are case-sensitive; an unknown id exits 2 before any claude run)
```

It prints one line per scenario, in the order 1–14, O1–O3, W1–W7, C1–C3, then `total <seconds>s`:

```
pass  7  41s
FAIL  11  38s  gh pr merge got no --match-head-commit equal to the worktree's HEAD
total 412s
```

The number is the seconds of the scenario's flow (scenarios of one flow share its runs). The exit code is 1 when any
scenario fails and 2 for an unknown id or a missing prerequisite. The summed cost of the runs goes to stderr. A flow
that fails keeps its directories, and the runner says where: `origin.git/`, `repo/`, `gh/` (the fake's `canned.json`,
`state.json`, `calls.log`) and `log/` (one stream-json file per turn).

## Prerequisites

- A logged-in `claude` on PATH. **Every run calls the model (`--model sonnet`) and costs tokens**; it is in no gate and
  not in CI.
- `jq`, `node`, and `git` 2.38 or newer (`merge-tree --write-tree`). The runner checks them before the first flow.
- bash 3.2 or newer.

## Time and cost of one full run

Not measured yet: the first full run fills this in. Read the `total` line for the time and the stderr `cost` line (the
sum of the stream-json `result` lines' `total_cost_usd`) for the cost, and write them here.

## How it is set up

- **Flows, not one run per scenario.** A flow is one sequence of turns on one fixture; each scenario is an assertion
  bound to a flow and a checkpoint (`bindings` in `scenarios.sh`). Naming scenarios runs only the flows they need, up
  to the last checkpoint needed. Skills that grill the user are answered with `go with your recommendations` until
  the checkpoint state exists (a draft, `plan.md`, the memory commit, a PR), at most 6 turns per checkpoint.
- **Close flows start from prepared state** (`prep_ticket`): the worktree, a committed fix, `ticket.md`, an approved
  `plan.md`, `review.md` and `evidence.md` — `/cutter:work` is not run.
- **Fake `gh`** (`bin/gh`) answers from `canned.json` and `state.json`, logs every call's argv to `calls.log`, and
  squash-merges into the bare origin on `pr merge`. **Fake `ssh`** (`bin/ssh`) is `GIT_SSH_COMMAND`: it runs
  `git-upload-pack` / `git-receive-pack` on the bare origin for `git@github.com:test/fixture.git`.
- **No real `gh`.** Every PATH directory holding a `gh` is replaced by a shadow directory of symlinks to its other
  executables; the runner runs with an empty `GH_CONFIG_DIR` and without `GH_TOKEN`, `GITHUB_TOKEN`,
  `GH_ENTERPRISE_TOKEN`. A flow with the fake also fails when its tool log has more executed `gh <sub> <sub2>`
  commands than the fake's call log has entries.
- **Permissions.** `claude -p` runs with `--permission-mode acceptEdits`, never `--dangerously-skip-permissions`. A
  `permission_denials` entry in the stream-json `result` in the skills' scope — any tool but Bash, a `cutter-`, `gh`
  or `glab` command, or one a skill's `allowed-tools` or the runner's grants cover — fails every scenario of the flow
  and names the command. Any other denial is the model's own look around (`git -C … log`, running a repo script): it
  is printed on stderr as `note: <flow> denied (not the skill's): <command>` and fails nothing. What
  a user must allow, passed with `--settings` (an untrusted workspace ignores `.claude/settings.json`): `git -C * add *`,
  `git -C * commit *`, `gh api graphql *`, `cutter-land issue *`, `cutter-land comment *`.
- **The plugin under test** is `CUTTER_E2E_PLUGIN` (default: this repo). It is passed as `--plugin-dir`, its `bin/` comes
  right after the fake `gh` on PATH, every PATH entry containing `/.claude/plugins/` is dropped, and a flow fails before
  calling `claude` when `command -v cutter-land` does not resolve into that `bin/`.

## Showing a scenario can fail

Run a scenario against a copy of the plugin with one edit; it must print `FAIL`:

```bash
copy="$(mktemp -d)" && cp -R . "$copy/cutter"
# 1. cutter-land merge without the pin: edit "$copy/cutter/bin/cutter-land", delete `--match-head-commit "$(git -C "$path" rev-parse HEAD)"`
CUTTER_E2E_PLUGIN="$copy/cutter" bash tests/e2e/run.sh 11
# 2. close without the blocker check: edit "$copy/cutter/skills/close/SKILL.md", delete the last bullet of Step 0
CUTTER_E2E_PLUGIN="$copy/cutter" bash tests/e2e/run.sh 14
# 3. close waiting in the foreground: edit "$copy/cutter/skills/close/SKILL.md", delete the `run_in_background` paragraph of Step 3.3
CUTTER_E2E_PLUGIN="$copy/cutter" bash tests/e2e/run.sh C3
```

## The runner's own test

`bash tests/e2e-runner.test.sh` checks the runner offline with a stub `claude` (`CUTTER_E2E_CLAUDE`): a denial in the
skills' scope is reported with its command and one outside it is only a note, a tool-log `gh` call missing from the
fake's log fails the flow, an unknown id exits 2, and a failing scenario makes the exit code non-zero. It is in the
gates.
