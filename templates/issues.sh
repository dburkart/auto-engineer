#!/usr/bin/env bash
# scripts/issues — local todo-tracker CLI
#
# Stores issues on an orphan `tracker` branch, accessed via a pinned worktree
# at .auto-engineer/worktree/. Main and feature branches never see issue files;
# tracker state evolves on its own branch with its own history.
#
# Self-bootstraps: on first invocation, creates the orphan branch + worktree
# if they don't exist yet. Fetches origin/tracker before every read and
# push-with-rebase-retry after every write.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
BRANCH="tracker"
WORKTREE="$REPO_ROOT/.auto-engineer/worktree"
ISSUES_DIR="$WORKTREE/.auto-engineer/issues"
REMOTE="origin"
LOCK_FILE="$REPO_ROOT/.auto-engineer/.lock"
LOCK_TIMEOUT=60

die() { echo "issues: $*" >&2; exit 1; }

acquire_lock() {
  command -v flock >/dev/null 2>&1 || die "flock is required but not found in PATH"
  mkdir -p "$(dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  flock -w "$LOCK_TIMEOUT" 9 || die "timed out after ${LOCK_TIMEOUT}s waiting for lock at $LOCK_FILE"
}
now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

normalize_id() {
  local raw="${1#\#}"
  [[ "$raw" =~ ^[0-9]+$ ]] || die "invalid issue id: $1"
  printf "%04d" "$((10#$raw))"
}

# ---- bootstrap ----

remote_has_tracker() {
  git -C "$REPO_ROOT" ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1
}

local_has_tracker() {
  git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"
}

init_orphan_branch() {
  local tmp; tmp="$(mktemp -d)"
  (
    cd "$tmp"
    git init -q -b "$BRANCH" .
    mkdir -p .auto-engineer/issues
    touch .auto-engineer/issues/.gitkeep
    cat > README.md <<'EOF'
# Tracker state branch

This branch holds the auto-engineer local to-do tracker state.
It is an **orphan branch** — it shares no history with `main`.
Every commit here mutates issue files under `.auto-engineer/issues/`.

Do not merge this branch into `main` or vice versa. Use the
`scripts/issues` CLI (from main) to read and mutate issues.
EOF
    git add -A
    git -c commit.gpgsign=false commit -q -m "Initialize tracker branch"
    git remote add "$REMOTE" "$(git -C "$REPO_ROOT" remote get-url "$REMOTE")"
    git push -q "$REMOTE" "$BRANCH"
  )
  rm -rf "$tmp"
  git -C "$REPO_ROOT" fetch -q "$REMOTE" "$BRANCH"
}

ensure_worktree() {
  if [ -d "$WORKTREE/.git" ] || [ -f "$WORKTREE/.git" ]; then
    return
  fi

  git -C "$REPO_ROOT" fetch -q "$REMOTE" "$BRANCH" 2>/dev/null || true

  if ! remote_has_tracker && ! local_has_tracker; then
    echo "issues: initializing orphan '$BRANCH' branch (first run)..." >&2
    init_orphan_branch
  elif ! local_has_tracker; then
    git -C "$REPO_ROOT" branch -q --track "$BRANCH" "$REMOTE/$BRANCH"
  fi

  mkdir -p "$(dirname "$WORKTREE")"
  git -C "$REPO_ROOT" worktree add -q "$WORKTREE" "$BRANCH"
}

sync_worktree() {
  git -C "$WORKTREE" fetch -q "$REMOTE" "$BRANCH"
  git -C "$WORKTREE" reset --hard -q "$REMOTE/$BRANCH"
}

commit_push() {
  local msg="$1"
  git -C "$WORKTREE" add -A
  if git -C "$WORKTREE" diff --cached --quiet; then return; fi
  git -C "$WORKTREE" -c commit.gpgsign=false commit -q -m "$msg" -m "[skip ci]"
  local attempt=0
  while [ "$attempt" -lt 5 ]; do
    if git -C "$WORKTREE" push -q "$REMOTE" "$BRANCH" 2>/dev/null; then return; fi
    attempt=$((attempt + 1))
    git -C "$WORKTREE" fetch -q "$REMOTE" "$BRANCH"
    git -C "$WORKTREE" rebase -q "$REMOTE/$BRANCH" || {
      git -C "$WORKTREE" rebase --abort 2>/dev/null || true
      die "rebase conflict on tracker branch — resolve manually in $WORKTREE"
    }
  done
  die "failed to push tracker changes after 5 attempts"
}

# ---- frontmatter helpers ----

