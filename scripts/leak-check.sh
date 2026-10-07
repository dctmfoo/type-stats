#!/bin/sh
# No test copy of the app may outlive the checks: a leftover copy sits in the owner's menu bar with fake data.
# Looks for a TypeStats executable started from this project folder (its path or --data-dir under it).
# The owner's installed copy and other worktrees' copies are not in this folder, so they never match.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd -P)/
left=$(ps -axo pid=,command= | awk -v root="$root" '$2 ~ /\/TypeStats[^\/]*$/ && index($0, root)')
if [ -n "$left" ]; then
  echo "FAIL a test copy of TypeStats is still running (end it with pkill -TERM -f '<its data dir>'):"
  echo "$left" | cut -c1-200
  exit 1
fi
echo "PASS no test copy of TypeStats left running"
