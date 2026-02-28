# Card Info Display - Implementation Plan

## Overview

The `card` (alias `cid`) command displays a compact two-line summary of the inserted SD card's identity, capabilities, and filesystem type. It works whether the card is mounted or unmounted.

---

## Output Format

### Line 1 - Identity & Filesystem

```
<Manufacturer> <ProductName> <CardType> <CapacityGB>GB [<Filesystem>] <SDSpec> rev<Major>.<Minor> SN:<Serial> <Year>/<Month>
```

**Example:**
```
SanDisk SU16G SDHC 15GB [FAT32] SD 3.x rev1.0 SN:12345678 2024/03
```

### Line 2 - Speed & Capabilities

```
Class <N>, U<N>, V<N>, SPI <Freq> MHz  [<optional notes>]
```

**Example:**
```
Class 10, U1, V10, SPI 25.0 MHz  [formatted by P2FMTER]
```

Notes field is optional; preceded by two spaces before the bracket. Shows VBR OEM name if informational (e.g., our formatter stamps "P2FMTER").

---

## Data Sources and Field Calculations

### Line 1 Fields

| Field | Source | Register/API | Calculation |
|-------|--------|-------------|-------------|
| Manufacturer | CID byte[0] | `sd.readCIDRaw(@cid)` | MID byte → `lookupMID(mid)` table lookup in `midTable` DAT |
| Product Name | CID bytes[3:7] | `sd.readCIDRaw(@cid)` | 5 ASCII bytes, copy with `bytemove(@pnm, @cid.byte[3], 5)`, null-terminate with `BYTE[@pnm + 5] := 0` |
| Card Type | OCR bit 30 + size | `sd.getOCR()` + `sd.cardSizeSectors()` | CCS=0→SDSC, CCS=1 and <=32GB→SDHC, CCS=1 and >32GB→SDXC. Via `getCardType(ocr, sizeMB)` |
| Capacity | CSD / card size | `sd.cardSizeSectors()` | `sectors / 2048` → MB, `/ 1024` → GB (or keep MB) |
| Filesystem | MBR partition type | `sd.readSectorRaw(0, @buf2)` | Partition type byte at offset `$1C2`. Via `detectFilesystem()` |
| SD Spec Version | SCR register | `sd.readSCRRaw(@scr)` | Decode SD_SPEC, SD_SPEC3, SD_SPEC4, SD_SPECX fields. Via `getSDSpecVersion(@scr)` |
| Revision | CID byte[8] | `sd.readCIDRaw(@cid)` | PRV = byte[8], major = `PRV >> 4`, minor = `PRV & $0F` |
| Serial Number | CID bytes[9:12] | `sd.readCIDRaw(@cid)` | PSN = 32-bit big-endian: `(byte[9] << 24) | (byte[10] << 16) | (byte[11] << 8) | byte[12]` |
| Mfg Date | CID bytes[13:14] | `sd.readCIDRaw(@cid)` | MDT: year = `(byte[13] & $0F) << 4 + (byte[14] >> 4)` + 2000, month = `byte[14] & $0F` |

### Line 2 Fields

| Field | Source | Register/API | Calculation |
|-------|--------|-------------|-------------|
| Speed Class | SD Status byte[8] | `sd.readSDStatusRaw(@sdst)` | SPEED_CLASS: $00=0, $01=2, $02=4, $03=6, $04=10. Via `decodeSpeedClass()` |
| UHS Speed Grade | SD Status byte[14] | `sd.readSDStatusRaw(@sdst)` | Upper nibble of byte[14]: 0=none, 1=U1, 3=U3 |
| Video Speed Class | SD Status byte[15] | `sd.readSDStatusRaw(@sdst)` | Byte[15]: 0=none, 6=V6, 10=V10, 30=V30, 60=V60, 90=V90 |
| SPI Frequency | Driver state | `sd.getSPIFrequency()` | Returns Hz, display as `MHz` (divide by 1_000_000) with one decimal |
| Optional notes | VBR OEM name | Read VBR sector, bytes $03-$0A | 8 ASCII chars; show if informational (e.g., "P2FMTER") |

---

## Register Details

### CID Register (16 bytes, read via CMD10)

```
Byte  Bits    Field               Our Variable
 0    [127:120] MID              mid := cid.byte[0]
 1-2  [119:104] OID              oid[0..1] := cid.byte[1..2]
 3-7  [103:64]  PNM (product)    bytemove(@pnm, @cid.byte[3], 5)
 8    [63:56]   PRV (revision)   prv := cid.byte[8]  (major = >>4, minor = &$0F)
 9-12 [55:24]   PSN (serial)     32-bit big-endian from cid.byte[9..12]
13-14 [23:8]    MDT (mfg date)   year+month packed
15    [7:0]     CRC (ignored)
```

