#!/bin/sh

set -eu

if [ -f "$TEST_DIR/lib.sh" ]; then
	. "$TEST_DIR/lib.sh"
else
	die()
	{
		printf 'FAIL: %s\n' "$*" >&2
		exit 1
	}

	require_cmd()
	{
		command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
	}

	assert_grep()
	{
		pat=$1
		file=$2
		grep -q -- "$pat" "$file" || die "pattern '$pat' not found in $file"
	}

	mkdtemp_compat()
	{
		base=${TMPDIR:-/tmp}
		if command -v mktemp >/dev/null 2>&1; then
			d=$(mktemp -d "$base/uemacs-test.XXXXXX" 2>/dev/null || true)
			if [ -n "$d" ]; then
				printf '%s\n' "$d"
				return 0
			fi
		fi
		i=0
		while [ "$i" -lt 100 ]; do
			i=$((i + 1))
			d="$base/uemacs-test.$$.$(date +%s).$i"
			if mkdir "$d" 2>/dev/null; then
				printf '%s\n' "$d"
				return 0
			fi
		done
		return 1
	}
fi

tmp=$(mkdtemp_compat) || die "failed to create temp directory"
trap 'rm -rf "$tmp"' EXIT INT TERM

cc_cmd=${CC:-cc}
# CC can contain a compiler wrapper and/or flags (e.g. "ccache cc").
# Split it into words for command lookup and execution.
set -- $cc_cmd
require_cmd "$1"

harness="$tmp/pklock-harness"
source_c="$TEST_DIR/pklock_harness.c"
pklock_c="$ROOT/src/pklock.c"

if ! "$cc_cmd" -std=c99 -Wall -Wextra -Werror -pedantic \
	-I"$ROOT/include" -D_POSIX_C_SOURCE=200809L \
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

: >"$target.lock~"
printf '%s\n' "LOCKED_BY_USER" >"$target.lock~"
owner_lock_out="$tmp/owner-lock.out"
set +e
"$harness" lock "$target" >"$owner_lock_out" 2>&1
rc=$?
set -e
if [ "$rc" -ne 2 ]; then
	cat "$owner_lock_out" >&2
	die "LOCK-prefixed owner should be treated as owner (rc=2), got rc=$rc"
fi
assert_grep "LOCKED_BY_USER" "$owner_lock_out"
rm -f "$target.lock~"

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
