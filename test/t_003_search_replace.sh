#!/bin/sh
# t_003_search_replace.sh — search and replace smoke test
#
# Verifies replace-string by replacing all occurrences of a pattern
# in a file and comparing byte-for-byte against expected output.

set -eu
. "${TEST_DIR}/lib.sh"

make_tmpdir
trap cleanup_tmpdir EXIT

# --- test 1: replace all occurrences ---
note "replace-string: multiple occurrences"

input="$_tmpdir/sr1.txt"
output="$_tmpdir/sr1.txt"
expected="$_tmpdir/sr1_expected.txt"
cmdfile="$_tmpdir/sr1.em"

printf "foo and foo and foo\nfoo at start\nend foo\n" > "$input"
printf "bar and bar and bar\nbar at start\nend bar\n" > "$expected"

sed "s|FILE_PATH|$output|" > "$cmdfile" <<'CMD'
find-file "FILE_PATH"
beginning-of-file
replace-string "foo" "bar"
save-file
exit-emacs
CMD

run_em "$cmdfile"
assert_file_eq "replace-string foo->bar all occurrences" "$expected" "$output"

# --- test 2: replace with longer string ---
note "replace-string: different length replacement"

input2="$_tmpdir/sr2.txt"
output2="$_tmpdir/sr2.txt"
expected2="$_tmpdir/sr2_expected.txt"
cmdfile2="$_tmpdir/sr2.em"

printf "aa bb aa\ncc aa dd\n" > "$input2"
printf "ZZZ bb ZZZ\ncc ZZZ dd\n" > "$expected2"

sed "s|FILE_PATH|$output2|" > "$cmdfile2" <<'CMD'
find-file "FILE_PATH"
beginning-of-file
replace-string "aa" "ZZZ"
save-file
exit-emacs
CMD

run_em "$cmdfile2"
assert_file_eq "replace-string aa->ZZZ different lengths" "$expected2" "$output2"

# --- test 3: no-match replacement is harmless ---
note "replace-string: no matches leaves file unchanged"

input3="$_tmpdir/sr3.txt"
output3="$_tmpdir/sr3.txt"
expected3="$_tmpdir/sr3_expected.txt"
cmdfile3="$_tmpdir/sr3.em"

printf "hello world\n" > "$input3"
printf "hello world\n" > "$expected3"

sed "s|FILE_PATH|$output3|" > "$cmdfile3" <<'CMD'
find-file "FILE_PATH"
beginning-of-file
!force replace-string "NOTFOUND" "X"
save-file
exit-emacs
CMD

run_em "$cmdfile3"
assert_file_eq "replace-string no match leaves file unchanged" "$expected3" "$output3"

test_done
