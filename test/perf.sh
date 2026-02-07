#!/bin/sh

set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
APP=${APP:-em}
TARGET=${TARGET:-"$ROOT/build/bin/$APP"}
PERF_OUT=${PERF_OUT:-}

VERSION_ITERS=${VERSION_ITERS:-800}
HELP_ITERS=${HELP_ITERS:-300}
REF_ITERS=${REF_ITERS:-1000}
STARTUP_EMPTY_ITERS=${STARTUP_EMPTY_ITERS:-20}
STARTUP_LOAD_ITERS=${STARTUP_LOAD_ITERS:-12}
TYPE_ITERS=${TYPE_ITERS:-8}
KEY_ITERS=${KEY_ITERS:-8}

PERF_MIN_SECONDS=${PERF_MIN_SECONDS:-3}
PERF_MAX_ITERS=${PERF_MAX_ITERS:-128000}
PERF_TRIALS=${PERF_TRIALS:-3}
PERF_TERM=${PERF_TERM:-xterm}
BENCH_FILE_LINES=${BENCH_FILE_LINES:-4096}
TYPE_COMMANDS=${TYPE_COMMANDS:-400}
KEY_COMMANDS=${KEY_COMMANDS:-600}
PERF_INJECT_MODE=${PERF_INJECT_MODE:-none}
PERF_INJECT_FACTOR=${PERF_INJECT_FACTOR:-1}

if [ ! -x "$TARGET" ]; then
	echo "perf.sh: missing executable '$TARGET'" >&2
	exit 1
fi

mktemp_file()
{
	base=${TMPDIR:-/tmp}
	if command -v mktemp >/dev/null 2>&1; then
		f=$(mktemp "$base/uemacs-perf.XXXXXX" 2>/dev/null || true)
		if [ -n "$f" ]; then
			printf '%s\n' "$f"
			return 0
		fi
	fi
	i=0
	while [ "$i" -lt 100 ]; do
		i=$((i + 1))
		f="$base/uemacs-perf.$$.$(date +%s).$i"
		if (umask 077; set -C; : >"$f") 2>/dev/null; then
			printf '%s\n' "$f"
			return 0
		fi
	done
	return 1
}

bench_file=$(mktemp_file) || exit 1
cmd_empty=$(mktemp_file) || exit 1
cmd_load=$(mktemp_file) || exit 1
cmd_type=$(mktemp_file) || exit 1
cmd_key=$(mktemp_file) || exit 1

cleanup()
{
	rm -f "$bench_file" "$cmd_empty" "$cmd_load" "$cmd_type" "$cmd_key"
}
trap cleanup EXIT INT TERM

i=0
while [ "$i" -lt "$BENCH_FILE_LINES" ]; do
	printf '%s\n' \
		"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" \
		>>"$bench_file"
	i=$((i + 1))
done

cat >"$cmd_empty" <<EOF
0 exit-emacs
EOF

cat >"$cmd_load" <<EOF
find-file "$bench_file"
0 exit-emacs
EOF

i=0
while [ "$i" -lt "$TYPE_COMMANDS" ]; do
	echo 'insert-string "abcdefghijklmnopqrstuvwxyz0123456789"' \
		>>"$cmd_type"
	echo 'newline' >>"$cmd_type"
	i=$((i + 1))
done
echo '0 exit-emacs' >>"$cmd_type"

{
	echo 'insert-string "benchmarkline"'
	echo 'newline'
	echo 'insert-string "benchmarkline"'
	echo 'beginning-of-file'
} >"$cmd_key"
i=0
while [ "$i" -lt "$KEY_COMMANDS" ]; do
	echo 'forward-character' >>"$cmd_key"
	echo 'backward-character' >>"$cmd_key"
	echo 'next-line' >>"$cmd_key"
	echo 'previous-line' >>"$cmd_key"
	echo 'end-of-line' >>"$cmd_key"
	echo 'beginning-of-line' >>"$cmd_key"
	i=$((i + 1))
done
echo '0 exit-emacs' >>"$cmd_key"

run_editor_script()
{
	cmdfile=$1
	TERM="$PERF_TERM" "$TARGET" "@$cmdfile" >/dev/null 2>&1
}

run_mode_once()
{
	mode=$1
	case "$mode" in
	version)
		"$TARGET" --version >/dev/null 2>&1
		;;
	help)
		"$TARGET" --help >/dev/null 2>&1 || true
		;;
	ref)
		env true >/dev/null 2>&1
		;;
	startup_empty)
		run_editor_script "$cmd_empty"
		;;
	startup_load)
		run_editor_script "$cmd_load"
		;;
	type)
		run_editor_script "$cmd_type"
		;;
	key)
		run_editor_script "$cmd_key"
		;;
	*)
		echo "perf.sh: unknown mode '$mode'" >&2
		exit 1
		;;
	esac
}

should_inject_mode()
{
	mode=$1
	if [ "$PERF_INJECT_MODE" = "all" ] || [ "$PERF_INJECT_MODE" = "$mode" ]; then
		return 0
	fi
	return 1
}

now_ns()
{
	value=$(date +%s%N 2>/dev/null || true)
	case "$value" in
	*[!0-9]*|"")
		value=$(date +%s)
		value=$((value * 1000000000))
		;;
	esac
	echo "$value"
}

