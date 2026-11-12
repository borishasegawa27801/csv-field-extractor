#!/usr/bin/env bash
#
# Tests for csv_field_extractor.sh. Run with: bash test_csv_field_extractor.sh
# The suite is deliberately small and deterministic: no wall-clock reads, no
# sleeps, no network. Each assertion prints a TAP-like line and the script
# exits non-zero on the first failure.

set -euo pipefail

# shellcheck source=csv_field_extractor.sh
source "$(dirname "$0")/csv_field_extractor.sh"

PASS=0
FAIL=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf 'ok - %s\n' "$label"
    (( PASS += 1 ))
  else
    printf 'not ok - %s\n' "$label"
    printf '  expected: %q\n' "$expected"
    printf '  actual:   %q\n' "$actual"
    (( FAIL += 1 ))
  fi
}

assert_status() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf 'ok - %s\n' "$label"
    (( PASS += 1 ))
  else
    printf 'not ok - %s\n' "$label"
    printf '  expected status: %s\n' "$expected"
    printf '  actual status:   %s\n' "$actual"
    (( FAIL += 1 ))
  fi
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# --- csv_split_line ---------------------------------------------------------

out=$(csv_split_line 'a,b,c')
assert_eq $'a\nb\nc' "$out" "split plain fields"

out=$(csv_split_line '"a,b",c')
assert_eq $'a,b\nc' "$out" "comma inside quotes is data"

out=$(csv_split_line '"a""b",c')
assert_eq $'a"b\nc' "$out" "doubled quote collapses to one"

out=$(csv_split_line '"",x')
assert_eq $'\nx' "$out" "empty quoted field"

out=$(csv_split_line 'a,,c')
assert_eq $'a\n\nc' "$out" "empty unquoted field"

out=$(csv_split_line 'a')
assert_eq 'a' "$out" "single field"

# --- csv_header_index -------------------------------------------------------

hdr='name,age,city'
assert_eq '0' "$(csv_header_index "$hdr" name)" "header index first"
assert_eq '1' "$(csv_header_index "$hdr" age)" "header index middle"
assert_eq '2' "$(csv_header_index "$hdr" city)" "header index last"

set +e
csv_header_index "$hdr" missing >/dev/null 2>&1
rc=$?
set -e
assert_status '1' "$rc" "missing header returns 1"

# Quoted header names are handled by the same splitter.
hdr2='"first,name",age'
assert_eq '1' "$(csv_header_index "$hdr2" age)" "header index across quoted comma"
assert_eq '0' "$(csv_header_index "$hdr2" 'first,name')" "header index quoted name"

# --- csv_extract_field ------------------------------------------------------

cat > "$tmpdir/basic.csv" <<'EOF'
name,age,city
alice,30,berlin
bob,25,paris
EOF

assert_eq 'alice' "$(csv_extract_field "$tmpdir/basic.csv" name 2)" "extract first data row"
assert_eq '25' "$(csv_extract_field "$tmpdir/basic.csv" age 3)" "extract third column row 3"
assert_eq 'paris' "$(csv_extract_field "$tmpdir/basic.csv" city 3)" "extract last column"

out=$(csv_extract_field "$tmpdir/basic.csv" name)
assert_eq $'alice\nbob' "$out" "extract whole column"

# Missing column on a real file.
set +e
csv_extract_field "$tmpdir/basic.csv" nope 2 >/dev/null 2>&1
rc=$?
set -e
assert_status '1' "$rc" "missing column returns 1"

# Requested row beyond the file.
set +e
csv_extract_field "$tmpdir/basic.csv" name 99 >/dev/null 2>&1
rc=$?
set -e
assert_status '2' "$rc" "out-of-range line returns 2"

# Quoted fields with commas survive extraction.
cat > "$tmpdir/quoted.csv" <<'EOF'
id,label
1,"hello, world"
2,"a""b"
EOF

assert_eq 'hello, world' "$(csv_extract_field "$tmpdir/quoted.csv" label 2)" "quoted comma preserved"
assert_eq 'a"b' "$(csv_extract_field "$tmpdir/quoted.csv" label 3)" "escaped quote preserved"

# Empty fields stay empty.
cat > "$tmpdir/empty.csv" <<'EOF'
a,b,c
1,,3
EOF

assert_eq '' "$(csv_extract_field "$tmpdir/empty.csv" b 2)" "empty field yields empty string"

# Short rows: a missing trailing field is treated as empty rather than an error.
cat > "$tmpdir/short.csv" <<'EOF'
a,b,c
1,2
EOF

assert_eq '' "$(csv_extract_field "$tmpdir/short.csv" c 2)" "short row yields empty trailing field"

# Unreadable file.
set +e
csv_extract_field "$tmpdir/does-not-exist.csv" a 2 >/dev/null 2>&1
rc=$?
set -e
assert_status '1' "$rc" "unreadable file returns 1"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  exit 1
fi
exit 0
