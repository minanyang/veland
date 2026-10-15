---
name: threat-model
description: cutter's core trust boundary — skills grant wrapper scripts (cutter-land etc.) via allowed-tools; the scripts must build gh/glab/git argv themselves
metadata:
  type: project
---

The main boundary is the Claude Code permission system: skills declare `allowed-tools` (e.g. `Bash(cutter-land *)`), so anything a granted wrapper can do runs without a prompt. Wrappers take only an id/slug and build argv from origin, config and files under `.cutter/`.

**Why:** a grant on raw `gh`/`glab`/`git push` could be stretched into merge, force-push, or a different repo; the wrappers exist to stop that.

**How to apply:** when reviewing a wrapper, check (1) argv can't take flags from input, (2) repo/host stays pinned to origin, (3) which file paths it reads. Content the agent writes into `.cutter/` (PR body, issue draft) is agent-controlled. Prompt-injected text from issues or code can reach a published PR or issue unless something else gates it (a Write prompt, the user's approval). An `allowed-tools` prefix like `cutter-land *` covers every subcommand, including ones meant for other skills.

`cutter-land pr` (PR/MR create/edit) is granted in close and does not prompt. Since gh-35 (2026-10), `cutter-land issue` and `cutter-land comment` are deliberately NOT granted (public writes always prompt; `tests/skills.test.sh` fails on any grant in any skill that covers them, bare `Bash` included). The issue-draft content checks in `cutter-land issue` are quality gates, not a security boundary. Repo pinning comes from parsing origin's URL in `origin_parts`, so check any change to that parser.

`cutter-ticket --out` (#25, granted via `cutter-ticket *`) writes only `.cutter/gh-<n>/ticket.md`. `.git/info/exclude` does not stop a cloned repo from tracking `.cutter/...` symlinks, so check every path component of a pre-approved write, not only the leaf. That includes rename destinations: `mv -f a b` follows a symlink-to-dir `b` on macOS (verified in gh-24), so `need_file` on the source alone doesn't keep it inside `.cutter/`. Repo-controlled `.claude/cutter.json` (incl. a worktree's, which the agent edits) only tunes the context gate, which is a cost control and not a security boundary.

Claude Code matches allow rules per subcommand (split on `&& || ; | |& &` newline) after stripping wrappers (`timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, `noglob`, bare `xargs`, known-safe `VAR=` prefixes); redirect targets get a separate Edit/working-dir check. gh-22 tried a text guard rule ("a cutter script runs alone") and withdrew it (f008fb7): a probe of the engine's `tool.check` showed `cutter-x … > f`, `>f cutter-x …` and `ls; cutter-x …` already get `ask`, not `allow`, under `Bash(cutter-x *)`. The engine, not guard-bash.sh, is the boundary for stretched grants; don't re-request a text rule unless a new probe shows an `allow`.

Since gh-26, `.github/workflows/ci.yml` runs on `pull_request` (not `_target`), `contents: read`, no secrets, actions SHA-pinned; gates are the branch's own `.claude/cutter.json`, so CI green certifies whatever gate list the branch declares. `cutter-land merge`'s checks gate is a safety rail against merging red, not an authz boundary: its "no checks → is CI expected?" test reads the branch's workflows, so a branch can opt itself out. Judge it as fail-closed vs fail-open, not as a security boundary.
