# cutter

A crew of AI agents that ships your tickets — planned, verified, reviewed.

Each ticket is planned with you, built in its own worktree, verified by scripts rather than by the agent's word, and reviewed by an agent that never saw how it was built — then merged. cutter is a Claude Code plugin; a Codex edition is planned.

```
/cutter:open <idea>     →  draft a GitHub issue ─(you approve)→ gh-<n>
/cutter:work <ticket>   →  plan  ─(you approve)→  worktree → implement → commit → red-proof → verify + cold review → fix
/cutter:close <id>      →  rebase → verify → PR / merge → clean up
```

## Install

```
/plugin marketplace add minanyang/claude-plugins
/plugin install cutter@minanyang
```

Requires `git` and `node` (18+). `/cutter:open`, GitHub issue tickets and the `pr` / `pr-merge` close modes also need [`gh`](https://cli.github.com) logged in (`gh auth login`), or [`glab`](https://gitlab.com/gitlab-org/cli) for GitLab; without it, `close: local` still works. cutter checks before it pushes and tells you what is missing.

## The loop

### `/cutter:open <idea>`

Turns an idea, a bug or an improvement into a GitHub issue: it reads enough of the codebase to name the files involved, checks for an existing issue, classifies it with the repo's own labels (`bug`, `enhancement`, …) or, in organisation repos, its issue types, and follows the repo's issue templates. Before drafting it grills you on the product decisions the request leaves open — in rounds, a recommended answer for each question, as deep as the ticket needs — and lists whatever you did not settle under `## Assumptions`. It shows you the draft and creates the issue only when you approve. It never creates labels or types. Several ideas at once become one issue each.

An issue is optional: `/cutter:work` also takes a task described in words.

### `/cutter:work <ticket>`

The ticket can be:

| Ticket | Read with | Setup |
|---|---|---|
| a description in words | — | — |
| a GitHub issue number or URL | `gh issue view` | `gh auth login` |

The ticket id is `gh-<n>` for an issue, else a slug. The branch type follows the ticket's label or issue type (`bug` → `fix/…`).

It runs in two invocations and stops after each:

1. **Plan** — saves the ticket to `.cutter/<id>/ticket.md`, grills you on the technical decisions (and the product ones a GitHub issue leaves open, whose answers it posts to the issue as one comment), writes `.cutter/<id>/plan.md` (goal, acceptance criteria, approach, the files it binds, tests, assumptions, out of scope) and waits for your approval.
2. **Implement** — creates `.worktrees/<id>` on a new branch from the up-to-date base, implements (itself for small tickets, an engineer agent for larger ones), commits, proves the tests go red without the change, then runs the gates and a cold-context review **concurrently**. Blockers and majors are fixed; the original findings stay in `.cutter/<id>/review.md` with what was done about each.

### `/cutter:close <id>`

Rebases onto the current base, verifies again, then lands the branch as configured:

| `close` | |
|---|---|
| `pr` (default) | push and open a PR; you merge it, then run `/cutter:close <id>` again to clean up |
| `pr-merge` | push, open the PR and squash-merge it |
| `local` | squash the branch onto the base locally, no PR; the next ticket starts from that local base, pushed or not |

GitHub remotes use `gh`. GitLab remotes use `glab` — untested so far.

The skill declares `allowed-tools` for the commands that are safe to grant (opening or updating the PR/MR goes through `cutter-land pr`), and the writes go through `cutter-land`, which takes only the ticket id, so no settings rule should allow `gh pr merge` or `git push` for it. In `pr-merge` mode, running `/cutter:close` is your request to merge.

## Principles

- One ticket per session. `.cutter/<id>/` is the memory; a fresh session loses nothing.
- Implementation never happens in the main checkout.
- The reviewer gets the diff and the plan — never the implementer's account of what it did.
- Mechanical verification is a script, not a model waiting on a test runner.
- Every step stops so a human can intervene.

## Configuration

Optional `.claude/cutter.json`, committed with the project:

```json
{
  "base": "develop",
  "gates": ["pnpm lint", "pnpm typecheck", "pnpm test"],
  "setup": "pnpm install --frozen-lockfile",
  "close": "pr",
  "worktreeDir": ".worktrees",
  "generated": ["src/api/generated"],
  "contextGate": { "maxTokens": 120000 }
}
```

| Key | Default |
|---|---|
| `base` | `develop` if origin has it, else origin's default branch |
| `gates` | package.json `verify`, else whichever of `lint`, `typecheck`, `test` exist |
| `setup` | install dependencies from the lockfile (`pnpm` / `yarn` / `bun` / `npm ci`) |
| `close` | `pr` |
| `worktreeDir` | `.worktrees` |
| `generated` | paths left out of the review diff (lockfiles always are) |
| `contextGate.maxTokens` | `120000`; `0` turns the gate off |

`cutter-verify` reads `gates` from the ticket's worktree, so a gate the ticket adds verifies that ticket; when the list differs from the base branch's, it lists the gates added and removed. Every other key comes from the main checkout.

`.cutter/` and the worktree directory are added to `.git/info/exclude` automatically — your `.gitignore` is not touched.

## Scripts

On the Bash tool's PATH while the plugin is enabled (not in a plain terminal):

| Script | Does |
|---|---|
| `cutter-worktree init\|add\|list\|path\|rm <id>\|sync-base` | one worktree per ticket; `init` keeps `.cutter/` out of git before anything is written there; `rm` deletes the branch only if git sees it merged; `sync-base` fast-forwards the main checkout's base after a merged PR when it is on the base and git allows the fast-forward (unrelated uncommitted changes are kept) |
| `cutter-land check\|rebase\|push\|merge\|squash\|pr\|comment <id>`, `cutter-land issue <slug>` | the writes `/cutter:close`, `/cutter:open` and `/cutter:work` need, each built from the ticket id or draft slug alone: `check` lists uncommitted changes, `rebase` onto the base (conflicts left for you), `push` the ticket branch (lease only if origin has it), `merge` squash-merges the open PR/MR into the configured base, pinned to origin's repo and the verified head commit, never a fork's PR/MR, `squash` lands the branch on the base as one commit from `.cutter/<id>/commit-msg` in `local` mode, `pr` opens the PR/MR from `.cutter/<id>/pr-title` + `pr-body.md` or updates only its body, `issue` creates an issue from `.cutter/drafts/<slug>.md` (existing labels only), `comment` posts `.cutter/gh-<n>/comment.md` on issue `<n>` of origin's repo; `push`, `merge` and `pr` refuse when origin's push URL names another repo than its fetch URL |
| `cutter-verify <id>` | runs every gate once; fails if the tree moved during the run |
| `cutter-red-proof <id>` | runs the changed tests at HEAD, then reverts the implementation and checks they go red (jest, vitest, `node --test`); a test that fails at HEAD exits 2 |
| `cutter-review-packet <id>` | the reviewer's starting material: diff, changed files, conventions, last verify result |
| `cutter-ticket github <ref>` | prints a GitHub issue as Markdown |

`cutter-verify`, `cutter-red-proof` and `cutter-worktree add` run the project's own gates and setup commands and its test files, so granting them is as strong as granting the agent permission to write files in the repo.

## Agents

Invoke as `cutter:<name>` (the Agent tool needs the prefix).

| Agent | Does | Does not |
|---|---|---|
| `cutter:frontend-engineer` | UI changes in the project's existing frontend stack | backend, infra |
| `cutter:backend-engineer` | APIs, data access, server-side logic | UI, infra |
| `cutter:devops-engineer` | CI/CD, containers, IaC, deploy config | application code |
| `cutter:qa-engineer` | test design, reproducing bugs, flaky-test triage | production fixes |
| `cutter:code-reviewer` | cold-context review; reports only findings it is ≥ 80% confident in, read-only | fixes |
| `cutter:security-reviewer` | security review, threat modelling, dependency audit, read-only | fixes |

Agents use `memory: project`, stored under `.claude/agent-memory/cutter-<name>/`. `mcp__context7` and `mcp__playwright` are used when those MCP servers are installed, and skipped otherwise.

## Other skills

| Skill | Does |
|---|---|
| `/cutter:commit` | Commit what this session changed — only those paths, in the repo's own message style. Commits straight away; stops to ask only on a likely secret, unclear scope or unrelated changes. Say "message only" for a draft |
| `/cutter:code-review` | Review pending (uncommitted) changes |
| `/cutter:code-review-branch` | Review the whole branch against its base |

`cutter:code-reviewer` preloads the two review skills as its procedure; you can also run them yourself. Bare names (`/commit`) also work when no other skill has that name.

## Hooks

- **Guard** — blocks destructive Bash commands: `rm -rf`, force push (`--force-with-lease` is allowed), `git reset --hard`, `git clean -f`, `git branch -D`, `git checkout -- .`, package publishing, raw disk writes. It is **best-effort, not a sandbox**: it matches the command text, so a script, alias or `eval` gets past it, and a command that merely contains such a string (in a heredoc, say) is blocked too. If a project ships its own guard at `.claude/scripts/guard-bash.sh`, cutter's steps aside.
- **Context gate** — refuses `/cutter:work` and `/cutter:close` when the session already carries more than `contextGate.maxTokens`, and asks for `/clear` first.

## License

MIT
