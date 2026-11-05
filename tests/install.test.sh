#!/usr/bin/env bash
# Tests for install.sh. Run: bash tests/install.test.sh
# Each test uses fresh temporary directories; nothing outside them is touched.
set -euo pipefail
export LC_ALL=C

REPO="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/flowscribe-test.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

passed=0; failed=0
ok()   { passed=$((passed+1)); printf 'ok    %s\n' "$1"; }
fail() { failed=$((failed+1)); printf 'FAIL  %s\n' "$1"; [ -z "${2:-}" ] || printf '      %s\n' "$2"; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else fail "$name"; fi; }

# A copy of the release, so tests can change it without touching the repo.
release() { local d="$WORK/release-$1"; mkdir -p "$d"; cp -R "$REPO/install.sh" "$REPO/VERSION" "$REPO/payload" "$REPO/schema" "$d/"; printf '%s' "$d"; }
project() { local d="$WORK/project $1"; mkdir -p "$d"; printf '%s' "$d"; }   # note the space
tree()    { ( cd "$1" && find . -print | sort && find . -type f -exec shasum -a 256 {} + | sort ); }
run()     { bash "$1/install.sh" --target "$2" --yes "${@:3}"; }

R="$(release main)"

# ---------------------------------------------------------------- fresh install
P="$(project fresh)"
out="$(run "$R" "$P")"
check "fresh: skill installed in .agents"        test -f "$P/.agents/skills/flowscribe-sync/SKILL.md"
check "fresh: skill copied to .claude"           test -f "$P/.claude/skills/flowscribe-sync/SKILL.md"
check "fresh: schema installed"                  test -f "$P/.flowscribe/schema/v1/document.schema.json"
check "fresh: config installed"                  test -f "$P/.flowscribe/config.yaml"
check "fresh: manifest written"                  grep -q '^version ' "$P/.flowscribe/.install-manifest"
check "fresh: AGENTS.md has block"               grep -q -x -F '<!-- flowscribe:start -->' "$P/AGENTS.md"
check "fresh: CLAUDE.md imports AGENTS.md"       grep -q -x -F '@AGENTS.md' "$P/CLAUDE.md"
check "fresh: .gitignore ignores private/"       grep -q -x -F '.flowscribe/private/' "$P/.gitignore"
check "fresh: no node_modules or package.json"   test ! -e "$P/node_modules" -a ! -e "$P/package.json"

# ---------------------------------------------------------------- idempotent
before="$(tree "$P")"
out="$(run "$R" "$P")"
check "rerun: reports up to date"                grep -q 'Already up to date' <<<"$out"
check "rerun: nothing changed"                   test "$before" = "$(tree "$P")"

# ---------------------------------------------------------------- dry run
P="$(project dry)"
printf 'existing\n' > "$P/AGENTS.md"
before="$(tree "$P")"
out="$(run "$R" "$P" --dry-run)"
check "dry-run: shows plan"                      grep -q 'create    .agents/skills/flowscribe-init/SKILL.md' <<<"$out"
check "dry-run: writes nothing"                  test "$before" = "$(tree "$P")"

# ---------------------------------------------------------------- existing files are preserved
P="$(project existing)"
printf '# My project\n\nOwn rules.' > "$P/AGENTS.md"          # no trailing newline on purpose
printf 'node_modules/\n.env\n' > "$P/.gitignore"
printf 'Use tabs.\n' > "$P/CLAUDE.md"
cp "$P/AGENTS.md" "$WORK/agents.orig"; cp "$P/.gitignore" "$WORK/gitignore.orig"; cp "$P/CLAUDE.md" "$WORK/claude.orig"
run "$R" "$P" >/dev/null
check "existing: AGENTS.md keeps own content"    grep -q -x -F 'Own rules.' "$P/AGENTS.md"
check "existing: .gitignore keeps own lines"     grep -q -x -F '.env' "$P/.gitignore"
check "existing: CLAUDE.md keeps own lines"      grep -q -x -F 'Use tabs.' "$P/CLAUDE.md"
check "existing: block appears once"             test "$(grep -c -x -F '<!-- flowscribe:start -->' "$P/AGENTS.md")" = 1

