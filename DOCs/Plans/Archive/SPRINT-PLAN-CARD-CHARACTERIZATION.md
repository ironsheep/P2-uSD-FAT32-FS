# Sprint Plan: SD Card Characterization Tool

**Sprint Goal**: Create a non-destructive diagnostic tool to uniquely identify and characterize SD cards for compatibility testing

**Status**: PLANNING

---

## Background

### The Need

We need to validate the SD driver works across multiple card brands/models. To do this systematically, we need:
1. A way to uniquely identify each card (manufacturer, model, serial, date)
2. A way to characterize card capabilities (capacity, speed, features)
3. A way to inspect the existing filesystem formatting (sector size, cluster size, etc.)
4. A catalog of tested cards with their characteristics

### Deliverables

1. **SD_card_characterize.spin2** - Standalone diagnostic that dumps card info via debug
2. **CARD-CATALOG.md** - Documentation template for recording tested cards
3. Driver enhancements to expose card identification registers

---

## Card Identification Data Available

### Hardware Identification (via SPI Commands)

| Register | Command | Size | Information |
|----------|---------|------|-------------|
| **CID** | CMD10 | 128 bits | Manufacturer ID, Product Name, Serial #, Date, Revision |
| **CSD** | CMD9 | 128 bits | Capacity, Speed Class, Block Sizes, Version |
| **OCR** | CMD58 | 32 bits | Capacity Type (SDSC/SDHC/SDXC), Voltage Range |
| **SCR** | ACMD51 | 64 bits | SD Spec Version, Bus Widths, Security Features |

### CID Register Fields (Primary Identification)

| Field | Bits | Description |
|-------|------|-------------|
| MID | [127:120] | Manufacturer ID (8-bit code) |
| OID | [119:104] | OEM/Application ID (2-char ASCII) |
| PNM | [103:64] | Product Name (5-char ASCII) |
| PRV | [63:56] | Product Revision (BCD: n.m format) |
| PSN | [55:24] | Product Serial Number (32-bit unique) |
| MDT | [19:8] | Manufacturing Date (Year[19:12]+2000, Month[11:8]) |

### Known Manufacturer IDs

| MID | Manufacturer |
|-----|--------------|
| 0x1B | Panasonic |
| 0x4D | SanDisk |
| 0x74 | Transcend |
| 0x9E | Kingston |
| 0x2C | Micron |
| 0x55 | Samsung |
| 0x82 | Kingmax |
| 0xFE | Patriot |

### Filesystem Formatting Information (from VBR/BPB)

| Field | Offset | Description |
|-------|--------|-------------|
| Bytes per sector | 0x0B | Usually 512 |
| Sectors per cluster | 0x0D | 1, 2, 4, 8, 16, 32, 64, or 128 |
| Reserved sectors | 0x0E | Sectors before first FAT |
| Number of FATs | 0x10 | Usually 2 |
| Total sectors | 0x20 | 32-bit count |
| Sectors per FAT | 0x24 | FAT32 field |
| Root cluster | 0x2C | First cluster of root directory |
| FSInfo sector | 0x30 | Usually 1 |
| Backup boot sector | 0x32 | Usually 6 |
| Volume serial | 0x43 | 32-bit unique ID (often timestamp) |
| Volume label | 0x47 | 11-char label |
| FS type string | 0x52 | "FAT32   " |
| OEM name | 0x03 | 8-char string (e.g., "MSDOS5.0", "mkfs.fat") |

---

## Architectural Decision: Minimal Driver, Smart Diagnostic

### The Problem

Adding full card identification to the driver would bloat it with code not needed for file I/O:

| Feature | Code Size | Needed for File I/O? |
|---------|-----------|---------------------|
| Manufacturer name lookup table | ~100+ bytes | NO |
| Date/revision formatting | ~50 bytes | NO |
| Multiple accessor methods | ~200+ bytes | NO |
| String builders | ~100 bytes | NO |
| **Total bloat** | **~450+ bytes** | |

### The Solution: Raw Register Access

**Driver provides**: Minimal methods to read/expose raw register data
**Diagnostic tool provides**: All parsing, interpretation, and formatting

