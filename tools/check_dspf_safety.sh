#!/usr/bin/env bash
set -euo pipefail

# DDS fixed-format preflight checks for stream files.
# Fails on common issues that trigger CPD7410/CPD7596/CPD7606/CPD7672.

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  mapfile -t files < <(find src -maxdepth 1 -type f -name "*.DSPF" | sort)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No DSPF files found."
  exit 0
fi

fail=0

for f in "${files[@]}"; do
  [[ -f "$f" ]] || continue

  awk -v file="$f" '
    function report(msg, n, txt) {
      printf("%s:%d: %s\n", file, n, msg)
      printf("  %s\n", txt)
      bad = 1
    }

    BEGIN { bad = 0 }

    {
      line = $0

      if (index(line, "\t") > 0) {
        report("tab character found", NR, line)
      }

      if (line ~ /[^[:space:]]/ && line !~ /^ {5}A/ && line !~ /^\*|^ +\*/) {
        report("line does not start with a DDS-safe prefix (5 spaces + A, or comment style)", NR, line)
      }

      if (length(line) > 80) {
        report("line exceeds 80 columns (fixed-format risk)", NR, line)
      }

      # Do not attempt quote-pair validation here because valid DDS source
      # often uses continued literals split across physical lines.
    }

    END {
      if (bad) {
        exit 2
      }
    }
  ' "$f" || fail=1

done

if [[ $fail -ne 0 ]]; then
  echo "DDS preflight: FAILED"
  exit 1
fi

echo "DDS preflight: OK"
