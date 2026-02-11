#!/bin/sh
# test/lib.sh — shared test helpers for uemacs smoke tests
# Output is TAP (Test Anything Protocol) compliant.
# Safety: no rm -rf anywhere. Temp dirs validated before removal.

set -eu

# --- TAP state ---
_tnum=0
_fail=0

# --- output ---
die()  { printf "Bail out! %s\n" "$*" >&2; exit 1; }
note() { printf "# %s\n" "$*"; }

pass() {
	_tnum=$((_tnum + 1))
	printf "ok %d - %s\n" "$_tnum" "$*"
}

fail() {
	_tnum=$((_tnum + 1))
	_fail=$((_fail + 1))
	printf "not ok %d - %s\n" "$_tnum" "$*"
}

# --- assertions ---
assert_eq() {
	_label="$1"; _expected="$2"; _actual="$3"
	if [ "$_expected" = "$_actual" ]; then
		pass "$_label"
	else
		fail "$_label"
		note "expected: $_expected"
		note "actual:   $_actual"
	fi
}

assert_file_eq() {
	_label="$1"; _expected="$2"; _actual="$3"
	if cmp -s "$_expected" "$_actual"; then
		pass "$_label"
	else
		fail "$_label"
		diff -u "$_expected" "$_actual" | while IFS= read -r _line; do
			note "$_line"
		done
	fi
}

assert_file_contains() {
	_label="$1"; _file="$2"; _pattern="$3"
	if grep -qF "$_pattern" "$_file"; then
		pass "$_label"
	else
		fail "$_label"
		note "pattern '$_pattern' not found in $_file"
	fi
}

# --- temp dir management ---
_tmpdir=""

make_tmpdir() {
	_tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/uemacs-test.XXXXXX")"
	[ -d "$_tmpdir" ] || die "mktemp failed"
}

cleanup_tmpdir() {
	[ -n "$_tmpdir" ] || return 0
	# Validate prefix before removal — refuse anything unexpected
	case "$_tmpdir" in
		*/uemacs-test.*) ;;
		*) die "cleanup_tmpdir: refusing to remove '$_tmpdir' (bad prefix)" ;;
	esac
	[ -d "$_tmpdir" ] || return 0
	rm -r -- "$_tmpdir"
	_tmpdir=""
}

# --- editor helper ---
run_em() {
	_cmdfile="$1"
	[ -n "${TARGET:-}" ] || die "TARGET not set"
	[ -f "$_cmdfile" ] || die "command file not found: $_cmdfile"
	TERM=xterm "$TARGET" "@$_cmdfile" >/dev/null 2>&1
}

# --- TAP plan (emit at end) ---
test_done() {
	printf "1..%d\n" "$_tnum"
	[ "$_fail" -eq 0 ]
}
