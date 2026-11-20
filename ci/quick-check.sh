#!/usr/bin/env bash
# The cheap part of ci/jenkins-gate.sh, before a push: the format check and analyze (seconds). The tests run on Jenkins.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH=$HOME/fvm/bin:/opt/homebrew/bin:$HOME/.pub-cache/bin:$PATH
F=flutter; D=dart; command -v fvm >/dev/null && { F="fvm flutter"; D="fvm dart"; }
fails=0
step() { printf '   %-10s ' "$1"; shift; if "$@" >/tmp/qc-$$.log 2>&1; then echo ok; else echo FAILED; tail -20 /tmp/qc-$$.log | sed 's/^/      /'; fails=$((fails+1)); fi; }
step format $D format --output=none --set-exit-if-changed lib test example/lib
step analyze $F analyze --fatal-infos
rm -f /tmp/qc-$$.log; [ $fails = 0 ] && echo "quick-check: ok — push; Jenkins runs the rest"; exit $(( fails > 0 ))
