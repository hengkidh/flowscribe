#!/usr/bin/env bash
# flowscribe installer.
#
# Run it from an extracted, checksum-verified flowscribe release:
#   ./install.sh [--target DIR] [--dry-run] [--yes]
#   ./install.sh --uninstall [--target DIR] [--dry-run] [--yes]
#
# Guarantees (see SECURITY.md):
#   - no network access, no package managers, no eval, no sudo;
#   - never overwrites a file you changed: the new version is written next to it as *.flowscribe-new;
#   - refuses to write through symlinks or outside the target directory;
#   - shows the full plan and asks before writing anything (unless --yes);
#   - --uninstall removes only files it installed and you did not change, and never your documents.
#
# Compatible with bash 3.2 (macOS default).

set -euo pipefail
umask 022
export LC_ALL=C

readonly PROG="flowscribe install"
readonly MANIFEST_REL=".flowscribe/.install-manifest"
readonly AGENTS_START="<!-- flowscribe:start -->"
readonly AGENTS_END="<!-- flowscribe:end -->"
readonly GITIGNORE_START="# flowscribe:start"
readonly GITIGNORE_END="# flowscribe:end"
readonly CLAUDE_LINE="@AGENTS.md"

# ---------------------------------------------------------------- helpers

die()  { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }
warn() { printf '%s: warning: %s\n' "$PROG" "$*" >&2; }
say()  { printf '%s\n' "$*"; }

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [--target DIR] [--dry-run] [--yes]
  ./install.sh --uninstall [--target DIR] [--dry-run] [--yes]

Options:
  --target DIR   Project to install into (default: current directory).
  --dry-run      Show what would change and exit without writing anything.
  --yes          Do not ask for confirmation.
  --uninstall    Remove what flowscribe installed. Your documents in .flowscribe/ are kept.
  --version      Print the flowscribe version of this release.
  -h, --help     Show this help.
EOF
}

TMP_DIR=""
cleanup() { if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then rm -rf -- "$TMP_DIR"; fi; }
trap cleanup EXIT
trap 'exit 130' INT TERM

if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum -- "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 -- "$1" | awk '{print $1}'; }
else
  die "need sha256sum or shasum"
fi

