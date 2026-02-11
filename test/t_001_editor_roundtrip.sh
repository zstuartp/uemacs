#!/bin/sh
# t_001_editor_roundtrip.sh — core editing smoke test
#
# Verifies the fundamental editing cycle: open file, insert text at
# beginning and end, save, exit — then compare output byte-for-byte.

set -eu
. "${TEST_DIR}/lib.sh"

make_tmpdir
trap cleanup_tmpdir EXIT

# --- setup ---
output="$_tmpdir/output.txt"
expected="$_tmpdir/expected.txt"
cmdfile="$_tmpdir/cmd.em"

printf "middle line\n" > "$output"

# Build the expected result: HEADER + original + FOOTER + trailing newline
# (end-of-file positions after the last newline; insert-string "FOOTER~n"
#  adds FOOTER\n there, producing one extra blank line at EOF)
printf "HEADER\nmiddle line\nFOOTER\n\n" > "$expected"

# Build editor command script
sed "s|FILE_PATH|$output|" > "$cmdfile" <<'CMD'
find-file "FILE_PATH"
beginning-of-file
insert-string "HEADER~n"
end-of-file
insert-string "FOOTER~n"
save-file
exit-emacs
CMD

# --- run ---
note "editor roundtrip: insert at beginning and end, save"
run_em "$cmdfile"

# --- verify ---
assert_file_eq "roundtrip output matches expected" "$expected" "$output"

test_done
