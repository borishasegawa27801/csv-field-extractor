# csv-field-extractor

Extract named columns from a CSV file by header, with support for double-quoted
fields that contain commas.

```bash
source csv_field_extractor.sh

# One value: column "city" from data line 3 (line 1 is the header).
csv_extract_field people.csv city 3

# Every value in a column, one per line.
csv_extract_field people.csv name

# Just the index, if you want to do your own thing.
csv_header_index 'name,age,city' age   # -> 1
```

The three exported functions are:

- `csv_split_line <line>` — print each field of a single CSV line on its own
  line.
- `csv_header_index <header_line> <column_name>` — print the 0-based index of
  the named column, or return 1 if it is absent.
- `csv_extract_field <file> <column_name> [line_number]` — print the value of
  the named column from the given 1-based data line, or from every data line
  if `line_number` is omitted. Returns 1 if the column is missing or the file
  is unreadable, 2 if the requested data line does not exist.

## Why this exists

The usual `cut -d, -f2` breaks the moment a field contains a quoted comma, and
`awk -F,` is not much better. Rewriting the parser in every script that needs
one column is worse. This library is a single small state machine that handles
RFC 4180 quoting for the cases that actually show up in hand-written CSVs, and
nothing else.

The trade-off: it is line-oriented. A quoted field that spans multiple physical
lines is not supported. Supporting that would mean reading the entire file as
one string and tracking quote state across newlines, which changes the shape of
`csv_extract_field` from a line-at-a-time loop into a full-file scan. Most CSVs
produced by spreadsheets do not use embedded newlines, and the ones that do are
usually better handled by a real CSV library in a real language. If you need
that, this is not the tool.

## The awkward edge

Header matching is exact and case-sensitive. `csv_header_index 'name,age' Name`
returns 1, not 0. This is deliberate: a header `" name"` and a header `"name"`
are different columns, and silently trimming or folding them would hide data
problems. Quote your column name if it contains spaces or commas.

A short row is not an error. If row 2 of a file with header `a,b,c` is `1,2`,
then `csv_extract_field file.csv c 2` prints an empty line and exits 0. Treating
a missing trailing field as empty matches how most CSV readers behave and keeps
the caller from having to special-case ragged input.
