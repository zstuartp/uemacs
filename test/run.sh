#!/bin/sh
# test/run.sh — minimal test runner for uemacs
# Discovers and runs test/t_*.sh scripts.

set -eu

: "${ROOT:?ROOT must be set}"
: "${TARGET:?TARGET must be set}"
: "${TEST_DIR:?TEST_DIR must be set}"
: "${APP:?APP must be set}"

export ROOT TARGET TEST_DIR APP

total_pass=0
total_fail=0
ran=0

for t in "$TEST_DIR"/t_*.sh; do
	[ -f "$t" ] || continue
	name="$(basename "$t")"
	printf '%s\n' "--- $name ---"
	if sh "$t"; then
		total_pass=$((total_pass + 1))
	else
		total_fail=$((total_fail + 1))
	fi
	ran=$((ran + 1))
done

printf "\n=== %d test scripts: %d passed, %d failed ===\n" \
	"$ran" "$total_pass" "$total_fail"

[ "$total_fail" -eq 0 ]
