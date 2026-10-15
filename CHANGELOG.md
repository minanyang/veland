# Changelog

## 0.1.0 — unreleased

- The loop: `/cutter:open` (draft a GitHub issue, classified with the repo's labels or issue types; created on approval), `/cutter:work` (plan → worktree → implement → commit → red-proof → verify + cold review → fix) and `/cutter:close` (rebase → verify → `pr` / `pr-merge` / `local`, each landing the branch as one squash commit; `local` tickets build on the unpushed local base; fills the repo's PR template; checks `gh` / `glab` before pushing; cleans up squash-merged branches, local and remote; fast-forwards the main checkout's base after a merged PR when it is on the base and git allows it, keeping unrelated uncommitted changes).
- The grill: before drafting, `/cutter:open` (product questions) and `/cutter:work` (technical questions) walk the open decisions with you in rounds, a recommended answer per question and depth scaled to the ticket, from one shared `references/grill.md`; drafts and plans list what was not settled under `## Assumptions`. On a GitHub ticket, `/cutter:work` posts the product answers to the issue as one comment.
- Tickets from a description or a GitHub issue (`gh`).
- Scripts: `cutter-land` (`pr`, `issue` and `comment` build the PR/MR, issue and issue-comment commands from files under `.cutter/`), `cutter-worktree`, `cutter-verify` (runs the gates the ticket's worktree declares, listing changes against the base's), `cutter-red-proof`, `cutter-review-packet`, `cutter-ticket`.
- Agents: `frontend-engineer`, `backend-engineer`, `devops-engineer`, `qa-engineer`, `code-reviewer` (do-not-report list, confidence ≥ 80), `security-reviewer`.
- Skills: `commit`, `code-review`, `code-review-branch`.
- Hooks: guard against destructive Bash commands; context gate for the flow skills.
- Project config in `.claude/cutter.json`; ticket files in `.cutter/<id>/`, kept out of git via `.git/info/exclude`.
- Self-tests for the guard, the context gate and the scripts.
