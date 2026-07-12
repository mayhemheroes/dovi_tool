#!/usr/bin/env bash
#
# dovi_tool/mayhem/build.sh — build quietvoid/dovi_tool's cargo-fuzz target as a sanitized
# libFuzzer binary (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS), plus the project's
# own test suite with normal flags (mayhem/test.sh only RUNS it).
#
# Targets (mayhem/fuzz/fuzz_targets/*.rs — ported from the old fork's dolby_vision/fuzz crate):
#   parse_itu_t35_dashif — parses the input as an ST 2094-10 ITU-T T.35 DASH-IF payload via
#                          dolby_vision::st2094_10::itu_t35::ST2094_10ItuT35::parse_itu_t35_dashif.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export MAYHEM_JOBS
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# DWARF < 4 debug-info contract (§6.2 item 10): force DWARF 2 for our Rust CUs.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=--dwarf-version=2}"

cd "$SRC"

# Rust's ASan runtime (librustc-nightly_rt.asan.a) is built with the nightly's bundled LLVM
# (DWARF 5) and is linked before project code; strip its debug sections so the binary's
# .debug_info stays < DWARF 4. The stripped .a is baked into the image (offline re-run safe).
ASAN_RT="$(find "$RUSTUP_HOME/toolchains" -name "librustc-nightly_rt.asan.a" 2>/dev/null | head -1)"
if [ -n "$ASAN_RT" ] && [ -f "$ASAN_RT" ]; then
    echo "Stripping debug info from Rust ASan runtime to enforce DWARF < 4: $ASAN_RT"
    objcopy --strip-debug "$ASAN_RT"
fi

# libfuzzer-sys compiles libFuzzer from C++ via the cc crate; force DWARF 3 for those CUs too.
export CFLAGS="${CFLAGS:+$CFLAGS }-gdwarf-3"
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }-gdwarf-3"

# The cargo-fuzz crate is ADDITIVE under mayhem/fuzz/ (ported from the old fork's
# dolby_vision/fuzz — upstream ships no fuzz crate; the overlay stays purely additive).
FUZZ_DIR="mayhem/fuzz"
FUZZ_TARGETS=(parse_itu_t35_dashif)
TRIPLE="x86_64-unknown-linux-gnu"

# OSS-Fuzz Rust libFuzzer+ASan flags; --cfg fuzzing matches libfuzzer-sys. Rust instrumentation
# comes via RUSTFLAGS (-Zsanitizer=address), NOT clang's $SANITIZER_FLAGS (rustc ignores those);
# the cc-built libFuzzer runtime still honors CFLAGS/CXXFLAGS above.
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address ${RUST_DEBUG_FLAGS}"

echo "=== cargo fuzz build (image-default nightly toolchain, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
done

TARGET_DIR="$(cargo metadata --no-deps --format-version 1 --manifest-path "$FUZZ_DIR/Cargo.toml" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["target_directory"])')"
echo "fuzz target_directory: $TARGET_DIR"

REL="$TARGET_DIR/$TRIPLE/release"
for t in "${FUZZ_TARGETS[@]}"; do
  bin="$REL/$t"
  if [ ! -x "$bin" ]; then
    echo "ERROR: expected fuzz binary not found at $bin" >&2
    ls -la "$REL" >&2 || true
    exit 1
  fi
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Build the project's TEST suite too — with the crates' NORMAL flags (no sanitizer RUSTFLAGS) —
# so mayhem/test.sh only RUNS it, never compiles.
echo "=== cargo test --no-run (normal flags, pre-building the test suite) ==="
RUSTFLAGS="" cargo test --no-run --jobs "$MAYHEM_JOBS"
RUSTFLAGS="" cargo test --no-run --jobs "$MAYHEM_JOBS" \
  --manifest-path dolby_vision/Cargo.toml --features xml,serde

echo "build.sh complete:"
ls -la /mayhem/parse_itu_t35_dashif 2>&1 || true
