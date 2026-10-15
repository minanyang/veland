---
name: close
description: Land a ticket that /cutter:work finished — rebase it onto the current base, verify again, then open a PR, merge it, or merge locally, as the project configures; remove the worktree once merged. Use when the user runs /cutter:close <id>.
disable-model-invocation: true
allowed-tools:
  - Bash(cutter-land check *)
  - Bash(cutter-land rebase *)
  - Bash(cutter-land push *)
  - Bash(cutter-land merge *)
  - Bash(cutter-land squash *)
  - Bash(cutter-land pr *)
  - Bash(cutter-verify *)
  - Bash(cutter-worktree path *)
  - Bash(cutter-worktree rm *)
  - Bash(cutter-worktree sync-base)
  - Bash(git remote get-url origin)
  - Bash(gh auth status)
  - Bash(gh pr view *)
  - Bash(gh issue view *)
  - Bash(glab auth status)
  - Bash(glab mr view *)
---

# Close a ticket

`/cutter:close <id>` lands the branch `/cutter:work` produced. How it lands comes from `.claude/cutter.json`:

| `close` | What happens |
|---|---|
| `pr` (default) | push the branch, open a PR; a human merges it. Run `/cutter:close <id>` again after the merge to clean up. |
| `pr-merge` | push, open the PR, and squash-merge it. |
| `local` | no PR: squash the ticket branch onto the base branch locally. Pushing the base is left to the user. |

The PR tool follows `origin`: github.com → `gh`, a GitLab host → `glab`. Any other host, or no `origin`, supports only `local`.

Run one command per Bash call — no `&&`, `;` or `|` — so each call matches this skill's `allowed-tools` on its own. In `pr-merge` mode, running `/cutter:close` is the user's request to merge: state the PR URL, then merge.

## Step 0 — Take stock, stop on anything unfinished

```bash
cutter-worktree path <id>
cutter-land check <id>
```

Stop and say why if any of these holds:

- `pr` or `pr-merge`, and the PR tool is missing or logged out — check with `gh auth status` (or `glab auth status`) **before** rebasing or pushing, so a failure never leaves a pushed branch without a PR. Command not found → install it (https://cli.github.com, https://gitlab.com/gitlab-org/cli); non-zero exit → `gh auth login` / `glab auth login`. Mention that `"close": "local"` in `.claude/cutter.json` needs neither;
- no worktree for `<id>`: look for an open PR of the branch instead (the second run of `pr` mode, Step 4);
- uncommitted changes in the worktree;
- `.cutter/<id>/review.md` is missing, or lists a `blocker` / `major` with neither a fix nor a reason — round 1's in `## Fixes applied`, round 2's in `## Re-review` → `### Fixes applied` — that is `/cutter:work`'s job.

## Step 1 — Rebase onto the current base

```bash
cutter-land rebase <id>
```

The base is `base` from the config, else `develop` when origin has it, else origin's default branch. In `local` mode the rebase goes onto the local base when it contains `origin/<base>`, so tickets closed earlier and not pushed yet are kept; when the two have diverged it refuses — stop and leave reconciling the base to the user. On a conflict `cutter-land rebase` lists the conflicting files and leaves the rebase: stop, show them, and leave it for the user to resolve (or resolve it with them). Never `git rebase --skip` or drop a commit to get past it.

## Step 2 — Verify the rebased tree

```bash
cutter-verify <id>
```

It must pass on the rebased tree. A failure here is new (the base moved): fix it as a commit on the branch, or stop and report it.

## Step 3 — Land it

**`pr` and `pr-merge`:**

1. Push: `cutter-land push <id>` — it pushes only the ticket branch, with `--force-with-lease` only when origin already has it.
2. Open the PR against the base: write `.cutter/<id>/pr-title` (one line: the ticket's title, in the repo's commit style) and `.cutter/<id>/pr-body.md`, then run `cutter-land pr <id>`. It creates the PR/MR, or, when the branch already has an open one (a previous run that stopped before merging), replaces only its body and refuses a PR whose base is not the configured base. Body:
   - the plan's goal and acceptance criteria as a checklist, the final `cutter-verify` table, the review verdict with what was done about each finding, and `Closes #<n>` for a `gh-<n>` ticket or the ticket's URL for any other source. If the repo has a PR template (`.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE/`, `docs/` or root; `.gitlab/merge_request_templates/` for GitLab), fill its sections with this content instead of using this layout.
3. `pr-merge` only: state the PR URL, then `cutter-land merge <id>` — a squash merge without the delete-branch flags: `gh` would remove the worktree and branch behind cutter's back; Step 4 removes both, local and remote. It refuses a PR whose base is not the configured base. If it refuses over checks (pending, failed, or no result yet), stop: report the PR URL and the checks it named, tell the user to run `/cutter:close <id>` again once CI finishes, and never merge around it. Otherwise go to Step 4.
4. `pr`: report the PR URL and stop. The worktree stays until the PR is merged.

**`local`:**

1. Write `.cutter/<id>/commit-msg` — the squash commit's message: the ticket's title in the repo's commit style, then a blank line and a short body when it helps.
2. `cutter-land squash <id>` — one commit on the base with the branch's tree, applied in the main checkout with `git merge --ff-only` if it is on the base branch (uncommitted changes to files the ticket does not touch are kept), otherwise by updating the base ref. A refusal that says the base moved means go back to Step 1; one that names uncommitted changes in the main checkout is the user's to commit or stash — stop and show it, never stash, reset or discard them yourself.
3. Go to Step 4.

## Step 4 — Clean up after the merge

Only once the branch is merged (squash-merged PR, or the local squash). After a merged PR (`pr-merge`, or `pr` on its cleanup run) bring the main checkout's base up to date first; skip `sync-base` in `local` mode, whose base is already ahead:

```bash
cutter-worktree sync-base
cutter-worktree rm <id>
```

`sync-base` fast-forwards the base only when the main checkout is on it and `git merge --ff-only` allows it — uncommitted changes to files the incoming commits do not touch are kept; otherwise it leaves the base and says why. Never pull, reset or switch branches in the main checkout to make it go through.

It removes the worktree and deletes the branch once its changes are on the base — merged as git sees it, or squash-merged (every file it touched is identical on `origin/<base>`, or on the local base after a local squash) — along with the pushed branch on origin if a merged PR left it behind. A branch whose changes are not on the base is kept and reported; never delete it yourself. Keep `.cutter/<id>/` — it is the ticket's record.

## Step 5 — Report

What landed and where (PR URL or base commit), the final verify table, what `sync-base` did to the local base (fast-forwarded to which commit, or left behind and why), and what was cleaned up or left.

## Never

- Never land a branch whose rebased tree did not pass `cutter-verify`.
- Never force-push (except `cutter-land push`'s `--force-with-lease`), and never push the base branch in `local` mode.
- Never resolve a rebase conflict by dropping commits or `--skip`.
- Never remove a worktree before its branch is merged.
- Never merge in `pr` mode — that is the human's click.
