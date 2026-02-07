#!/bin/sh

set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
APP=${APP:-em}
TARGET=${TARGET:-"$ROOT/build/bin/$APP"}
TEST_DIR=${TEST_DIR:-"$ROOT/test"}
PERF_BASELINE=${PERF_BASELINE:-"$TEST_DIR/perf-baseline.txt"}
PERF_REGRESS_PCT=${PERF_REGRESS_PCT:-20}
PERF_WARN_PCT=${PERF_WARN_PCT:-10}
PERF_FAIL_ON_CLI=${PERF_FAIL_ON_CLI:-0}
if [ "$PERF_WARN_PCT" -ge "$PERF_REGRESS_PCT" ]; then
	PERF_WARN_PCT=$((PERF_REGRESS_PCT - 1))
fi
if [ "$PERF_WARN_PCT" -lt 0 ]; then
	PERF_WARN_PCT=0
fi
PERF_KEYS_EXPLICIT=0
if [ "${PERF_KEYS+x}" = x ] && [ -n "$PERF_KEYS" ]; then
	PERF_KEYS_EXPLICIT=1
fi
PERF_KEYS=${PERF_KEYS:-}
if [ -z "$PERF_KEYS" ]; then
	PERF_KEYS="startup_empty_norm_permille startup_load_norm_permille"
	PERF_KEYS="$PERF_KEYS type_norm_permille key_norm_permille"
	PERF_KEYS="$PERF_KEYS main_norm_permille dispatch_norm_permille"
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
	warn_limit=$((base * (100 + PERF_WARN_PCT) / 100))
	fail_limit=$((base * (100 + PERF_REGRESS_PCT) / 100))
	printf '%s: baseline=%s current=%s warn=%s fail=%s\n' \
		"$name" "$base" "$cur" "$warn_limit" "$fail_limit"
	if [ "$cur" -gt "$fail_limit" ]; then
		echo "Regression in $name: over ${PERF_REGRESS_PCT}% threshold" >&2
		return 1
	fi
	if [ "$cur" -gt "$warn_limit" ]; then
		echo "Warning in $name: over ${PERF_WARN_PCT}% threshold" >&2
		return 3
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
	warn_min=$((base * (100 - PERF_WARN_PCT) / 100))
	fail_min=$((base * (100 - PERF_REGRESS_PCT) / 100))
	printf '%s: baseline=%s current=%s warn=%s fail=%s\n' \
		"$name" "$base" "$cur" "$warn_min" "$fail_min"
	if [ "$cur" -lt "$fail_min" ]; then
		echo "Regression in $name: throughput dropped by over " \
			"${PERF_REGRESS_PCT}%" >&2
		return 1
	fi
	if [ "$cur" -lt "$warn_min" ]; then
		echo "Warning in $name: throughput dropped by over " \
			"${PERF_WARN_PCT}%" >&2
		return 3
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
		rc=0
		compare_metric "$key" "$base" "$cur" || rc=$?
		if [ "$rc" -eq 0 ]; then
			return 0
		fi
		if [ "$rc" -eq 3 ]; then
			return 3
		fi
		;;
	*)
		rc=0
		compare_rate "$key" "$base" "$cur" || rc=$?
		if [ "$rc" -eq 0 ]; then
			return 0
		fi
		if [ "$rc" -eq 3 ]; then
			return 3
		fi
		;;
	esac
	return 1
}

used_norm=0
perf_fail=0
cli_fail=0
perf_warn=0
cli_warn=0
missing_keys=0
for key in $PERF_KEYS; do
	case "$key" in
	*[!A-Za-z0-9_]*|"")
		echo "perf-compare: invalid PERF_KEYS entry '$key'" >&2
		exit 1
		;;
	esac
	rc=0
	if compare_optional_rate "$key"; then
		rc=0
	else
		rc=$?
	fi
	if [ "$rc" -eq 0 ]; then
		used_norm=1
		continue
	elif [ "$rc" -eq 2 ]; then
		missing_keys=$((missing_keys + 1))
		continue
	fi
	used_norm=1
	is_warn=0
	if [ "$rc" -eq 3 ]; then
		is_warn=1
	elif [ "$rc" -ne 1 ]; then
		echo "perf-compare: unexpected status ($rc) for '$key'" >&2
		exit 1
	fi
	case "$key" in
	startup_*|type_*|key_*|main_*|dispatch_*)
		if [ "$is_warn" -eq 1 ]; then
			perf_warn=$((perf_warn + 1))
		else
			perf_fail=$((perf_fail + 1))
		fi
		;;
	*)
		if [ "$is_warn" -eq 1 ]; then
			cli_warn=$((cli_warn + 1))
		else
			cli_fail=$((cli_fail + 1))
		fi
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

if [ "$perf_warn" -gt 0 ]; then
	echo "perf-compare: interactive warning count=$perf_warn" >&2
fi

if [ "$PERF_FAIL_ON_CLI" = "1" ] && [ "$cli_fail" -gt 0 ]; then
	echo "perf-compare: CLI regression count=$cli_fail" >&2
	exit 1
fi

if [ "$cli_warn" -gt 0 ]; then
	echo "perf-compare: CLI warning count=$cli_warn" >&2
fi
