# cutter

A crew of AI agents that ships your tickets — planned, verified, reviewed.

Each ticket is planned with you, built in its own worktree, verified by scripts rather than by the agent's word, and reviewed by an agent that never saw how it was built — then merged. cutter is a Claude Code plugin; a Codex edition is planned.

```
/cutter:open <idea>     →  draft a GitHub issue ─(you approve)→ gh-<n>
/cutter:work <ticket>   →  plan  ─(you approve)→  worktree → implement → commit → red-proof → pre-review gates → verify + cold review → fix → review the fixes
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

With issue forms (`.github/ISSUE_TEMPLATE/*.yml`) it picks the form by the ticket's kind and drafts one `### <field label>` section per field, in the form's order, with the form's labels and title prefix — the sections an issue filed from the web would have, since `gh issue create --body` bypasses forms. Without forms it uses its own layout. Titles state the problem (a bug) or the need (a feature). `cutter-land issue` refuses a draft, naming the line or field, when a required form section is missing or empty, the acceptance criteria are missing or a criterion is not numbered (`AC1 — …`), two checkboxes share a line, or a phrase from `references/banned-phrases.txt` (`TBD`, `handle edge cases`, …) appears outside code.

Creating the issue (`cutter-land issue`) and posting `/cutter:work`'s planning comment (`cutter-land comment`) are deliberately not in the skills' `allowed-tools`: both are public writes, so each asks for your permission even after you approved the draft — the approval does not rest on the model stopping. In auto mode the classifier decides instead of a prompt.

An issue is optional: `/cutter:work` also takes a task described in words.

### `/cutter:work <ticket>`

The ticket can be:

| Ticket | Read with | Setup |
|---|---|---|
| a description in words | — | — |
| a GitHub issue number or URL | `gh issue view` | `gh auth login` |

The ticket id is `gh-<n>` for an issue, else a slug. The branch type follows the ticket's label or issue type (`bug` → `fix/…`).

It runs in two invocations and stops after each:

1. **Plan** — saves the ticket to `.cutter/<id>/ticket.md`, grills you on the technical decisions (and the product ones a GitHub issue leaves open, whose answers it posts to the issue as one comment once you approve the plan), writes `.cutter/<id>/plan.md` (goal, numbered acceptance criteria, approach, the files it binds, the readers of every term it changes with the search that found them, the tool behaviour it relies on with the command and output that show it, overlap with other branches and PRs, a table of the test case proving each criterion, assumptions, out of scope) and waits for your approval. `cutter-plan-check` refuses the plan, naming each line, until every section the checks read is filled; when the plan binds more than three files, a fresh `Explore` agent reads it cold and lists what it would have to guess, and you are asked what the code does not answer.
2. **Implement** — creates `.worktrees/<id>` on a new branch from the up-to-date base, implements (itself for small tickets, an engineer agent for larger ones), commits, proves the tests go red without the change, then runs the gates and a cold-context review **concurrently**. Blockers and majors are fixed, and the fix commits get one more cold review of their own; the findings of each numbered round stay in `.cutter/<id>/review.md` with what was done about each; a new full round follows only when you approve a change to the plan. A problem the change causes is fixed in the ticket; anything beyond it is asked, not left. `.cutter/<id>/evidence.md` holds each criterion's state — `met` with its evidence, `deferred` in your words, or `asked` — and the Stop gate keeps the session from ending while one is unaccounted for.

### `/cutter:close <id>`

Rebases onto the current base, verifies again, then lands the branch as configured:

| `close` | |
|---|---|
| `pr` (default) | push and open a PR; you merge it, then run `/cutter:close <id>` again to clean up |
| `pr-merge` | push, open the PR and squash-merge it |
| `local` | squash the branch onto the base locally, no PR; the next ticket starts from that local base, pushed or not |

GitHub remotes use `gh`. GitLab remotes use `glab` — untested so far.

The skill declares `allowed-tools` for the commands that are safe to grant (opening or updating the PR/MR goes through `cutter-land pr`), and the writes go through `cutter-land`, which takes only the ticket id, so no settings rule should allow `gh pr merge` or `git push` for it. In `pr-merge` mode, running `/cutter:close` is your request to merge. Through the grant hook (see [Hooks](#hooks)), those grants hold for the rest of the session in which you typed `/cutter:close`, so the merge after the background `cutter-land wait` runs without a prompt.

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
  "redProof": { "command": "pytest {file}", "tests": ["tests/test_*.py"] },
  "preReviewGates": ["ruff check ."],
  "contextGate": { "maxTokens": 200000 }
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
| `redProof.command` | JavaScript runners (jest, vitest, `node --test`) are detected. For any other stack, a shell command containing `{file}`, run once per changed test file in the worktree root with the shell-quoted path substituted; the file's exit code is the result |
| `redProof.tests` | required with `redProof.command`: git pathspec globs naming the test files (`tests/*.test.sh`) |
| `preReviewGates` | none. Shell commands (quick gates: lint, typecheck) that `cutter-review-packet` runs first; a failure exits 1 and no packet is built |
| `contextGate.maxTokens` | `200000`; `0` turns the gate off. A file that does not parse, or a `maxTokens` that is not a number, gets the default and a warning |

`cutter-verify` reads `gates` from the ticket's worktree, so a gate the ticket adds verifies that ticket; when the list differs from the base branch's, it lists the gates added and removed. The context gate reads `contextGate` from the nearest `.claude/cutter.json` at or above the session's working directory, up to the repo root (none outside a repo), so inside a worktree it is the worktree's file. `redProof` and `preReviewGates` are read from the ticket's worktree, else the main checkout. Every other key comes from the main checkout.

`.cutter/` and the worktree directory are added to `.git/info/exclude` automatically — your `.gitignore` is not touched.

## Scripts

On the Bash tool's PATH while the plugin is enabled (not in a plain terminal):

| Script | Does |
|---|---|
| `cutter-worktree init\|add\|list\|path\|rm <id>\|sync-base` | one worktree per ticket; `init` keeps `.cutter/` out of git before anything is written there; `rm` deletes the branch only if git sees it merged; `sync-base` fast-forwards the main checkout's base after a merged PR when it is on the base and git allows the fast-forward (unrelated uncommitted changes are kept) |
| `cutter-land check\|rebase\|push\|merge\|wait\|squash\|pr\|comment <id>`, `cutter-land issue <slug>` | the writes `/cutter:close`, `/cutter:open` and `/cutter:work` need, each built from the ticket id or draft slug alone: `check` lists uncommitted changes, `rebase` onto the base (conflicts left for you), `push` the ticket branch (lease only if origin has it), `merge` squash-merges the open PR/MR into the configured base, pinned to origin's repo and the verified head commit, never a fork's PR/MR, and on GitHub only when the PR's head is the worktree's HEAD, the branch contains `origin/<base>` (exit 4 if it moved) and its checks are green (exit 3 when they are only still running), `wait` polls the PR's checks by the same rule until green, failed or 30 minutes, `squash` lands the branch on the base as one commit from `.cutter/<id>/commit-msg` in `local` mode, `pr` opens the PR/MR from `.cutter/<id>/pr-title` + `pr-body.md` or updates only its body, `issue` creates an issue from `.cutter/drafts/<slug>.md` (existing labels only), then deletes the draft, `comment` posts `.cutter/gh-<n>/comment.md` on issue `<n>` of origin's repo, only when the url in `.cutter/gh-<n>/ticket.md`'s header is that issue's, then renames it to `comment.posted.md` so it is posted once; `push`, `merge` and `pr` refuse when origin's push URL names another repo than its fetch URL |
| `cutter-verify <id>` | runs every gate once; fails if the tree moved during the run |
| `cutter-red-proof <id>` | runs the changed tests at HEAD, then reverts the implementation and checks they go red (jest, vitest, `node --test`, or the `redProof` command of any other stack); a test that fails at HEAD exits 2 |
| `cutter-plan-check <id>` | refuses `.cutter/<id>/plan.md`, naming every line at fault, when a criterion has no `## Tests` row, the Tests table is missing or has another header, a phrase from `references/banned-phrases.txt` appears outside code, `## Readers` is empty or an entry has no hit line, a `## Tool behaviour relied on` claim has no `$` command block with output, or `## Overlap` is empty |
| `cutter-review-packet <id> [--fixes]` | runs `preReviewGates` first (a failure exits 1, no packet), then builds the reviewer's starting material: diff, changed files, conventions, last verify result, and `## Plan checks` — each `## Tests` case not among its test file's added lines on the branch, and each `(gone)` Readers term still in the tree; it adds `security review: required` with the reasons when the diff touches a script a skill grants in `allowed-tools`, a skill's or agent's frontmatter, `hooks/hooks.json`, a script it registers, or a file such a script or hook loads (one level, by a static `source` or relative `require`); `--fixes` covers only the commits since the last review, with its findings (the plan checks still read the whole branch) |
| `cutter-ticket github <ref> [--out <path>]` | prints a GitHub issue of origin's repo as Markdown, or writes it to `--out`, which must be that issue's `.cutter/gh-<n>/ticket.md` (a number, or that repo's issue URL; another repo's is refused, and so is any other argument) |
| `cutter-ticket issue-types` | prints the issue types of origin's repo, one per line; nothing for a repo without them |

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

Agents use `memory: project`, stored under `.claude/agent-memory/cutter-<name>/` and committed: `/cutter:work` moves what agents wrote during the ticket onto its branch (`cutter-worktree memory`), so it is merged with the work. Review packets leave it out of their diff and list the commits that touch it; the report shows you the branch's whole memory diff. `mcp__context7` and `mcp__playwright` are used when those MCP servers are installed, and skipped otherwise.

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
- **Stop gate** — a session owns a ticket once it runs `cutter-worktree add <id>` or types `/cutter:work <id>` for an approved plan (the latest session to bind it owns it). While the ticket's worktree exists, the session cannot end a turn while `.cutter/<id>/evidence.md` misses a criterion, leaves one `pending`, or has an `asked` question that is not in the turn's last message. In a session that typed `/cutter:open`, `/cutter:work` or `/cutter:close`, and for `cutter:code-reviewer` and `cutter:security-reviewer`, it also refuses a last message that calls something unverified, unchecked or not yet confirmed (English or Chinese, outside code). It blocks once per stop, lets the turn end while background tasks run, and fails open on its own errors. Session bindings live in `.cutter/.sessions/`.
- **Grant** — Claude Code applies a skill's `allowed-tools` only to the turn in which you typed it: the turn a background task wakes (close's merge after `cutter-land wait`, work's steps after the gates or reviewers finish), a later turn of the same session (work after you say "approved, go") and a `--resume` turn fall back to your normal permissions, so the loop would stop to ask, or be refused under `claude -p`. When you type `/cutter:open`, `/cutter:work` or `/cutter:close`, the hook records that skill's `Bash(...)` grants as its `SKILL.md` lists them at that moment, and allows a single command (no `;`, `&`, `|`, `<`, `>`, `$`, backtick or newline) matching one of them for the whole session in which you typed the skill — not in subagents, and not another skill's grants. Only a skill you typed (or passed to `claude -p`) counts: the hook confirms the prompt against the session's transcript before its first grant, so a prompt you did not type — a scheduled (`CronCreate`) one naming the skill, say — grants nothing. A cutter script run on a ticket (`cutter-land`, `cutter-worktree`, `cutter-verify`, `cutter-red-proof`, `cutter-review-packet`, `cutter-plan-check`) is allowed only for the ticket you typed the skill for — `/cutter:work 53` binds `gh-53`; a task in words binds the first ticket the skill works on. `cutter-verify`, `cutter-review-packet` and `cutter-red-proof` run the commands in that worktree's `.claude/cutter.json`, so an edit to that file runs without a prompt the next time they run in the session. Records live in `${CLAUDE_PLUGIN_DATA}/sessions/`, outside the repo, so the agent cannot write itself one without asking. For the loop to finish unattended you need to allow nothing for the skills' grants; `cutter-land issue` and `cutter-land comment` still ask by design.

## License

MIT
