#!/usr/bin/env bash
# Tests for the one-line installer (scripts/get.sh.in) and scripts/build-release.sh.
# Run: bash tests/get.test.sh   (no network: downloads use file:// mirrors)
set -euo pipefail
export LC_ALL=C COPYFILE_DISABLE=1

REPO="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/flowscribe-get-test.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
VERSION="$(tr -d '[:space:]' < "$REPO/VERSION")"
NAME="flowscribe-v$VERSION"

passed=0; failed=0
ok()   { passed=$((passed+1)); printf 'ok    %s\n' "$1"; }
fail() { failed=$((failed+1)); printf 'FAIL  %s\n' "$1"; [ -z "${2:-}" ] || printf '      %s\n' "$2"; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else fail "$name"; fi; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }

# Fake gh CLI first on PATH, so tests never call a real one. Behaviour is set per test.
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status")        [ "${FAKE_GH_AUTH:-no}" = yes ] ;;
  "attestation verify") [ "${FAKE_GH_ATTEST:-fail}" = ok ] || { echo "fake: attestation failed" >&2; exit 1; } ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

DIST="$WORK/dist"
bash "$REPO/scripts/build-release.sh" "$VERSION" example/flowscribe "$DIST" >/dev/null

# get <home> <project> [installer args...]: runs get.sh the way users do, from a pipe.
get() {
  local home="$1" proj="$2"; shift 2
  ( cd "$proj" && FLOWSCRIBE_HOME="$home" FLOWSCRIBE_DOWNLOAD_BASE="file://$DIST" bash -s -- "$@" < "$DIST/get.sh" )
}
expect_fail() { # name, expected message, command...
  local name="$1" msg="$2"; shift 2
  local out rc=0; out="$("$@" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] && grep -q -F -- "$msg" <<<"$out"; then ok "$name"; else fail "$name" "rc=$rc out=$out"; fi
}
newdir() { mkdir -p "$WORK/$1"; printf '%s' "$WORK/$1"; }

# ---------------------------------------------------------------- build
check "build: archive, get.sh and SHA256SUMS exist" test -f "$DIST/$NAME.tar.gz" -a -f "$DIST/get.sh" -a -f "$DIST/SHA256SUMS"
check "build: checksum embedded in get.sh"          grep -q "sha256='$(sha "$DIST/$NAME.tar.gz")'" "$DIST/get.sh"
check "build: no placeholders left"                 test -z "$(grep -E '@(VERSION|SHA256|REPO)@' "$DIST/get.sh" || true)"
check "build: SHA256SUMS lists both files"          test "$(wc -l < "$DIST/SHA256SUMS" | tr -d ' ')" = 2
check "build: no macOS metadata in archive"         test -z "$(tar -tzf "$DIST/$NAME.tar.gz" | grep '/\._' || true)"

# ---------------------------------------------------------------- happy path
H="$(newdir home1)"; P="$(newdir proj1)"
out="$(get "$H" "$P" --yes 2>&1)"
check "get: checksum verified"                      grep -q 'checksum verified' <<<"$out"
check "get: attestation skipped when gh signed out" grep -q 'attestation not checked' <<<"$out"
check "get: release kept for reuse"                 test -f "$H/$VERSION/install.sh" -a -f "$H/$VERSION/.flowscribe-verified"
check "get: project installed"                      test -f "$P/.agents/skills/flowscribe-sync/SKILL.md"
check "get: no temp files left in project"          test -z "$(find "$P" -name 'flowscribe-get.*')"

P2="$(newdir proj2)"; mv "$DIST/$NAME.tar.gz" "$WORK/archive.bak"
out="$(get "$H" "$P2" --yes 2>&1)"
check "get: second project reuses release offline" grep -q 'using verified release' <<<"$out"
check "get: second project installed"               test -f "$P2/AGENTS.md"
mv "$WORK/archive.bak" "$DIST/$NAME.tar.gz"

P3="$(newdir proj3)"
get "$(newdir home-dry)" "$P3" --dry-run >/dev/null 2>&1
check "get: installer options pass through"         test -z "$(ls -A "$P3")"

# ---------------------------------------------------------------- attestation
P="$(newdir proj-att-ok)"
out="$(FAKE_GH_AUTH=yes FAKE_GH_ATTEST=ok get "$(newdir home-att-ok)" "$P" --yes 2>&1)"
check "attest: verified when gh is signed in"       grep -q 'build attestation verified' <<<"$out"

H="$(newdir home-att-bad)"; P="$(newdir proj-att-bad)"
expect_fail "attest: failure refuses install"       "attestation could not be verified" \
  env FAKE_GH_AUTH=yes FAKE_GH_ATTEST=fail bash -c "$(declare -f get); DIST='$DIST'; get '$H' '$P' --yes"
check "attest: nothing installed or kept"           test -z "$(ls -A "$P")" -a ! -e "$H/$VERSION"

expect_fail "attest: required but unavailable"      "FLOWSCRIBE_REQUIRE_ATTESTATION=1" \
  env FLOWSCRIBE_REQUIRE_ATTESTATION=1 bash -c "$(declare -f get); DIST='$DIST'; get '$(newdir home-req)' '$(newdir proj-req)' --yes"

