#!/usr/bin/env bash
# Check this repository's accessibility trees against the committed baselines.
#
# Usage: ./check-a11y.sh [path-to-autospec-checkout]
#
# The baselines in .autospec/a11y-baselines/ are a positive control: these pages are written
# to be correct, so any regression the gate reports here is either a real change to them or a
# bug in the gate. Regression *detection* is covered by autospec's own unit tests, which drive
# a real browser through a labelled/unlabelled pair — a corpus of deliberately broken pages
# would need one committed baseline per page and would only restate what those tests prove.
#
# To accept an intentional change: re-run with --update, read the diff, commit it.
set -u

AUTOSPEC="${1:-../autospec}"
GATE="$AUTOSPEC/skills/autospec-shared/scripts/ui-a11y-baseline.mjs"
if [ ! -f "$GATE" ]; then
  echo "check-a11y.sh: cannot find $GATE — pass the path to an autospec checkout" >&2
  exit 2
fi

HERE="$(cd "$(dirname "$0")" && pwd -P)"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null; fi
}
trap cleanup EXIT

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
# Threaded: a real browser holds keep-alive connections, which deadlocks the single-threaded
# http.server partway through a run.
python3 -c "
import sys, functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
handler = functools.partial(SimpleHTTPRequestHandler, directory=sys.argv[2])
ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), handler).serve_forever()
" "$PORT" "$HERE" >/dev/null 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:$PORT/index.html" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
if ! curl -fsS "http://127.0.0.1:$PORT/index.html" >/dev/null 2>&1; then
  echo "check-a11y.sh: static server never came up on port $PORT" >&2
  exit 2
fi

# --update is forwarded so re-recording goes through this script rather than a hand-built
# command with a different route list.
node "$GATE" --base-url "http://127.0.0.1:$PORT" \
  --routes /index.html /runs.html /states.html \
  --baseline-dir "$HERE/.autospec/a11y-baselines" "$@" 2>&1 | grep -v '^check-a11y'
status="${PIPESTATUS[0]}"

case "$status" in
  0) echo "check-a11y.sh: OK — trees match the committed baselines" ;;
  3) echo "check-a11y.sh: the gate could not run (Playwright unavailable)" >&2 ;;
  *) echo "check-a11y.sh: an accessibility regression was reported above" >&2 ;;
esac
exit "$status"
