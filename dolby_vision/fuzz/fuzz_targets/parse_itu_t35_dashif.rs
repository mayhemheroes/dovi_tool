#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let _ = dolby_vision::st2094_10::itu_t35::ST2094_10ItuT35::parse_itu_t35_dashif(data);
});
