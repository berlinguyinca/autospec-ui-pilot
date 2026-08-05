#!/usr/bin/env bash
# Run autospec's UI gate over this repository and compare the result to EXPECTED.tsv.
#
# Usage: ./check.sh [path-to-autospec-checkout]
#
# Exits non-zero when observed findings and the contract disagree — a rule that stopped
# firing, or started firing somewhere new. The "over-fire" and "missed" rows are expected
# to disagree with correctness but agree with the table; they are the recorded defects.
set -u

AUTOSPEC="${1:-../autospec}"
LINT="$AUTOSPEC/scripts/lint-ui.sh"
if [ ! -f "$LINT" ]; then
  echo "check.sh: cannot find $LINT — pass the path to an autospec checkout" >&2
  exit 2
fi

HERE="$(cd "$(dirname "$0")" && pwd -P)"
OBSERVED="$(mktemp)"
CONTRACT="$(mktemp)"
trap 'rm -f "$OBSERVED" "$CONTRACT"' EXIT

# Observed: "path<TAB>rule" per finding, plus "path<TAB>-" for a file with none.
for f in "$HERE/index.html" "$HERE"/styles/*.css \
         "$HERE"/fixtures/violations/* "$HERE"/fixtures/known-gaps/*; do
  [ -f "$f" ] || continue
  rel="${f#"$HERE"/}"
  out="$(bash "$LINT" "$f" 2>&1)"
  # Breakage is detected by its message, not by the exit code: lint-ui.sh exits with the
  # finding count, and also uses 2 for "awk failed", so exit 2 is ambiguous between a
  # broken gate and a file with two findings.
  case "$out" in
    'lint-ui: awk failed'*)
      echo "check.sh: lint-ui.sh could not run on $rel: $out" >&2
      exit 2
      ;;
  esac
  if [ -z "$out" ]; then
    printf '%s\t-\n' "$rel" >> "$OBSERVED"
  else
    printf '%s\n' "$out" | cut -d: -f1 | sort -u | while IFS= read -r rule; do
      printf '%s\t%s\n' "$rel" "$rule" >> "$OBSERVED"
    done
  fi
done
sort -u -o "$OBSERVED" "$OBSERVED"

# Contract: the same shape, taken from EXPECTED.tsv. A "missed" row states the rule that
# *should* fire, so the file is expected to be observed clean instead.
awk -F'\t' '
  /^#/ || NF < 3 { next }
  {
    path = $1; rule = $2; verdict = $3
    if (verdict == "missed") { print path "\t-" }
    else { print path "\t" rule }
  }
' "$HERE/EXPECTED.tsv" | sort -u > "$CONTRACT"

if diff -u "$CONTRACT" "$OBSERVED" > /dev/null; then
  printf 'UI gate matches EXPECTED.tsv (%d rows)\n' "$(wc -l < "$CONTRACT" | tr -d ' ')"
  exit 0
fi

echo "UI gate disagrees with EXPECTED.tsv:"
echo "  < contract   > observed"
diff -u "$CONTRACT" "$OBSERVED" | tail -n +4
exit 1
