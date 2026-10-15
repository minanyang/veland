# Changelog

## 0.1.0 — unreleased

- The loop: `/cutter:open` (draft a GitHub issue, classified with the repo's labels or issue types; created on approval), `/cutter:work` (plan → worktree → implement → commit → red-proof → verify + cold review → fix) and `/cutter:close` (rebase → verify → `pr` / `pr-merge` / `local`; fills the repo's PR template; checks `gh` / `glab` before pushing; cleans up squash-merged branches, local and remote; fast-forwards the main checkout's base after a merged PR when it is on the base and git allows it, keeping unrelated uncommitted changes).
- Tickets from a description or a GitHub issue (`gh`).
- Scripts: `cutter-worktree`, `cutter-verify`, `cutter-red-proof`, `cutter-review-packet`, `cutter-ticket`.
- Agents: `frontend-engineer`, `backend-engineer`, `devops-engineer`, `qa-engineer`, `code-reviewer` (do-not-report list, confidence ≥ 80), `security-reviewer`.
- Skills: `commit`, `code-review`, `code-review-branch`.
- Hooks: guard against destructive Bash commands; context gate for the flow skills.
- Project config in `.claude/cutter.json`; ticket files in `.cutter/<id>/`, kept out of git via `.git/info/exclude`.
- Self-tests for the guard, the context gate and the scripts.
