# Card Characterize — Theory of Operations

*SD_card_characterize.spin2*

## Overview

The card characterization utility reads and displays all SD card register information. It extracts every field from the CID, CSD, SCR, and OCR registers, plus the FAT32 VBR/BPB, providing a comprehensive picture of the card's identity, capabilities, and filesystem configuration.

Fields are annotated as `[USED]` (actively used by the driver) or `[INFO]` (informational only) to help users understand which data matters for driver operation.

## Card Registers

SD cards contain several read-only registers that describe the card's identity and capabilities. These are read through specific SPI commands during initialization.

### CID Register (Card Identification) - 16 bytes

The CID uniquely identifies each physical card.

| Field | Bits | Description |
|-------|------|-------------|
| MID | [127:120] | Manufacturer ID (8-bit code) |
| OID | [119:104] | OEM/Application ID (2 ASCII chars) |
| PNM | [103:64] | Product Name (5 ASCII chars) |
| PRV | [63:56] | Product Revision (BCD major.minor) |
| PSN | [55:24] | Serial Number (32-bit unique) |
| MDT | [19:8] | Manufacturing Date (year + month) |
| CRC | [7:1] | CRC7 checksum |

**Parsing**: Bytes are in big-endian order as received from the card. Multi-byte fields are reconstructed with shifts: `cid_psn := (buf[9] << 24) | (buf[10] << 16) | (buf[11] << 8) | buf[12]`.

**Driver usage**: The MID field is recorded for card identification only. It does **not** affect SPI speed — every card runs at `min(TRAN_SPEED, 25 MHz)`. (A per-manufacturer SPI cap, e.g. derating PNY/Phison cards to 20 MHz, was considered in early-2026 PNY research but evaluated and **never adopted**; see `DOCs/Research/PNY-MICROSD-SPI-ISSUES.md`.)

### CSD Register (Card Specific Data) - 16 bytes

The CSD describes the card's data transfer capabilities and capacity.

**Two versions**:
- CSD v1.0 (structure=0): SDSC cards, capacity from C_SIZE + multiplier
- CSD v2.0 (structure=1): SDHC/SDXC cards, capacity from C_SIZE directly

| Field | Bits | Driver Use | Description |
|-------|------|------------|-------------|
| CSD_STRUCTURE | [127:126] | USED | Version (0=SDSC, 1=SDHC) |
| TAAC | [119:112] | USED | Read access time-1 |
| NSAC | [111:104] | USED | Read access time-2 (clocks) |
| TRAN_SPEED | [103:96] | USED | Max transfer rate |
| CCC | [95:84] | INFO | Command class support bits |
| READ_BL_LEN | [83:80] | USED | Max read block length |
| C_SIZE | varies | USED | Device size |
| R2W_FACTOR | [28:26] | USED | Write time = read time x 2^factor |

**TRAN_SPEED decoding**: Bits [6:3] index a time value table (1.0 to 8.0), bits [2:0] index a unit table (100 kbit/s to 100 Mbit/s). The product gives maximum transfer rate. Most SDHC cards report 25 MHz (standard) or 50 MHz (high speed).

**Capacity calculation**:
- CSD v1.0: `capacity_MB = ((C_SIZE + 1) << (C_SIZE_MULT + 2)) >> (20 - READ_BL_LEN)`
- CSD v2.0: `capacity_MB = (C_SIZE + 1) / 2` (each C_SIZE unit = 512KB)

**Timeout calculation**:
- SDSC: Derived from TAAC/NSAC/R2W_FACTOR lookup tables
- SDHC/SDXC: Fixed at 100ms read, 250ms write (per specification)

### OCR Register (Operating Conditions) - 4 bytes

The OCR reports the card's voltage support and capacity type.

| Field | Bit | Driver Use | Description |
|-------|-----|------------|-------------|
| Power Up | [31] | INFO | 0=busy, 1=ready |
| CCS | [30] | USED | Card Capacity Status (0=SDSC, 1=SDHC) |
| UHS-II | [29] | INFO | UHS-II card indicator |
| S18A | [24] | INFO | 1.8V switching accepted |
| Voltage | [23:15] | INFO | Supported voltage ranges (2.7V-3.6V) |

**Driver usage**: The CCS bit is critical -- it determines whether the card uses byte addressing (SDSC: sector << 9) or block addressing (SDHC/SDXC: sector number directly).

### SCR Register (SD Configuration) - 8 bytes

The SCR describes SD specification support and features.

| Field | Bits | Driver Use | Description |
|-------|------|------------|-------------|
| SD_SPEC | [59:56] | USED | SD specification version |
| SD_SPEC3 | [47] | INFO | SD 3.0 support |
| SD_BUS_WIDTHS | [51:48] | INFO | Supported bus widths |
| SD_SECURITY | [54:52] | INFO | Security support level |
| CMD_SUPPORT | [33:32] | INFO | CMD20/CMD23 support |

**Driver usage**: SD_SPEC determines if CMD6 (High Speed mode switching) is available (requires SD 2.0+).

## Manufacturer Lookup Table

The utility includes a lookup table mapping manufacturer IDs to names:

```
$01 = Panasonic    $02 = Toshiba/Kioxia   $03 = SanDisk
$1B = Samsung      $41 = Kingston         $74 = Transcend
$AD = Longsys/Lexar  $FE = PNY OEM       ...and more
```

The table uses a compact format: `BYTE id, "Name", 0` with `$FF` as end marker. The `lookupManufacturer()` method walks the table linearly.

## VBR/BPB Parsing

After reading card registers, the utility reads the FAT32 filesystem information:

1. Reads MBR sector 0 to find partition type and start
2. If FAT32 ($0B or $0C), reads VBR at the partition start sector
3. Extracts and displays: OEM name, volume label, volume serial, bytes/sector, sectors/cluster, reserved sectors, FAT count, sectors/FAT, root cluster, total sectors, data region start, total clusters

Non-FAT32 cards (exFAT, NTFS, etc.) skip VBR parsing with a note.

## Unique Card ID Generation

The utility generates a unique identifier string from CID fields:

```
Format: Manufacturer_ProductName_Revision_SerialNumber_ManufacturingDate
Example: SanDisk_SD64G_8.0_12345678_202306
```

This ID can be used to track individual cards in a database (see ../cards/CARD-CATALOG.md).

## Output Structure

The report is organized into clearly labeled sections:
1. Card register read status (OK/FAILED for each)
2. CID register fields with manufacturer lookup
3. CSD register fields with timing and capacity calculations
4. OCR register fields with voltage window
5. SCR register fields with SD version determination
6. Raw register hex dumps for verification
7. FAT32 filesystem information
8. Unique card ID
9. Driver usage summary (which fields matter and why)