### SCR Register (8 bytes, read via ACMD51)

```
Byte  Bits    Field
 0    [63:56]  SCR_STRUCTURE[7:4], SD_SPEC[3:0]
 1    [55:48]  DATA_STAT_AFTER_ERASE[7], SD_SECURITY[6:4], SD_BUS_WIDTHS[3:0]
 2    [47:40]  SD_SPEC3[7], EX_SECURITY[6:3], SD_SPEC4[2], SD_SPECX[1:0] (upper)
 3    [39:32]  SD_SPECX[7:6] (lower 2 bits), reserved
```

Version decode chain:
- `SD_SPEC < 2` → SD 1.x
- `SD_SPEC3 == 0` → SD 2.0
- `SD_SPEC4 == 0` → SD 3.x
- Then use `SD_SPECX`: 0→4.x, 1→5.x, 2→6.x, 3→7.x, 4→8.x, 5→9.x

### OCR Register (32 bits, from CMD58 during init)

```
Bit 30: CCS (Card Capacity Status) - 0=SDSC, 1=SDHC/SDXC
```

### SD Status Register (64 bytes, read via ACMD13) — NOT YET WORKING

```
Byte  Bits    Field
 8    [311:304] SPEED_CLASS       $00=0, $01=2, $02=4, $03=6, $04=10
14    [263:260] UHS_SPEED_GRADE   upper nibble: 0=none, 1=U1, 3=U3
15    [255:248] VIDEO_SPEED_CLASS  0=none, 6=V6, 10=V10, 30=V30, 60=V60, 90=V90
```

ACMD13 requires CMD55 prefix, then CMD13. Response is 64 bytes read like a data block.

### MBR (Sector 0) — Filesystem Detection

```
Offset  Field
$1BE    Partition entry 1 (16 bytes)
$1C2    Partition type byte:
          $00 = Empty
          $01 = FAT12
          $04, $06, $0E = FAT16
          $0B, $0C = FAT32
          $07 = exFAT or NTFS (resolve via VBR OEM at $03)
          $83 = Linux ext
          $EE = GPT
$1FE    MBR signature ($55AA little-endian, check as WORD == $AA55)
```

---

## Existing Helper Methods (in SD_demo_shell.spin2)

All implemented and compiling (shell lines referenced):

| Method | Line | Purpose |
|--------|------|---------|
| `initRawAccess()` | 1837 | Calls `sd.initCardOnly()` to start worker cog without mount |
| `lookupMID(mid)` | 1845 | DAT table lookup: MID byte → manufacturer name pointer |
| `hexDigit(nibble)` | 1865 | Convert 0-15 to ASCII hex char |
| `getCardType(ocr, sizeMB)` | 1874 | OCR CCS bit + capacity → SDSC/SDHC/SDXC string |
| `getSDSpecVersion(p_scr)` | 1886 | SCR register → SD spec version string |
| `decodeSpeedClass(classByte)` | 1925 | SD Status SPEED_CLASS byte → integer (0,2,4,6,10) |
| `detectFilesystem()` | 1939 | MBR partition type → filesystem name string |
| `resolveType07()` | 1964 | Disambiguate type $07: VBR OEM → exFAT vs NTFS |

### DAT Lookup Tables

- **midTable** (line 2239): 15 manufacturer entries as `word MID, word @name` pairs, 4 bytes/entry, sentinel `$00, 0`
- **Filesystem strings** (line 2276): fsUnknown, fsFAT32, fsFAT16, fsFAT12, fsExFAT, fsNTFS, fsLinux, fsGPT, fsEmpty
- **Card type strings** (line 2288): ctSDSC, ctSDHC, ctSDXC

---

## The Bug: initRawAccess() Causes Garbage and Hang

### Symptoms

1. `card` command prints breadcrumbs `[A] [B] [C] init card` cleanly
2. Then garbage bytes flood the serial output (non-ASCII, 120+ bytes)
3. Shell becomes permanently unresponsive (main cog stuck at `WAITATN`)
4. Subsequent commands (e.g., `help`) get no response

### What We Know (Facts)

1. **Driver has NO functional code changes** — diff shows only added comments (ACMD13 code all commented out). The compiled driver binary is identical to the last committed version.

2. **Shell has substantial changes** — new methods (helpers, detectFilesystem, etc.), new DAT tables, modified `do_mount()` (pre-flight check), rewritten `do_card_info()`, rewritten `get_command()` (now uses `rxline()`).

3. **The committed version's `fsck` and `bench` commands also call `initRawAccess()` and work** — so `sd.initCardOnly()` → `start()` → `cogspin()` is a proven working code path.

