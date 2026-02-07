#!/bin/sh

set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
APP=${APP:-em}
PERF_AB_A=${PERF_AB_A:-HEAD}
PERF_AB_B=${PERF_AB_B:-}
PERF_AB_ROUNDS=${PERF_AB_ROUNDS:-3}
PERF_AB_INCLUDE_CLI=${PERF_AB_INCLUDE_CLI:-0}
PERF_AB_KEYS=${PERF_AB_KEYS:-}
if [ -z "$PERF_AB_KEYS" ]; then
	PERF_AB_KEYS="startup_empty_norm_permille startup_load_norm_permille"
	PERF_AB_KEYS="$PERF_AB_KEYS type_norm_permille key_norm_permille"
	PERF_AB_KEYS="$PERF_AB_KEYS main_norm_permille dispatch_norm_permille"
fi
for key in $PERF_AB_KEYS; do
	case "$key" in
	*[!A-Za-z0-9_]*|"")
		echo "perf-ab: invalid PERF_AB_KEYS entry '$key'" >&2
		exit 1
		;;
	esac
done

if [ -z "$PERF_AB_B" ]; then
	echo "perf-ab: set PERF_AB_B to a ref (example: PERF_AB_B=master)" >&2
	exit 1
fi

if [ "$PERF_AB_ROUNDS" -le 0 ]; then
	echo "perf-ab: PERF_AB_ROUNDS must be > 0" >&2
	exit 1
fi

if ! command -v git >/dev/null 2>&1; then
	echo "perf-ab: git is required" >&2
	exit 1
fi
if ! command -v tar >/dev/null 2>&1; then
	echo "perf-ab: tar is required" >&2
	exit 1
fi

mktemp_dir()
{
	base=${TMPDIR:-/tmp}
	if command -v mktemp >/dev/null 2>&1; then
		d=$(mktemp -d "$base/uemacs-perf-ab.XXXXXX" 2>/dev/null || true)
		if [ -n "$d" ]; then
			printf '%s\n' "$d"
			return 0
		fi
	fi
	i=0
	while [ "$i" -lt 100 ]; do
		i=$((i + 1))
		d="$base/uemacs-perf-ab.$$.$(date +%s).$i"
		if mkdir "$d" 2>/dev/null; then
			printf '%s\n' "$d"
			return 0
		fi
	done
	return 1
}

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

key_tag()
{
	printf '%s\n' "$1" | tr -c 'A-Za-z0-9_' '_'
}

median_of_key()
{
	prefix=$1
	key=$2
	work=$3
	tag=$(key_tag "$key")
	values="$work/values.$prefix.$tag"
	sorted="$work/sorted.$prefix.$tag"
	: >"$values"
	i=1
	while [ "$i" -le "$PERF_AB_ROUNDS" ]; do
		v=$(read_value "$key" "$work/$prefix.$i" || true)
		if [ -n "$v" ]; then
			printf '%s\n' "$v" >>"$values"
		fi
		i=$((i + 1))
	done
	count=$(wc -l <"$values" | tr -d ' ')
	if [ "$count" -eq 0 ]; then
		echo ""
		return 0
	fi
	sort -n "$values" >"$sorted"
	idx=$(((count + 1) / 2))
	sed -n "${idx}p" "$sorted"
}

show_delta_pct()
{
	a=$1
	b=$2
	if [ "$a" -eq 0 ]; then
		echo "n/a"
		return 0
	fi
	awk -v av="$a" -v bv="$b" 'BEGIN {
		d=((bv-av)*100.0)/av;
		printf "%.1f%%", d;
	}'
}

a_commit=$(git -C "$ROOT" rev-parse --verify "$PERF_AB_A^{commit}" 2>/dev/null \
	|| true)
b_commit=$(git -C "$ROOT" rev-parse --verify "$PERF_AB_B^{commit}" 2>/dev/null \
	|| true)
if [ -z "$a_commit" ] || [ -z "$b_commit" ]; then
	echo "perf-ab: invalid refs A='$PERF_AB_A' B='$PERF_AB_B'" >&2
	exit 1
fi

tmp_root=$(mktemp_dir) || {
	echo "perf-ab: failed to create temporary directory" >&2
	exit 1
}
a_dir="$tmp_root/a"
b_dir="$tmp_root/b"
a_build="$tmp_root/build-a"
b_build="$tmp_root/build-b"
a_target="$a_build/bin/$APP"
b_target="$b_build/bin/$APP"

cleanup()
{
	rm -rf "$tmp_root"
}
trap cleanup EXIT INT TERM

if ! mkdir -p "$a_dir" "$b_dir"; then
	echo "perf-ab: failed to create temporary source directories" >&2
	exit 1
fi

if ! git -C "$ROOT" archive "$a_commit" | tar -x -C "$a_dir"; then
	echo "perf-ab: failed to export A ($PERF_AB_A)" >&2
	exit 1
fi
if ! git -C "$ROOT" archive "$b_commit" | tar -x -C "$b_dir"; then
	echo "perf-ab: failed to export B ($PERF_AB_B)" >&2
	exit 1
fi

if ! make -C "$a_dir" APP="$APP" BUILD_DIR="$a_build" >/dev/null; then
	echo "perf-ab: build failed for A ($PERF_AB_A)" >&2
	exit 1
fi
if ! make -C "$b_dir" APP="$APP" BUILD_DIR="$b_build" >/dev/null; then
	echo "perf-ab: build failed for B ($PERF_AB_B)" >&2
	exit 1
fi

i=1
while [ "$i" -le "$PERF_AB_ROUNDS" ]; do
	ROOT="$a_dir" APP="$APP" TARGET="$a_target" \
		PERF_INCLUDE_CLI="$PERF_AB_INCLUDE_CLI" \
		PERF_OUT="$tmp_root/a.$i" sh "$a_dir/test/perf.sh" || {
		echo "perf-ab: perf run failed for A in round $i" >&2
		exit 1
	}
	ROOT="$b_dir" APP="$APP" TARGET="$b_target" \
		PERF_INCLUDE_CLI="$PERF_AB_INCLUDE_CLI" \
		PERF_OUT="$tmp_root/b.$i" sh "$b_dir/test/perf.sh" || {
		echo "perf-ab: perf run failed for B in round $i" >&2
		exit 1
	}
	i=$((i + 1))
done

echo "A=$PERF_AB_A ($a_commit)"
echo "B=$PERF_AB_B ($b_commit)"
echo "rounds=$PERF_AB_ROUNDS"
printf '%-30s %-10s %-10s %-8s\n' "metric" "A-median" "B-median" "delta"
for key in $PERF_AB_KEYS; do
	a_med=$(median_of_key a "$key" "$tmp_root")
	b_med=$(median_of_key b "$key" "$tmp_root")
	if [ -z "$a_med" ] || [ -z "$b_med" ]; then
		printf '%-30s %-10s %-10s %-8s\n' "$key" "-" "-" "n/a"
		continue
	fi
	delta=$(show_delta_pct "$a_med" "$b_med")
	printf '%-30s %-10s %-10s %-8s\n' "$key" "$a_med" "$b_med" "$delta"
done
