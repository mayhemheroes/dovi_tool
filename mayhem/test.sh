#!/usr/bin/env bash
#
# dovi_tool/mayhem/test.sh — RUN quietvoid/dovi_tool's own test suite (`cargo test` for the
# dovi_tool CLI crate + the dolby_vision library crate) and emit a CTRF summary.
# exit 0 iff no test failed.
#
# PATCH-grade oracle: dovi_tool ships a real assertion suite —
#   - tests/ (integration, assert_cmd): runs the built dovi_tool binary over committed HEVC/RPU
#     sample assets and asserts exact outputs — golden-file comparisons of extracted/injected
#     RPUs, demux/mux/convert results, editor/generator outputs (predicates on bytes/JSON);
#   - src unit tests (CLI internals);
#   - dolby_vision src tests incl. src/xml/tests.rs: known-answer XML parsing assertions.
# These assert concrete values / golden outputs, so a no-op / exit(0) patch CANNOT pass.
# This script only RUNS the suite; mayhem/build.sh pre-compiled it with `cargo test --no-run`.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not available — cannot run the test suite" >&2
  emit_ctrf "cargo-test" 0 1 0; exit 2
fi

echo "=== running cargo test (dovi_tool CLI suite + dolby_vision library suite) ==="
# RUSTFLAGS cleared so nothing is inherited from the sanitizer build (same fingerprint as the
# `cargo test --no-run` pre-build in build.sh — nothing recompiles here).
out="$(RUSTFLAGS="" cargo test --no-fail-fast --jobs "$MAYHEM_JOBS" 2>&1)"; rc=$?
echo "$out"
out2="$(RUSTFLAGS="" cargo test --no-fail-fast --jobs "$MAYHEM_JOBS" \
        --manifest-path dolby_vision/Cargo.toml --features xml,serde 2>&1)"; rc2=$?
echo "$out2"

# libtest prints one line per test binary:
#   test result: ok. 12 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; ...
PASSED=0; FAILED=0; IGNORED=0
while read -r p f i; do
  PASSED=$(( PASSED + p )); FAILED=$(( FAILED + f )); IGNORED=$(( IGNORED + i ))
done < <(printf '%s\n%s\n' "$out" "$out2" \
  | sed -n 's/^test result:.* \([0-9][0-9]*\) passed; \([0-9][0-9]*\) failed; \([0-9][0-9]*\) ignored.*/\1 \2 \3/p')

# If we parsed no result lines, fall back to the cargo exit codes (e.g. compile error).
if [ "$(( PASSED + FAILED + IGNORED ))" -eq 0 ]; then
  echo "could not parse any 'test result:' lines; using cargo exit codes $rc/$rc2" >&2
  [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && { emit_ctrf "cargo-test" 1 0 0; exit 0; }
  emit_ctrf "cargo-test" 0 1 0; exit 1
fi

emit_ctrf "cargo-test" "$PASSED" "$FAILED" "$IGNORED"
