<div align="center">

# veland

Your agent says it's done. veland checks, then lands it.

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE) [![Claude Code plugin](https://img.shields.io/badge/Claude_Code-plugin-D97757)](https://code.claude.com/docs/en/plugins)

**English** · [繁體中文](README.zh-TW.md)

</div>

Each ticket is planned with you, built in its own worktree, verified by scripts rather than by the agent's word, and reviewed by an agent that never saw how it was built — then merged. veland is a Claude Code plugin; a Codex edition is planned.

## Why

Left to itself, a coding agent:

- **reports work done without verifying it** — "tests pass" because it says so, not because they ran;
- **works from a vague plan** — what counts as done, which files it touches and what else depends on them are never written down;
- **merges with nothing checking it** — the same context that wrote the change judges it.

veland turns each ticket into a loop that does not take the agent's word:

- one ticket per session, with everything the next session needs in `.veland/<id>/`;
- implementation in its own worktree, never in the main checkout;
- a plan with numbered acceptance criteria, checked by a script before you see it;
- verification by scripts — the project's gates, and new tests that must fail without the change;
- review by an agent that gets the diff and the plan, never the implementer's account;
- a stop at every step, so you can intervene.

## The commands

```
/veland:open <idea>     →  draft a ticket ─(you approve)→ GitHub issue gh-<n>, or .veland/<slug>/ticket.md
/veland:work <ticket>   →  plan  ─(you approve)→  worktree → implement → commit → red-proof → pre-review gates → verify + cold review → fix → review the fixes
/veland:close <id>      →  rebase → verify → PR / merge → clean up
/veland:batch <tickets> →  work and close many tickets from one terminal, each in a background worker
```

**`/veland:open <idea>`** turns an idea, a bug or an improvement into a GitHub issue in the repo's own issue forms, labels and types — or, with `tickets: files`, into a ticket file under `.veland/` that stays on your machine. It asks you the product questions the idea leaves open, shows you the draft, and creates the ticket only when you approve.

**`/veland:work <ticket>`** takes an issue or a task in words. First it plans: it asks the technical questions, writes a plan with acceptance criteria, the files it binds and the test proving each criterion, and stops for your approval. Then it builds in a worktree: implement, commit, prove the new tests go red without the change, run the gates and a cold review together, fix what the review finds, and report.

**`/veland:close <id>`** rebases, verifies again and lands the branch as one squash commit — a PR you merge, a PR it merges once checks pass, or a local merge — then cleans up.

Every step in detail: [docs/loop.md](docs/loop.md).

## Install

```
/plugin marketplace add minanyang/claude-plugins
/plugin install veland@minanyang
```

Requires `git` and `node` (18+). GitHub issue tickets (`tickets: github`, which `/veland:open` then files) and the `pr` / `pr-merge` close modes also need [`gh`](https://cli.github.com) logged in (`gh auth login`), or [`glab`](https://gitlab.com/gitlab-org/cli) for GitLab; without it, `tickets: files` and `close: local` still work. veland checks before it pushes and tells you what is missing.

### Quick start

```
/veland:open add a --json flag to the export command
/veland:work 12
/veland:close gh-12
```

1. `/veland:open` asks its questions, shows the draft, and creates the issue (say #12) when you approve.
2. `/veland:work 12` plans ticket `gh-12` and stops. Read the plan, answer or approve, then run `/veland:work gh-12` again (or say "go") to build it.
3. `/veland:close gh-12` lands it. By default it opens a PR; once you merge it, run `/veland:close gh-12` again to clean up.

Optional settings — base branch, gates, close mode, where tickets live — live in `.claude/veland.json`: see [docs/configuration.md](docs/configuration.md). `tickets` is `"github"` (GitHub issues) or `"files"` (`.veland/<slug>/ticket.md`, never pushed); without it, a repo whose `origin` is on github.com gets `github` and any other gets `files`. It is independent of `close`: a repo can keep its ticket files off GitHub and still land them by PR, though in `pr` and `pr-merge` modes the PR body carries the plan's goal and acceptance criteria.

## Batch

`/veland:batch gh-12 gh-13` or `--search "label:bug"` plans all tickets and asks in one round. `.veland/_batch/board.md` shows each ticket's phase, session and outcome.

- `batch.parallel` caps implementation workers (default `1`); tickets land one at a time.
- `claude --resume <session id>` opens a worker.
- Planning writes only under `.veland/`. After approval, workers edit and run commands from the ticket unattended: batch only issues you trust.
- Allow `Bash(git -C * add *)` and `Bash(git -C * commit *)` ([caveat](tests/e2e/README.md)); the board lists other denials.
- In `pr` mode, tickets sharing files give overlapping PRs; above 1, agent memory lands on several branches.

## What's inside

### Agents

Invoke as `veland:<name>` (the Agent tool needs the prefix).

| Agent | Does | Does not |
|---|---|---|
| `veland:frontend-engineer` | UI changes in the project's existing frontend stack | backend, infra |
| `veland:backend-engineer` | APIs, data access, server-side logic | UI, infra |
| `veland:devops-engineer` | CI/CD, containers, IaC, deploy config | application code |
| `veland:qa-engineer` | test design, reproducing bugs, flaky-test triage | production fixes |
| `veland:code-reviewer` | cold-context review; reports only findings it is ≥ 80% confident in, read-only | fixes |
| `veland:security-reviewer` | security review, threat modelling, dependency audit, read-only | fixes |

### Skills

| Skill | Does |
|---|---|
| `/veland:open` | Draft a ticket — a GitHub issue, or with `tickets: files` a file under `.veland/` — and create it on approval |
| `/veland:work` | Plan a ticket, then build, verify and review it in a worktree |
| `/veland:close` | Rebase, verify, land and clean up |
| `/veland:batch` | Work and close many tickets from one terminal, each in a background worker |
| `/veland:commit` | Commit what this session changed — only those paths, in the repo's own message style. Commits straight away; stops to ask only on a likely secret, unclear scope or unrelated changes. Say "message only" for a draft |
| `/veland:code-review` | Review pending (uncommitted) changes |
| `/veland:code-review-branch` | Review the whole branch against its base |

The scripts the skills run are in [docs/scripts.md](docs/scripts.md).

### Hooks

| Hook | Does |
|---|---|
| Guard | Blocks destructive Bash commands (`rm -rf`, force push, `git reset --hard`, …) |
| Context gate | Refuses `/veland:work` and `/veland:close` in a session already too large |
| Stop gate | Keeps a session from ending while a criterion is unaccounted for |
| Grant | Keeps a typed flow skill's grants for the rest of its session |

Details: [docs/hooks.md](docs/hooks.md).

## Safety and permissions

- **The guard is best-effort, not a sandbox.** It matches the command text, so a script, alias or `eval` gets past it.
- **Public writes always ask.** Creating an issue and posting the planning comment are not in any skill's `allowed-tools`, so each asks for your permission even after you approved the draft. In auto mode the classifier decides instead of a prompt.
- **Writes take only the ticket id.** Pushing, opening and merging the PR go through `veland-land`, which builds each command from the ticket id, so no settings rule should allow `gh pr merge` or `git push`.
- **Grants last for the session you typed the skill in.** [The grant hook](docs/hooks.md#grant) allows a single command matching the skill's grants, never in subagents, and runs veland's scripts only for the ticket you typed the skill for.
- **Some scripts run project code.** `veland-verify`, `veland-red-proof` and `veland-worktree add` run the project's gates, setup and tests, so granting them is as strong as letting the agent write files in the repo.

## License

veland is released under the [MIT License](LICENSE).

The name veland refers to this project; please don't use it as the name of a fork or derivative work — saying a fork is based on veland is fine.
