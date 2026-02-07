#!/bin/sh

set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
APP=${APP:-em}
TARGET=${TARGET:-"$ROOT/build/bin/$APP"}
TEST_DIR=${TEST_DIR:-"$ROOT/test"}
PERF_BASELINE=${PERF_BASELINE:-"$TEST_DIR/perf-baseline.txt"}
PERF_REGRESS_PCT=${PERF_REGRESS_PCT:-20}
PERF_FAIL_ON_CLI=${PERF_FAIL_ON_CLI:-0}
PERF_KEYS_EXPLICIT=0
if [ "${PERF_KEYS+x}" = x ] && [ -n "$PERF_KEYS" ]; then
	PERF_KEYS_EXPLICIT=1
fi
PERF_KEYS=${PERF_KEYS:-}
if [ -z "$PERF_KEYS" ]; then
	PERF_KEYS="startup_empty_norm_permille startup_load_norm_permille"
	PERF_KEYS="$PERF_KEYS type_norm_permille key_norm_permille"
	PERF_KEYS="$PERF_KEYS version_norm_permille help_norm_permille"
fi

if [ ! -f "$PERF_BASELINE" ]; then
	echo "perf-compare: baseline not found: $PERF_BASELINE" >&2
	echo "Run: make perf-baseline" >&2
	exit 1
fi

mktemp_file()
{
	base=${TMPDIR:-/tmp}
	if command -v mktemp >/dev/null 2>&1; then
		f=$(mktemp "$base/uemacs-perf-current.XXXXXX" 2>/dev/null || true)
		if [ -n "$f" ]; then
			printf '%s\n' "$f"
			return 0
		fi
	fi
	i=0
	while [ "$i" -lt 100 ]; do
		i=$((i + 1))
		f="$base/uemacs-perf-current.$$.$(date +%s).$i"
		if (umask 077; set -C; : >"$f") 2>/dev/null; then
			printf '%s\n' "$f"
			return 0
		fi
	done
	return 1
}

tmp=$(mktemp_file) || {
	echo "perf-compare: failed to create temporary file" >&2
	exit 1
}
trap 'rm -f "$tmp"' EXIT INT TERM

ROOT="$ROOT" APP="$APP" TARGET="$TARGET" PERF_OUT="$tmp" \
	sh "$TEST_DIR/perf.sh"

read_value()
{
	key=$1
	file=$2
	awk -F= -v k="$key" '
		$1 == k { v = $2 }
		END {
			if (v != "") {
				print v
			}
		}
	' "$file"
}

compare_metric()
{
	name=$1
	base=$2
	cur=$3
	if [ "$base" -le 0 ]; then
		echo "$name: baseline <= 0, skipping threshold check"
		return 0
	fi
	limit=$((base * (100 + PERF_REGRESS_PCT) / 100))
	printf '%s: baseline=%s current=%s limit=%s\n' \
		"$name" "$base" "$cur" "$limit"
	if [ "$cur" -gt "$limit" ]; then
		echo "Regression in $name: over ${PERF_REGRESS_PCT}% threshold" >&2
		return 1
	fi
	return 0
}

compare_rate()
{
	name=$1
	base=$2
	cur=$3
	if [ "$base" -le 0 ]; then
		echo "$name: baseline <= 0, skipping threshold check"
		return 0
	fi
	min_rate=$((base * (100 - PERF_REGRESS_PCT) / 100))
	printf '%s: baseline=%s current=%s minimum=%s\n' \
		"$name" "$base" "$cur" "$min_rate"
	if [ "$cur" -lt "$min_rate" ]; then
		echo "Regression in $name: throughput dropped by over " \
			"${PERF_REGRESS_PCT}%" >&2
		return 1
	fi
	return 0
}

base_version=$(read_value version_seconds "$PERF_BASELINE")
base_help=$(read_value help_seconds "$PERF_BASELINE")
cur_version=$(read_value version_seconds "$tmp")
cur_help=$(read_value help_seconds "$tmp")

if [ -z "$base_version" ] || [ -z "$base_help" ] \
	|| [ -z "$cur_version" ] || [ -z "$cur_help" ]; then
	echo "perf-compare: failed to parse perf snapshot" >&2
	echo "baseline: $PERF_BASELINE" >&2
	echo "current: $tmp" >&2
	exit 1
fi

compare_optional_rate()
{
	key=$1
	base=$(read_value "$key" "$PERF_BASELINE" || true)
	cur=$(read_value "$key" "$tmp" || true)
	if [ -z "$base" ] || [ -z "$cur" ]; then
		return 2
	fi
	case "$key" in
	*_seconds)
		if compare_metric "$key" "$base" "$cur"; then
			return 0
		fi
		;;
	*)
		if compare_rate "$key" "$base" "$cur"; then
			return 0
		fi
		;;
	esac
	return 1
}

used_norm=0
perf_fail=0
cli_fail=0
missing_keys=0
for key in $PERF_KEYS; do
	case "$key" in
	*[!A-Za-z0-9_]*|"")
		echo "perf-compare: invalid PERF_KEYS entry '$key'" >&2
		exit 1
		;;
	esac
	if compare_optional_rate "$key"; then
		used_norm=1
		continue
	elif [ "$?" -eq 2 ]; then
		missing_keys=$((missing_keys + 1))
		continue
	fi
	used_norm=1
	case "$key" in
	startup_*|type_*|key_*)
		perf_fail=$((perf_fail + 1))
		;;
	*)
		cli_fail=$((cli_fail + 1))
		;;
	esac
done

if [ "$missing_keys" -gt 0 ] && [ "$PERF_KEYS_EXPLICIT" -eq 1 ]; then
	echo "perf-compare: missing requested keys in snapshot: " \
		"$missing_keys" >&2
	exit 1
fi

if [ "$used_norm" -eq 0 ]; then
	# Fallback for older snapshots that do not include throughput fields.
	compare_metric version_seconds "$base_version" "$cur_version"
	compare_metric help_seconds "$base_help" "$cur_help"
fi

if [ "$perf_fail" -gt 0 ]; then
	echo "perf-compare: interactive regression count=$perf_fail" >&2
	exit 1
fi

if [ "$PERF_FAIL_ON_CLI" = "1" ] && [ "$cli_fail" -gt 0 ]; then
	echo "perf-compare: CLI regression count=$cli_fail" >&2
	exit 1
fi
