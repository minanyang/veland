#!/bin/bash
# Shared helpers for veland's bin/ scripts. Sourced, never run.
#
# Layout inside the project (the main checkout, wherever the script is called from):
#   .claude/veland.json   optional project config, committed
#   .veland/<id>/         ticket files (spec, plan, review, logs), never committed
#   .worktrees/<id>/      one worktree per ticket (configurable: worktreeDir)
# Both .veland/ and the worktree dir are added to .git/info/exclude, never to .gitignore.

say() { printf '%s\n' "$*"; }
die() { printf 'veland: %s\n' "$*" >&2; exit 2; }
# Newlines and carriage returns escaped, other control characters replaced: a value must not print lines
# that read as a script's own (a forged `pr:` or `ticket dir:`).
shown() { local s="${1//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; printf '%s' "${s//[[:cntrl:]]/?}"; }

# The main checkout's root, also when called from inside a worktree.
main_root() {
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die "not inside a git repository"
  dirname "$common"
}

ROOT="$(main_root)"
CONFIG="$ROOT/.claude/veland.json"

# cfg <dotted.key> [default] — print a config value (arrays one item per line).
cfg() { cfg_in "$CONFIG" "$@"; }

# cfg_in <file> <dotted.key> [default] — the same, from another config file.
cfg_in() {
  local file=$1; shift
  [ -f "$file" ] || { [ $# -gt 1 ] && printf '%s\n' "$2"; return 0; }
  # shellcheck disable=SC2016  # JavaScript, not shell
  node -e '
    const [file, key, dflt] = process.argv.slice(1)
    let v
    try { v = key.split(".").reduce((o, k) => (o == null ? undefined : o[k]), JSON.parse(require("fs").readFileSync(file, "utf8"))) }
    catch (e) { console.error(`veland: cannot read ${file}: ${e.message}`); process.exit(2) }
    if (v === undefined || v === null) { if (dflt !== undefined) console.log(dflt); process.exit(0) }
    console.log(Array.isArray(v) ? v.join("\n") : typeof v === "object" ? JSON.stringify(v) : String(v))
  ' "$file" "$1" ${2+"$2"}
}

# wt_cfg <worktree> <dotted.key> — a config value from the worktree's veland.json, else the main checkout's.
wt_cfg() {
  local file="$1/.claude/veland.json"
  [ -f "$file" ] || file="$CONFIG"
  cfg_in "$file" "$2"
}

# gate_changes <base-cfg> <cfg> — gates added (+) and removed (-) in <cfg> against <base-cfg>; an empty or missing base lists every gate as added.
gate_changes() {
  gate_set() { [ -s "$1" ] && cfg_in "$1" gates | sed '/^$/d' | sort -u; }
  comm -3 <(gate_set "$1") <(gate_set "$2") | awk -F'\t' '{ print ($1 == "" ? "  + " $2 : "  - " $1) }'
}

check_id() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid ticket id '$1' (letters, digits, . _ -)"
}

worktree_dir() { printf '%s/%s\n' "$ROOT" "$(cfg worktreeDir .worktrees)"; }
task_dir() { printf '%s/.veland/%s\n' "$ROOT" "$1"; }

# The worktree of ticket <id>, or die.
wt_path() {
  local p
  p="$(worktree_dir)/$1"
  [ -e "$p/.git" ] || die "ticket $1 has no worktree at $p (run: veland-worktree add $1)"
  printf '%s\n' "$p"
}

# Base branch name: config `base`, else develop if origin has it, else origin's default, else main.
base_branch() {
  local b
  b="$(cfg base)"
  if [ -z "$b" ]; then
    if git -C "$ROOT" show-ref --verify --quiet refs/remotes/origin/develop; then b=develop
    else b="$(git -C "$ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"; b="${b#origin/}"
    fi
  fi
  printf '%s\n' "${b:-main}"
}

# A ref to start from and diff against: origin/<base> when the remote has it, else the local branch.
# In `close: local` mode the local base wins when it contains origin/<base>: tickets squashed onto it
# but not pushed yet are part of the base.
base_ref() {
  local b
  b="$(base_branch)"
  if ! git -C "$ROOT" show-ref --verify --quiet "refs/remotes/origin/$b"; then printf '%s\n' "$b"
  elif [ "$(cfg close pr)" = local ] && git -C "$ROOT" merge-base --is-ancestor "refs/remotes/origin/$b" "refs/heads/$b" 2>/dev/null; then printf '%s\n' "$b"
  else printf 'origin/%s\n' "$b"
  fi
}

# The lines the skills resolve `.veland/<id>/` paths and the base from: `ticket dir: <abs>` and `base: <branch> (<ref>)`.
ticket_lines() { # <id>
  say "ticket dir: $(shown "$(task_dir "$1")")"
  say "base: $(shown "$(base_branch)") ($(shown "$(base_ref)"))"
}

# In `close: local` mode, true when the local base and origin/<base> each have commits the other lacks.
base_diverged() {
  local b
  b="$(base_branch)"
  [ "$(cfg close pr)" = local ] || return 1
  git -C "$ROOT" show-ref --verify --quiet "refs/remotes/origin/$b" || return 1
  git -C "$ROOT" show-ref --verify --quiet "refs/heads/$b" || return 1
  ! git -C "$ROOT" merge-base --is-ancestor "refs/remotes/origin/$b" "refs/heads/$b" &&
    ! git -C "$ROOT" merge-base --is-ancestor "refs/heads/$b" "refs/remotes/origin/$b"
}

# Package manager from the lockfile in <dir>.
package_manager() {
  if [ -f "$1/pnpm-lock.yaml" ]; then echo pnpm
  elif [ -f "$1/yarn.lock" ]; then echo yarn
  elif [ -f "$1/bun.lockb" ] || [ -f "$1/bun.lock" ]; then echo bun
  elif [ -f "$1/package-lock.json" ]; then echo npm
  else echo npm
  fi
}

has_script() { # <dir> <script>
  [ -f "$1/package.json" ] && node -e 'process.exit((require(process.argv[1]).scripts || {})[process.argv[2]] ? 0 : 1)' "$1/package.json" "$2"
}

# Keep veland's directories out of git without touching the project's .gitignore.
ensure_excluded() {
  local exclude entry
  exclude="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  mkdir -p "$(dirname "$exclude")"
  touch "$exclude"
  for entry in "/.veland/" "/$(cfg worktreeDir .worktrees)/"; do
    grep -qxF "$entry" "$exclude" || printf '%s\n' "$entry" >>"$exclude"
  done
}

# Agents may write their memory into a worktree while it is frozen; it is committed later
# (veland-worktree memory), so it never counts as a change to the tree under test.
MEMORY_EXCLUDE=':(exclude).claude/agent-memory'
tree_status() { git -C "$1" status --porcelain -- . "$MEMORY_EXCLUDE"; } # <dir>

# Ticket-level lock shared by verify and red-proof, so a test run never overlaps a tree rewrite.
take_lock() { # <id>
  local lock
  lock="$(task_dir "$1")/lock"
  mkdir -p "$(task_dir "$1")"
  mkdir "$lock" 2>/dev/null || die "ticket $1 is already being verified or red-proofed (lock: $lock, pid $(cat "$lock/pid" 2>/dev/null || echo '?')); remove the directory if that process is gone"
  echo $$ >"$lock/pid"
  LOCK_DIR="$lock"
}
release_lock() { [ -n "${LOCK_DIR:-}" ] && rm -r "$LOCK_DIR" 2>/dev/null; return 0; }