# ---------------------------------------------------------------- update: changed files are never overwritten
R2="$(release v2)"
printf '0.2.0\n' > "$R2/VERSION"
printf '\nNew in 0.2.0.\n' >> "$R2/payload/files/.agents/skills/flowscribe-sync/SKILL.md"
printf '\nNew in 0.2.0.\n' >> "$R2/payload/files/.agents/skills/flowscribe-init/SKILL.md"
printf 'Changed in 0.2.0.\n' >> "$R2/payload/agents-block.md"
printf '\nMy local tweak.\n' >> "$P/.agents/skills/flowscribe-sync/SKILL.md"
cp "$P/.agents/skills/flowscribe-sync/SKILL.md" "$WORK/tweaked"
out="$(run "$R2" "$P")"
check "update: user-changed file kept"           cmp -s "$WORK/tweaked" "$P/.agents/skills/flowscribe-sync/SKILL.md"
check "update: new version written beside it"    grep -q 'New in 0.2.0.' "$P/.agents/skills/flowscribe-sync/SKILL.md.flowscribe-new"
check "update: unchanged file updated"           grep -q 'New in 0.2.0.' "$P/.agents/skills/flowscribe-init/SKILL.md"
check "update: AGENTS block refreshed"           grep -q 'Changed in 0.2.0.' "$P/AGENTS.md"
check "update: AGENTS own content intact"        grep -q -x -F 'Own rules.' "$P/AGENTS.md"
check "update: manifest version bumped"          grep -q -x -F 'version 0.2.0' "$P/.flowscribe/.install-manifest"

# ---------------------------------------------------------------- uninstall
mkdir -p "$P/.flowscribe/flows"; printf 'my doc\n' > "$P/.flowscribe/flows/checkout.md"
rm -f "$P/.agents/skills/flowscribe-sync/SKILL.md.flowscribe-new"
run "$R2" "$P" --uninstall >/dev/null
check "uninstall: installed skill removed"       test ! -e "$P/.agents/skills/flowscribe-init"
check "uninstall: .claude copy removed"          test ! -e "$P/.claude/skills/flowscribe-init"
check "uninstall: user-changed file kept"        cmp -s "$WORK/tweaked" "$P/.agents/skills/flowscribe-sync/SKILL.md"
check "uninstall: user documents kept"           test -f "$P/.flowscribe/flows/checkout.md"
check "uninstall: manifest removed"              test ! -e "$P/.flowscribe/.install-manifest"
check "uninstall: AGENTS.md restored exactly"    cmp -s <(cat "$WORK/agents.orig"; echo) "$P/AGENTS.md"
check "uninstall: .gitignore restored exactly"   cmp -s "$WORK/gitignore.orig" "$P/.gitignore"
check "uninstall: CLAUDE.md restored exactly"    cmp -s "$WORK/claude.orig" "$P/CLAUDE.md"

P="$(project clean)"
run "$R" "$P" >/dev/null; run "$R" "$P" --uninstall >/dev/null
check "uninstall: fresh project left empty"      test -z "$(ls -A "$P")"

# ---------------------------------------------------------------- coexistence with another skill pack
# Simulates a pack whose installer copies its own skills into .agents/ and overwrites AGENTS.md (cp -f).
P="$(project coexist)"
run "$R" "$P" >/dev/null
mkdir -p "$P/.agents/skills/other-skill" "$P/.agents/rules"
printf -- '---\nname: other-skill\ndescription: x\n---\n' > "$P/.agents/skills/other-skill/SKILL.md"
printf -- '---\ntrigger: always_on\n---\nOther rules.\n' > "$P/.agents/rules/other.md"
printf '# Other pack directives\n' > "$P/AGENTS.md"                       # their cp -f wipes our block
out="$(run "$R" "$P" --dry-run)"
check "coexist: missing block is detected"       grep -q 'edit      AGENTS.md' <<<"$out"
run "$R" "$P" >/dev/null
check "coexist: block restored"                  grep -q -x -F '<!-- flowscribe:start -->' "$P/AGENTS.md"
check "coexist: other pack's AGENTS.md kept"     grep -q -x -F '# Other pack directives' "$P/AGENTS.md"
run "$R" "$P" --uninstall >/dev/null
check "coexist: uninstall keeps other skill"     test -f "$P/.agents/skills/other-skill/SKILL.md"
check "coexist: uninstall keeps other rules"     test -f "$P/.agents/rules/other.md"
check "coexist: uninstall keeps their AGENTS.md" test "$(cat "$P/AGENTS.md")" = '# Other pack directives'
check "coexist: flowscribe skills gone"          test ! -e "$P/.agents/skills/flowscribe-sync"

