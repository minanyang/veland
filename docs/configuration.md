# Configuration

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

The close modes are described in [the loop](loop.md#cutterclose-id).

## Where each key is read from

`cutter-verify` reads `gates` from the ticket's worktree, so a gate the ticket adds verifies that ticket; when the list differs from the base branch's, it lists the gates added and removed. The context gate reads `contextGate` from the nearest `.claude/cutter.json` at or above the session's working directory, up to the repo root (none outside a repo), so inside a worktree it is the worktree's file. `redProof` and `preReviewGates` are read from the ticket's worktree, else the main checkout. Every other key comes from the main checkout.

`.cutter/` and the worktree directory are added to `.git/info/exclude` automatically — your `.gitignore` is not touched.
