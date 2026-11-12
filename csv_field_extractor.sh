#!/usr/bin/env bash
#
# csv_field_extractor.sh -- extract named columns from a CSV file by header.
#
# The parser is a small state machine over the raw bytes of one line. It
# tracks whether we are inside a double-quoted field so that commas inside
# quotes are treated as data rather than separators. Doubled quotes ("")
# inside a quoted field are collapsed to a single quote, matching RFC 4180.
#
# The trade-off: this is a line-oriented parser, not a streaming parser.
# Multi-line quoted fields (a quoted field that contains a literal newline)
# are therefore NOT supported. Supporting them would require reading the
# whole file as one string and tracking quote state across newlines, which
# is more code than the problem usually warrants. This limitation is stated
# in the README and tested in the test suite.

set -euo pipefail

# csv_split_line <line>
#
# Split one CSV line into fields, honouring double-quoted fields that may
# contain commas. Each field is printed on its own line. The caller is
# expected to read the result with `mapfile` or a while-read loop.
#
# Why print one field per line instead of using IFS? Because a quoted field
# can contain a literal newline in a fully compliant parser, and even without
# that, a field can contain any byte except a NUL. A newline-delimited
# output is the only separator we can be sure is unambiguous for the common
# case we support.
csv_split_line() {
  local line="$1"
  local len=${#line}
  local i=0
  local field=""
  local in_quotes=0
  local c

  while (( i < len )); do
    c=${line:i:1}
    if (( in_quotes )); then
      if [[ "$c" == '"' ]]; then
        # A doubled quote inside a quoted field is an escaped quote.
        if (( i + 1 < len )) && [[ ${line:i+1:1} == '"' ]]; then
          field+='"'
          (( i += 2 ))
          continue
        fi
        in_quotes=0
        (( i += 1 ))
        continue
      fi
      field+="$c"
    else
      if [[ "$c" == '"' ]]; then
        in_quotes=1
        (( i += 1 ))
        continue
      fi
      if [[ "$c" == ',' ]]; then
        printf '%s\n' "$field"
        field=""
        (( i += 1 ))
        continue
      fi
      field+="$c"
    fi
    (( i += 1 ))
  done
  printf '%s\n' "$field"
}

# csv_header_index <header_line> <column_name>
#
# Print the 0-based index of <column_name> in the header line. Returns 1 and
# prints nothing if the column is not present. The comparison is exact and
# case-sensitive; we do not normalise whitespace because a header like
# " name" is a different column from "name" and the caller should be able to
# say so.
csv_header_index() {
  local header="$1"
  local want="$2"
  local idx=0
  local field

  while IFS= read -r field; do
    if [[ "$field" == "$want" ]]; then
      printf '%s\n' "$idx"
      return 0
    fi
    (( idx += 1 ))
  done < <(csv_split_line "$header")

  return 1
}

# csv_extract_field <file> <column_name> [line_number]
#
# Print the value of <column_name> from the given 1-based data line of <file>.
# Line 1 is the header; data starts at line 2. If <line_number> is omitted,
# every data line is printed, one value per line.
#
# Returns 1 if the column is missing from the header, 2 if the requested
# data line does not exist, and 0 on success.
csv_extract_field() {
  local file="$1"
  local column="$2"
  local want_line="${3:-}"
  local header
  local index
  local lineno=0
  local line
  local fields
  local value

  if [[ ! -r "$file" ]]; then
    printf 'csv_extract_field: cannot read %s\n' "$file" >&2
    return 1
  fi

  # Read the header line. `read` returns non-zero on EOF, which is fine for
  # an empty file: the column will simply not be found.
  IFS= read -r header < "$file" || true
  if [[ -z "$header" ]]; then
    return 1
  fi

  if ! index=$(csv_header_index "$header" "$column"); then
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    (( lineno += 1 ))
    (( lineno == 1 )) && continue
    if [[ -n "$want_line" ]] && (( lineno != want_line )); then
      continue
    fi
    fields=$(csv_split_line "$line")
    # Pull the field at `index` out of the newline-delimited list. `mapfile`
    # is a bash builtin, so this stays dependency-free.
    mapfile -t __csv_fields <<< "$fields"
    if (( index < ${#__csv_fields[@]} )); then
      value=${__csv_fields[index]}
    else
      value=""
    fi
    printf '%s\n' "$value"
    if [[ -n "$want_line" ]]; then
      return 0
    fi
  done < "$file"

  if [[ -n "$want_line" ]]; then
    return 2
  fi
  return 0
}
