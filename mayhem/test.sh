#!/bin/bash
# test.sh — functional oracle for chesslib: run the library's OWN Maven (JUnit/Surefire) test
# suite and emit a CTRF (ctrf.io) one-line summary. Exits non-zero iff failures+errors > 0.
#
# A no-op/stub harness change cannot pass this: it runs chesslib's real unit tests (board, FEN,
# move generation / perft, PGN parsing, bitboard, etc.) which assert concrete chess behavior.
set -uo pipefail

SRC="${SRC:-/mayhem}"
cd "$SRC"

export JAVA_HOME="${JAVA_HOME:-/opt/jdk}"
export PATH="$JAVA_HOME/bin:/opt/maven/bin:$PATH"

# chesslib's UnicodePrinter/PGN-UTF8 tests assert Unicode chess glyphs and parse UTF-8 PGN files.
# The base image has no default UTF-8 locale, so the JVM defaults to file.encoding=US-ASCII and
# those tests fail with mojibake (expected:<9814 (rook glyph)> but was:<63 ('?')>). Run the suite
# the way upstream CI does — with a UTF-8 locale + file.encoding=UTF-8 propagated to the forked
# Surefire JVM via JAVA_TOOL_OPTIONS.
export LANG=C.UTF-8 LC_ALL=C.UTF-8
export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8 ${JAVA_TOOL_OPTIONS:-}"

LOG="$(mktemp)"
# Run the suite; capture output. Don't let a non-zero mvn exit abort the script before we parse.
mvn -B test 2>&1 | tee "$LOG"
MVN_RC="${PIPESTATUS[0]}"

# Surefire prints a final aggregate line: "Tests run: N, Failures: F, Errors: E, Skipped: S".
# Take the LAST such line (the build-level total).
SUMMARY_LINE="$(grep -E 'Tests run: [0-9]+, Failures: [0-9]+, Errors: [0-9]+, Skipped: [0-9]+' "$LOG" | tail -1)"

TESTS=0; FAILURES=0; ERRORS=0; SKIPPED=0
if [ -n "$SUMMARY_LINE" ]; then
    TESTS=$(echo "$SUMMARY_LINE"    | sed -E 's/.*Tests run: ([0-9]+).*/\1/')
    FAILURES=$(echo "$SUMMARY_LINE" | sed -E 's/.*Failures: ([0-9]+).*/\1/')
    ERRORS=$(echo "$SUMMARY_LINE"   | sed -E 's/.*Errors: ([0-9]+).*/\1/')
    SKIPPED=$(echo "$SUMMARY_LINE"  | sed -E 's/.*Skipped: ([0-9]+).*/\1/')
fi

FAILED=$((FAILURES + ERRORS))
PASSED=$((TESTS - FAILED - SKIPPED))
[ "$PASSED" -lt 0 ] && PASSED=0

# If mvn failed but Surefire reported no test failures (e.g. compile error), treat as a failure.
if [ "$MVN_RC" -ne 0 ] && [ "$FAILED" -eq 0 ] && [ -z "$SUMMARY_LINE" ]; then
    FAILED=1
fi

rm -f "$LOG"

printf 'CTRF {"results":{"tool":{"name":"maven-surefire"},"summary":{"tests":%d,"passed":%d,"failed":%d,"skipped":%d,"pending":0,"other":0}}}\n' \
    "$TESTS" "$PASSED" "$FAILED" "$SKIPPED"

[ "$FAILED" -eq 0 ] && exit 0 || exit 1
