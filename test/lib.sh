#!/bin/sh

set -u

die()
{
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

note()
{
	printf '# %s\n' "$*"
}

require_cmd()
{
	command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

assert_file()
{
	[ -f "$1" ] || die "missing file: $1"
}

assert_exec()
{
	[ -x "$1" ] || die "not executable: $1"
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