# ---------------------------------------------------------------- refusals (security)
expect_fail() { # name, expected message, command...
  local name="$1" msg="$2"; shift 2
  local out rc=0; out="$("$@" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] && grep -q -F -- "$msg" <<<"$out"; then ok "$name"; else fail "$name" "rc=$rc out=$out"; fi
}

P="$(project symlink-top)"; mkdir -p "$WORK/outside-top"; ln -s "$WORK/outside-top" "$P/.agents"
expect_fail "refuse: .agents is a symlink"       "is a symlink" run "$R" "$P"
check "refuse: nothing written outside"          test -z "$(ls -A "$WORK/outside-top")"

P="$(project symlink-deep)"; mkdir -p "$WORK/outside-deep" "$P/.flowscribe"; ln -s "$WORK/outside-deep" "$P/.flowscribe/schema"
expect_fail "refuse: symlink deeper in path"     "symlink" run "$R" "$P"
check "refuse: nothing written through it"       test -z "$(ls -A "$WORK/outside-deep")"

P="$(project symlink-agents)"; printf 'victim\n' > "$WORK/victim-agents"; ln -s "$WORK/victim-agents" "$P/AGENTS.md"
expect_fail "refuse: AGENTS.md is a symlink"     "is a symlink" run "$R" "$P"
check "refuse: symlink target untouched"         grep -q -x 'victim' "$WORK/victim-agents"

P="$(project agents-dir)"; mkdir -p "$P/AGENTS.md"
expect_fail "refuse: AGENTS.md is a directory"   "not a regular file" run "$R" "$P"
check "refuse: directory left empty"             test -z "$(ls -A "$P/AGENTS.md")"

P="$(project new-dir)"; run "$R" "$P" >/dev/null
printf '\nlocal\n' >> "$P/.agents/skills/flowscribe-sync/SKILL.md"
R5="$(release new-dir)"; printf '0.3.0\n' > "$R5/VERSION"; printf '\nv3\n' >> "$R5/payload/files/.agents/skills/flowscribe-sync/SKILL.md"
mkdir -p "$P/.agents/skills/flowscribe-sync/SKILL.md.flowscribe-new"
expect_fail "refuse: *.flowscribe-new is a dir"  "not a regular file" run "$R5" "$P"

P="$(project markers)"; printf '<!-- flowscribe:start -->\nno end marker\n' > "$P/AGENTS.md"
expect_fail "refuse: broken markers"             "broken flowscribe markers" run "$R" "$P"

expect_fail "refuse: running from a pipe"        "not from a pipe" bash -c "cat '$R/install.sh' | bash -s -- --yes"
expect_fail "refuse: home directory"             "home directory" env HOME="$(project home)" bash "$R/install.sh" --target "$WORK/project home" --yes
expect_fail "refuse: unknown option"             "unknown option" bash "$R/install.sh" --evil
expect_fail "refuse: installing into release"    "release itself" bash "$R/install.sh" --target "$R" --yes

R3="$(release with-link)"; ln -s /etc/passwd "$R3/payload/files/.flowscribe/templates/evil.md"
expect_fail "refuse: symlink inside release"     "release contains symlinks" run "$R3" "$(project linkrel)"

R4="$(release odd-name)"; printf 'x\n' > "$R4/payload/files/.flowscribe/templates/bad name.md"
expect_fail "refuse: unexpected file name"       "unexpected file in release" run "$R4" "$(project oddname)"

# Tampered manifest: entries outside managed paths must be ignored, even when the hash matches.
P="$(project tampered)"; run "$R" "$P" >/dev/null
printf 'precious\n' > "$P/precious.txt"; printf 'precious\n' > "$WORK/precious-outside.txt"
h="$(shasum -a 256 "$P/precious.txt" | awk '{print $1}')"
printf 'file %s precious.txt\nfile %s ../precious-outside.txt\nfile %s .flowscribe/../precious.txt\n' "$h" "$h" "$h" \
  >> "$P/.flowscribe/.install-manifest"
run "$R" "$P" --uninstall >/dev/null 2>&1 || true
check "tampered manifest: file in project kept"  test -f "$P/precious.txt"
check "tampered manifest: file outside kept"     test -f "$WORK/precious-outside.txt"

# ---------------------------------------------------------------- summary
printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
