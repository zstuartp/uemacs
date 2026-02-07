#!/bin/sh

set -eu

. "$TEST_DIR/lib.sh"

tmp=$(mkdtemp_compat) || die "failed to create temp directory"
trap 'rm -rf "$tmp"' EXIT INT TERM

assert_exec "$TARGET"

version_out="$tmp/version.out"
help_out="$tmp/help.out"

"$TARGET" --version >"$version_out" 2>&1 || die "--version failed"
assert_grep "uEmacs/Pk version" "$version_out"

set +e
"$TARGET" --help >"$help_out" 2>&1
rc=$?
set -e

if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
	die "--help exit code was $rc (expected 0 or 1)"
fi

assert_grep "Usage: " "$help_out"
assert_grep "--version" "$help_out"
