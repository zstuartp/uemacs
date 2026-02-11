#!/bin/sh
# t_002_cursor_movement.sh — navigation smoke test
#
# Verifies cursor movement commands by positioning the cursor and
# inserting marker strings, then checking they appear at the expected
# locations in the saved output.

set -eu
. "${TEST_DIR}/lib.sh"

make_tmpdir
trap cleanup_tmpdir EXIT

# --- test 1: beginning-of-file / end-of-file ---
note "cursor: beginning-of-file and end-of-file markers"

input="$_tmpdir/nav1.txt"
output="$_tmpdir/nav1.txt"
expected="$_tmpdir/nav1_expected.txt"
cmdfile="$_tmpdir/nav1.em"

printf "aaa\nbbb\nccc\n" > "$input"
# end-of-file positions after the last newline; inserting "EOF~n" there
# adds EOF\n, producing one extra trailing blank line
printf "BOFaaa\nbbb\nccc\nEOF\n\n" > "$expected"

sed "s|FILE_PATH|$output|" > "$cmdfile" <<'CMD'
find-file "FILE_PATH"
beginning-of-file
insert-string "BOF"
end-of-file
insert-string "EOF~n"
save-file
exit-emacs
CMD

run_em "$cmdfile"
assert_file_eq "beginning/end of file markers" "$expected" "$output"

# --- test 2: next-line + end-of-line ---
note "cursor: next-line and end-of-line"

input2="$_tmpdir/nav2.txt"
output2="$_tmpdir/nav2.txt"
expected2="$_tmpdir/nav2_expected.txt"
cmdfile2="$_tmpdir/nav2.em"

printf "line1\nline2\nline3\n" > "$input2"
printf "line1\nline2MARK\nline3\n" > "$expected2"

sed "s|FILE_PATH|$output2|" > "$cmdfile2" <<'CMD'
find-file "FILE_PATH"
beginning-of-file
next-line
end-of-line
insert-string "MARK"
save-file
exit-emacs
CMD

run_em "$cmdfile2"
assert_file_eq "next-line + end-of-line marker" "$expected2" "$output2"

# --- test 3: forward-character ---
note "cursor: forward-character positioning"

input3="$_tmpdir/nav3.txt"
output3="$_tmpdir/nav3.txt"
expected3="$_tmpdir/nav3_expected.txt"
cmdfile3="$_tmpdir/nav3.em"

printf "ABCDEF\n" > "$input3"
printf "ABCXDEF\n" > "$expected3"

sed "s|FILE_PATH|$output3|" > "$cmdfile3" <<'CMD'
find-file "FILE_PATH"
beginning-of-file
3 forward-character
insert-string "X"
save-file
exit-emacs
CMD

run_em "$cmdfile3"
assert_file_eq "forward-character inserts at correct position" "$expected3" "$output3"

test_done
