---
name: work
description: Take one ticket from intake to a reviewed, verified branch — plan it, implement it in its own worktree, prove its tests, have a cold-context agent review it, fix what the review finds. Use when the user runs /cutter:work with a GitHub issue, a ticket id, or a task described in words.
disable-model-invocation: true
allowed-tools:
  - Bash(cutter-worktree init *)
  - Bash(cutter-worktree add *)
  - Bash(cutter-ticket *)
  - Bash(cutter-red-proof *)
  - Bash(cutter-review-packet *)
  - Bash(cutter-verify *)
---

# Work a ticket

`/cutter:work <ticket>` runs in two invocations, and stops after each so the user stays in control:

1. **Plan** — read the ticket, write `.cutter/<id>/plan.md`, stop for approval.
2. **Implement** — after approval (`/cutter:work <id>` again, or the user says go in the same session): worktree → implement → commit → red-proof → verify + review → fix → report, then stop. Merging is `/cutter:close <id>`.

One ticket per session. Everything the next session needs lives in `.cutter/<id>/`.

The scripts below (`cutter-worktree`, `cutter-ticket`, `cutter-red-proof`, `cutter-verify`, `cutter-review-packet`) are on the Bash tool's PATH while the plugin is enabled. Run them from the project; they find the main checkout themselves. Run one command per Bash call — no `&&`, `;` or `|`.

## Step 0 — Which ticket, which phase

Work out the id from the argument:

| Argument | Id | Ticket text |
|---|---|---|
| GitHub issue number or URL | `gh-<number>` | `cutter-ticket github <arg>` |
| an id that has `.cutter/<id>/` | that id | already there |
| words describing a task | a short kebab-case slug of it, ≤ 30 characters | the user's words |

If `.cutter/<id>/plan.md` has `Status: approved`, go to Step 2. If it exists as a draft, show it and ask for approval or changes. Otherwise Step 1.

## Step 1 — Plan, then stop

Run `cutter-worktree init <id>` first — it creates `.cutter/<id>/` and keeps `.cutter/` out of git before anything is written there. Save the ticket text verbatim to `.cutter/<id>/ticket.md`. Read enough of the codebase to bind the plan to real files. Ask the user only what the ticket leaves genuinely open — product questions, not things the code answers.

Write `.cutter/<id>/plan.md`:

```markdown
# <id> — <title>

Status: draft

## Goal
One or two sentences: the outcome, not the steps.

## Acceptance criteria
- Each one checkable: a behaviour, a test, a command's output.

## Approach
What changes and why this way. Name the alternative you rejected when there was a real one.

## Files
The files this ticket binds, each with what changes in it. Implementation stays inside this list.

## Tests
Which test proves each criterion — new or changed test files. A criterion no test can cover says how it is verified instead.

## Out of scope
What a reader might expect here but this ticket does not do.
```

Show the plan and **stop**. On approval, set `Status: approved` and continue (or end, if the user wants a fresh session for the implementation).

## Step 2 — Worktree

```bash
cutter-worktree add <id> --type <feat|fix|refactor|chore|docs> --slug <2–4 word slug>
```

Take the type from the ticket when it says: a `bug` label or issue type → `fix`; `enhancement`, `feature` → `feat`; `documentation` → `docs`. Otherwise judge it from the plan.

It cuts the branch from the up-to-date base and runs the project's setup (dependency install by default). All edits from here on go into `.worktrees/<id>/`. **Never edit the main checkout.**

## Step 3 — Implement

Choose the path by size:

| | Direct — you implement | Delegated — an engineer agent implements |
|---|---|---|
| Scope | plan binds ≤ 3 files | more |
| Kind | copy, styling, a located bug fix, a field added to an existing shape | new route, component tree, contract change, migration |

When in doubt, take the direct path: escalating later is cheap, a wasted agent run is not.

Delegated: spawn `cutter:frontend-engineer`, `cutter:backend-engineer` or `cutter:devops-engineer` by what the files are. Give it the absolute paths of `plan.md` and the worktree, and: *"Implement only what the plan binds, in this worktree. Write the tests the plan names, so they fail without your change. Run the affected test files while iterating, the full gate once at the end. Do not commit, push or merge."* Independent parts in different areas can go to two agents in one message.

## Step 4 — Commit

In the worktree: stage the changed paths explicitly, never `-A`, then commit in the repo's own message style (`git log -n 5 --oneline`). No push.

```bash
git -C <worktree> add -- <paths>
git -C <worktree> commit -m "<message>"
```

## Step 5 — Red-proof

```bash
cutter-red-proof <id>
```

Every changed test file must go **red** with the implementation reverted. A `GREEN` file does not test the change: fix the test, commit, run again. Never send a diff to review with a `GREEN` in it. (It runs JavaScript/TypeScript tests; on other stacks it says unsupported — then state in the report that red-proof did not run.) Exit 2 naming test files that do not pass at HEAD is not a pass either: the test is broken, its environment is missing, or the runner is one red-proof does not support — fix it, or state in the report that red-proof could not run and why.

## Step 6 — Verify and review, concurrently

Build the packet, then in **one message**: start `cutter-verify <id>` in the background and spawn the reviewers.

```bash
cutter-review-packet <id>
```

- `cutter:code-reviewer`, always. Give it **only** the path of `.cutter/<id>/review-packet.md` and the instruction: *"Read the packet first and whole, then everything it lists in one message. Judge the diff against plan.md's acceptance criteria: does it satisfy them, is anything missing, is anything there the plan did not ask for, does it break the repo's conventions. Findings only."*
- `cutter:security-reviewer` too, when the change touches auth or permissions, payments, a new endpoint, or handling of user input — same packet, asked only about injection, authorization, secrets and unsafe input in the changed surface.

**Never give a reviewer the implementer's report or your own summary.** The reviewer judges the diff against the plan, not against an account of it — that is the point of a cold context.

**The tree is frozen** until every reviewer and the verify run have returned: no edits in the worktree while they read or test it.

Write the findings to `.cutter/<id>/review.md`, verbatim in substance, headed with the verdict and the criteria they were judged against.

## Step 7 — Act on the findings

| Severity | Default |
|---|---|
| `blocker`, `major`, any confirmed security finding | fix, always |
| `minor` | fix if it is a real bug; leave it if it is taste or argues for scope the plan did not bind |
| `nit` | fix if it is a one-liner in code you already touched |

- A finding you believe is wrong is not "fixed" to make it go away: say why in `review.md` and leave the code.
- A fix that needs scope the plan did not bind is not yours: record it and raise it.
- Small fixes in files you can name: do them yourself. Larger: one engineer agent, handed the findings verbatim and the files.

Fixes are further commits on the branch. Then `cutter-red-proof <id>` again if tests changed, and `cutter-verify <id>` once on the final tree. **Do not re-review the fixed tree** — append `## Fixes applied` to `review.md` (per finding: what changed or why not, and the commit), never overwrite the original findings.

## Step 8 — Report and stop

Report: the branch and commits, the final `cutter-verify` table, red-proof's result, the review verdict and what was done about each finding, anything left open. Then stop. The next step is `/cutter:close <id>`.

## Never

- Never edit the main checkout; the worktree is the only place changes go.
- Never push, open a PR or merge here.
- Never implement beyond what `plan.md` binds; new scope goes back to the plan, with the user.
- Never give a reviewer the implementer's account.
- Never write to the worktree while a reviewer, `cutter-verify` or `cutter-red-proof` is running in it.
- Never spawn an agent just to run the test suite — `cutter-verify` does it without a model waiting.
- Never stop with a `blocker` or `major` neither fixed nor explained.
