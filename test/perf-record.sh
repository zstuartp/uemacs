#!/bin/sh

set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
APP=${APP:-em}
TARGET=${TARGET:-"$ROOT/build/bin/$APP"}
TEST_DIR=${TEST_DIR:-"$ROOT/test"}
PERF_HISTORY=${PERF_HISTORY:-"$TEST_DIR/perf-history.csv"}
PERF_RECORD_MODE=${PERF_RECORD_MODE:-tag}

if [ ! -x "$TARGET" ]; then
	echo "perf-record: missing executable '$TARGET'" >&2
	exit 1
fi

detect_tag()
{
	if command -v git >/dev/null 2>&1; then
		git -C "$ROOT" describe --tags --exact-match 2>/dev/null || true
	fi
}

tag=$(detect_tag)
if [ -z "$tag" ]; then
	tag="(none)"
fi

if [ "$PERF_RECORD_MODE" = "tag" ] && [ "$tag" = "(none)" ]; then
	echo "perf-record: skip (not at a tag)"
	echo "Set PERF_RECORD_MODE=always to record this commit."
	exit 0
fi

ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
os=$(uname -s 2>/dev/null || echo unknown)
sha=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)

mktemp_file()
{
	base=${TMPDIR:-/tmp}
	if command -v mktemp >/dev/null 2>&1; then
		f=$(mktemp "$base/uemacs-perf-record.XXXXXX" 2>/dev/null || true)
		if [ -n "$f" ]; then
			printf '%s\n' "$f"
			return 0
		fi
	fi
	i=0
	while [ "$i" -lt 100 ]; do
		i=$((i + 1))
		f="$base/uemacs-perf-record.$$.$(date +%s).$i"
		if (umask 077; set -C; : >"$f") 2>/dev/null; then
			printf '%s\n' "$f"
			return 0
		fi
	done
	return 1
}

tmp=$(mktemp_file) || {
	echo "perf-record: failed to create temporary file" >&2
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

csv_quote()
{
	value=$1
	value=$(printf '%s' "$value" | tr '\r\n' ' ' | sed 's/"/""/g')
	printf '"%s"' "$value"
}

version_rate=$(read_value version_ops_per_sec "$tmp")
help_rate=$(read_value help_ops_per_sec "$tmp")
version_seconds=$(read_value version_seconds "$tmp")
help_seconds=$(read_value help_seconds "$tmp")
ref_rate=$(read_value ref_ops_per_sec "$tmp")
version_norm=$(read_value version_norm_permille "$tmp")
help_norm=$(read_value help_norm_permille "$tmp")
startup_empty_rate=$(read_value startup_empty_ops_per_sec "$tmp" || true)
startup_load_rate=$(read_value startup_load_ops_per_sec "$tmp" || true)
type_rate=$(read_value type_ops_per_sec "$tmp" || true)
key_rate=$(read_value key_ops_per_sec "$tmp" || true)
startup_empty_norm=$(read_value startup_empty_norm_permille "$tmp" || true)
startup_load_norm=$(read_value startup_load_norm_permille "$tmp" || true)
type_norm=$(read_value type_norm_permille "$tmp" || true)
key_norm=$(read_value key_norm_permille "$tmp" || true)

mkdir -p "$(dirname "$PERF_HISTORY")"
if [ ! -f "$PERF_HISTORY" ]; then
	printf '%s%s\n' \
		"timestamp,tag,commit,os,version_ops_per_sec,help_ops_per_sec," \
		"version_seconds,help_seconds,ref_ops_per_sec," \
		"version_norm_permille,help_norm_permille," \
		"startup_empty_ops_per_sec,startup_load_ops_per_sec," \
		"type_ops_per_sec,key_ops_per_sec," \
		"startup_empty_norm_permille,startup_load_norm_permille," \
		"type_norm_permille,key_norm_permille" \
		>"$PERF_HISTORY"
fi

printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
	"$(csv_quote "$ts")" \
	"$(csv_quote "$tag")" \
	"$(csv_quote "$sha")" \
	"$(csv_quote "$os")" \
	"$version_rate" "$help_rate" \
	"$version_seconds" "$help_seconds" "$ref_rate" \
	"$version_norm" "$help_norm" \
	"$startup_empty_rate" "$startup_load_rate" \
	"$type_rate" "$key_rate" \
	"$startup_empty_norm" "$startup_load_norm" \
	"$type_norm" "$key_norm" >>"$PERF_HISTORY"

echo "perf-record: added entry to $PERF_HISTORY"