# A relative path we are willing to manage: plain characters, no '..', no leading '/'.
valid_rel() {
  case "$1" in
    ""|/*|*/|*//*) return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._/-]+$' || return 1
  case "/$1/" in
    */../*|*/./*) return 1 ;;
  esac
  return 0
}

# Only these locations may ever be written or removed by this script.
managed_rel() {
  case "$1" in
    .agents/skills/flowscribe-*/*|.claude/skills/flowscribe-*/*|.flowscribe/*) return 0 ;;
  esac
  return 1
}

# Fails if any existing component between TARGET and TARGET/REL is a symlink.
no_symlink_in_path() {
  local path="$TARGET" part rest="$1"
  while [ -n "$rest" ]; do
    part="${rest%%/*}"
    if [ "$part" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    path="$path/$part"
    if [ -L "$path" ]; then return 1; fi
    [ -e "$path" ] || return 0
  done
  return 0
}

# Write SRC to DEST atomically (temp file in the same directory, then rename).
install_file() {
  local src="$1" dest="$2" dir tmp
  # mv onto a directory would move the file *into* it; only regular files (or nothing) may be replaced.
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    [ -f "$dest" ] || [ -L "$dest" ] || die "$dest exists and is not a regular file"
  fi
  dir="$(dirname -- "$dest")"
  mkdir -p -- "$dir"
  tmp="$(mktemp "$dir/.flowscribe.XXXXXX")"
  cat -- "$src" > "$tmp"
  chmod 644 "$tmp"   # $tmp is an absolute path from mktemp
  mv -f -- "$tmp" "$dest"
}

count_line() { # exact whole-line matches of $1 in file $2
  grep -c -x -F -- "$1" "$2" 2>/dev/null || true
}

# Print FILE with the block between START/END markers replaced by BLOCKFILE (or appended).
render_block() {
  local file="$1" start="$2" end="$3" blockfile="$4"
  if [ -f "$file" ] && [ "$(count_line "$start" "$file")" -ge 1 ]; then
    START="$start" END="$end" awk '
      FNR == NR { blk = blk $0 "\n"; next }
      $0 == ENVIRON["START"] { printf "%s\n%s", $0, blk; skip = 1; next }
      $0 == ENVIRON["END"]   { skip = 0 }
      !skip { print }
    ' "$blockfile" "$file"
  else
    if [ -f "$file" ] && [ -s "$file" ]; then
      cat -- "$file"
      [ -z "$(tail -c 1 -- "$file")" ] || printf '\n'
      printf '\n'
    fi
    printf '%s\n' "$start"
    cat -- "$blockfile"
    printf '%s\n' "$end"
  fi
}

# Print FILE without the START..END block (inclusive) and without one blank line right before it.
strip_block() {
  START="$1" END="$2" awk '
    $0 == ENVIRON["START"] { skip = 1; if (blank > 0) blank--; next }
    skip { if ($0 == ENVIRON["END"]) skip = 0; next }
    $0 == "" { blank++; next }
    { while (blank > 0) { print ""; blank-- } print }
    END { while (blank > 0) { print ""; blank-- } }
  ' "$3"
}

# Markers must be absent, or present exactly once each and in order.
check_markers() {
  local file="$1" start="$2" end="$3" ns ne ls le
  [ -f "$file" ] || return 0
  ns="$(count_line "$start" "$file")"; ne="$(count_line "$end" "$file")"
  if [ "$ns" -eq 0 ] && [ "$ne" -eq 0 ]; then return 0; fi
  if [ "$ns" -ne 1 ] || [ "$ne" -ne 1 ]; then return 1; fi
  ls="$(grep -n -x -F -- "$start" "$file" | cut -d: -f1)"
  le="$(grep -n -x -F -- "$end" "$file" | cut -d: -f1)"
  [ "$ls" -lt "$le" ]
}

is_blank_file() { [ -z "$(tr -d '[:space:]' < "$1")" ]; }

confirm() {
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  if ! ( exec < /dev/tty ) 2>/dev/null; then
    die "no terminal to ask for confirmation; re-run with --yes after reviewing --dry-run"
  fi
  local ans=""
  printf '%s [y/N] ' "$1" > /dev/tty
  IFS= read -r ans < /dev/tty || true
  case "$ans" in y|Y|yes|YES) return 0 ;; esac
  say "Nothing changed."
  exit 0
}

# ---------------------------------------------------------------- arguments

MODE="install"; DRY_RUN=0; ASSUME_YES=0; TARGET_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target)    [ $# -ge 2 ] || die "--target needs a directory"; TARGET_ARG="$2"; shift 2 ;;
    --target=*)  TARGET_ARG="${1#--target=}"; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --yes|-y)    ASSUME_YES=1; shift ;;
    --uninstall) MODE="uninstall"; shift ;;
    --version)   MODE="version"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage >&2; die "unknown option: $1" ;;
  esac
done

# ---------------------------------------------------------------- source (this release)

case "${BASH_SOURCE[0]:-}" in
  ""|bash|-bash|/dev/*|/proc/*)
    die "run install.sh from a downloaded and verified release, not from a pipe (see README)" ;;
esac
SRC="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [ ! -f "$SRC/VERSION" ] || [ ! -d "$SRC/payload/files" ] || [ ! -f "$SRC/payload/agents-block.md" ] \
   || [ ! -d "$SRC/schema/v1" ]; then
  die "release is incomplete: $SRC"
fi
VERSION="$(tr -d '[:space:]' < "$SRC/VERSION")"
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' || die "invalid VERSION file"

if [ "$MODE" = "version" ]; then say "flowscribe $VERSION"; exit 0; fi

if [ -n "$(find "$SRC/payload" "$SRC/schema" -type l -print -quit)" ]; then
  die "release contains symlinks; refusing to install"
fi

# ---------------------------------------------------------------- target

[ -n "$TARGET_ARG" ] || TARGET_ARG="$PWD"
[ -d "$TARGET_ARG" ] || die "target is not a directory: $TARGET_ARG"
TARGET="$(cd -P -- "$TARGET_ARG" && pwd -P)"
HOME_REAL=""; if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then HOME_REAL="$(cd -P -- "$HOME" && pwd -P)"; fi
[ "$TARGET" != "/" ] || die "refusing to install into /"
[ "$TARGET" != "$HOME_REAL" ] || die "refusing to install into your home directory; cd into a project first"
case "$TARGET/" in "$SRC"/*) die "refusing to install into the flowscribe release itself" ;; esac
[ -w "$TARGET" ] || die "target is not writable: $TARGET"
for top in AGENTS.md CLAUDE.md .gitignore .agents .claude .flowscribe .agents/skills .claude/skills; do
  [ ! -L "$TARGET/$top" ] || die "$top is a symlink; refusing to write through it"
done
for top in AGENTS.md CLAUDE.md .gitignore; do
  [ ! -e "$TARGET/$top" ] || [ -f "$TARGET/$top" ] || die "$top exists and is not a regular file"
done
nl='
'
case "$SRC$TARGET" in *"$nl"*) die "paths containing newlines are not supported" ;; esac

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flowscribe.XXXXXX")"
PLAN="$TMP_DIR/plan"; : > "$PLAN"
MANIFEST="$TARGET/$MANIFEST_REL"

# Previous manifest: "file <sha256> <rel>" lines, validated before use.
OLD="$TMP_DIR/old-manifest"; : > "$OLD"
if [ -f "$MANIFEST" ]; then
  [ ! -L "$MANIFEST" ] || die "install manifest is a symlink; refusing"
  while IFS=' ' read -r kind hash rel extra; do
    [ "$kind" = "file" ] || continue
    if [ -n "${extra:-}" ] || ! printf '%s' "$hash" | grep -Eq '^[0-9a-f]{64}$' \
       || ! valid_rel "$rel" || ! managed_rel "$rel"; then
      warn "ignoring invalid manifest entry: $rel"; continue
    fi
    printf '%s %s\n' "$hash" "$rel" >> "$OLD"
  done < "$MANIFEST"
fi
old_hash() { awk -v r="$1" '$2 == r { print $1; exit }' "$OLD"; }
manifest_flag() { [ -f "$MANIFEST" ] && grep -q -x -F -- "$1" "$MANIFEST"; }

# ================================================================ uninstall

if [ "$MODE" = "uninstall" ]; then
  [ -f "$MANIFEST" ] || die "flowscribe is not installed in $TARGET (no $MANIFEST_REL)"
  say "flowscribe uninstall from $TARGET"; say ""
  removed=0; kept=0
  while IFS=' ' read -r hash rel; do
    dest="$TARGET/$rel"
    if ! no_symlink_in_path "$rel"; then say "  keep    $rel (symlink in path)"; kept=$((kept+1)); continue; fi
    [ -f "$dest" ] || continue
    if [ "$(sha256 "$dest")" = "$hash" ]; then
      say "  remove  $rel"; printf 'rm %s\n' "$rel" >> "$PLAN"; removed=$((removed+1))
    else
      say "  keep    $rel (you changed it)"; kept=$((kept+1))
    fi
  done < "$OLD"
  check_markers "$TARGET/AGENTS.md" "$AGENTS_START" "$AGENTS_END" || die "AGENTS.md has broken flowscribe markers; fix them by hand"
  check_markers "$TARGET/.gitignore" "$GITIGNORE_START" "$GITIGNORE_END" || die ".gitignore has broken flowscribe markers; fix them by hand"
  [ -f "$TARGET/AGENTS.md" ] && [ "$(count_line "$AGENTS_START" "$TARGET/AGENTS.md")" -eq 1 ] && say "  edit    AGENTS.md (remove flowscribe block)"
  [ -f "$TARGET/.gitignore" ] && [ "$(count_line "$GITIGNORE_START" "$TARGET/.gitignore")" -eq 1 ] && say "  edit    .gitignore (remove flowscribe block)"
  manifest_flag "claude-line added" && say "  edit    CLAUDE.md (remove $CLAUDE_LINE)"
  say ""; say "Your documents in .flowscribe/ (flows, modules, decisions, log, private) are kept."
  say "$removed file(s) to remove, $kept kept."
  if [ "$DRY_RUN" -eq 1 ]; then say "Dry run: nothing changed."; exit 0; fi
  confirm "Uninstall?"

  while IFS=' ' read -r _ rel; do rm -f -- "$TARGET/$rel"; done < "$PLAN"
  if [ -f "$TARGET/AGENTS.md" ] && [ "$(count_line "$AGENTS_START" "$TARGET/AGENTS.md")" -eq 1 ]; then
    strip_block "$AGENTS_START" "$AGENTS_END" "$TARGET/AGENTS.md" > "$TMP_DIR/agents"
    if is_blank_file "$TMP_DIR/agents" && manifest_flag "agents created"; then rm -f -- "$TARGET/AGENTS.md"
    else install_file "$TMP_DIR/agents" "$TARGET/AGENTS.md"; fi
  fi
  if [ -f "$TARGET/.gitignore" ] && [ "$(count_line "$GITIGNORE_START" "$TARGET/.gitignore")" -eq 1 ]; then
    strip_block "$GITIGNORE_START" "$GITIGNORE_END" "$TARGET/.gitignore" > "$TMP_DIR/gitignore"
    if is_blank_file "$TMP_DIR/gitignore" && manifest_flag "gitignore created"; then rm -f -- "$TARGET/.gitignore"
    else install_file "$TMP_DIR/gitignore" "$TARGET/.gitignore"; fi
  fi
  if manifest_flag "claude-line added" && [ -f "$TARGET/CLAUDE.md" ] && [ ! -L "$TARGET/CLAUDE.md" ]; then
    grep -v -x -F -- "$CLAUDE_LINE" "$TARGET/CLAUDE.md" > "$TMP_DIR/claude" || true
    if is_blank_file "$TMP_DIR/claude" && manifest_flag "claude created"; then rm -f -- "$TARGET/CLAUDE.md"
    else install_file "$TMP_DIR/claude" "$TARGET/CLAUDE.md"; fi
  fi
  rm -f -- "$MANIFEST"
  # Remove directories this script manages, only if they are now empty.
  for base in "$TARGET/.agents/skills" "$TARGET/.claude/skills"; do
    if [ ! -d "$base" ] || [ -L "$base" ]; then continue; fi
    for d in "$base"/flowscribe-*; do
      if [ ! -d "$d" ] || [ -L "$d" ]; then continue; fi
      find "$d" -depth -type d -exec rmdir {} \; 2>/dev/null || true
    done
  done
  for d in .flowscribe/templates .flowscribe/schema/v1 .flowscribe/schema .agents/skills .agents .claude/skills .claude .flowscribe; do
    if [ -d "$TARGET/$d" ] && [ ! -L "$TARGET/$d" ]; then rmdir -- "$TARGET/$d" 2>/dev/null || true; fi
  done
  say "Uninstalled."
  exit 0
fi

# ================================================================ install: plan

# Collect "<rel> <source>" pairs for every file this release manages.
SOURCES="$TMP_DIR/sources"; : > "$SOURCES"
( cd "$SRC/payload/files" && find . -type f -print ) | sed 's|^\./||' | sort | while IFS= read -r rel; do
  if ! valid_rel "$rel" || ! managed_rel "$rel"; then die "unexpected file in release: $rel"; fi
  printf '%s %s\n' "$rel" "$SRC/payload/files/$rel"
  case "$rel" in
    .agents/skills/*) printf '%s %s\n' ".claude/skills/${rel#.agents/skills/}" "$SRC/payload/files/$rel" ;;
  esac
done >> "$SOURCES"
( cd "$SRC/schema/v1" && find . -type f -name '*.json' -print ) | sed 's|^\./||' | sort | while IFS= read -r name; do
  valid_rel "$name" || die "unexpected schema file: $name"
  printf '%s %s\n' ".flowscribe/schema/v1/$name" "$SRC/schema/v1/$name"
done >> "$SOURCES"
[ -s "$SOURCES" ] || die "release has no files"

new=0; upd=0; same=0; conflict=0
while IFS=' ' read -r rel src; do
  dest="$TARGET/$rel"
  no_symlink_in_path "$rel" || die "a component of $rel is a symlink; refusing"
  shash="$(sha256 "$src")"
  if [ ! -e "$dest" ]; then
    printf 'create %s %s %s\n' "$shash" "$rel" "$src" >> "$PLAN"; new=$((new+1))
  elif [ ! -f "$dest" ]; then
    die "$rel exists and is not a regular file"
  else
    dhash="$(sha256 "$dest")"
    if [ "$dhash" = "$shash" ]; then
      printf 'same %s %s %s\n' "$shash" "$rel" "$src" >> "$PLAN"; same=$((same+1))
    elif [ -n "$(old_hash "$rel")" ] && [ "$(old_hash "$rel")" = "$dhash" ]; then
      printf 'update %s %s %s\n' "$shash" "$rel" "$src" >> "$PLAN"; upd=$((upd+1))
    else
      printf 'conflict %s %s %s\n' "$shash" "$rel" "$src" >> "$PLAN"; conflict=$((conflict+1))
    fi
  fi
done < "$SOURCES"

check_markers "$TARGET/AGENTS.md" "$AGENTS_START" "$AGENTS_END" \
  || die "AGENTS.md has broken flowscribe markers (each must appear once, start before end); fix them by hand"
check_markers "$TARGET/.gitignore" "$GITIGNORE_START" "$GITIGNORE_END" \
  || die ".gitignore has broken flowscribe markers; fix them by hand"

GITIGNORE_BLOCK="$TMP_DIR/gitignore-block"
cat > "$GITIGNORE_BLOCK" <<'EOF'
# Internal flowscribe documents, captures and storyboards: never committed.
.flowscribe/private/
.flowscribe/screens/
EOF

render_block "$TARGET/AGENTS.md" "$AGENTS_START" "$AGENTS_END" "$SRC/payload/agents-block.md" > "$TMP_DIR/agents"
render_block "$TARGET/.gitignore" "$GITIGNORE_START" "$GITIGNORE_END" "$GITIGNORE_BLOCK" > "$TMP_DIR/gitignore"
agents_changes=1; gitignore_changes=1; claude_change=0
[ -f "$TARGET/AGENTS.md" ] && cmp -s "$TMP_DIR/agents" "$TARGET/AGENTS.md" && agents_changes=0
[ -f "$TARGET/.gitignore" ] && cmp -s "$TMP_DIR/gitignore" "$TARGET/.gitignore" && gitignore_changes=0
if [ ! -f "$TARGET/CLAUDE.md" ] || [ "$(count_line "$CLAUDE_LINE" "$TARGET/CLAUDE.md")" -eq 0 ]; then claude_change=1; fi

# ---------------------------------------------------------------- install: show plan

prev=""; [ -f "$MANIFEST" ] && prev="$(awk '$1 == "version" { print $2; exit }' "$MANIFEST")"
if [ -n "$prev" ]; then say "flowscribe $prev -> $VERSION in $TARGET"; else say "flowscribe $VERSION -> $TARGET"; fi
say ""
while IFS=' ' read -r action _ rel _; do
  case "$action" in
    create)   say "  create    $rel" ;;
    update)   say "  update    $rel" ;;
    conflict) say "  conflict  $rel  (you changed it: kept; new version -> $rel.flowscribe-new)" ;;
  esac
done < "$PLAN"
[ "$agents_changes" -eq 0 ] || say "  edit      AGENTS.md  (flowscribe block between markers; the rest is untouched)"
[ "$gitignore_changes" -eq 0 ] || say "  edit      .gitignore  (ignore .flowscribe/private/ and .flowscribe/screens/)"
[ "$claude_change" -eq 0 ] || say "  edit      CLAUDE.md  (add line: $CLAUDE_LINE)"
say ""
say "$new new, $upd updated, $same unchanged, $conflict conflict(s). No other files are touched."

if [ "$new" -eq 0 ] && [ "$upd" -eq 0 ] && [ "$conflict" -eq 0 ] && [ "$agents_changes" -eq 0 ] \
   && [ "$gitignore_changes" -eq 0 ] && [ "$claude_change" -eq 0 ]; then
  say "Already up to date."; exit 0
fi
if [ "$DRY_RUN" -eq 1 ]; then say "Dry run: nothing changed."; exit 0; fi
confirm "Install?"

# ---------------------------------------------------------------- install: apply

flags="$TMP_DIR/flags"; : > "$flags"
manifest_flag "agents created"     && echo "agents created"     >> "$flags"
manifest_flag "gitignore created"  && echo "gitignore created"  >> "$flags"
manifest_flag "claude created"     && echo "claude created"     >> "$flags"
manifest_flag "claude-line added"  && echo "claude-line added"  >> "$flags"

entries="$TMP_DIR/entries"; : > "$entries"
while IFS=' ' read -r action shash rel src; do
  case "$action" in
    create|update) install_file "$src" "$TARGET/$rel"; echo "file $shash $rel" >> "$entries" ;;
    same)          echo "file $shash $rel" >> "$entries" ;;
    conflict)
      install_file "$src" "$TARGET/$rel.flowscribe-new"
      # Keep the previous manifest hash so a later run can still tell the file was changed by you.
      h="$(old_hash "$rel")"; [ -z "$h" ] || echo "file $h $rel" >> "$entries" ;;
  esac
done < "$PLAN"

if [ "$agents_changes" -eq 1 ]; then
  [ -e "$TARGET/AGENTS.md" ] || echo "agents created" >> "$flags"
  install_file "$TMP_DIR/agents" "$TARGET/AGENTS.md"
fi
if [ "$gitignore_changes" -eq 1 ]; then
  [ -e "$TARGET/.gitignore" ] || echo "gitignore created" >> "$flags"
  install_file "$TMP_DIR/gitignore" "$TARGET/.gitignore"
fi
if [ "$claude_change" -eq 1 ]; then
  if [ -f "$TARGET/CLAUDE.md" ]; then
    { cat -- "$TARGET/CLAUDE.md"; [ -z "$(tail -c 1 -- "$TARGET/CLAUDE.md")" ] || printf '\n'; printf '%s\n' "$CLAUDE_LINE"; } > "$TMP_DIR/claude"
  else
    echo "claude created" >> "$flags"; printf '%s\n' "$CLAUDE_LINE" > "$TMP_DIR/claude"
  fi
  echo "claude-line added" >> "$flags"
  install_file "$TMP_DIR/claude" "$TARGET/CLAUDE.md"
fi

{
  echo "# flowscribe install manifest. Used by install.sh to update and uninstall safely; do not edit."
  echo "version $VERSION"
  sort -u "$flags"
  sort -k3 "$entries"
} > "$TMP_DIR/manifest"
install_file "$TMP_DIR/manifest" "$MANIFEST"

say ""
say "Installed flowscribe $VERSION."
[ "$conflict" -eq 0 ] || say "Review the *.flowscribe-new files: merge what you want, then delete them."
say "Next: ask your agent to run the flowscribe-init skill."
