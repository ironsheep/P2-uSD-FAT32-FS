# Card Labels — Master

The single source of truth for **what is physically printed on a card**. Label text
is read under a microscope and hand-entered; it is entered **here, once**, and every
other document refers to this file rather than repeating the text.

Card records name their label by ID. `CARD-CATALOG.md` and `CARD-REFERENCE.md`
resolve the ID to text; they do not carry their own copies. `tools/check_card_labels.sh`
verifies that every reference resolves and that no entry is orphaned.

## Why the key is assigned rather than read from the card

**No field readable from the card can identify its label.** The relationship between
printed label and silicon is many-to-many in both directions, in this drawer:

- One silicon key, two labels — `Phison_SD16G_3.0` is both a PNY card and a Sony card
- One brand, four MIDs — Gigastone-printed labels sit on `$00`, `$12`, `$74` and `$9F`

And a serial number keys one *physical card*, not the *product* whose label is
printed identically on every unit of that SKU — so keying on it would mean
re-transcribing one label once per card in a matched set.

So the ID is **assigned by us** when a label is first read.

## Rules

**The `Printed` field is a literal transcription, in the order it appears on the
card.** Do not normalise the order, expand abbreviations, correct the
manufacturer's capitalisation, or tidy the punctuation. The field's whole value is
that someone holding the card can compare it left-to-right; reorder it and the
check becomes a judgement, and a reordered transcription is indistinguishable from
a wrong one. The order genuinely varies between products — some cards print the
capacity first, some last, some not at all.

**The `Printed` field contains nothing but the transcription.** Analysis,
counterfeit findings, twin relationships, our own card nicknames and internal
numbering all go in `Notes`. This split exists because the two were previously
entangled in one field, after which "what is literally printed on this card" was no
longer answerable from the field meant to answer it.

**Line breaks on the physical card are recorded as ` / `.** A microSD label is laid
out in lines, and flattening them is the main reason two readings of one card
disagree. The 26 entries below were captured before this convention and are
flattened; their line structure is unknown, not one line.

**Capacity in the ID is the PRINTED capacity**, which is not always the reported
capacity.

**ID scheme:** `<brand>-<distinguishing product words>-<printed capacity>`, lower
case, hyphenated. Where a later product is indistinguishable under that scheme,
append a disambiguator when the second one is found.

---

## Labels

### amazon-basics-xc-64gb
- **Printed:** Amazon Basics microSD XC I (10) U3 A2 V30
- **Notes:** —

### cloudisk-microsd-2gb-class4
- **Printed:** microSD 2GB Class 4 — "Cloudisk"
- **Notes:** Confirmed counterfeit; silicon PNM `"asdfg"`; silicon twin of the Lerdisk 1 GB. Printed text extracted from a field that had mixed transcription with analysis, and has not been re-read under the microscope since.

### gigastone-camera-plus-64gb
- **Printed:** Gigastone "Camera Plus" microSD XC I, A1 V30 U3 64GB
- **Notes:** —

### gigastone-high-endurance-8gb
- **Printed:** Gigastone 10x High Endurance 8GB MLC microSD HC I U1
- **Notes:** —

### gigastone-high-endurance-16gb
- **Printed:** Gigastone 10x High Endurance 16GB MLC microSD HC I U3 V30 4K
- **Notes:** —

### gigastone-microsd-hc-a1-u1-32gb
- **Printed:** Gigastone 32GB microSD HC I A1 U1 (10)
- **Notes:** Referenced by two records — the card record and its 2026-05-24 recertification.

### kingston-microsd-hc-8gb
- **Printed:** Kingston 8GB microSD HC I ui (10) "Taiwan" F(c)o
- **Notes:** The trailing `F(c)o` is printed on the card and is deliberately preserved; it was lost in one copy previously. Card is dead (no init in either socket, runs hot).

### lerdisk-microsd-1gb-class4
- **Printed:** microSD 1GB Class 4 — "Lerdisk"
- **Notes:** Suspected counterfeit; silicon PNM `"asdfg"`; silicon twin of the Cloudisk 2 GB. Printed text extracted from a field that had mixed transcription with analysis, and has not been re-read under the microscope since.

### lexar-a1-v30-u3-64gb
- **Printed:** Lexar A1 V30 U3 64GB microSD XC
- **Notes:** Red card body. "Red card" is our disambiguator against the Lexar PLAY 128GB, not printed text.

