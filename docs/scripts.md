# Scripts

On the Bash tool's PATH while the plugin is enabled (not in a plain terminal). The skills call them; you rarely need to.

`cutter-verify`, `cutter-red-proof` and `cutter-worktree add` run the project's own gates and setup commands and its test files, so granting them is as strong as granting the agent permission to write files in the repo.

## cutter-worktree

`cutter-worktree init|add|list|path|rm <id>|sync-base` — one worktree per ticket.

- `init` keeps `.cutter/` out of git before anything is written there.
- `init <id>` and `add` print `ticket dir: <path>` and `base: <branch> (<ref>)`, the lines the skills resolve `.cutter/<id>/` paths and the base from.
- Without an id, `init` prints what `/cutter:open` drafts from: the drafts directory, each issue form (`form: <file> name: … labels: … title: … required: … fields: …`, values JSON, or `forms: none`), Markdown templates and the banned phrases.
- `rm` deletes the branch only if git sees it merged.
- `sync-base` fast-forwards the main checkout's base after a merged PR when it is on the base and git allows the fast-forward (unrelated uncommitted changes are kept).

## cutter-land

`cutter-land check|rebase|push|merge|wait|squash|pr|comment <id>`, `cutter-land issue <slug>` — the writes `/cutter:close`, `/cutter:open` and `/cutter:work` need, each built from the ticket id or draft slug alone.

- `check` prints the configured close mode (`mode: <close>`, refusing any value but `pr`, `pr-merge`, `local`), then, before looking for the worktree, `ticket dir: <path>`, `base: <branch> (<ref>)` and `review: <path>` or `review: missing`, and lists uncommitted changes. In `pr`/`pr-merge` mode on GitHub it prints the branch's PR state (`pr: MERGED <url>` sends `/cutter:close` to cleanup), and in `pr`/`pr-merge` mode the repo's PR/MR template in the worktree (`pr template: <path>`, or `none`).
- `rebase` rebases onto the base (conflicts left for you).
- `push` pushes the ticket branch (lease only if origin has it).
- `merge` squash-merges the open PR/MR into the configured base, pinned to origin's repo and the verified head commit, never a fork's PR/MR, and on GitHub only when the PR's head is the worktree's HEAD, the branch contains `origin/<base>` (exit 4 if it moved) and its checks are green (exit 3 when they are only still running).
- `wait` polls the PR's checks by the same rule until green, failed or 30 minutes.
- `squash` lands the branch on the base as one commit from `.cutter/<id>/commit-msg` in `local` mode.
- `pr` opens the PR/MR from `.cutter/<id>/pr-title` + `pr-body.md` or updates only its body, refuses a body that lacks any `##` heading of the template `check` names, and refuses a branch whose PR is already merged.
- `issue` creates an issue from `.cutter/drafts/<slug>.md` (existing labels only), then deletes the draft.
- `comment` posts `.cutter/gh-<n>/comment.md` on issue `<n>` of origin's repo, only when the url in `.cutter/gh-<n>/ticket.md`'s header is that issue's, then renames it to `comment.posted.md` so it is posted once.
- `push`, `merge` and `pr` refuse when origin's push URL names another repo than its fetch URL.

## cutter-verify

`cutter-verify <id>` runs every gate once; fails if the tree moved during the run.

## cutter-red-proof

`cutter-red-proof <id>` runs the changed tests at HEAD, then reverts the implementation and checks they go red (jest, vitest, `node --test`, or the `redProof` command of any other stack); a test that fails at HEAD exits 2.

## cutter-plan-check

`cutter-plan-check <id>` refuses `.cutter/<id>/plan.md`, naming every line at fault, when:

- a criterion has no `## Tests` row, or the Tests table is missing or has another header;
- a phrase from `references/banned-phrases.txt` appears outside code;
- `## Readers` is empty or an entry has no hit line;
- a `## Tool behaviour relied on` claim has no `$` command block with output;
- `## Overlap` is empty;
- and, ending in `cold read required: <n> files — …`, when `## Files` has more than three top-level bullets and `.cutter/<id>/cold-read.md` is missing, blank or not a regular file.

## cutter-review-packet

`cutter-review-packet <id> [--fixes]` runs `preReviewGates` first (a failure exits 1, no packet), then builds the reviewer's starting material: diff, changed files, conventions, last verify result, and `## Plan checks` — each `## Tests` case not among its test file's added lines on the branch, and each `(gone)` Readers term still in the tree.

- It adds `security review: required` with the reasons when the diff touches a script a skill grants in `allowed-tools`, a skill's or agent's frontmatter, `hooks/hooks.json`, a script it registers, or a file such a script or hook loads (one level, by a static `source` or relative `require`).
- `--fixes` covers only the commits since the last review, with its findings (the plan checks still read the whole branch).

## cutter-grill

`cutter-grill` prints the shared grill (`references/grill.md`) that `/cutter:open` and `/cutter:work` follow; a skill cannot Read a file under the plugin root without a prompt.

## cutter-ticket

- `cutter-ticket github <ref> [--out <path>]` prints a GitHub issue of origin's repo as Markdown, or writes it to `--out`, which must be that issue's `.cutter/gh-<n>/ticket.md` (a number, or that repo's issue URL; another repo's is refused, and so is any other argument).
- `cutter-ticket issue-types` prints the issue types of origin's repo, one per line; nothing for a repo without them.
