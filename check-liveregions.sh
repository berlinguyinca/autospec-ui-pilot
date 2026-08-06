#!/usr/bin/env bash
# Drive this repository's states through autospec's live-region gate and compare the result
# to EXPECTED-live.tsv.
#
# Usage: ./check-liveregions.sh [path-to-autospec-checkout]
#
# Unlike check.sh, this gate needs the pages served and a browser to drive them, so it
# starts a local static server on a free port and stops it on the way out.
set -u

AUTOSPEC="${1:-../autospec}"
GATE="$AUTOSPEC/skills/autospec-shared/scripts/ui-liveregion-evidence.mjs"
if [ ! -f "$GATE" ]; then
  echo "check-liveregions.sh: cannot find $GATE — pass the path to an autospec checkout" >&2
  exit 2
fi

HERE="$(cd "$(dirname "$0")" && pwd -P)"
OBSERVED="$(mktemp)"
CONTRACT="$(mktemp)"
REPORT="$(mktemp)"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null; fi
  rm -f "$OBSERVED" "$CONTRACT" "$REPORT"
}
trap cleanup EXIT

# A port the kernel hands out, so concurrent checkouts do not collide.
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$HERE" >/dev/null 2>&1 &
SERVER_PID=$!

# Wait for the server rather than sleeping a guessed interval.
for _ in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:$PORT/states.html" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
if ! curl -fsS "http://127.0.0.1:$PORT/states.html" >/dev/null 2>&1; then
  echo "check-liveregions.sh: static server never came up on port $PORT" >&2
  exit 2
fi

# Observed: "route[state]<TAB>rule" per finding, plus "route[state]<TAB>-" for a clean one.
for manifest in "$HERE/.autospec/ui-test-hooks.json" "$HERE/fixtures/live-regions/hooks.json"; do
  node "$GATE" --base-url "http://127.0.0.1:$PORT" --manifest "$manifest" --json "$REPORT" >/dev/null 2>&1
  status=$?
  # 3 is "Playwright unavailable, nothing was collected" — an unknown, not a pass, so it
  # must not be allowed to look like a clean run.
  if [ "$status" -eq 3 ]; then
    echo "check-liveregions.sh: the gate could not run (Playwright unavailable)" >&2
    exit 2
  fi
  python3 - "$REPORT" >> "$OBSERVED" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
findings = report.get("findings", [])
seen = set()
for f in findings:
    key = f"{f['route']}[{f['state']}]"
    seen.add(key)
    print(f"{key}\t{f['rule']}")
for row in report.get("states", []):
    key = f"{row['route']}[{row['state']}]"
    if key not in seen:
        print(f"{key}\t-")
PY
done

grep -v -e '^#' -e '^[[:space:]]*$' "$HERE/EXPECTED-live.tsv" | sort > "$CONTRACT"
sort "$OBSERVED" -o "$OBSERVED"

if diff -u "$CONTRACT" "$OBSERVED" > /dev/null; then
  echo "check-liveregions.sh: OK — $(wc -l < "$CONTRACT" | tr -d ' ') rows match the contract"
  exit 0
fi

echo "check-liveregions.sh: the gate and EXPECTED-live.tsv disagree." >&2
echo "  '-' lines are the contract, '+' lines are what the gate reported." >&2
diff -u "$CONTRACT" "$OBSERVED" >&2
exit 1
