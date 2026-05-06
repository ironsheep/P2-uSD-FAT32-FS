# Diagnostic Tests

Internal-only test programs for characterizing SD card behavior and debugging driver issues. Not included in release packages.

> **Note:** This directory is a candidate for removal. Most of these utilities served a specific debugging purpose and have limited ongoing value beyond serving as examples of how to probe card behavior.

| File | Purpose |
|------|---------|
| `SD_card_info_tests.spin2` | Card identification and register dump |
| `SD_diag_cmd13_capture.spin2` | CMD13 framing analysis (pre-capture + post-capture byte streams) |
| `SD_diag_fsck_window_test.spin2` | FSCK windowed bitmap validation for large cards |
| `SD_freq_sweep_tests.spin2` | SPI frequency sweep to find card limits |
| `SD_spi_limit_test.spin2` | SPI timing margin testing |
| `SD_stack_depth_test.spin2` | Worker cog stack high-water mark measurement |
| `SD_speed_characterize.spin2` | Maximum SPI speed tester (moved from src/UTILS/) |
| `SD_frequency_characterize.spin2` | Sysclk frequency tester (moved from src/UTILS/) |
| `SD_macca_diagnostic.spin2` | (v1) Marginal-card diagnostic with decision-tree branching gated on `sd.mount()`. Superseded by v2/v3; kept as historical artifact. |
| `SD_macca_diagnostic_v2.spin2` | (v2) Mount-free read/write channel certification. Uses `initCardOnly()` so cards that fail to mount can still be diagnosed. 6×6 sysclk × SPI matrix with write-time instrumentation and confirm-via-read on busy timeout. |
| `SD_macca_diagnostic_v3.spin2` | (v3) v2 plus conditional sample-mode and align_delay retries on failing cells, sustained-load (32-write erase-block stress) and multi-block (CMD25/CMD18) phases. Insurance-grade single-session characterization. |