measure_loop()
{
	iters=$1
	mode=$2
	start_ns=$(now_ns)
	i=0
	while [ "$i" -lt "$iters" ]; do
		run_mode_once "$mode"
		if [ "$PERF_INJECT_FACTOR" -gt 1 ] && should_inject_mode "$mode"; then
			j=1
			while [ "$j" -lt "$PERF_INJECT_FACTOR" ]; do
				run_mode_once "$mode"
				j=$((j + 1))
			done
		fi
		i=$((i + 1))
	done
	end_ns=$(now_ns)
	echo $((end_ns - start_ns))
}

measure_metric_once()
{
	mode=$1
	iters=$2
	min_ns=$((PERF_MIN_SECONDS * 1000000000))
	elapsed_ns=$(measure_loop "$iters" "$mode")
	while [ "$elapsed_ns" -lt "$min_ns" ] \
		&& [ "$iters" -lt "$PERF_MAX_ITERS" ]; do
		iters=$((iters * 2))
		elapsed_ns=$(measure_loop "$iters" "$mode")
	done
	if [ "$elapsed_ns" -le 0 ]; then
		seconds=0
		rate=0
	else
		seconds=$(((elapsed_ns + 999999999) / 1000000000))
		rate=$((iters * 1000000000 / elapsed_ns))
	fi
	echo "$iters $seconds $rate"
}

measure_metric()
{
	mode=$1
	start_iters=$2
	trial=0
	sum_iters=0
	sum_seconds=0
	sum_rate=0

	if [ "$PERF_TRIALS" -le 0 ]; then
		echo "perf.sh: PERF_TRIALS must be > 0" >&2
		exit 1
	fi

	while [ "$trial" -lt "$PERF_TRIALS" ]; do
		trial=$((trial + 1))
		set -- $(measure_metric_once "$mode" "$start_iters")
		iters=$1
		seconds=$2
		rate=$3
		sum_iters=$((sum_iters + iters))
		sum_seconds=$((sum_seconds + seconds))
		sum_rate=$((sum_rate + rate))
	done

	echo "$((sum_iters / PERF_TRIALS)) $((sum_seconds / PERF_TRIALS))" \
		" $((sum_rate / PERF_TRIALS))"
}

set -- $(measure_metric version "$VERSION_ITERS")
version_iters=$1
version_seconds=$2
version_ops_per_sec=$3

set -- $(measure_metric help "$HELP_ITERS")
help_iters=$1
help_seconds=$2
help_ops_per_sec=$3

set -- $(measure_metric ref "$REF_ITERS")
ref_iters=$1
ref_seconds=$2
ref_ops_per_sec=$3

set -- $(measure_metric startup_empty "$STARTUP_EMPTY_ITERS")
startup_empty_iters=$1
startup_empty_seconds=$2
startup_empty_ops_per_sec=$3

set -- $(measure_metric startup_load "$STARTUP_LOAD_ITERS")
startup_load_iters=$1
startup_load_seconds=$2
startup_load_ops_per_sec=$3

set -- $(measure_metric type "$TYPE_ITERS")
type_iters=$1
type_seconds=$2
type_ops_per_sec=$3

set -- $(measure_metric key "$KEY_ITERS")
key_iters=$1
key_seconds=$2
key_ops_per_sec=$3

normalize_rate()
{
	rate=$1
	ref=$2
	if [ "$ref" -le 0 ]; then
		echo 0
	else
		echo $((rate * 1000 / ref))
	fi
}

version_norm_permille=$(normalize_rate "$version_ops_per_sec" \
	"$ref_ops_per_sec")
help_norm_permille=$(normalize_rate "$help_ops_per_sec" "$ref_ops_per_sec")
startup_empty_norm_permille=$(normalize_rate "$startup_empty_ops_per_sec" \
	"$ref_ops_per_sec")
startup_load_norm_permille=$(normalize_rate "$startup_load_ops_per_sec" \
	"$ref_ops_per_sec")
type_norm_permille=$(normalize_rate "$type_ops_per_sec" "$ref_ops_per_sec")
key_norm_permille=$(normalize_rate "$key_ops_per_sec" "$ref_ops_per_sec")

out_file=${PERF_OUT:-/dev/stdout}
cat >"$out_file" <<EOF
# uEmacs perf snapshot
target=$TARGET
perf_min_seconds=$PERF_MIN_SECONDS
perf_trials=$PERF_TRIALS
version_iters=$version_iters
version_seconds=$version_seconds
version_ops_per_sec=$version_ops_per_sec
help_iters=$help_iters
help_seconds=$help_seconds
help_ops_per_sec=$help_ops_per_sec
ref_iters=$ref_iters
ref_seconds=$ref_seconds
ref_ops_per_sec=$ref_ops_per_sec
startup_empty_iters=$startup_empty_iters
startup_empty_seconds=$startup_empty_seconds
startup_empty_ops_per_sec=$startup_empty_ops_per_sec
startup_load_iters=$startup_load_iters
startup_load_seconds=$startup_load_seconds
startup_load_ops_per_sec=$startup_load_ops_per_sec
type_iters=$type_iters
type_seconds=$type_seconds
type_ops_per_sec=$type_ops_per_sec
key_iters=$key_iters
key_seconds=$key_seconds
key_ops_per_sec=$key_ops_per_sec
version_norm_permille=$version_norm_permille
help_norm_permille=$help_norm_permille
startup_empty_norm_permille=$startup_empty_norm_permille
startup_load_norm_permille=$startup_load_norm_permille
type_norm_permille=$type_norm_permille
key_norm_permille=$key_norm_permille
EOF
