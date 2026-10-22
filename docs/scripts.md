# Scripts

On the Bash tool's PATH while the plugin is enabled (not in a plain terminal). The skills call them; you rarely need to.

`veland-verify`, `veland-red-proof` and `veland-worktree add` run the project's own gates and setup commands and its test files, so granting them is as strong as granting the agent permission to write files in the repo.

## veland-worktree

`veland-worktree init|add|list|path|rm <id>|sync-base` — one worktree per ticket.

- `init` first prints where tickets live, `tickets: github` or `tickets: files` (the `tickets` setting; any other value exits 2 before anything is created), then keeps `.veland/` out of git before anything is written there.
- `init <id>` and `add` print `ticket dir: <path>` and `base: <branch> (<ref>)`, the lines the skills resolve `.veland/<id>/` paths and the base from.
- Without an id, `init` prints what `/veland:open` drafts from: the drafts directory, each issue form (`form: <file> name: … labels: … title: … required: … fields: …`, values JSON, or `forms: none`), Markdown templates and the banned phrases.
- `rm` deletes the branch only if git sees it merged.
- `sync-base` fast-forwards the main checkout's base after a merged PR when it is on the base and git allows the fast-forward (unrelated uncommitted changes are kept).

## veland-land

`veland-land check|rebase|push|merge|wait|squash|pr|comment <id>`, `veland-land issue|ticket <slug>` — the writes `/veland:close`, `/veland:open` and `/veland:work` need, each built from the ticket id or draft slug alone.

- `check` prints the configured close mode (`mode: <close>`, refusing any value but `pr`, `pr-merge`, `local`), then, before looking for the worktree, `ticket dir: <path>`, `base: <branch> (<ref>)`, `review: <path>` or `review: missing` and `tickets: <github|files>` (refusing any other value), and lists uncommitted changes. In `pr`/`pr-merge` mode on GitHub it prints the branch's PR state (`pr: MERGED <url>` sends `/veland:close` to cleanup), and in `pr`/`pr-merge` mode the repo's PR/MR template in the worktree (`pr template: <path>`, or `none`).
- `rebase` rebases onto the base (conflicts left for you).
- `push` pushes the ticket branch (lease only if origin has it).
- `merge` squash-merges the open PR/MR into the configured base, pinned to origin's repo and the verified head commit, never a fork's PR/MR, and on GitHub only when the PR's head is the worktree's HEAD, the branch contains `origin/<base>` (exit 4 if it moved) and its checks are green (exit 3 when they are only still running).
- `wait` polls the PR's checks by the same rule until green, failed or 30 minutes.
- `squash` lands the branch on the base as one commit from `.veland/<id>/commit-msg` in `local` mode; for a `gh-<n>` ticket it adds `Closes #<n>` as its own paragraph (before a closing trailer block) unless `commit-msg` has that line, so pushing the base closes the issue.
- `pr` opens the PR/MR from `.veland/<id>/pr-title` + `pr-body.md` or updates only its body, refuses a body that lacks any `##` heading of the template `check` names, and refuses a branch whose PR is already merged.
- `issue` creates an issue from `.veland/drafts/<slug>.md` (existing labels only), then deletes the draft; it refuses `tickets: files` before any `gh` call.
- `ticket` (`tickets: files` only) writes `.veland/drafts/<slug>.md` verbatim to `.veland/<slug>/ticket.md` and deletes the draft, with the checks of `issue` for a draft without forms and no `gh` call or `origin`; it refuses `Labels:`, `Type:` and `Form:` header lines, an existing `.veland/<slug>/`, and the slugs `gh-<n>` and `drafts`.
- `comment` posts `.veland/gh-<n>/comment.md` on issue `<n>` of origin's repo, only when the url in `.veland/gh-<n>/ticket.md`'s header is that issue's, then renames it to `comment.posted.md` so it is posted once.
- `push`, `merge` and `pr` refuse when origin's push URL names another repo than its fetch URL.

## veland-verify

`veland-verify <id>` runs every gate once; fails if the tree moved during the run.

## veland-red-proof

`veland-red-proof <id>` runs the changed tests at HEAD, then reverts the implementation and checks they go red (jest, vitest, `node --test`, or the `redProof` command of any other stack); a test that fails at HEAD exits 2.

## veland-plan-check

`veland-plan-check <id>` refuses `.veland/<id>/plan.md`, naming every line at fault, when:

- a criterion has no `## Tests` row, or the Tests table is missing or has another header;
- a phrase from `references/banned-phrases.txt` appears outside code;
- `## Readers` is empty or an entry has no hit line;
- a `## Tool behaviour relied on` claim has no `$` command block with output;
- `## Overlap` is empty;
- and, ending in `cold read required: <n> files — …`, when `## Files` has more than three top-level bullets and `.veland/<id>/cold-read.md` is missing, blank or not a regular file.

## veland-review-packet

`veland-review-packet <id> [--fixes]` runs `preReviewGates` first (a failure exits 1, no packet), then builds the reviewer's starting material: diff, changed files, conventions, last verify result, and `## Plan checks` — each `## Tests` case not among its test file's added lines on the branch, and each `(gone)` Readers term still in the tree.

- It adds `security review: required` with the reasons when the diff touches a script a skill grants in `allowed-tools`, a skill's or agent's frontmatter, `hooks/hooks.json`, a script it registers, or a file such a script or hook loads (one level, by a static `source` or relative `require`).
- `--fixes` covers only the commits since the last review, with its findings (the plan checks still read the whole branch).

## veland-batch

The mechanics of `/veland:batch`. Refusals print `veland-batch: <why>` on stderr with exit 2.

- `veland-batch init <arg>... [--search "<query>"]` resolves every argument to a ticket (`gh-<n>`, `<n>`, `#<n>`, an issue URL of origin's repo, an existing id) before writing anything, then writes `.veland/_batch/tickets` and the board. A batch with an unsettled ticket is not replaced; a settled one is moved to `.veland/_batch.<timestamp>/`.
- `veland-batch run <id> <plan|reply|implement|close>` runs one worker turn in the foreground: `claude -p` (or `$VELAND_BATCH_CLAUDE`) with `--session-id`, or `--resume` for `reply`, which sends `.veland/_batch/<id>/reply.md`. It records `runs.tsv`, the stream-json log, the permission denials and `turn.md` (every assistant text block of the run) under `.veland/_batch/<id>/`, and refuses what `status` would not list.
- `veland-batch status` rewrites and prints the board, then the actions allowed now: `plan <id>`, `implement <id>`, `close <id>`, `answer <id>` (` approvable` when a passing draft can be approved) and `done`.
- `veland-batch drop <id>` stops the ticket's running worker and never schedules it again.

`batch.parallel` ([configuration](configuration.md)) caps the implementation workers.

## veland-grill

`veland-grill` prints the shared grill (`references/grill.md`) that `/veland:open` and `/veland:work` follow; a skill cannot Read a file under the plugin root without a prompt.

## veland-ticket

- `veland-ticket github <ref> [--out <path>]` prints a GitHub issue of origin's repo as Markdown, or writes it to `--out`, which must be that issue's `.veland/gh-<n>/ticket.md` (a number, or that repo's issue URL; another repo's is refused, and so is any other argument).
- `veland-ticket issue-types` prints the issue types of origin's repo, one per line; nothing for a repo without them.