### lexar-play-a2-128gb
- **Printed:** Lexar PLAY A2 128GB microSD XC
- **Notes:** Blue card body. "Blue card" is our disambiguator against the Lexar A1 64GB, not printed text. Fastest card measured to date.

### pny-microsd-hc-16gb
- **Printed:** PNY 16GB microSD HC I
- **Notes:** Same silicon key as the Sony SR-16D 16GB (`Phison_SD16G_3.0`) — a worked example of one silicon carrying two labels.

### samsung-evo-select-128gb
- **Printed:** Samsung EVO Select microSD XC I U3
- **Notes:** Printed text carries no capacity. Serial discrepancy open between the catalog row and the card record; any sweep run settles it.

### samsung-pro-endurance-128gb
- **Printed:** Samsung Pro Endurance microSD XC I U3 V30
- **Notes:** Printed text carries no capacity.

### sandisk-extreme-64gb
- **Printed:** SanDisk Extreme 64GB U3 A2 microSD XC I V30
- **Notes:** —

### sandisk-extreme-pro-64gb
- **Printed:** SanDisk Extreme PRO 64GB microSD XC I V30 U3
- **Notes:** —

### sandisk-extreme-pro-128gb
- **Printed:** SanDisk Extreme PRO 128GB microSD XC I V30 U3 A1
- **Notes:** —

### sandisk-industrial-16gb
- **Printed:** SanDisk Industrial microSD HC I, U1 C10, 16GB
- **Notes:** Capacity printed last.

### sandisk-industrial-su-1gb
- **Printed:** NOT TRANSCRIBED
- **Notes:** The previous field read "microSD 1GB — SanDisk Industrial SU series", but "SanDisk Industrial SU series" appears to be inferred from the CID product name `SU01G` rather than read off the card. **This card is not in our possession** — it is a customer's card in Italy — so its printed label can never be verified. Its register and performance data remain historical and valid; only the label transcription is unavailable.

### sandisk-max-endurance-32gb
- **Printed:** SanDisk MAX ENDURANCE microSD HC I U3 V30 (10)
- **Notes:** Printed text carries no capacity.

### sandisk-microsd-hc-8gb-taiwan
- **Printed:** SanDisk 8GB (4) microSD HC, Made in Taiwan
- **Notes:** —

### sandisk-nintendo-switch-128gb
- **Printed:** SanDisk 128GB Nintendo Switch microSD XC I
- **Notes:** Capacity printed second.

### sony-sr-16d-16gb
- **Printed:** Sony 16GB microSD HC (10) i U3 SR-16D, Made in Taiwan
- **Notes:** Same silicon key as the PNY 16GB (`Phison_SD16G_3.0`) — a worked example of one silicon carrying two labels.

### sp-elite-64gb
- **Printed:** SP Elite microSD XC UHS-I U1 (10)
- **Notes:** Printed text carries no capacity. Silicon MID `$9F` is shared with a Gigastone-branded card.

### unbranded-chinese-8gb-card1
- **Printed:** microSD HC 8GB (4)
- **Notes:** No brand printed. Chinese text present on the card, not transcribed. Our internal designation is "Card #1"; that is not printed.

### unbranded-chinese-8gb-card2
- **Printed:** NOT TRANSCRIBED
- **Notes:** The previous field read "Unlabeled 8GB microSD (Chinese text/no brand) - Card #2", which is a description of the card rather than a transcription of it — no printed text was ever captured. The card carries Chinese text and no brand. Our internal designation is "Card #2"; that is not printed. **Re-readable: the card is in the drawer.**

### wd-purple-qd101-64gb
- **Printed:** Western Digital WD Purple QD101 microSD XC I U1 (10) 64GB
- **Notes:** Capacity printed last.

---

## Entries needing a microscope

Two entries above carry `NOT TRANSCRIBED` rather than a guess:

| Label ID | Why | Recoverable? |
|---|---|---|
| `unbranded-chinese-8gb-card2` | Field held a description, never a transcription | **Yes** — card is in the drawer |
| `sandisk-industrial-su-1gb` | Text appears inferred from the CID product name | **No** — card is a customer's, in Italy |

---

*Master created: 2026-08-19, synthesised from the 26 card records' `Label:` fields.*
*Labels: 26. Analysis was deliberately not carried across; only printed text was.*
