---
name: open
description: Open a ticket — turn an idea, a bug or an improvement into a GitHub issue grounded in the codebase, classified with the repo's own labels or issue types, ready for /cutter:work. Use when the user runs /cutter:open with something to file.
disable-model-invocation: true
allowed-tools:
  - Bash(git remote get-url origin)
  - Bash(gh auth status)
  - Bash(gh issue list *)
  - Bash(gh label list *)
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

If one already covers it, show it and ask whether to add to it instead.

Then grill: read `references/grill.md` at the plugin root (two levels above this skill's base directory) and follow it. The questions here are product questions — what changes for the user, the edge cases, what counts as done.

## Step 2 — Classify

Decide the kind: `feature`, `bug`, `improvement`, `docs` or `chore`. Then map it to what the repo already has — never create labels or types:

```bash
gh label list --limit 100 --json name,description
gh api graphql -f query='query($o:String!,$r:String!){repository(owner:$o,name:$r){issueTypes(first:25){nodes{name}}}}' -f o=<owner> -f r=<repo>
```

- Issue types (organisation repos only; `null` elsewhere): pick the one that matches — typically `Bug`, `Feature`, `Task`.
- Labels: the matching existing label — `bug` for a bug, `enhancement` for a feature or improvement, `documentation` for docs — if the repo has it. No match, no label.

If the repo has issue forms (`.github/ISSUE_TEMPLATE/*.yml` or `*.yaml`, except `config.yml`), pick the form by the kind: a bug takes the form whose `labels` include the repo's bug label; a feature, improvement, docs or chore takes the one labelled `enhancement`, else the closest by `name`. Read it whole and draft in its shape instead of the layout below: `Form: <file name>` in the header, the form's `labels` as `Labels:`, its `title` as the title's prefix, and one `### <field label>` section per field that is not `type: markdown`, in the form's order — every `required: true` field filled. Markdown (`.md`) templates: follow the matching template's sections.

## Step 3 — Draft and stop

Run `cutter-worktree init` and write the draft to `.cutter/drafts/<short-slug>.md` (slug: lowercase letters, digits and `-`). Line 1 is `# <title>`; optional `Labels: a, b` (existing labels only), `Type: <name>` and `Form: <file name>` lines follow directly; then a blank line and the body:

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

Every criterion is checkable: no `TBD`, `handle edge cases`, `as needed` or the other phrases in `references/banned-phrases.txt` at the plugin root — `cutter-land issue` refuses them outside code, as it refuses an unnumbered criterion, two checkboxes on one line and an empty or missing required form section.

Show the user the title, the kind with the label, type or form it maps to, and the body. **Stop** until the user approves or edits it.

## Step 4 — Create

```bash
cutter-land issue <short-slug>
```

It reads only that draft, refuses a label the repo does not have or a draft that fails the checks above (naming the line or field — fix the draft and run it again), and creates the issue in origin's repo. It is not in this skill's `allowed-tools` on purpose: creating a public issue always asks for permission, so the approval does not rest on the model stopping.

Report the issue URL and the next step, `/cutter:work gh-<n>`. Delete the draft only after the issue exists.

## Several at once

When one request yields several tickets, first show a table of the request's goals, each mapped to the ticket and the criterion that covers it. A goal with no row is raised with the user before any draft is written. Then draft each, show them together, and create the ones the user approves. One issue per independent piece of work: a piece that can ship and be reviewed alone is its own ticket.

## Never

- Never create an issue before the user has seen and approved the draft.
- Never create labels, issue types, milestones or projects.
- Never assign people, set milestones or add to projects unless asked.
- Never put secrets, tokens, internal URLs or customer data in an issue body — it may be public.
- Never reply that something is unverified, unchecked or not yet confirmed: check it first. Only when a check is impossible, say so, naming what was tried and why it cannot be checked.