4. **Mount worked before our changes** — the committed `do_mount()` went straight to `sd.mount()` without the pre-flight `initRawAccess()` check. Now `do_mount()` also calls `initRawAccess()` first, so mount may also be broken (untested).

5. **USB log evidence** — garbage bytes start in the same serial packet as `[C] init card\r\n`. The bytes `$63 $77 $61 $10` follow immediately, then bursts of non-ASCII data over ~200ms (matching `initCard()` timeline: 100ms power delay + 82ms recovery clocks). Total ~120 bytes of garbage before silence.

6. **Serial pins (62/63) are separate from SD pins (58-61)** — no pin overlap. Smart pin B-field offsets in SPI config correctly reference pin 61 only.

7. **Main cog stuck at WAITATN** — the worker cog never completes CMD_INIT_CARD_ONLY and never sends COGATN back to the caller.

### Root Cause Investigation Status

The investigation was exploring these angles when the session ended:

1. **Debug system conflict** — This theory was investigated and RULED OUT. Debug and serial share pin 62 without conflict. The P2 debug system and serial smart pins coexist correctly.

2. **Shell binary size / layout shift** — Adding ~420 lines of new code to the shell (new methods, DAT tables) changes the compiled binary layout. All hub memory addresses shift. If there's a subtle pnut-ts compiler issue with address computation, the `@cog_stack` address in `cogspin()` could be wrong. This would explain why the committed version works but ours doesn't.

3. **Something else in the shell changes** — The `get_command()` rewrite (from character-by-character to `rxline()`) changed serial behavior. The help screen rewrite (from DAT string to inline `fstr0` calls) added many string constants. These changes increase the binary size and shift addresses.

### What Has NOT Been Tested Yet

- Whether the current binary's `mount` command also fails (it now calls `initRawAccess()` too)
- Whether compiling without `-d` eliminates the garbage
- Whether reverting ALL shell changes (keeping only the diagnostic do_card_info) fixes the issue
- Whether `fsck` or `bench` still work with the current binary

---

## do_card_info() — Full Implementation (Currently Stripped to Diagnostic)

The full implementation needs these locals:

```spin2
PUB do_card_info() | wasMounted, cid[4], csd[4], scr[2], mid, pnm[2], prv, psn, mdt, ocr, sizeMB, spiHz, sdst[16]
```

**Local variable count: ~30 longs = 120 bytes** on the main cog's stack (not the worker cog's stack — this is fine, main cog has ample stack).

Note: In Spin2, all locals are LONGs (4 bytes). `cid[4]` = 16 bytes, `scr[2]` = 8 bytes, `pnm[2]` = 8 bytes (need 6 bytes for 5-char name + null), `sdst[16]` = 64 bytes for SD Status.

### Full Code Flow (When Working)

```
1. Save mounted state
2. If not mounted: initRawAccess() to start worker cog + init card
3. Read CID register → parse MID, PNM, PRV, PSN, MDT
4. Read CSD register → calculate card size
5. Read SCR register → determine SD spec version
6. Get OCR → determine card type (SDSC/SDHC/SDXC)
7. Read ACMD13 SD Status → speed class, UHS grade, video class  [BLOCKED: driver ACMD13 support disabled]
8. Detect filesystem from MBR
9. Get SPI frequency
10. Format and print Line 1
11. Format and print Line 2
12. If was not mounted: sd.stop() to shut down worker cog
```

### Driver ACMD13 Support (Disabled)

The driver-side ACMD13 support was added but caused the worker cog corruption bug. All ACMD13 code in the driver is currently commented out:

- `CMD_READ_SD_STATUS = 29` (enum, line 102)
- Worker dispatch case (line 682-683)
- `do_read_sd_status()` wrapper (line 1110-1114)
- `readSDStatusRaw()` PUB API (line 2629-2630)
- `readSDStatus()` PRI implementation (line 3278, entire ~85-line function removed)

The ACMD13 implementation pattern follows the same architecture as readCID/readCSD/readSCR:
```
PUB API → send_command() → worker dispatch → PRI wrapper → PRI implementation
```

The PRI implementation sends CMD55 (APP_CMD prefix) then CMD13, reads 64 bytes like a data block using the streamer.

---

## Recommended Next Steps

1. **Isolate the root cause**: Build the committed version (`git stash`, compile, test `card`) to confirm it works. Then incrementally add changes back to find which one breaks it.

2. **Test mount**: With the current binary, test `mount` to see if it also produces garbage (since it now calls `initRawAccess()`).

3. **Test without debug**: Modify `run_test.sh` or compile directly without `-d` to eliminate debug system as a variable.

4. **Once working**: Restore full `do_card_info()` implementation, re-enable ACMD13 driver support.