# ---------------------------------------------------------------- tampering
T="$WORK/tampered"; cp -R "$DIST" "$T"
printf 'x' >> "$T/$NAME.tar.gz"
H="$(newdir home-tamper)"; P="$(newdir proj-tamper)"
expect_fail "tamper: modified archive refused"      "checksum mismatch" \
  bash -c "cd '$P' && FLOWSCRIBE_HOME='$H' FLOWSCRIBE_DOWNLOAD_BASE='file://$T' bash -s -- --yes < '$T/get.sh'"
check "tamper: nothing installed or kept"           test -z "$(ls -A "$P")" -a ! -e "$H/$VERSION"

H="$(newdir home-fake)"; mkdir -p "$H/$VERSION"; cp "$REPO/install.sh" "$H/$VERSION/"
expect_fail "tamper: unverified cache refused"      "was not verified" get "$H" "$(newdir proj-fake)" --yes

H="$(newdir home-wrong)"; mkdir -p "$H/$VERSION"; cp "$REPO/install.sh" "$H/$VERSION/"; echo deadbeef > "$H/$VERSION/.flowscribe-verified"
expect_fail "tamper: cache with other checksum refused" "was not verified" get "$H" "$(newdir proj-wrong)" --yes

H="$(newdir home-link)"; ln -s "$(newdir elsewhere)" "$H/$VERSION"
expect_fail "tamper: symlinked cache refused"       "is a symlink" get "$H" "$(newdir proj-link)" --yes

# Malicious archives with a matching checksum (as if the release itself were bad).
render() { # archive -> get.sh for it
  sed -e "s|@VERSION@|$VERSION|g" -e "s|@SHA256@|$(sha "$1")|g" -e "s|@REPO@|example/flowscribe|g" "$REPO/scripts/get.sh.in"
}
evil() { # name, how-to-build-stage
  local d="$WORK/evil-$1"; mkdir -p "$d/stage/$NAME" "$d/dist"
  cp "$REPO/install.sh" "$REPO/VERSION" "$d/stage/$NAME/"
  ( cd "$d/stage" && eval "$2" )
  render "$d/dist/$NAME.tar.gz" > "$d/dist/get.sh"; printf '%s' "$d/dist"
}
run_evil() { # dist -> runs get.sh from it
  bash -c "cd '$(newdir "proj-$(basename "$(dirname "$1")")")' && FLOWSCRIBE_HOME='$WORK/home-$(basename "$(dirname "$1")")' FLOWSCRIBE_DOWNLOAD_BASE='file://$1' bash -s -- --yes < '$1/get.sh'"
}
D="$(evil symlink "ln -s /etc '$NAME/etc-link' && tar -czf ../dist/$NAME.tar.gz '$NAME'")"
expect_fail "archive: symlink refused"              "link" run_evil "$D"
D="$(evil outside "echo x > outside.txt && tar -czf ../dist/$NAME.tar.gz '$NAME' outside.txt")"
expect_fail "archive: file outside release dir refused" "unexpected path" run_evil "$D"
D="$(evil hardlink "ln '$NAME/VERSION' '$NAME/VERSION2' && tar -czf ../dist/$NAME.tar.gz '$NAME'")"
expect_fail "archive: hard link refused"            "link" run_evil "$D"
check "archive: nothing written outside"            test ! -e "$WORK/outside.txt"

# ---------------------------------------------------------------- script integrity
sed -e "s|@SHA256@|$(sha "$DIST/$NAME.tar.gz")|g" -e "s|@REPO@|example/flowscribe|g" "$REPO/scripts/get.sh.in" > "$WORK/unrendered.sh"
expect_fail "integrity: unrendered template refused" "not produced by the flowscribe release workflow" \
  bash -c "bash -s < '$WORK/unrendered.sh'"

H="$(newdir home-trunc)"; P="$(newdir proj-trunc)"
head -c "$(( $(wc -c < "$DIST/get.sh") * 2 / 3 ))" "$DIST/get.sh" > "$WORK/truncated.sh"
( cd "$P" && FLOWSCRIBE_HOME="$H" FLOWSCRIBE_DOWNLOAD_BASE="file://$DIST" bash -s -- --yes < "$WORK/truncated.sh" ) >/dev/null 2>&1 || true
check "integrity: truncated download runs nothing"  test -z "$(ls -A "$H")" -a -z "$(ls -A "$P")"

expect_fail "integrity: http mirror refused"        "must start with https:// or file://" \
  bash -c "cd '$(newdir proj-http)' && FLOWSCRIBE_HOME='$(newdir home-http)' FLOWSCRIBE_DOWNLOAD_BASE='http://example.com' bash -s < '$DIST/get.sh'"
expect_fail "integrity: relative FLOWSCRIBE_HOME refused" "absolute path" \
  bash -c "cd '$(newdir proj-rel)' && FLOWSCRIBE_HOME='relative/dir' bash -s < '$DIST/get.sh'"

# ---------------------------------------------------------------- summary
printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