fm_get() {
  local file="$1" key="$2"
  awk -v k="$key" '
    NR==1 && /^---$/ { fm=1; next }
    fm && /^---$/ { exit }
    fm && $1 == k":" {
      sub(/^[^:]+: */, "")
      if (length($0) >= 2 && substr($0, 1, 1) == "\"" && substr($0, length($0), 1) == "\"") {
        $0 = substr($0, 2, length($0) - 2)
      }
      print
      exit
    }
  ' "$file"
}

fm_set() {
  local file="$1" key="$2" val="$3"
  local tmp; tmp="$(mktemp)"
  awk -v k="$key" -v v="$val" '
    BEGIN { in_fm=0; set=0 }
    NR==1 && /^---$/ { in_fm=1; print; next }
    in_fm && /^---$/ {
      if (!set) printf("%s: %s\n", k, v)
      in_fm=0; print; next
    }
    in_fm && $1 == k":" { printf("%s: %s\n", k, v); set=1; next }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

bump_updated() { fm_set "$1" "updated" "$(now_utc)"; }

next_id() {
  local max=0 f id
  shopt -s nullglob
  for f in "$ISSUES_DIR"/*.md; do
    id="$(basename "$f" .md)"
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    (( 10#$id > max )) && max="$((10#$id))"
  done
  shopt -u nullglob
  printf "%04d" "$((max + 1))"
}

labels_to_json() {
  local raw="$1"
  raw="${raw#[}"; raw="${raw%]}"
  if [ -z "$raw" ]; then printf "[]"; return; fi
  printf "["
  local first=1 IFS=','
  for item in $raw; do
    item="${item# }"; item="${item% }"
    [ -n "$item" ] || continue
    [ $first -eq 1 ] || printf ","
    printf "\"%s\"" "$item"
    first=0
  done
  printf "]"
}

# ---- subcommands ----

cmd_list() {
  ensure_worktree; sync_worktree
  local show_all=0 as_json=0
  for arg in "$@"; do
    case "$arg" in
      --all) show_all=1 ;;
      --json) as_json=1 ;;
      *) die "unknown flag: $arg" ;;
    esac
  done

  local first=1
  if [ $as_json -eq 1 ]; then printf "["; fi
  shopt -s nullglob
  for f in "$ISSUES_DIR"/*.md; do
    local id state title labels assignee
    id="$(basename "$f" .md)"
    state="$(fm_get "$f" state)"
    title="$(fm_get "$f" title)"
    labels="$(fm_get "$f" labels)"
    assignee="$(fm_get "$f" assignee)"
    if [ "$show_all" -eq 0 ] && [ "$state" != "open" ]; then continue; fi

    if [ $as_json -eq 1 ]; then
      [ $first -eq 1 ] || printf ","
      printf '{"id":"%s","state":"%s","title":%s,"labels":%s,"assignee":%s}' \
        "$id" "$state" \
        "$(printf '%s' "$title" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        "$(labels_to_json "$labels")" \
        "$(printf '%s' "${assignee:-}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
      first=0
    else
      printf "#%s  [%-6s]  %s\n" "$id" "$state" "$title"
    fi
  done
  shopt -u nullglob
  if [ $as_json -eq 1 ]; then printf "]\n"; fi
}

cmd_show() {
  ensure_worktree; sync_worktree
  local id="" as_json=0
  for arg in "$@"; do
    case "$arg" in
      --json) as_json=1 ;;
      *) id="$arg" ;;
    esac
  done
  [ -n "$id" ] || die "usage: issues show <id>"
  id="$(normalize_id "$id")"
  local f="$ISSUES_DIR/$id.md"
  [ -f "$f" ] || die "no such issue: #$id"
  if [ $as_json -eq 1 ]; then
    python3 - "$f" <<'PY'
import json, sys, re
path = sys.argv[1]
with open(path) as fh:
    raw = fh.read()
m = re.match(r'^---\n(.*?)\n---\n(.*)$', raw, re.DOTALL)
fm = {}
if m:
    for line in m.group(1).splitlines():
        if ": " not in line:
            continue
        k, v = line.split(": ", 1)
        k = k.strip()
        v = v.strip()
        if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
            v = v[1:-1]
        if k == "labels":
            inner = v.strip()
            if inner.startswith("[") and inner.endswith("]"):
                inner = inner[1:-1]
            items = [x.strip() for x in inner.split(",") if x.strip()]
            fm[k] = items
        else:
            fm[k] = v
    body = m.group(2)
else:
    body = raw
fm["body"] = body
print(json.dumps(fm))
PY
  else
    cat "$f"
  fi
}

cmd_new() {
  ensure_worktree; sync_worktree
  local title="" priority="" body="" assignee=""
  local -a labels=()
  local read_body_stdin=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --priority) priority="$2"; shift 2 ;;
      --label) labels+=("$2"); shift 2 ;;
      --assignee) assignee="$2"; shift 2 ;;
      --body) [ "$2" = "-" ] && read_body_stdin=1 || body="$2"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  if [ -z "$title" ]; then
    printf "Title: " >&2; read -r title
  fi
  [ -n "$title" ] || die "title is required"

  if [ -z "$priority" ]; then
    printf "Priority (P0/P1/P2/P3) [P2]: " >&2; read -r priority
    priority="${priority:-P2}"
  fi
  [[ "$priority" =~ ^P[0-3]$ ]] || die "priority must be P0/P1/P2/P3"

  if [ $read_body_stdin -eq 1 ]; then body="$(cat)"; fi

  local id; id="$(next_id)"
  local ts; ts="$(now_utc)"
  local label_list="priority:$priority"
  for l in "${labels[@]}"; do label_list="$label_list, $l"; done

  local f="$ISSUES_DIR/$id.md"
  mkdir -p "$ISSUES_DIR"
  {
    echo "---"
    echo "id: \"$id\""
    echo "title: $title"
    echo "state: open"
    echo "labels: [$label_list]"
    echo "assignee: \"$assignee\""
    echo "created: $ts"
    echo "updated: $ts"
    echo "closed_by_pr: \"\""
    echo "---"
    echo ""
    if [ -n "$body" ]; then
      echo "$body"
    else
      echo "## Motivation"
      echo "<edit me>"
      echo ""
      echo "## Work"
      echo "- [ ] <edit me>"
      echo ""
      echo "## Context"
      echo ""
      echo "## Comments"
    fi
  } > "$f"

  commit_push "[tracker] create #$id — $title"
  echo "#$id"
}

cmd_update() {
  ensure_worktree; sync_worktree
  local id=""
  local new_title="" new_body="" read_body_stdin=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) new_title="$2"; shift 2 ;;
      --body) [ "$2" = "-" ] && read_body_stdin=1 || new_body="$2"; shift 2 ;;
      *) id="$1"; shift ;;
    esac
  done
  [ -n "$id" ] || die "usage: issues update <id> [--title T] [--body -]"
  id="$(normalize_id "$id")"
  local f="$ISSUES_DIR/$id.md"
  [ -f "$f" ] || die "no such issue: #$id"

  if [ $read_body_stdin -eq 1 ]; then new_body="$(cat)"; fi

  if [ -n "$new_title" ]; then fm_set "$f" "title" "$new_title"; fi
  if [ -n "$new_body" ]; then
    python3 - "$f" "$new_body" <<'PY'
import sys, re
path, body = sys.argv[1], sys.argv[2]
with open(path) as fh:
    raw = fh.read()
m = re.match(r'^(---\n.*?\n---\n)(.*)$', raw, re.DOTALL)
if m:
    with open(path, 'w') as fh:
        fh.write(m.group(1) + "\n" + body.rstrip() + "\n")
PY
  fi
  bump_updated "$f"
  commit_push "[tracker] update #$id"
}

cmd_comment() {
  ensure_worktree; sync_worktree
  local id="${1:-}" text="${2:-}"
  [ -n "$id" ] && [ -n "$text" ] || die "usage: issues comment <id> <text>"
  id="$(normalize_id "$id")"
  local f="$ISSUES_DIR/$id.md"
  [ -f "$f" ] || die "no such issue: #$id"

  local who; who="$(git -C "$REPO_ROOT" config user.name 2>/dev/null || echo "unknown")"
  local ts; ts="$(now_utc)"
  if ! grep -q "^## Comments" "$f"; then
    printf "\n## Comments\n" >> "$f"
  fi
  {
    echo ""
    echo "### $ts — $who"
    echo "$text"
  } >> "$f"
  bump_updated "$f"
  commit_push "[tracker] comment #$id"
}

cmd_close() {
  ensure_worktree; sync_worktree
  local id="" comment=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --comment) comment="$2"; shift 2 ;;
      *) id="$1"; shift ;;
    esac
  done
  [ -n "$id" ] || die "usage: issues close <id> [--comment MSG]"
  id="$(normalize_id "$id")"
  local f="$ISSUES_DIR/$id.md"
  [ -f "$f" ] || die "no such issue: #$id"

  if [ -n "$comment" ]; then cmd_comment "$id" "$comment"; sync_worktree; fi
  fm_set "$f" "state" "closed"
  bump_updated "$f"
  commit_push "[tracker] close #$id"
}

cmd_assign() {
  ensure_worktree; sync_worktree
  local id="${1:-}" who="${2:-}"
  [ -n "$id" ] || die "usage: issues assign <id> <user|--unassign>"
  id="$(normalize_id "$id")"
  local f="$ISSUES_DIR/$id.md"
  [ -f "$f" ] || die "no such issue: #$id"
  if [ "$who" = "--unassign" ]; then who=""; fi
  fm_set "$f" "assignee" "\"$who\""
  bump_updated "$f"
  commit_push "[tracker] assign #$id → ${who:-<none>}"
}

cmd_label() {
  ensure_worktree; sync_worktree
  local id="${1:-}"; shift || true
  [ -n "$id" ] || die "usage: issues label <id> --add L | --remove L"
  id="$(normalize_id "$id")"
  local f="$ISSUES_DIR/$id.md"
  [ -f "$f" ] || die "no such issue: #$id"

  local add="" remove=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --add) add="$2"; shift 2 ;;
      --remove) remove="$2"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  local cur; cur="$(fm_get "$f" labels)"
  cur="${cur#[}"; cur="${cur%]}"
  local -a items=()
  local IFS=','
  for item in $cur; do
    item="${item# }"; item="${item% }"
    if [ -z "$item" ]; then continue; fi
    if [ -n "$remove" ] && [ "$item" = "$remove" ]; then continue; fi
    items+=("$item")
  done
  if [ -n "$add" ]; then
    local exists=0
    for item in "${items[@]}"; do
      if [ "$item" = "$add" ]; then exists=1; fi
    done
    if [ $exists -eq 0 ]; then items+=("$add"); fi
  fi
  local joined; joined="$(IFS=', '; echo "${items[*]}")"
  fm_set "$f" "labels" "[$joined]"
  bump_updated "$f"
  commit_push "[tracker] label #$id"
}

cmd_rm() {
  ensure_worktree; sync_worktree
  local id="${1:-}"
  [ -n "$id" ] || die "usage: issues rm <id>"
  id="$(normalize_id "$id")"
  local f="$ISSUES_DIR/$id.md"
  [ -f "$f" ] || die "no such issue: #$id"
  git -C "$WORKTREE" rm -q "$f"
  commit_push "[tracker] delete #$id"
}

cmd_search() {
  ensure_worktree; sync_worktree
  local q="${1:-}"
  [ -n "$q" ] || die "usage: issues search <query>"
  grep -l -i -- "$q" "$ISSUES_DIR"/*.md 2>/dev/null | while read -r f; do
    local id state title
    id="$(basename "$f" .md)"
    state="$(fm_get "$f" state)"
    title="$(fm_get "$f" title)"
    printf "#%s  [%-6s]  %s\n" "$id" "$state" "$title"
  done
}

cmd_sync() {
  ensure_worktree
  sync_worktree
  echo "synced $REMOTE/$BRANCH into $WORKTREE"
}

usage() {
  cat <<EOF
usage: issues <command> [args]

Read:
  list [--all] [--json]     List open (or all) issues
  show <id> [--json]        Print one issue
  search <query>            Grep open issues

Write:
  new [--title T] [--priority P0|P1|P2|P3] [--label L]* [--assignee U] [--body -]
  update <id> [--title T] [--body -]
  comment <id> <text>
  close <id> [--comment MSG]
  assign <id> <user|--unassign>
  label <id> --add L | --remove L
  rm <id>

Plumbing:
  sync                      Fast-forward local worktree to origin/tracker
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  ""|-h|--help|help) usage; exit 0 ;;
esac

acquire_lock

case "$cmd" in
  list)            cmd_list "$@" ;;
  show|read|view)  cmd_show "$@" ;;
  new|add|create)  cmd_new "$@" ;;
  update|edit)     cmd_update "$@" ;;
  comment)         cmd_comment "$@" ;;
  close)           cmd_close "$@" ;;
  assign)          cmd_assign "$@" ;;
  label)           cmd_label "$@" ;;
  rm|delete)       cmd_rm "$@" ;;
  search)          cmd_search "$@" ;;
  sync)            cmd_sync "$@" ;;
  *) echo "issues: unknown command '$cmd'" >&2; usage >&2; exit 1 ;;
esac
