#!/bin/bash
# Measures watch app launch phases against a throwaway backend (A12). Prints the trace lines of N launches.
# usage: watch-launch-bench.sh <app> <sim-udid> <runs> [TT_DEV_SERVER TT_DEV_COOKIE]   (the dev env is only used for the first launch)
# The simulator must be a `timetrack-dev-*` clone. Reads the unified log subsystem de.linolaske.timetrack.
set -eu
APP="$1"; UDID="$2"; RUNS="$3"; SERVER="${4:-}"; COOKIE="${5:-}"
BID=de.linolaske.timetrack.watchkitapp
xcrun simctl install "$UDID" "$APP"
[ -n "$SERVER" ] && xcrun simctl keychain "$UDID" reset
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
if [ -n "$SERVER" ]; then
  MARK=$(date +"%Y-%m-%d %H:%M:%S")
  SIMCTL_CHILD_TT_DEV_SERVER="$SERVER" SIMCTL_CHILD_TT_DEV_COOKIE="$COOKIE" xcrun simctl launch "$UDID" "$BID" >/dev/null
  sleep 8
  echo "--- run 0 (first launch after boot/install, dev sign-in)"
  xcrun simctl spawn "$UDID" log show --start "$MARK" --predicate 'subsystem == "de.linolaske.timetrack"' --style compact 2>/dev/null | grep -E 'launch' | sed -E 's/^.*launch[^ ]* *//' || true
  xcrun simctl terminate "$UDID" "$BID"
fi
for i in $(seq 1 "$RUNS"); do
  sleep 2
  MARK=$(date +"%Y-%m-%d %H:%M:%S")
  xcrun simctl launch "$UDID" "$BID" >/dev/null
  sleep 6
  echo "--- run $i"
  xcrun simctl spawn "$UDID" log show --start "$MARK" --predicate 'subsystem == "de.linolaske.timetrack"' --style compact 2>/dev/null | grep -E 'launch' | sed -E 's/^.*launch[^ ]* *//' || true
  xcrun simctl terminate "$UDID" "$BID"
done
