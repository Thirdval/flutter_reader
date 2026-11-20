#!/usr/bin/env bash
# The package's gate on Jenkins (job flutter_reader/ci; Jenkinsfile) — what its old .github/workflows/ci.yml ran: pub get, analyze
# (fatal infos), the format check, the tests. Every step runs and reports; the gate fails if any did. On a runner (fvm in
# ~/fvm/bin, the SDK from .fvmrc), inside the runner's one-gate-at-a-time queue (class 0, with the app and web gates).
# No secret.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH=$HOME/fvm/bin:$PATH CI=1 TZ=UTC
C=${GIT_COMMIT:-manual}
. "$HOME/gate-queue.sh"; wait_turn 0 "jenkins flutter_reader ${C:0:12}"
fails=0
step() { local name=$1; shift; local t=$(date +%s); echo "── $name"; "$@"; local rc=$?
  printf '   %s %s (%ss)\n' "$name" "$([ $rc -eq 0 ] && echo PASS || echo FAIL)" $(( $(date +%s) - t ))
  [ $rc -eq 0 ] || fails=$((fails + 1)); return $rc; }
step fvm-install fvm install || { echo "flutter_reader gate · fvm install failed"; exit 1; }
step pub-get fvm flutter pub get || { echo "flutter_reader gate · pub get failed"; exit 1; }
step analyze fvm flutter analyze --fatal-infos
step format fvm dart format --output=none --set-exit-if-changed lib test example/lib
step test fvm flutter test --exclude-tags benchmark
step test-bench fvm flutter test --tags benchmark
echo "flutter_reader gate · $fails failing step(s)"
exit $(( fails > 0 ))
