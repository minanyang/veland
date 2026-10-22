---
name: roadmap
description: Keep `.veland/roadmap.md` — an ordered table of versions, each with the reason for its place, plus what is not yet assigned, later or decided against. Merges new requirements into it once the user approves, shows it, and turns a version into one ticket per item for /veland:batch <version>. Use when the user runs /veland:roadmap.
disable-model-invocation: true
allowed-tools:
  - Bash(veland-worktree init)
  - Bash(veland-grill)
  - Bash(veland-roadmap show)
  - Bash(veland-roadmap show *)
  - Bash(veland-roadmap check)
  - Bash(veland-roadmap apply)
  - Bash(veland-roadmap link *)
  - Bash(veland-land ticket *)
  - Bash(git remote get-url origin)
  - Bash(gh auth status)
  - Bash(gh label list *)
  - Bash(gh issue list *)
  - Bash(veland-ticket issue-types)
---

# Keep the roadmap

`/veland:roadmap [requirements]` keeps `.veland/roadmap.md`: which version comes next, what is in it, and why it comes where it does. The file is inside `.veland/`, so it is never committed. `veland-roadmap` is its only reader and writer: it checks a draft, applies it, links ticket ids and shows the file. This skill never writes `.veland/roadmap.md` itself.

Run one command per Bash call — no `&&`, `;` or `|`. The arguments pick the path:

- None → **Show**.
- Exactly `tickets <name>` → run `veland-roadmap show <name>`. When it prints that version, take **Tickets**; otherwise the arguments are requirements.
- Anything else → **Requirements**.

## The file

```markdown
# Roadmap

| Version | Contents | Why this order | State |
|---|---|---|---|
| v1 | Export as CSV `gh-12`; Export as JSON `gh-13` | Both reuse the existing export path and ship alone | Done 2026-10-20 |
| v2 | Scheduled exports | Needs v1's formats; the riskiest piece, so it waits | Planned |

## Not yet assigned
- Export to S3

## Later
- A web UI for exports

## Decided against
- Excel export — CSV opens in Excel; a second writer to maintain is not worth it
```

- One row per version, in the order they ship. A `Version` is letters, digits, `.`, `_` and `-`, starts with a letter or digit, is unique and is never all digits (`v1`, `0.2`, `beta`).
- `Contents` holds the version's items separated by `; `. An item that has a ticket ends with its id in backticks (`gh-<n>` or a `.veland/<id>/` slug); `veland-roadmap link` adds it, never you. A `|` inside a cell is written `\|`.
- `Why this order` is never empty: why this version comes here — what it depends on, the risk it takes or retires, whether it ships alone.
- `State` is free text (`Planned`, `In progress`); `Done <YYYY-MM-DD>` is written only by `/veland:batch <version>` once all the row's tickets have landed.
- The three sections each appear once, after the table. A `## Decided against` entry gives its reason after ` — `.

## Show

```bash
veland-roadmap show
```

Relay its output as printed — each version with its state and numbered items, then `next:` — and stop. A `no roadmap:` line is relayed with the next step, `/veland:roadmap <requirements>`. Write nothing.

## Requirements

### Step 1 — Ground it

```bash
veland-worktree init
veland-roadmap show
```

A non-zero exit from either stops the skill: relay its message. `init` keeps `.veland/` out of git before anything is written there. `show` prints the roadmap as it is now; when it prints `no roadmap:`, the draft starts from the layout above with no rows.

Read just enough of the codebase to place each requirement: what already exists, what it would build on, what it would touch. A claim about the code carries its evidence (`path:line`, or the command run and its output); a claim with none is looked up before it is shown.

Then grill: run `veland-grill`, which prints the plugin's shared `references/grill.md`, and follow it. The questions are product questions — what each requirement gives the user, which ones belong together, what must come first, what can wait or should not be done at all. The roadmap has no `## Assumptions` section: every assumption the grill leaves goes into the proposal message (Step 3), above the draft.

### Step 2 — Draft

Write `.veland/roadmap.draft.md`. It starts as a byte-for-byte copy of `.veland/roadmap.md` (Read it whole), or of the layout above when there is none, and the new requirements are merged into it:

- Each requirement goes into a version, or into `## Not yet assigned`, `## Later` or `## Decided against` (with its reason).
- A new version is a new row, placed by order: what it depends on first, then risk, then what can ship alone. Moving a row up or down keeps it.
- Every existing row, state and section entry stays byte-for-byte. Change one only when the user's own words ask for it (move, drop, rename, re-scope) — never to tidy it, and never a `Done` row.

Then:

```bash
veland-roadmap check
```

On exit 1, each `<file>:<line>: <why>` names a fault: fix the draft and run it again until it exits 0. Exit 2 (`veland-roadmap: <why>`) stops the skill: relay it. On exit 0, each `not kept: <line>` is an existing row or entry the draft no longer has as it was. One the user did not ask to change is restored from `.veland/roadmap.md` and `check` run again. Each `new id: <version> <id>` is a ticket id the draft adds to a row; add one only for a ticket the user named or approved in this session.

### Step 3 — Show and stop

Show, in one message: the assumptions the grill left (omit when none); the draft's path; the draft verbatim as rendered markdown; then the `not kept:` and `new id:` lines `check` printed, verbatim — or, when it printed no `not kept:` line, that every existing row and entry is kept. **Stop** until the user approves or asks for changes. Changes go into the draft, then `check` again and the draft shown again.

### Step 4 — Apply

Only after the user approves:

```bash
veland-roadmap apply
```

