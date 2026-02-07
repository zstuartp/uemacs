#!/bin/sh

set -eu

. "$TEST_DIR/lib.sh"

makefile="$ROOT/Makefile"
assert_file "$makefile"

if grep -q -- "hunspell-1.7" "$makefile"; then
	die "Makefile contains version-pinned hunspell fallback"
fi

assert_grep "HUNSPELL_LIB ?= hunspell" "$makefile"