```
┌─────────────────────────────────────────────────────────────────┐
│                    SD_card_driver.spin2                         │
│                    (MINIMAL ADDITIONS)                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Existing (no changes needed):                                  │
│    - CSD already read during mount (for capacity)               │
│    - OCR already read during init (for card type)               │
│    - VBR/BPB already parsed (for filesystem)                    │
│                                                                 │
│  New methods (~80 lines total):                                 │
│    readCIDRaw(p_buf)    → copies 16 bytes of raw CID            │
│    readCSDRaw(p_buf)    → copies 16 bytes of raw CSD            │
│    readSCRRaw(p_buf)    → copies 8 bytes of raw SCR             │
│    getOCR()             → returns 32-bit OCR value              │
│    getVBRSector(p_buf)  → copies 512-byte VBR for inspection    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Raw bytes
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                SD_card_characterize.spin2                       │
│                (ALL INTERPRETATION HERE)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CID Parsing:                                                   │
│    - Extract MID, OID, PNM, PRV, PSN, MDT from raw bytes        │
│    - Manufacturer name lookup table                             │
│    - Date formatting (YYYY-MM)                                  │
│    - Revision formatting (n.m)                                  │
│                                                                 │
│  CSD Parsing:                                                   │
│    - Version detection, capacity calculation                    │
│    - Speed class decoding, block size extraction                │
│                                                                 │
│  SCR Parsing:                                                   │
│    - SD spec version decoding                                   │
│    - Bus width support, security features                       │
│                                                                 │
│  VBR/BPB Parsing:                                               │
│    - OEM name, volume label, serial                             │
│    - Cluster size, FAT parameters                               │
│    - Partition table inspection                                 │
│                                                                 │
│  Output Generation:                                             │
│    - Formatted debug output                                     │
│    - Unique card ID string                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Benefits

1. **Driver stays lean** - Only ~80 lines added for raw access
2. **No lookup tables in driver** - Manufacturer names stay in diagnostic
3. **Diagnostic is disposable** - Not needed for production use
4. **Easy to extend** - Add more parsing without touching driver
5. **Clear separation** - Driver does I/O, diagnostic does interpretation

---

## Current Driver Status

### Already Implemented

- [x] CMD9 (SEND_CSD) - Read during mount, stored internally
- [x] CMD58 (READ_OCR) - Read during init, stored internally
- [x] VBR reading - `do_mount()` reads and parses BPB
- [x] Volume label - `volumeLabel()` method

### Needs Implementation (Minimal)

- [ ] `readCIDRaw(p_buf)` - Read 16-byte CID via CMD10
- [ ] `readCSDRaw(p_buf)` - Expose existing CSD data
- [ ] `readSCRRaw(p_buf)` - Read 8-byte SCR via ACMD51
- [ ] `getOCR()` - Expose existing OCR value
- [ ] `getVBRSector(p_buf)` - Expose VBR for inspection

**Estimated driver additions**: ~80 lines, ~200 bytes compiled

---

## Implementation Phases

### Phase 1: Add Raw Register Access to Driver

**Goal**: Minimal driver methods to expose raw register data

**Driver Changes** (`SD_card_driver.spin2`):

```spin2
'' ──────────────────────────────────────────────────────────────
'' LOW-LEVEL CARD INFORMATION (for diagnostics)
'' ──────────────────────────────────────────────────────────────

PUB readCIDRaw(p_buf) : result
  '' Read Card Identification register (16 bytes) into buffer.
  '' Returns SUCCESS or error code.
  return send_command(CMD_READ_CID, p_buf, 0, 0, 0)

PUB readCSDRaw(p_buf) : result
  '' Copy cached CSD register (16 bytes) into buffer.
  '' Card must be mounted. Returns SUCCESS or error code.
  if not (flags & F_MOUNTED)
    return set_error(E_NOT_MOUNTED)
  longmove(p_buf, @csd_data, 4)  ' Copy 16 bytes (4 longs)
  return SUCCESS

PUB readSCRRaw(p_buf) : result
  '' Read SD Configuration register (8 bytes) into buffer.
  '' Returns SUCCESS or error code.
  return send_command(CMD_READ_SCR, p_buf, 0, 0, 0)

PUB getOCR() : ocr
  '' Return cached 32-bit OCR register value.
  return ocr_value

PUB getVBRSector(p_buf) : result
  '' Read Volume Boot Record sector (512 bytes) into buffer.
  '' Card must be mounted. Returns SUCCESS or error code.
  if not (flags & F_MOUNTED)
    return set_error(E_NOT_MOUNTED)
  return send_command(CMD_READ, vbr_sec, p_buf, 512, 0)
```

**Worker Cog Additions**:
- `CMD_READ_CID` - Calls existing `readCID()` pattern (identical to `readCSD()`)
- `CMD_READ_SCR` - New: CMD55 + ACMD51 sequence

**Implementation Notes**:
- CID read is identical to existing CSD read (~20 lines)
- SCR read requires CMD55 prefix (~30 lines)
- Store OCR during init (already done, just expose)
- Store CSD during mount (already done, just expose)

### Phase 2: Create Characterization Diagnostic

**Goal**: Standalone diagnostic tool with all parsing/interpretation logic

**File**: `tools/SD_card_characterize.spin2`

**Diagnostic Responsibilities**:

1. **CID Parsing** (16 bytes → readable fields):
   ```spin2
   PRI parseCID(p_cid) | mid, oid, pnm, prv, psn, mdt
     mid := BYTE[p_cid][0]                          ' Manufacturer ID
     oid := (BYTE[p_cid][1] << 8) | BYTE[p_cid][2]  ' OEM ID (2 ASCII chars)
     ' ... extract PNM (5 chars), PRV (BCD), PSN (32-bit), MDT (12-bit)
   ```

2. **Manufacturer Lookup Table** (in diagnostic, NOT driver):
   ```spin2
   DAT
     mfr_table   BYTE  $1B, "Panasonic", 0
                 BYTE  $4D, "SanDisk", 0
                 BYTE  $74, "Transcend", 0
                 BYTE  $9E, "Kingston", 0
                 ' ... etc
   ```

3. **CSD Parsing** (capacity, speed, features)
4. **SCR Parsing** (SD version, bus widths)
5. **VBR/BPB Parsing** (filesystem formatting details)
6. **Output Generation** (formatted debug report)

**Output Format**:
```
==============================================
  SD Card Characterization Report
