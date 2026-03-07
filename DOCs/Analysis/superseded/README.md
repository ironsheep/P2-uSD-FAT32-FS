# Superseded Analyses

Earlier analyses whose root cause diagnoses were corrected by subsequent investigation. These documents are preserved for transparency — the symptom descriptions and card data they contain remain accurate, but their conclusions have been replaced.

The corrected analysis is [CMD13-ROOT-CAUSE-ANALYSIS.md](../CMD13-ROOT-CAUSE-ANALYSIS.md).

## Contents

| Document | Original Conclusion | Why Superseded |
|----------|-------------------|----------------|
| [CMD13-COMPATIBILITY-ANALYSIS.md](CMD13-COMPATIBILITY-ANALYSIS.md) | CMD13 failure is a card-specific defect | Driver R1 parsing error — bit 7 not checked per SD spec 7.3.2.1 |
| [USER-REPORT-ADATA-CMD13-ANALYSIS.md](USER-REPORT-ADATA-CMD13-ANALYSIS.md) | AData card blocks on CMD13 due to broken firmware | Same root cause — driver accepted pre-response bytes as R1 |

Each document contains a superseded notice at the top with a link to the corrected analysis.
