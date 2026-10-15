---
name: open
description: Open a ticket — turn an idea, a bug or an improvement into a GitHub issue grounded in the codebase, classified with the repo's own labels or issue types, ready for /cutter:work. Use when the user runs /cutter:open with something to file.
disable-model-invocation: true
allowed-tools:
  - Bash(git remote get-url origin)
  - Bash(gh auth status)
  - Bash(gh issue list *)
  - Bash(gh label list *)
  - Bash(gh issue create *)
  - Bash(cutter-worktree init)
---

# Open a ticket

`/cutter:open <what>` files one GitHub issue for later work with `/cutter:work gh-<n>`. It does not plan or implement. Opening an issue is visible to everyone who can see the repo, so it **shows the draft and waits for the user's go** before creating anything.

GitHub only. Run one command per Bash call — no `&&`, `;` or `|`. Check before anything else:

```bash
git remote get-url origin
gh auth status
```

Stop, saying which and how to fix it, when `origin` is not on github.com, `gh` is not installed (command not found → https://cli.github.com), or not logged in (non-zero exit → `gh auth login`). Do not fall back to the web API or a browser.

## Step 1 — Ground it

Read just enough of the codebase to make the ticket concrete: which module, route, component or file it is about, and what happens there today. Search before claiming something is missing. Ask the user only what the request leaves genuinely open — a product question, not something the code answers.

Look for an existing issue first:

```bash
gh issue list --state open --search "<key words>" --limit 10
```

If one already covers it, show it and ask whether to add to it instead.

## Step 2 — Classify

Decide the kind: `feature`, `bug`, `improvement`, `docs` or `chore`. Then map it to what the repo already has — never create labels or types:

```bash
gh label list --limit 100 --json name,description
gh api graphql -f query='query($o:String!,$r:String!){repository(owner:$o,name:$r){issueTypes(first:25){nodes{name}}}}' -f o=<owner> -f r=<repo>
```

- Issue types (organisation repos only; `null` elsewhere): pick the one that matches — typically `Bug`, `Feature`, `Task`.
- Labels: the matching existing label — `bug` for a bug, `enhancement` for a feature or improvement, `documentation` for docs — if the repo has it. No match, no label.

If the repo has issue templates (`.github/ISSUE_TEMPLATE/`), follow the matching template's sections instead of the layout below.

## Step 3 — Draft and stop

Run `cutter-worktree init` and write the body to `.cutter/drafts/<short-slug>.md`:

```markdown
## Context
What happens today and where — name the files or routes. For a bug: steps to reproduce, expected, actual.

## Goal
The outcome, in one or two sentences.

## Acceptance criteria
- [ ] Each one checkable: a behaviour, a test, a command's output.

## Out of scope
What a reader might expect here but this ticket does not cover. Omit if nothing.
```

Show the user the title, the kind with the label or type it maps to, and the body. Title: short, imperative, in the repo's language and style (`gh issue list --limit 10` shows it). **Stop** until the user approves or edits it.

## Step 4 — Create

```bash
gh issue create --title "<title>" --body-file .cutter/drafts/<short-slug>.md [--label <label>] [--type <type>]
```

Report the issue URL and the next step, `/cutter:work gh-<n>`. Delete the draft only after the issue exists.

## Several at once

When the user lists several things, draft each, show them together, and create the ones the user approves. One issue per independent piece of work: a piece that can ship and be reviewed alone is its own ticket.

## Never

- Never create an issue before the user has seen and approved the draft.
- Never create labels, issue types, milestones or projects.
- Never assign people, set milestones or add to projects unless asked.
- Never put secrets, tokens, internal URLs or customer data in an issue body — it may be public.
