# Suite-level setup. bats-core loads this file once before the tests in this
# directory. It puts the coderabbit stub first on PATH, so a test that calls
# coderabbit without its own stub reaches the recording stub, and
# teardown_suite() fails the run when that happens.
#
# teardown_suite() runs in the suite process, so it never sees variables that
# a test exports. CODERABBIT_SUITE_RECORD exists only so that the self-test can
# point a direct teardown_suite call at a fixture file.

_CODERABBIT_STUB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures/coderabbit-stub" && pwd)"

setup_suite() {
  export PATH="$_CODERABBIT_STUB_DIR:$PATH"
}

teardown_suite() {
  local record="${CODERABBIT_SUITE_RECORD:-$BATS_SUITE_TMPDIR/coderabbit-calls}"
  if [ -s "$record" ]; then
    echo "coderabbit was called during the suite; calls recorded in $record:" >&2
    cat "$record" >&2
    return 1
  fi
}