It checks the draft again and writes nothing on a fault: fix, show again and wait. Otherwise it renames the draft to `.veland/roadmap.md` and prints `roadmap: <path>` and the `not kept:` and `new id:` lines. Report those, and the next step: `/veland:roadmap tickets <next version>`.

## Tickets

`/veland:roadmap tickets <version>` turns each item of the version that has no ticket id into one ticket. `show` has already printed the items, numbered.

### Step 1 — Ground it

```bash
veland-worktree init
```

A non-zero exit stops the skill: relay its message. Its first line, `tickets: github` or `tickets: files`, picks the path for the rest of this section. The lines after it are what the drafts are built from: `drafts: <path>`, one `form: <file> name: … labels: … title: … required: … fields: …` line per issue form (or `forms: none`), one `template: <file>` line per Markdown template, and `banned: […]`. Values are JSON.

With `tickets: github`, check:

```bash
git remote get-url origin
gh auth status
```

Stop, saying which and how to fix it, when `origin` is not on github.com, `gh` is not installed (command not found → https://cli.github.com), or not logged in (non-zero exit → `gh auth login`). With `tickets: files`, run no `gh` command and no git remote command anywhere in this section.

Items that already end in an id are skipped. When none is left, say so and stop.

Read just enough of the codebase to make each item concrete, with evidence as in Requirements Step 1. Look for an existing ticket for each item first. With `tickets: github`:

```bash
gh issue list --state open --search "<key words>" --limit 10
```

With `tickets: files`, search the titles — line 1 — of every `.veland/*/ticket.md` with the Grep tool. A match is offered for linking instead of a new ticket; on the user's yes, link it as in Step 4.

Then grill once for the whole version: run `veland-grill` and ask the product questions of all its items in one round.

### Step 2 — Classify

With `tickets: files`, only the kind: `feature`, `bug`, `improvement`, `docs` or `chore`. With `tickets: github`, map each item's kind to what the repo already has — never create labels or types:

```bash
gh label list --limit 100 --json name,description
veland-ticket issue-types
```

A non-zero exit from `veland-ticket issue-types` stops the skill: relay its message. Pick the matching issue type (`Bug`, `Feature`, `Task`) and existing label (`bug`, `enhancement`, `documentation`); no match, none. With `form:` lines, a bug takes the form whose `labels` include the repo's bug label and anything else the one labelled `enhancement`; draft in its shape: `Form: <file>` and its `labels` as `Labels:` in the header, its `title` (unless `none`) as the title's prefix, one `### <label>` section per `fields:` entry, in order, every `required:` one filled. A `form: <file> error: …` line is relayed and that form not used.

### Step 3 — Draft and stop

One draft per item, at `<drafts>/<slug>.md`, `<drafts>` being `init`'s `drafts:` path. The slug comes from the item's text: lowercase letters, digits and `-`, starting with a letter or digit, never `gh-<n>` or `drafts`; with `tickets: files` it becomes the ticket id. Line 1 is `# <title>`; with `tickets: github`, optional `Labels: a, b`, `Type: <name>` and `Form: <file>` lines follow directly — a `tickets: files` draft has none; then a blank line and the body:

```markdown
# <title>
Labels: <label>
Type: <issue type>

## Context
What happens today and where — name the files or routes. The roadmap version this item belongs to.

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

No `TBD`, `handle edge cases`, `as needed` or other phrase on `init`'s `banned:` line outside code: the create commands refuse them, as they refuse an unnumbered criterion.

Show all the drafts together, each once: its item (`<n>. <item>`), one line `Kind: <kind> → <label, type or form file name>` (or `→ ticket file`), its path, then the file verbatim as rendered markdown. **Stop** until the user approves or edits them.

### Step 4 — Create and link

For each approved draft, with `tickets: files`:

```bash
veland-land ticket <slug>
```

It prints `ticket: <path>`; the id is the slug. With `tickets: github`:

```bash
veland-land issue <slug>
```

It is not in this skill's `allowed-tools` on purpose: creating a public issue always asks for permission. It prints the issue URL from `gh`; the id is `gh-<n>`, `<n>` read from that URL. Either refuses a draft that fails its checks, naming the line — fix it and run it again. Then link the new ticket to its item, `<n>` being the item's number in `show`'s output:

```bash
veland-roadmap link <version> <n> <id>
```

Exit 2 (`veland-roadmap: <why>`) is relayed; never edit the roadmap to work around it. Report each item with its id, and the next step: `/veland:batch <version>`.

## Replies

- Lead with the result. No first sentence that announces what comes next, and no closing recap or offer.
- Between routine tool calls, at most one line per phase change — a phase is one of this skill's numbered steps.
- Say each fact once: what the reply has already shown is not summarised again.

Some things are exempt from these rules and are written in full: a security warning; a question to the user; and anything persisted — the draft roadmap, issue bodies, and the files under `.veland/`.

The final reply is the path's last step: `show`'s output, `apply`'s `roadmap:`, `not kept:` and `new id:` lines with the next step, or the ids linked with the next step.

## Never

- Never write `.veland/roadmap.md` with Write, Edit or a shell redirect; it changes only through `veland-roadmap apply` and `veland-roadmap link`.
- Never run `veland-roadmap apply` before the user has seen and approved the draft.
- Never change an existing row, state or section entry the user did not ask to change.
- Never create an issue or a ticket file before the user has seen and approved its draft.
- Never create labels, issue types, milestones or projects.
- Never put secrets, tokens, internal URLs or customer data in an issue body — it may be public.
- Never reply that something is unverified, unchecked or not yet confirmed: check it first. Only when a check is impossible, say so, naming what was tried and why it cannot be checked.
