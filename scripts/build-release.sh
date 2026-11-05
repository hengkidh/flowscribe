#!/usr/bin/env bash
# Builds the release files. Used by the release workflow and by the tests.
#
#   scripts/build-release.sh <version> <owner/repo> <out-dir>
#
# Produces in <out-dir>:
#   flowscribe-v<version>.tar.gz   the release (reproducible when built with GNU tar)
#   get.sh                         one-line installer with the archive's SHA-256 embedded
#   SHA256SUMS                     checksums of both
set -euo pipefail
export LC_ALL=C COPYFILE_DISABLE=1   # COPYFILE_DISABLE: no macOS ._ metadata files in the archive

die() { printf 'build-release: error: %s\n' "$*" >&2; exit 1; }
[ $# -eq 3 ] || die "usage: scripts/build-release.sh <version> <owner/repo> <out-dir>"
version="$1"; repo="$2"; out="$3"

printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' || die "invalid version: $version"
printf '%s' "$repo" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || die "invalid repository: $repo"

root="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
[ "$(tr -d '[:space:]' < "$root/VERSION")" = "$version" ] || die "VERSION file does not match $version"

if command -v sha256sum >/dev/null 2>&1; then sha256() { sha256sum -- "$1" | awk '{print $1}'; }
else sha256() { shasum -a 256 -- "$1" | awk '{print $1}'; }; fi

name="flowscribe-v$version"
stage="$(mktemp -d "${TMPDIR:-/tmp}/flowscribe-build.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT

mkdir -p "$stage/$name" "$out"
for f in install.sh VERSION payload schema spec examples README.md LICENSE SECURITY.md CONTRIBUTING.md; do
  cp -R "$root/$f" "$stage/$name/"
done
[ -z "$(find "$stage/$name" -type l -print)" ] || die "symlink in release"
find "$stage/$name" \( -name '.DS_Store' -o -name '*.flowscribe-new' \) -delete

if tar --version 2>/dev/null | grep -q 'GNU tar'; then
  epoch="$(git -C "$root" log -1 --format=%ct 2>/dev/null || echo 0)"
  tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner --format=posix \
      --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
      -C "$stage" -cf - "$name" | gzip -n -9 > "$out/$name.tar.gz"
else
  tar -C "$stage" -cf - "$name" | gzip -n -9 > "$out/$name.tar.gz"
fi

sum="$(sha256 "$out/$name.tar.gz")"
sed -e "s|@VERSION@|$version|g" -e "s|@SHA256@|$sum|g" -e "s|@REPO@|$repo|g" \
  "$root/scripts/get.sh.in" > "$out/get.sh"
if grep -Eq '@(VERSION|SHA256|REPO)@' "$out/get.sh"; then die "unrendered placeholder in get.sh"; fi
bash -n "$out/get.sh" || die "get.sh has a syntax error"

(cd "$out" && for f in "$name.tar.gz" get.sh; do printf '%s  %s\n' "$(sha256 "$f")" "$f"; done > SHA256SUMS)
cat "$out/SHA256SUMS"
