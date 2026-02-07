#!/bin/sh

set -eu

. "$TEST_DIR/lib.sh"

tmp=$(mkdtemp_compat) || die "failed to create temp directory"
trap 'rm -rf "$tmp"' EXIT INT TERM

out="$tmp/perf.out"

ROOT="$ROOT" APP="$APP" TARGET="$TARGET" PERF_OUT="$out" \
	VERSION_ITERS=2 HELP_ITERS=2 REF_ITERS=2 \
	STARTUP_EMPTY_ITERS=1 STARTUP_LOAD_ITERS=1 \
	TYPE_ITERS=1 KEY_ITERS=1 \
	BENCH_FILE_LINES=8 TYPE_COMMANDS=4 KEY_COMMANDS=4 \
	PERF_TRIALS=1 PERF_MIN_SECONDS=1 PERF_MAX_ITERS=16 \
	sh "$TEST_DIR/perf.sh"

assert_file "$out"
assert_grep "version_ops_per_sec=" "$out"
assert_grep "help_ops_per_sec=" "$out"
assert_grep "ref_ops_per_sec=" "$out"
assert_grep "version_norm_permille=" "$out"
assert_grep "help_norm_permille=" "$out"
assert_grep "startup_empty_ops_per_sec=" "$out"
assert_grep "startup_load_ops_per_sec=" "$out"
assert_grep "type_ops_per_sec=" "$out"
assert_grep "key_ops_per_sec=" "$out"
assert_grep "startup_empty_norm_permille=" "$out"
assert_grep "startup_load_norm_permille=" "$out"
assert_grep "type_norm_permille=" "$out"
assert_grep "key_norm_permille=" "$out"
