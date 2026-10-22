# Changelog

## Unreleased

- A `tickets` setting in `.claude/veland.json`, independent of `close`: `"github"` files `/veland:open`'s tickets as GitHub issues, `"files"` writes them to `.veland/<slug>/ticket.md` with no `gh` and no `origin` (`veland-land ticket`). Without it, a github.com `origin` means `github`, anything else `files`.

## 0.1.0 — 2026-10-21

Initial release.

- `/veland:open` drafts a GitHub issue in the repo's issue forms, labels and types, and creates it once you approve.
- `/veland:work` plans a ticket with you, then builds it in its own worktree: implement, commit, prove the new tests fail without the change, verify with the project's gates, and review cold.
- `/veland:close` rebases, verifies again and lands the branch as one squash commit — a PR, a PR it merges once checks pass, or a local merge — then cleans up.
- Scripts, not the agent's word, decide: plans, evidence and review rounds are checked before you see them, and a Stop hook keeps a session from ending with a criterion unaccounted for.
- Six agents (frontend, backend, devops, QA, code review, security review), three skills (`commit`, `code-review`, `code-review-branch`) and hooks that guard destructive commands, gate on context size and keep a typed skill's grants for its session.
- Self-tests for the scripts and hooks, and an end-to-end suite that drives open, work and close against a fake `gh` (`tests/e2e/`).

See the README for configuration and every component.
