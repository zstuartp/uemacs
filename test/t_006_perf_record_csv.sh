#!/bin/sh

set -eu

. "$TEST_DIR/lib.sh"

tmp=$(mkdtemp_compat) || die "failed to create temp directory"
trap 'rm -rf "$tmp"' EXIT INT TERM

history="$tmp/perf-history.csv"

ROOT="$ROOT" APP="$APP" TARGET="$TARGET" TEST_DIR="$TEST_DIR" \
	PERF_HISTORY="$history" PERF_RECORD_MODE=always \
	VERSION_ITERS=2 HELP_ITERS=2 REF_ITERS=2 \
	STARTUP_EMPTY_ITERS=1 STARTUP_LOAD_ITERS=1 \
	TYPE_ITERS=1 KEY_ITERS=1 MAIN_ITERS=1 DISPATCH_ITERS=1 \
	BENCH_FILE_LINES=8 TYPE_COMMANDS=4 KEY_COMMANDS=4 \
	MAIN_COMMANDS=6 DISPATCH_COMMANDS=6 \
	PERF_TRIALS=1 PERF_MIN_SECONDS=1 PERF_MAX_ITERS=16 \
	sh "$TEST_DIR/perf-record.sh"

assert_file "$history"

header_count=$(grep -c '^timestamp,tag,commit,os,' "$history" || true)
[ "$header_count" -eq 1 ] || die "expected single CSV header line"

line_count=$(wc -l <"$history" | tr -d ' ')
[ "$line_count" -eq 2 ] || die "expected header + one data row"

header_fields=$(awk -F, 'NR==1 { print NF }' "$history")
row_fields=$(awk -F, 'NR==2 { print NF }' "$history")
[ "$header_fields" -eq "$row_fields" ] \
	|| die "CSV header/data field mismatch ($header_fields vs $row_fields)"

assert_grep 'main_ops_per_sec' "$history"
assert_grep 'dispatch_ops_per_sec' "$history"
assert_grep 'main_norm_permille' "$history"
assert_grep 'dispatch_norm_permille' "$history"
