#!/bin/sh

set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
APP=${APP:-em}
TARGET=${TARGET:-"$ROOT/build/bin/$APP"}
TEST_DIR=${TEST_DIR:-"$ROOT/test"}
PERF_SCRIPT=${PERF_SCRIPT:-"$TEST_DIR/perf.sh"}
PERF_COMPARE=${PERF_COMPARE:-"$TEST_DIR/perf-compare.sh"}
SELF_TYPE_COMMANDS=${SELF_TYPE_COMMANDS:-512}
SELF_KEY_COMMANDS=${SELF_KEY_COMMANDS:-16}
SELF_MIN_SECONDS=${SELF_MIN_SECONDS:-2}
SELF_MAX_ITERS=${SELF_MAX_ITERS:-2048}
SELF_BASE_THRESH=${SELF_BASE_THRESH:-60}
SELF_INJECT_FACTOR=${SELF_INJECT_FACTOR:-4}
SELF_INJECT_THRESH=${SELF_INJECT_THRESH:-20}

if [ ! -x "$TARGET" ]; then
	echo "perf-selfcheck: missing executable '$TARGET'" >&2
	exit 1
fi

if [ ! -f "$PERF_SCRIPT" ]; then
	echo "perf-selfcheck: missing script '$PERF_SCRIPT'" >&2
	exit 1
fi

if [ ! -f "$PERF_COMPARE" ]; then
	echo "perf-selfcheck: missing script '$PERF_COMPARE'" >&2
	exit 1
fi

mktemp_file()
{
	base=${TMPDIR:-/tmp}
	if command -v mktemp >/dev/null 2>&1; then
		f=$(mktemp "$base/uemacs-perf-selfcheck.XXXXXX" 2>/dev/null || true)
		if [ -n "$f" ]; then
			printf '%s\n' "$f"
			return 0
		fi
	fi
	i=0
	while [ "$i" -lt 100 ]; do
		i=$((i + 1))
		f="$base/uemacs-perf-selfcheck.$$.$(date +%s).$i"
		if (umask 077; set -C; : >"$f") 2>/dev/null; then
			printf '%s\n' "$f"
			return 0
		fi
	done
	return 1
}

baseline=$(mktemp_file) || {
	echo "perf-selfcheck: failed to create baseline temp file" >&2
	exit 1
}
fail_log=$(mktemp_file) || {
	echo "perf-selfcheck: failed to create failure log temp file" >&2
	exit 1
}

cleanup()
{
	rm -f "$baseline" "$fail_log"
}
trap cleanup EXIT INT TERM

echo "perf-selfcheck: writing baseline"
ROOT="$ROOT" APP="$APP" TARGET="$TARGET" PERF_OUT="$baseline" \
	VERSION_ITERS=2 HELP_ITERS=2 REF_ITERS=2 \
	STARTUP_EMPTY_ITERS=1 STARTUP_LOAD_ITERS=1 TYPE_ITERS=2 KEY_ITERS=1 \
	BENCH_FILE_LINES=64 TYPE_COMMANDS="$SELF_TYPE_COMMANDS" \
	KEY_COMMANDS="$SELF_KEY_COMMANDS" PERF_TRIALS=1 \
	PERF_MIN_SECONDS="$SELF_MIN_SECONDS" PERF_MAX_ITERS="$SELF_MAX_ITERS" \
	sh "$PERF_SCRIPT"

echo "perf-selfcheck: checking baseline against current build"
ROOT="$ROOT" APP="$APP" TARGET="$TARGET" PERF_BASELINE="$baseline" \
	VERSION_ITERS=2 HELP_ITERS=2 REF_ITERS=2 \
	STARTUP_EMPTY_ITERS=1 STARTUP_LOAD_ITERS=1 TYPE_ITERS=2 KEY_ITERS=1 \
	BENCH_FILE_LINES=64 TYPE_COMMANDS="$SELF_TYPE_COMMANDS" \
	KEY_COMMANDS="$SELF_KEY_COMMANDS" PERF_TRIALS=1 \
	PERF_MIN_SECONDS="$SELF_MIN_SECONDS" PERF_MAX_ITERS="$SELF_MAX_ITERS" \
	PERF_FAIL_ON_CLI=0 PERF_REGRESS_PCT="$SELF_BASE_THRESH" \
	PERF_KEYS=type_ops_per_sec \
	sh "$PERF_COMPARE"

echo "perf-selfcheck: injecting slowdown in type mode (expected fail)"
if ROOT="$ROOT" APP="$APP" TARGET="$TARGET" PERF_BASELINE="$baseline" \
	VERSION_ITERS=2 HELP_ITERS=2 REF_ITERS=2 \
	STARTUP_EMPTY_ITERS=1 STARTUP_LOAD_ITERS=1 TYPE_ITERS=2 KEY_ITERS=1 \
	BENCH_FILE_LINES=64 TYPE_COMMANDS="$SELF_TYPE_COMMANDS" \
	KEY_COMMANDS="$SELF_KEY_COMMANDS" PERF_TRIALS=1 \
	PERF_MIN_SECONDS="$SELF_MIN_SECONDS" PERF_MAX_ITERS="$SELF_MAX_ITERS" \
	PERF_FAIL_ON_CLI=0 PERF_KEYS=type_ops_per_sec \
	PERF_INJECT_MODE=type PERF_INJECT_FACTOR="$SELF_INJECT_FACTOR" \
	PERF_REGRESS_PCT="$SELF_INJECT_THRESH" \
	sh "$PERF_COMPARE" >"$fail_log" 2>&1; then
	cat "$fail_log" >&2
	echo "perf-selfcheck: expected regression was not detected" >&2
	exit 1
fi

echo "perf-selfcheck: regression detector is working"
