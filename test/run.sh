#!/bin/sh

set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
TEST_DIR=${TEST_DIR:-"$ROOT/test"}
APP=${APP:-em}
TARGET=${TARGET:-"$ROOT/build/bin/$APP"}

count=0
pass=0
fail=0

for test_file in "$TEST_DIR"/t_*.sh; do
	[ -f "$test_file" ] || continue

	count=$((count + 1))
	name=$(basename "$test_file")
	printf '==> %s\n' "$name"

	if ROOT="$ROOT" TEST_DIR="$TEST_DIR" APP="$APP" TARGET="$TARGET" \
		MAKE_CMD="${MAKE_CMD:-make}" sh "$test_file"; then
		pass=$((pass + 1))
		printf 'ok  - %s\n' "$name"
	else
		fail=$((fail + 1))
		printf 'not ok - %s\n' "$name"
	fi
done

if [ "$count" -eq 0 ]; then
	echo "No tests found in $TEST_DIR"
	exit 1
fi

printf 'Tests: %s, Passed: %s, Failed: %s\n' "$count" "$pass" "$fail"
[ "$fail" -eq 0 ]