==============================================

--- CARD HARDWARE IDENTIFICATION ---
  Manufacturer ID:    0x4D (SanDisk)
  OEM/Application:    "SD"
  Product Name:       "SU16G"
  Product Revision:   8.0
  Serial Number:      0x12345678
  Manufacturing Date: 2023-05 (May 2023)

--- CARD CAPABILITIES ---
  Card Type:          SDHC (High Capacity)
  Capacity:           15,931,539,456 bytes (14.84 GB)
  Total Sectors:      31,116,288
  SD Spec Version:    3.0
  Max Transfer Speed: 50 MHz (High Speed)
  Supported Bus:      1-bit, 4-bit

--- RAW REGISTERS ---
  CID: 4D 53 44 53 55 31 36 47 80 12 34 56 78 01 59 XX
  CSD: 40 0E 00 32 5B 59 00 00 3A 7F 80 03 XX XX XX XX
  OCR: 0xC0FF8000
  SCR: XX XX XX XX XX XX XX XX

--- FILESYSTEM FORMATTING ---
  OEM Name:           "mkfs.fat"
  Volume Label:       "TEST-CARD  "
  Volume Serial:      0xABCD1234
  FS Type:            "FAT32   "
  Bytes/Sector:       512
  Sectors/Cluster:    64 (32 KB clusters)
  Reserved Sectors:   32
  Number of FATs:     2
  Sectors per FAT:    3,808
  Root Cluster:       2
  Total Clusters:     472,896
  Data Region Start:  Sector 7,648
  Free Space:         15,123,456,000 bytes

--- PARTITION TABLE ---
  Type: MBR
  Partition 1: FAT32 LBA (0x0C)
    Start: Sector 2048
    Size:  31,114,240 sectors

==============================================
  Card ID: SanDisk_SU16G_8.0_12345678_202305
==============================================
END_CHARACTERIZATION
```

**Unique Card ID Format**:
`{Manufacturer}_{ProductName}_{Revision}_{Serial}_{YYYYMM}`

Example: `SanDisk_SU16G_8.0_12345678_202305`

### Phase 3: Create Card Catalog Template

**Goal**: Documentation for recording tested cards

**File**: `DOCs/CARD-CATALOG.md`

**Template per card**:
```markdown
## Card: SanDisk Ultra 16GB SDHC

**Unique ID**: `SanDisk_SU16G_8.0_12345678_202305`

### Identification
| Field | Value |
|-------|-------|
| Manufacturer | SanDisk (0x4D) |
| Product Name | SU16G |
| Revision | 8.0 |
| Serial | 0x12345678 |
| Mfg Date | May 2023 |

### Capabilities
| Field | Value |
|-------|-------|
| Type | SDHC |
| Capacity | 14.84 GB |
| Speed Class | Class 10 |
| SD Version | 3.0 |

### Test Results
| Test | Status | Notes |
|------|--------|-------|
| Mount | PASS | |
| Read | PASS | |
| Write | PASS | |
| Seek | PASS | |
| Format | PASS | |

### Notes
- Purchased from Amazon, 2023
- Works reliably at both 25MHz and 50MHz
```

---

## Estimated Effort

| Phase | Effort | Complexity | Notes |
|-------|--------|------------|-------|
| Phase 1: Raw Register Access | ~2 hours | Low | ~80 lines driver changes |
| Phase 2: Characterization Diagnostic | ~4 hours | Medium | All parsing/formatting here |
| Phase 3: Card Catalog Template | ~30 min | Low | Documentation only |
| **Total** | **~6.5 hours** | | |

**Comparison with "Full Driver Integration" approach:**

| Approach | Driver Code | Driver Size | Flexibility |
|----------|-------------|-------------|-------------|
| Raw Access (chosen) | ~80 lines | +200 bytes | High - diagnostic handles all |
| Full Integration | ~300+ lines | +500+ bytes | Low - driver locked in |

---

## Success Criteria

1. **Minimal driver impact** - Driver adds only raw access methods (~80 lines)
2. **No driver bloat** - Lookup tables and formatting stay in diagnostic tool
3. **Diagnostic runs non-destructively** - No writes to card
4. **Unique identification** - Each card produces unique ID string
5. **Complete characterization** - All register fields decoded
6. **Filesystem details** - Formatting parameters extracted
7. **Catalog ready** - Can record and compare 10-12 cards

---

## Open Questions

1. Should we read the MBR partition table to show partition info?
2. Should we detect filesystem type (FAT16 vs FAT32) for older cards?
3. Should the diagnostic save output to a file on the card? (Would make it non-read-only)
4. What other cards do we have available for testing?

---

*Document created: 2026-01-18*
*Status: PLANNING - Ready for implementation*
