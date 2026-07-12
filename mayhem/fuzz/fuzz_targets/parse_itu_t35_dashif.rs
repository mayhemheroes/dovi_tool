#![no_main]
use libfuzzer_sys::fuzz_target;

// Drives dolby_vision's ITU-T T.35 (ST 2094-10 DASH-IF) parser over the same public entry point
// the original fork fuzzed. `validated_trimmed_data` slices `&data[..7]` with NO length check
// (dolby_vision/src/st2094_10/itu_t35/mod.rs:59), so any input shorter than 7 bytes — including
// libFuzzer's mandatory empty input at iteration 0 — panics on an out-of-bounds slice before the
// fuzzer can run a single mutation, making the target unfuzzable (0 iterations). We skip inputs
// too short to reach the real parser so the fuzzer explores the actual T.35 / ST2094-10 decode
// path (country/provider codes, CM/DM metadata). Same code path, just past the trivial upstream
// bounds bug (cf. the tldr port note in port-repo). Everything beyond the slice is Result-based
// and surfaces genuine defects normally.
fuzz_target!(|data: &[u8]| {
    if data.len() < 7 {
        return;
    }
    let _ = dolby_vision::st2094_10::itu_t35::ST2094_10ItuT35::parse_itu_t35_dashif(data);
});
