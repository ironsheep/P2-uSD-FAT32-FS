# Analysis

Technical deep-dives into driver design decisions, predecessor driver analysis, and card compatibility investigations.

## Contents

| Document | Description |
|----------|-------------|
| [CMD12-SPCE-ANALYSIS.md](CMD12-SPCE-ANALYSIS.md) | CMD12 framing anomaly on SP Elite card — read-ahead pipeline vs STOP_TRANSMISSION |
| [CMD13-ROOT-CAUSE-ANALYSIS.md](CMD13-ROOT-CAUSE-ANALYSIS.md) | R1 response parsing fix — the actual root cause of CMD13 failures across all cards |
| [ERROR-REPORTING-AUDIT-2026-07-31.md](ERROR-REPORTING-AUDIT-2026-07-31.md) | Public API error flow audit — 19 findings on dropped, misreported, and unreachable errors |
| [AUDIT-SEVERITY-ANALYSIS.md](AUDIT-SEVERITY-ANALYSIS.md) | Audit test severity classification and downgrade rationale |
| [REGRESSION-TEST-COVERAGE-ANALYSIS.md](REGRESSION-TEST-COVERAGE-ANALYSIS.md) | Gap analysis of regression test coverage with tiered strengthening plan |
| [DESIGN-EXPLORATION-FILE-HANDLES.md](DESIGN-EXPLORATION-FILE-HANDLES.md) | Design exploration for multi-file handle support |
| [MULTI-COG-INTERFACE-PATTERN.md](MULTI-COG-INTERFACE-PATTERN.md) | Multi-cog interface pattern for P2 drivers |
| [OB4269-FAT32-COMPLIANCE-ANALYSIS.md](OB4269-FAT32-COMPLIANCE-ANALYSIS.md) | OB4269 FAT32 driver specification compliance analysis |
| [OB4269-PERFORMANCE-STUDY.md](OB4269-PERFORMANCE-STUDY.md) | OB4269 FAT32 driver performance study |
| [SPI-BUS-STATE-ANALYSIS.md](SPI-BUS-STATE-ANALYSIS.md) | SPI bus state analysis for multi-device sharing |
| [STREAMER-TIMING-ANALYSIS.md](STREAMER-TIMING-ANALYSIS.md) | Streamer/FIFO timing analysis |

## Superseded

The [superseded/](superseded/) directory contains earlier analyses whose root cause diagnoses were corrected by subsequent investigation. They are preserved for transparency.
