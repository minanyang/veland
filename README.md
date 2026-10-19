<div align="center">

# cutter

A crew of AI agents that ships your tickets — planned, verified, reviewed.

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE) [![Claude Code plugin](https://img.shields.io/badge/Claude_Code-plugin-D97757)](https://code.claude.com/docs/en/plugins)

**English** · [繁體中文](README.zh-TW.md)

</div>

Each ticket is planned with you, built in its own worktree, verified by scripts rather than by the agent's word, and reviewed by an agent that never saw how it was built — then merged. cutter is a Claude Code plugin; a Codex edition is planned.

## Why

Left to itself, a coding agent:

- **reports work done without verifying it** — "tests pass" because it says so, not because they ran;
- **works from a vague plan** — what counts as done, which files it touches and what else depends on them are never written down;
- **merges with nothing checking it** — the same context that wrote the change judges it.

cutter turns each ticket into a loop that does not take the agent's word:

- one ticket per session, with everything the next session needs in `.cutter/<id>/`;
- implementation in its own worktree, never in the main checkout;
- a plan with numbered acceptance criteria, checked by a script before you see it;
- verification by scripts — the project's gates, and new tests that must fail without the change;
- review by an agent that gets the diff and the plan, never the implementer's account;
- a stop at every step, so you can intervene.

## The three commands

```
/cutter:open <idea>     →  draft a GitHub issue ─(you approve)→ gh-<n>
/cutter:work <ticket>   →  plan  ─(you approve)→  worktree → implement → commit → red-proof → pre-review gates → verify + cold review → fix → review the fixes
/cutter:close <id>      →  rebase → verify → PR / merge → clean up
```

**`/cutter:open <idea>`** turns an idea, a bug or an improvement into a GitHub issue in the repo's own issue forms, labels and types. It asks you the product questions the idea leaves open, shows you the draft, and creates the issue only when you approve.

**`/cutter:work <ticket>`** takes an issue or a task in words. First it plans: it asks the technical questions, writes a plan with acceptance criteria, the files it binds and the test proving each criterion, and stops for your approval. Then it builds in a worktree: implement, commit, prove the new tests go red without the change, run the gates and a cold review together, fix what the review finds, and report.

**`/cutter:close <id>`** rebases, verifies again and lands the branch as one squash commit — a PR you merge, a PR it merges once checks pass, or a local merge — then cleans up.

Every step in detail: [docs/loop.md](docs/loop.md).

## Install

```
/plugin marketplace add minanyang/claude-plugins
/plugin install cutter@minanyang
```

Requires `git` and `node` (18+). `/cutter:open`, GitHub issue tickets and the `pr` / `pr-merge` close modes also need [`gh`](https://cli.github.com) logged in (`gh auth login`), or [`glab`](https://gitlab.com/gitlab-org/cli) for GitLab; without it, `close: local` still works. cutter checks before it pushes and tells you what is missing.

### Quick start

```
/cutter:open add a --json flag to the export command
/cutter:work 12
/cutter:close gh-12
```

1. `/cutter:open` asks its questions, shows the draft, and creates the issue (say #12) when you approve.
2. `/cutter:work 12` plans ticket `gh-12` and stops. Read the plan, answer or approve, then run `/cutter:work gh-12` again (or say "go") to build it.
3. `/cutter:close gh-12` lands it. By default it opens a PR; once you merge it, run `/cutter:close gh-12` again to clean up.

Optional settings — base branch, gates, close mode — live in `.claude/cutter.json`: see [docs/configuration.md](docs/configuration.md).

## What's inside

### Agents

Invoke as `cutter:<name>` (the Agent tool needs the prefix).

| Agent | Does | Does not |
|---|---|---|
| `cutter:frontend-engineer` | UI changes in the project's existing frontend stack | backend, infra |
| `cutter:backend-engineer` | APIs, data access, server-side logic | UI, infra |
| `cutter:devops-engineer` | CI/CD, containers, IaC, deploy config | application code |
| `cutter:qa-engineer` | test design, reproducing bugs, flaky-test triage | production fixes |
| `cutter:code-reviewer` | cold-context review; reports only findings it is ≥ 80% confident in, read-only | fixes |
| `cutter:security-reviewer` | security review, threat modelling, dependency audit, read-only | fixes |

### Skills

| Skill | Does |
|---|---|
| `/cutter:open` | Draft a GitHub issue and create it on approval |
| `/cutter:work` | Plan a ticket, then build, verify and review it in a worktree |
| `/cutter:close` | Rebase, verify, land and clean up |
| `/cutter:commit` | Commit what this session changed — only those paths, in the repo's own message style. Commits straight away; stops to ask only on a likely secret, unclear scope or unrelated changes. Say "message only" for a draft |
| `/cutter:code-review` | Review pending (uncommitted) changes |
| `/cutter:code-review-branch` | Review the whole branch against its base |

The scripts the skills run are in [docs/scripts.md](docs/scripts.md).

### Hooks

| Hook | Does |
|---|---|
| Guard | Blocks destructive Bash commands (`rm -rf`, force push, `git reset --hard`, …) |
| Context gate | Refuses `/cutter:work` and `/cutter:close` in a session already too large |
| Stop gate | Keeps a session from ending while a criterion is unaccounted for |
| Grant | Keeps a typed flow skill's grants for the rest of its session |

Details: [docs/hooks.md](docs/hooks.md).

## Safety and permissions

- **The guard is best-effort, not a sandbox.** It matches the command text, so a script, alias or `eval` gets past it.
- **Public writes always ask.** Creating an issue and posting the planning comment are not in any skill's `allowed-tools`, so each asks for your permission even after you approved the draft. In auto mode the classifier decides instead of a prompt.
- **Writes take only the ticket id.** Pushing, opening and merging the PR go through `cutter-land`, which builds each command from the ticket id, so no settings rule should allow `gh pr merge` or `git push`.
- **Grants last for the session you typed the skill in.** [The grant hook](docs/hooks.md#grant) allows a single command matching the skill's grants, never in subagents, and runs cutter's scripts only for the ticket you typed the skill for.
- **Some scripts run project code.** `cutter-verify`, `cutter-red-proof` and `cutter-worktree add` run the project's gates, setup and tests, so granting them is as strong as letting the agent write files in the repo.

## License

MIT
