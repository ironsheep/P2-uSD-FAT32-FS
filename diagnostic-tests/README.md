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
