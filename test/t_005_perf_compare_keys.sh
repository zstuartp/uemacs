#!/bin/sh

set -eu

. "$TEST_DIR/lib.sh"

tmp=$(mkdtemp_compat) || die "failed to create temp directory"
trap 'rm -rf "$tmp"' EXIT INT TERM

base="$tmp/baseline.out"
log="$tmp/compare.log"

ROOT="$ROOT" APP="$APP" TARGET="$TARGET" PERF_OUT="$base" \
	VERSION_ITERS=2 HELP_ITERS=2 REF_ITERS=2 \
	STARTUP_EMPTY_ITERS=1 STARTUP_LOAD_ITERS=1 \
	TYPE_ITERS=1 KEY_ITERS=1 \
	BENCH_FILE_LINES=8 TYPE_COMMANDS=4 KEY_COMMANDS=4 \
	PERF_TRIALS=1 PERF_MIN_SECONDS=1 PERF_MAX_ITERS=16 \
	sh "$TEST_DIR/perf.sh"

assert_file "$base"

set +e
ROOT="$ROOT" APP="$APP" TARGET="$TARGET" PERF_BASELINE="$base" \
	VERSION_ITERS=2 HELP_ITERS=2 REF_ITERS=2 \
	STARTUP_EMPTY_ITERS=1 STARTUP_LOAD_ITERS=1 \
	TYPE_ITERS=1 KEY_ITERS=1 \
	BENCH_FILE_LINES=8 TYPE_COMMANDS=4 KEY_COMMANDS=4 \
	PERF_TRIALS=1 PERF_MIN_SECONDS=1 PERF_MAX_ITERS=16 \
	PERF_KEYS=missing_metric \
	sh "$TEST_DIR/perf-compare.sh" >"$log" 2>&1
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
	cat "$log" >&2
	die "perf-compare accepted missing explicit key"
fi

assert_grep "missing requested keys in snapshot" "$log"
