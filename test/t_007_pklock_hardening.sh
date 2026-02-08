#!/bin/sh

set -eu

. "$TEST_DIR/lib.sh"

tmp=$(mkdtemp_compat) || die "failed to create temp directory"
trap 'rm -rf "$tmp"' EXIT INT TERM

cc_cmd=${CC:-cc}
require_cmd "$cc_cmd"

harness="$tmp/pklock-harness"
source_c="$TEST_DIR/pklock_harness.c"
pklock_c="$ROOT/src/pklock.c"

if ! "$cc_cmd" -std=c99 -Wall -Wextra -Werror -pedantic \
	-I"$ROOT/src" "$source_c" "$pklock_c" -o "$harness"; then
	die "failed to build pklock harness"
fi

target="$tmp/target.txt"
: >"$target"

first_lock="$tmp/first-lock.out"
"$harness" lock "$target" >"$first_lock" 2>&1 || die "first lock failed"
assert_grep "^OK$" "$first_lock"

second_lock="$tmp/second-lock.out"
set +e
"$harness" lock "$target" >"$second_lock" 2>&1
rc=$?
set -e
if [ "$rc" -ne 2 ]; then
	cat "$second_lock" >&2
	die "second lock should report owner string (rc=2), got rc=$rc"
fi
assert_grep "@" "$second_lock"

unlock_out="$tmp/unlock.out"
"$harness" unlock "$target" >"$unlock_out" 2>&1 || die "unlock failed"
assert_grep "^OK$" "$unlock_out"

ln -s "$tmp/symlink-target" "$target.lock~"
symlink_out="$tmp/symlink-lock.out"
set +e
"$harness" lock "$target" >"$symlink_out" 2>&1
rc=$?
set -e
if [ "$rc" -ne 3 ]; then
	cat "$symlink_out" >&2
	die "symlink lock should fail with LOCK ERROR (rc=3), got rc=$rc"
fi
assert_grep "LOCK ERROR" "$symlink_out"
rm -f "$target.lock~"

: >"$target.lock~"
malformed_out="$tmp/malformed-lock.out"
set +e
"$harness" lock "$target" >"$malformed_out" 2>&1
rc=$?
set -e
if [ "$rc" -ne 3 ]; then
	cat "$malformed_out" >&2
	die "empty lock should fail with LOCK ERROR (rc=3), got rc=$rc"
fi
assert_grep "LOCK ERROR" "$malformed_out"
rm -f "$target.lock~"

long_name="$tmp/$(awk 'BEGIN { for (i = 0; i < 700; ++i) printf "a" }')"
long_out="$tmp/long-lock.out"
set +e
"$harness" lock "$long_name" >"$long_out" 2>&1
rc=$?
set -e
if [ "$rc" -ne 3 ]; then
	cat "$long_out" >&2
	die "long path should fail with LOCK ERROR (rc=3), got rc=$rc"
fi
assert_grep "path too long" "$long_out"
