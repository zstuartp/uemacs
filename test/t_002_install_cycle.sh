#!/bin/sh

set -eu

. "$TEST_DIR/lib.sh"

tmp=$(mkdtemp_compat) || die "failed to create temp directory"
trap 'rm -rf "$tmp"' EXIT INT TERM

dest="$tmp/dest"
prefix="/usr/local"
bindir="$dest$prefix/bin"
installed="$bindir/$APP"
build_log="$tmp/install.log"
remove_log="$tmp/uninstall.log"

if ! MAKEFLAGS= "$MAKE_CMD" --no-print-directory install \
	DESTDIR="$dest" PREFIX="$prefix" APP="$APP" >"$build_log" 2>&1; then
	cat "$build_log" >&2
	die "make install failed in temp DESTDIR"
fi

assert_exec "$installed"

"$installed" --version >/dev/null 2>&1 || die "installed binary did not run"

if ! MAKEFLAGS= "$MAKE_CMD" --no-print-directory uninstall \
	DESTDIR="$dest" PREFIX="$prefix" APP="$APP" >"$remove_log" 2>&1; then
	cat "$remove_log" >&2
	die "make uninstall failed in temp DESTDIR"
fi

if [ -e "$installed" ] || [ -L "$installed" ]; then
	die "installed binary still present after uninstall"
fi
