# Changelog

## 0.1.0 — unreleased

- The loop: `/cutter:open` (draft a GitHub issue, classified with the repo's labels or issue types; created on approval), `/cutter:work` (plan → worktree → implement → commit → red-proof → verify + cold review → fix → one cold review of the fix commits) and `/cutter:close` (rebase → verify → `pr` / `pr-merge` / `local`, each landing the branch as one squash commit; `local` tickets build on the unpushed local base; fills the repo's PR template; checks `gh` / `glab` before pushing; cleans up squash-merged branches, local and remote; fast-forwards the main checkout's base after a merged PR when it is on the base and git allows it, keeping unrelated uncommitted changes).
- The grill: before drafting, `/cutter:open` (product questions) and `/cutter:work` (technical questions) walk the open decisions with you in rounds, a recommended answer per question and depth scaled to the ticket, from one shared `references/grill.md`; drafts and plans list what was not settled under `## Assumptions`. On a GitHub ticket, `/cutter:work` posts the product answers to the issue as one comment.
- Issues: `.github/ISSUE_TEMPLATE/` bug and feature forms (blank issues off); `/cutter:open` drafts in a repo's form fields, titles by problem or need, numbers criteria, cites evidence for its Context and maps a multi-ticket request's goals to tickets first; `cutter-land issue` refuses drafts with missing required sections, unnumbered criteria, two checkboxes on a line or a phrase from `references/banned-phrases.txt`. Creating an issue and posting the planning comment always ask for permission.
- The flow skills and review agents check a claim before replying rather than reporting it unverified.
- Tickets from a description or a GitHub issue (`gh`).
- Scripts: `cutter-land` (`pr`, `issue` and `comment` build the PR/MR, issue and issue-comment commands from files under `.cutter/`), `cutter-worktree`, `cutter-verify` (runs the gates the ticket's worktree declares, listing changes against the base's; on cutter itself, lists the worktree's `bin/` and `scripts/` files that differ from the running copy), `cutter-red-proof`, `cutter-review-packet` (`--fixes` for the commits since the last review), `cutter-ticket` (reads issues of origin's repo only).
- Agent memory written during `/cutter:work` — in the main checkout or the worktree — is committed on the ticket's branch before the report (`cutter-worktree memory`), leaving the main checkout clean; `cutter-verify` and `cutter-red-proof` ignore memory an agent writes into the worktree while they run.
- `redProof.command` / `redProof.tests` let `cutter-red-proof` run any test runner; `preReviewGates` run before `cutter-review-packet` builds, so no reviewer reads a diff that fails the quick gates.
- Agents: `frontend-engineer`, `backend-engineer`, `devops-engineer`, `qa-engineer`, `code-reviewer` (do-not-report list, confidence ≥ 80), `security-reviewer`.
- Skills: `commit`, `code-review`, `code-review-branch`.
- Hooks: guard against destructive Bash commands; context gate for the flow skills.
- Project config in `.claude/cutter.json`; ticket files in `.cutter/<id>/`, kept out of git via `.git/info/exclude`.
- CI: `.github/workflows/ci.yml` runs the project's gates (`scripts/ci-gates.sh`) on Linux and macOS for pushes to `main` and pull requests; `cutter-land merge` on GitHub refuses a PR whose head is not pushed or whose checks are not green.
- Self-tests for the guard, the context gate and the scripts.
