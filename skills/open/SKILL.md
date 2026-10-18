---
name: open
description: Open a ticket — turn an idea, a bug or an improvement into a GitHub issue grounded in the codebase, classified with the repo's own labels or issue types, ready for /cutter:work. Use when the user runs /cutter:open with something to file.
disable-model-invocation: true
allowed-tools:
  - Bash(git remote get-url origin)
  - Bash(gh auth status)
  - Bash(gh issue list *)
  - Bash(gh issue view *)
  - Bash(cutter-grill)
  - Bash(gh label list *)
  - Bash(cutter-ticket issue-types)
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

Read just enough of the codebase to make the ticket concrete: which module, route, component or file it is about, and what happens there today. Search before claiming something is missing.

Every file, route or current behaviour the draft's Context names carries its evidence: `path:line`, or the command run and its output. A claim with none is looked up before the draft is shown — never shown as a guess.

Look for an existing issue first:

```bash
gh issue list --state open --search "<key words>" --limit 10
```

If one already covers it, show it (`gh issue view <number>`) and ask whether to add to it instead.

Then grill: run `cutter-grill`, which prints the plugin's shared `references/grill.md`, and follow it. The questions here are product questions — what changes for the user, the edge cases, what counts as done.

## Step 2 — Classify

```bash
cutter-worktree init
```

It prints what the draft is built from: `drafts: <path>`, one `form: <file> name: … labels: … title: … required: … fields: …` line per issue form in `.github/ISSUE_TEMPLATE/` (or `forms: none`), one `template: <file>` line per Markdown template, and `banned: […]`. Values are JSON. A non-zero exit stops the skill: relay its message.

Decide the kind: `feature`, `bug`, `improvement`, `docs` or `chore`. Then map it to what the repo already has — never create labels or types:

```bash
gh label list --limit 100 --json name,description
cutter-ticket issue-types
```

A non-zero exit from `cutter-ticket issue-types` stops the skill: relay its message, as for the checks above.

- Issue types (one per line; nothing outside organisation repos): pick the one that matches — typically `Bug`, `Feature`, `Task`.
- Labels: the matching existing label — `bug` for a bug, `enhancement` for a feature or improvement, `documentation` for docs — if the repo has it. No match, no label.

If `init` printed `form:` lines, pick the form by the kind: a bug takes the form whose `labels` include the repo's bug label; a feature, improvement, docs or chore takes the one labelled `enhancement`, else the closest by `name`. Draft in its shape instead of the layout below: the line's file as `Form: <file>` in the header, its `labels` as `Labels:`, its `title` (unless `none`) as the title's prefix, and one `### <label>` section per `fields:` entry, in that order — every `required:` one filled. A `form: <file> error: …` line is relayed to the user, and that form is not used. When no form fits and a `template:` line names a matching Markdown template, read that one file, `.github/ISSUE_TEMPLATE/<file>`, and follow its sections.

## Step 3 — Draft and stop

Write the draft to `<drafts>/<short-slug>.md`, `<drafts>` being the path on Step 2's `drafts:` line (slug: lowercase letters, digits and `-`). Line 1 is `# <title>`; optional `Labels: a, b` (existing labels only), `Type: <name>` and `Form: <file name>` lines follow directly; then a blank line and the body:

```markdown
# <title>
Labels: <label>, <label>
Type: <issue type>

## Context
What happens today and where — name the files or routes. For a bug: steps to reproduce, expected, actual.

## Goal
The outcome, in one or two sentences.

## Acceptance criteria
- [ ] AC1 — Each one checkable and numbered: a behaviour, a test, a command's output.
- [ ] AC2 — One checkbox per line.

## Out of scope
What a reader might expect here but this ticket does not cover. Omit if nothing.

## Assumptions
Decisions the grill did not settle with the user, each with the answer taken. Omit if none.
```

Title: a bug by the problem observed (`Close reports a merged PR as open`), a feature by the need (`A way to file issues that follow the repo's forms`), in the repo's language — never a `scope:` prefix unless the form's `title` sets one, even when existing issues have one.

Every criterion is checkable: no `TBD`, `handle edge cases`, `as needed` or the other phrases on Step 2's `banned:` line — `cutter-land issue` refuses them outside code, as it refuses an unnumbered criterion, two checkboxes on one line and an empty or missing required form section.

Show the draft once: one line `Kind: <kind> → <label, type or form file name>` (the kind is not in the file), the draft's path on one line, then the file verbatim as rendered markdown — never summarised again in the same reply. **Stop** until the user approves or edits it.

## Step 4 — Create

```bash
cutter-land issue <short-slug>
```

It reads only that draft, refuses a label the repo does not have or a draft that fails the checks above (naming the line or field — fix the draft and run it again), and creates the issue in origin's repo. It is not in this skill's `allowed-tools` on purpose: creating a public issue always asks for permission, so the approval does not rest on the model stopping.

Report the issue URL and the next step, `/cutter:work gh-<n>`. `cutter-land issue` deletes the draft once the issue exists; when creation fails the draft stays for the next run.

## Several at once

When one request yields several tickets, first show a table of the request's goals, each mapped to the ticket and the criterion that covers it. A goal with no row is raised with the user before any draft is written. Then draft each, show them together — each as in Step 3, its `Kind:` line, path and file verbatim, shown once — and create the ones the user approves. One issue per independent piece of work: a piece that can ship and be reviewed alone is its own ticket.

## Replies

- Lead with the result. No first sentence that announces what comes next, and no closing recap or offer.
- Between routine tool calls, at most one line per phase change — a phase is one of this skill's numbered steps.
- Say each fact once: what the reply has already shown is not summarised again.

Some things are exempt from these rules and are written in full: a security warning; an irreversible action, both its warning and the statement made before acting on it, such as `/cutter:close` stating the PR URL before it merges; a question to the user; and anything persisted — code, commits, issue and PR bodies, and the files under `.cutter/`.

The final reply is Step 4's: the issue URL and the next step.

## Never

- Never create an issue before the user has seen and approved the draft.
- Never create labels, issue types, milestones or projects.
- Never assign people, set milestones or add to projects unless asked.
- Never put secrets, tokens, internal URLs or customer data in an issue body — it may be public.
- Never reply that something is unverified, unchecked or not yet confirmed: check it first. Only when a check is impossible, say so, naming what was tried and why it cannot be checked.
