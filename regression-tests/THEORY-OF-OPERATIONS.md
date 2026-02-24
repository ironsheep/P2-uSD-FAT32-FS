# Regression Test Suite — Theory of Operations

*Technical reference for the P2-uSD-Study SD card driver regression test suite.*

---

## 1. Executive Summary

The regression test suite validates the `micro_sd_fat32_fs.spin2` — a Propeller 2 SD card driver that uses smart pins for SPI communication, the P2 streamer for bulk data transfer, and a dedicated worker cog for all card I/O. The suite currently contains **16 core test files** producing an estimated **343 test assertions**. The original 10 files are joined by 6 additional files covering directory handles, volume operations, register access, speed/CMD6, CRC diagnostics, and subdirectory operations with cross-buffer cache coherence testing. Three additional test files (error handling, card info, card display) and infrastructure tests (FIFO, fstr) provide supplementary coverage outside the core count.

**Verified on hardware (2026-02-24):** 11 core suites totaling **263 tests** — all passing (mount 21, file_ops 22, read_write 38, directory 28, seek 37, multicog 14, multihandle 19, multiblock 6, raw_sector 14, format 46, subdir_ops 18).

The tests exercise the driver from low-level raw sector I/O through the full FAT32 filesystem stack, including multi-cog concurrent access, multi-handle file operations, and card formatting validation. Every test runs on real hardware (P2 Edge + physical SD card) via the `run_test.sh` headless test runner.

---

## 2. Test Framework Architecture

### 2.1 Shared Framework: isp_rt_utilities.spin2

All core test files use a shared utilities object that provides:

| Method | Purpose |
|--------|---------|
| `startTestGroup(pDesc)` | Begin a named group of related tests |
| `startTest(pDesc)` | Begin a single numbered test; auto-increments count |
| `evaluateSingleValue(result, pMsg, expected)` | Assert exact value match (top-level test) |
| `evaluateSingleValueHex(result, pMsg, expected)` | Assert hex value match (top-level test) |
| `evaluateBool(result, pMsg, expected)` | Assert boolean match (top-level test) |
| `evaluateRange(result, pMsg, min, max)` | Assert value within range (top-level test) |
| `evaluateNotZero(result, pMsg)` | Assert value is non-zero (top-level test) |
| `evaluateStringMatch(pResult, pMsg, pExpected)` | Assert string equality (top-level test) |
| `evaluateBufferMatch(pBuf1, pBuf2, len, pMsg)` | Assert byte-for-byte buffer equality (top-level test) |
| `evaluateSubValue(result, pMsg, expected)` | Assert value within a sub-test series |
| `evaluateSubValueHex(result, pMsg, expected)` | Assert hex value within a sub-test series |
| `evaluateSubBool(result, pMsg, expected)` | Assert boolean within a sub-test series |
| `recordPass()` / `recordFail()` | Manual pass/fail for tests that verify implicitly |
| `setCheckCountPerTest(n)` | Configure sub-test grouping divisor |
| `ShowTestEndCounts()` | Print final summary with pass/fail totals |

**Pattern generation and verification:**

| Method | Purpose |
|--------|---------|
| `fillBufferWithPattern(pBuf, len, start)` | Fill with incrementing byte pattern |
| `fillBufferWithValue(pBuf, len, val)` | Fill with constant value |
| `fillBufferWithRandom(pBuf, len)` | Fill with random bytes (P2 `getrnd()`) |
| `verifyBufferPattern(pBuf, len, start)` | Verify incrementing pattern match |
| `verifyBufferValue(pBuf, len, val)` | Verify constant value match |
| `dbgMemDump(pMsg, pBytes, len)` | Hex dump for debugging |

### 2.2 Test Execution Model

```
run_test.sh (from tools/ directory)
  └─ pnut-ts compile (includes -I paths to src/ for driver)
      └─ pnut-term-ts -r download to P2 RAM
          └─ Headless capture via debug() output
              └─ Parse "END_SESSION" to detect completion
                  └─ Log saved to tools/logs/
```

- All output is via `debug()` statements (P2 debug channel on pin 62)
- Tests signal completion with `debug("END_SESSION")`
- The test runner captures output until END_SESSION or timeout
- Each test file is self-contained: mounts, runs tests, unmounts, reports summary

### 2.3 Test Identification

Each test is identified by:
- **Test number** — auto-incremented by `startTest()` (e.g., `Test #7`)
- **Test name** — descriptive string (e.g., `"seek(0) - beginning of file"`)
- **Test group** — logical grouping (e.g., `"Cross-Sector Seeks"`)
- **Sub-tests** — multiple assertions within one test, aggregated as pass/fail

---

## 3. Test Suite Overview

### 3.1 Core Test Files (~325 tests)

| # | Test File | Tests | Focus Area | Driver API Category |
|---|-----------|:-----:|------------|---------------------|
| 1 | `SD_RT_mount_tests.spin2` | 21 | Mount/unmount lifecycle, card detection, error states | Lifecycle |
| 2 | `SD_RT_file_ops_tests.spin2` | 22 | File create, open, close, delete, rename, move | File Operations |
| 3 | `SD_RT_read_write_tests.spin2` | 38 | Read/write data integrity, patterns, boundaries, large multi-cluster | Data I/O |
| 4 | `SD_RT_directory_tests.spin2` | 28 | Directory create, navigate, enumerate, nesting | Directory Operations |
| 5 | `SD_RT_seek_tests.spin2` | 37 | Seek, tell, position tracking, cross-sector seeks | File Positioning |
| 6 | `SD_RT_multicog_tests.spin2` | 14 | Multi-cog singleton, concurrent access, stress test | Multi-Cog Safety |
| 7 | `SD_RT_multihandle_tests.spin2` | 19 | V3 handle API, independent positions, limits, errors | Multi-Handle |
| 8 | `SD_RT_multiblock_tests.spin2` | 6 | CMD18/CMD25 multi-sector read/write round-trips | Raw Multi-Block |
| 9 | `SD_RT_raw_sector_tests.spin2` | 14 | Raw sector read/write, patterns, address boundaries | Raw Sector I/O |
| 10 | `SD_RT_format_tests.spin2` | 46 | FAT32 format validation, MBR/VBR/FSInfo/FAT structure | Format Utility |
| 11 | `SD_RT_dirhandle_tests.spin2` | ~22 | V3 directory handle enumeration, pool interaction, paths | Directory Handle API |
| 12 | `SD_RT_volume_tests.spin2` | ~20 | Volume label, VBR access, syncAll, sync, setDate | Volume Operations |
| 13 | `SD_RT_register_tests.spin2` | ~10 | CSD register, timeout values, capacity cross-check | Register Access |
| 14 | `SD_RT_speed_tests.spin2` | ~14 | SPI frequency, CMD6, high-speed mode, speed boundaries | Speed/CMD6 API |
| 15 | `SD_RT_crc_diag_tests.spin2` | ~14 | CRC counters, validation toggle, CMD13 diagnostics | CRC Diagnostic |
| 16 | `SD_RT_subdir_ops_tests.spin2` | 18 | Cross-buffer cache coherence, empty files, subdir operations | Subdirectory Ops |
| | **Total** | **~343** | | |

### 3.2 Supplementary Test Files (not in 236 count)

| Test File | Purpose |
|-----------|---------|
| `SD_RT_error_handling_tests.spin2` | Error conditions: invalid handles, EOF behavior, directory errors, handle reuse |
| `SD_RT_card_info_tests.spin2` | Struct-based register access certification (CID, SCR, OCR, SD Status) |
| `SD_RT_card_display_test.spin2` | Card info display via fstr output (demo shell pattern certification) |
| `SD_RT_fifo_tests.spin2` | String FIFO (isp_string_fifo) inter-cog communication regression tests |
| `SD_RT_fstr_tests.spin2` | Serial fstr mechanism test (not SD driver — serial library) |
| `SD_RT_fstr_args_tests.spin2` | Serial fstr argument handling test (not SD driver — serial library) |

### 3.3 Framework File

| File | Purpose |
|------|---------|
| `isp_rt_utilities.spin2` | Shared test assertion framework, pattern generation, memory dump utilities |

---

## 4. Detailed Theory of Operations

### 4.1 SD_RT_mount_tests.spin2 (21 tests)

**Purpose:** Validate the driver lifecycle — initialization, mount, unmount, remount, and error handling for operations attempted without a mounted filesystem.

**Why we test this:** The mount sequence is the entry point for all filesystem operations. If mounting fails or produces corrupt state, every subsequent operation is unreliable. This test file ensures the driver correctly initializes the SPI bus, performs the SD card identification protocol (CMD0/CMD8/ACMD41/CMD58), reads the MBR and VBR to locate the FAT32 partition, and properly tears down on unmount.

#### Test Groups

**Group 1: Pre-Mount Error Handling**
Tests that operations fail gracefully before any card is mounted. This catches null-pointer dereferences, uninitialized state access, and missing guard clauses.

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Operations before mount fail | `openFile()`, `read()`, `newFile()` | Returns false/error | Driver must not crash on pre-mount calls |
| error() returns meaningful code | `error()` | Returns E_NOT_MOUNTED (-20) | Per-cog error system works before mount |

**Group 2: Mount and Card Detection**
Tests the full initialization sequence from `start()` through `mount()`.

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| start() returns valid cog ID | `start(CS, MOSI, MISO, SCK)` | Returns 0-7 | Worker cog launches successfully |
| mount() succeeds | `mount()` | Returns true | Card init + filesystem parse works |
| Card size is reasonable | `cardSizeSectors()` | > 0 | CSD register read and capacity calculation |
| Volume label readable | `volumeLabel()` | Non-null pointer | FAT32 root directory parsed |
| Free space available | `freeSpace()` | > 0 | FAT scanned for free clusters |
| SPI frequency correct | `getSPIFrequency()` | ~25 MHz | Smart pin clock configuration |

**Group 3: Unmount and Remount**
Tests that unmount properly flushes state and allows clean remount.

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| unmount() succeeds | `unmount()` | Returns true | Pending writes flushed, state cleared |
| Operations after unmount fail | `openFile()` etc. | Returns false/error | State properly torn down |
| Remount succeeds | `mount()` after unmount | Returns true | Fresh initialization works |
| Data accessible after remount | `openFile()`, `read()` | Correct data | No stale state from prior session |

**Group 4: Singleton Pattern**
Verifies that repeated `start()` calls return the same cog ID, not allocate new cogs.

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Second start() returns same cog | `start()` (repeat call) | Same cog ID | Singleton enforced — prevents cog leak |
| Third start() returns same cog | `start()` (third call) | Same cog ID | Pattern is stable |

---

### 4.2 SD_RT_file_ops_tests.spin2 (22 tests)

**Purpose:** Validate file lifecycle operations — create, open, close, delete, rename, and move using both legacy (single-file) and V3 (multi-handle) APIs.

**Why we test this:** File operations are the primary user-facing API. They involve complex interactions between directory entry manipulation, FAT chain allocation, and sector caching. Bugs here manifest as data loss, phantom files, or filesystem corruption.

#### Test Groups

**Group 1: File Creation and Deletion**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| newFile() creates file | `newFile()` | Returns true | Directory entry created, cluster allocated |
| File appears in directory | `readDirectory()` | File listed | Directory entry written to card |
| deleteFile() removes file | `deleteFile()` | Returns true | Entry marked deleted ($E5), clusters freed |
| Deleted file not in directory | `readDirectory()` | File absent | Deletion is visible |
| Delete non-existent file fails | `deleteFile()` | Returns false | Error handling for missing file |

**Group 2: File Open/Close Cycle**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| openFile() existing file | `openFile()` | Returns true | Directory search finds file |
| openFile() non-existent fails | `openFile()` | Returns false | Graceful error on missing file |
| closeFile() succeeds | `closeFile()` | No error | Pending writes flushed, state cleaned |
| File data persists after close | `openFile()` + `read()` | Original data | Write flush completed correctly |

**Group 3: Rename and Move**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| rename() changes name | `rename()` | Returns true | Directory entry name updated |
| Old name gone | `openFile()` old name | Returns false | Old entry invalidated |
| New name works | `openFile()` new name | Returns true | New entry searchable |
| moveFile() to subdirectory | `moveFile()` | Returns true | Cross-directory entry transfer |

**Group 4: V3 Handle-Based Creation**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| createFileNew() returns handle | `createFileNew()` | Handle >= 0 | V3 creation path works |
| createFileNew() existing fails | `createFileNew()` duplicate | E_FILE_EXISTS (-41) | Won't overwrite existing file |
| writeHandle() + closeFileHandle() | `writeHandle()`, `closeFileHandle()` | Data persists | V3 write path to card |

---

### 4.3 SD_RT_read_write_tests.spin2 (38 tests)

**Purpose:** Validate data integrity for read and write operations across various sizes, patterns, and boundary conditions.

**Why we test this:** Data integrity is the most critical property of a storage driver. The P2 driver uses the streamer for bulk transfers (4-5x faster than byte loops), which means timing alignment between the SPI clock smart pin and the streamer data path must be exact. A single-bit timing error produces silent data corruption. These tests catch such errors by writing known patterns and verifying every byte on readback.

#### Test Groups

**Group 1: Small Writes and Reads**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Write 1 byte, read back | `write(1)`, `read(1)` | Byte matches | Minimum transfer works |
| Write string, read back | `write("Hello")`, `read(5)` | String matches | Multi-byte short transfer |
| Write 10 bytes, verify | `write(10)`, `read(10)` | All bytes match | Small buffer integrity |

**Group 2: Sector-Boundary Writes**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Write exactly 512 bytes | `write(512)`, `read(512)` | All match | Single sector, no boundary crossing |
| Write 513 bytes (cross boundary) | `write(513)`, `read(513)` | All match | Forces second sector allocation |
| Write 1024 bytes (2 sectors) | `write(1024)`, `read(1024)` | All match | Multi-sector sequential write |

**Group 3: Pattern Verification**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Sequential pattern (0-255) | Write pattern, read all | Every byte correct | Detects byte-swap, offset, or shift errors |
| Alternating AA/55 | Write alternating, verify | Pattern intact | Detects stuck bits or polarity errors |
| All-FF pattern | Write $FF fill, verify | All $FF | Detects spurious zero bits |
| All-00 pattern | Write $00 fill, verify | All $00 | Detects spurious one bits |
| Random pattern | Write random, verify | Exact match | Catches any systematic corruption |

**Group 4: Large File Writes**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Write 2KB (4 sectors) | `write(2048)`, `read(2048)` | All match | Multi-sector sequential integrity |
| Write 4KB (8 sectors) | `write(4096)`, `read(4096)` | All match | Larger sequential transfer |
| Cluster boundary crossing | Write past cluster boundary | Data intact | FAT chain followed during write |

**Group 5: Overwrite and Append**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Overwrite shorter with longer | Write, close, rewrite longer | Longer data | File grows correctly |
| Overwrite longer with shorter | Write, close, rewrite shorter | Shorter data, correct size | File truncation or size update |
| Append via write at EOF | `seek(EOF)`, `write()` | Both parts intact | Append doesn't corrupt existing data |

---

### 4.4 SD_RT_directory_tests.spin2 (28 tests)

**Purpose:** Validate directory creation, navigation, enumeration, and cleanup across nested structures up to 5 levels deep.

**Why we test this:** Directory operations modify the FAT32 directory table structure — creating 32-byte entries, allocating clusters for new directories, and maintaining the `.` and `..` self/parent references. Navigation uses per-cog directory context (cog_dir_sec[]), which must be correctly maintained. Deep nesting tests the cluster chain following for directory data.

#### Test Groups

**Group 1: Directory Creation**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| newDirectory() creates dir | `newDirectory()` | Returns true | Directory entry with attribute $10 created |
| Directory appears in listing | `readDirectory()` | Directory listed | Entry visible in parent |
| Duplicate directory fails | `newDirectory()` same name | Returns false | Name collision detected |

**Group 2: Directory Navigation**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| changeDirectory() into subdir | `changeDirectory()` | Returns true | Per-cog directory context updated |
| Files visible inside subdir | `readDirectory()` | Files listed | Context switch to child cluster chain |
| changeDirectory("..") to parent | `changeDirectory(@"..")` | Returns true | Parent navigation via ".." entry |
| changeDirectory("/") to root | `changeDirectory(@"/")` | Returns true | Absolute path reset to root cluster |
| Non-existent directory fails | `changeDirectory()` bad name | Returns false | Missing directory detected |

**Group 3: Directory Enumeration**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Enumerate root contents | `readDirectory()` loop | All files/dirs listed | Sequential entry reading works |
| File count matches | Count entries | Expected count | No phantom or missing entries |
| Attributes correct | `attributes()` | $10 for dirs, $20 for files | Entry type detection |

**Group 4: Deep Nesting (5 levels)**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Create 5-deep directory tree | 5x `newDirectory()` + `changeDirectory()` | All succeed | Deep nesting supported |
| Create file at depth 5 | `newFile()` at level 5 | Returns true | File creation at deep nesting |
| Navigate back via 5x ".." | 5x `changeDirectory(@"..")` | Reach root | Parent chain traversal |

**Group 5: Boundary Conditions**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Empty directory listing | Create empty dir, enumerate | Only "." and ".." entries | FAT32 empty dir convention |
| Max filename length (8.3) | `newFile(@"12345678.123")` | Created successfully | 8.3 name length limit |

**Group 6: Cleanup**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Delete files and directories | `deleteFile()` on tree | All deleted | Recursive cleanup works |

---

### 4.5 SD_RT_seek_tests.spin2 (37 tests)

**Purpose:** Validate file position management — seek to absolute positions, cross-sector seeks, random access patterns, and boundary conditions including EOF.

**Why we test this:** Seek operations require the driver to locate the correct cluster and sector for any arbitrary byte position within a file. This involves following the FAT chain (cluster-to-cluster) and calculating the offset within a sector. Errors here produce reads from wrong positions — silent data corruption that's extremely hard to diagnose in applications.

#### Pre-Test Setup
A 2048-byte file (4 sectors) is created with a position-dependent pattern: `byte[i] = i & $FF`. This means position 100 contains value 100, position 256 contains value 0, etc. — making it trivial to verify seek correctness.

#### Test Groups

**Group 1: Basic Seek Operations**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| seek(0) — start of file | `seek(0)` + `read(1)` | Byte = 0 | Seek to beginning works |
| seek(100) — mid-sector | `seek(100)` + `read(1)` | Byte = 100 | Absolute positioning works |
| seek(255) — pattern boundary | `seek(255)` + `read(1)` | Byte = 255 | Near 256-byte pattern wrap |
| seek(256) — pattern wraps | `seek(256)` + `read(1)` | Byte = 0 | Pattern repeats at 256 |

**Group 2: Cross-Sector Seeks**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| seek(511) — last byte, sector 1 | `seek(511)` + `read(1)` | Byte = 255 | Sector boundary - 1 |
| seek(512) — first byte, sector 2 | `seek(512)` + `read(1)` | Byte = 0 | Crosses 512-byte sector boundary |
| seek(1023) — last byte, sector 2 | `seek(1023)` + `read(1)` | Byte = 255 | Second boundary approach |
| seek(1024) — first byte, sector 3 | `seek(1024)` + `read(1)` | Byte = 0 | Second boundary crossing |

**Group 3: Random Access Pattern**
Tests 8 non-sequential positions (1500, 200, 1999, 0, 750, 2000, 512, 1024) to verify that seeking forward and backward works correctly — the driver must re-traverse the FAT chain for backward seeks.

**Group 4: readByte() Direct Access**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| readByte(0), (100), (512), (1000) | `readByte(pos)` | Correct values | Combined seek+read API |

**Group 5: Seek Edge Cases**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| seek() beyond EOF | `seek(size + 100)` | Returns false | Out-of-bounds rejected |
| seek() to exact EOF-1 | `seek(size - 1)` | Returns true, correct byte | Last valid position |
| seek(0) in empty file | Create 0-byte, seek(0) | Succeeds | Empty file handled |
| seek(1) in empty file | Create 0-byte, seek(1) | Fails | Beyond empty EOF |

**Group 6: Sequential vs Seek Consistency**
Verifies that seeking back to position 0 and re-reading produces the same bytes as the initial sequential read — catches stale buffer bugs.

---

### 4.6 SD_RT_multicog_tests.spin2 (14 tests)

**Purpose:** Validate multi-cog safety — the singleton driver pattern, hardware lock serialization, concurrent access from multiple P2 cogs, and per-cog error isolation.

**Why we test this:** The P2 has 8 cogs that share hub memory. The SD driver uses a single worker cog for all SPI I/O, serialized through a hardware lock and a shared parameter block. If the lock mechanism fails, concurrent cog access produces corrupted commands, garbled data, or deadlocks. These tests launch 3 worker cogs that hammer the driver simultaneously.

#### Test Groups

**Group 1: Singleton Verification**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| First start() returns valid cog | `start()` | cog ID 0-7 | Worker cog allocated |
| Second start() returns same | `start()` again | Same cog ID | No duplicate cog allocation |
| Third start() returns same | `start()` again | Same cog ID | Singleton is stable |
| mount() succeeds | `mount()` | Returns true | Filesystem ready for multi-cog |

**Group 2: Worker Cog Singleton Test**
Launches 3 worker cogs via `cogspin()`. Each worker independently calls `start()` and records the returned cog ID.

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Workers launched | `cogspin()` x 3 | All launched | Cogs allocated for workers |
| All workers see same cog ID | Worker results | All match main cog ID | Singleton spans cogs |
| All workers report success | Worker status | All STATUS_PASS | No worker errors |

**Group 3: Concurrent Read Operations**
3 worker cogs simultaneously attempt to open and read the same file. The hardware lock serializes access — at most one cog communicates with the worker at a time.

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Concurrent reads complete | Worker completion | No deadlock | Lock mechanism works under contention |

**Group 4: Stress Test**
Each of 3 worker cogs performs 10 iterations of open/read/close cycles in a tight loop, hammering the lock and parameter block.

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Stress iterations complete | Worker iteration counts | All reach 10 | No crashes under heavy load |
| All workers report success | Worker status | All STATUS_PASS | Sustained reliability |

**Group 5: Per-Cog Error**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| error() returns per-cog value | `error()` | Valid code or 0 | Error isolation between cogs |

---

### 4.7 SD_RT_multihandle_tests.spin2 (19 tests)

**Purpose:** Validate the V3 multi-file handle API — independent file positions, handle limits, single-writer policy, handle lifecycle, sync, and EOF detection.

**Why we test this:** The V3 API allows up to 6 simultaneously open files, each with its own position, buffer, and state. This is critical for applications that need to read configuration while writing logs, or process multiple data streams. Each handle has a 512-byte per-handle buffer that eliminates cache thrashing — testing verifies these buffers are truly independent.

#### Test Groups

**Group 1: Multiple Read Handles**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Open 4 files, get unique handles | 4x `openFileRead()` | All valid, all unique | Handle allocation works |
| Read from 4 handles, correct data | 4x `readHandle()` | Each returns its file's data | Independent data streams |

**Group 2: Independent Handle Positions**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Same file, 2 handles | 2x `openFileRead()` same file | Both valid, different handles | Same file can be opened twice |
| Seek one, both maintain position | `seekHandle(h1, 12)`, read both | h1 at offset 12, h2 at offset 0 | Positions are independent |

**Group 3: Single-Writer Policy**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Second write-open returns error | 2x `openFileWrite()` same file | E_FILE_ALREADY_OPEN (-92) | Prevents concurrent write corruption |
| Read allowed while write-open | `openFileWrite()` + `openFileRead()` | Both succeed | Readers don't block writers |

**Group 4: Handle Limit Enforcement**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| 7th file open fails | Open 6, then 7th | E_TOO_MANY_FILES (-90) | Hard limit enforced (MAX_OPEN_FILES=6) |

**Group 5: Handle Reuse**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Close frees slot for reuse | Open 4, close in mixed order, reopen | Valid handle obtained | Handle slots recycled |

**Group 6: Write Persistence**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Write survives close/reopen | Create, write, close, reopen, read | Content matches | Data reaches card |

**Group 7: Sync Operations**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| syncHandle() flushes to card | `syncHandle()` mid-write | Returns success | Dirty buffer written to card |
| Continued writing after sync | Write more after sync | Data intact | Handle still usable |

**Group 8: EOF Detection**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| eofHandle() state transitions | Check at start, after full read, after seek back | Correct at each point | EOF flag tracks position |

**Group 9: Invalid Handle Errors**

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| readHandle(-1) | `readHandle(-1, ...)` | E_INVALID_HANDLE (-91) | Negative handle rejected |
| readHandle(99) | `readHandle(99, ...)` | E_INVALID_HANDLE (-91) | Out-of-range rejected |
| writeHandle on closed handle | `writeHandle()` after close | E_INVALID_HANDLE (-91) | Closed handle rejected |
| seekHandle(-1) | `seekHandle(-1, 0)` | E_INVALID_HANDLE (-91) | Seek validates handle |
| Double close | Close, then close again | E_INVALID_HANDLE on 2nd | Idempotent protection |
| tellHandle(-1), fileSizeHandle(-1), syncHandle(-1), eofHandle(-1) | Various(-1) | All E_INVALID_HANDLE | All handle APIs validate |

---

### 4.8 SD_RT_multiblock_tests.spin2 (6 tests)

**Purpose:** Validate CMD18 (READ_MULTIPLE_BLOCK) and CMD25 (WRITE_MULTIPLE_BLOCK) multi-sector transfers — the streamer-based bulk I/O path that provides 4-5x throughput over single-sector transfers.

**Why we test this:** Multi-block transfers are the performance-critical path. They use SD commands CMD18/CMD25 which keep the data bus active across sector boundaries, avoiding per-sector command overhead. The streamer handles continuous data flow, and the CRC must be validated for each sector within the multi-block sequence. Any timing misalignment between streamer and SPI clock corrupts all subsequent sectors in the transfer.

#### Test Details

| Test | Sectors | API Under Test | Pattern | What We Verify | Why |
|------|:-------:|----------------|---------|----------------|-----|
| Round-trip 8 sectors | 8 | `writeSectorsRaw()` + `readSectorsRaw()` | `(sector*17 + byte) & $FF` | All 4,096 bytes match | Basic multi-block integrity |
| Multi-write, single-read | 8 | `writeSectorsRaw(8)`, then 8x `readSectorRaw()` | `(i*23 + byte + $A0) & $FF` | Each individual read matches | CMD25 write compatible with CMD17 reads |
| Single-write, multi-read | 8 | 8x `writeSectorRaw()`, then `readSectorsRaw(8)` | `(i*31 + byte + $B0) & $FF` | Multi-read matches individual writes | CMD24 writes compatible with CMD18 read |
| count=1 fallback | 1 | `writeSectorsRaw(1)` + `readSectorsRaw(1)` | — | Both return 1 | Single-sector via multi-block API |
| count=0 edge case | 0 | `writeSectorsRaw(0)` + `readSectorsRaw(0)` | — | Both return 0 | Zero-count handled gracefully |
| Large 64-sector transfer | 64 | `writeSectorsRaw(64)` + `readSectorsRaw(64)` | `(sector + byte) & $FF` | All 32,768 bytes match | Stress: 32KB continuous transfer |

---

### 4.9 SD_RT_raw_sector_tests.spin2 (14 tests)

**Purpose:** Validate the raw sector read/write API — direct access to card sectors bypassing the filesystem layer. Tests use `initCardOnly()` instead of `mount()`.

**Why we test this:** Raw sector access is the foundation that the filesystem builds on. It exercises the SPI smart pin configuration, streamer data path, and CRC validation without any FAT32 complexity. Testing patterns that stress all 8 data bits (sequential, alternating, all-ones, all-zeros) catches bit-level errors in the SPI/streamer path.

#### Phase 1: Write 5 Patterns

Each pattern is written to a dedicated sector (100,000-100,004) with boundary markers (head: $DEADBEEF, tail: $CAFEBABE) and immediately read back for verification.

| Test | Sector | Pattern | What It Catches |
|------|:------:|---------|-----------------|
| Pattern A (sequential) | 100,000 | `i & $FF` (0-255 repeating) | Byte offset errors, shift errors |
| Pattern B (alternating) | 100,001 | `$AA/$55` alternating | Stuck bits, polarity inversion |
| Pattern C (all FF) | 100,002 | `$FF` fill | Spurious zero bits |
| Pattern D (all 00) | 100,003 | `$00` fill | Spurious one bits |
| Pattern E (offset) | 100,004 | `(i + $E0) & $FF` | Different offset than Pattern A |

#### Phase 2: Read in Reverse Order
Re-reads all 5 sectors in reverse order (100,004 first) to verify that later writes didn't corrupt earlier sectors — catches sector address aliasing bugs.

#### Phase 3: Full Data Verification
Byte-by-byte verification of all 496 data bytes (excluding markers) for Patterns A and B.

#### Phase 4: Address Boundaries

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Read sector 0 (MBR) | `readSectorRaw(0)` | Signature $55AA at 510-511 | LBA 0 addressing works |
| Read sector 1,000,000 | `readSectorRaw(1_000_000)` | Completes without crash | Large LBA addressing |

---

### 4.10 SD_RT_format_tests.spin2 (46 tests)

**Purpose:** Validate the FAT32 format utility — verify that after formatting, the MBR, VBR, FSInfo, FAT tables, and root directory conform to the FAT32 specification and produce a filesystem that mounts and is usable.

**Why we test this:** The format utility writes the critical on-card structures that define the filesystem. A single byte error in the VBR (e.g., wrong bytes-per-sector, wrong FAT size) makes the card unreadable. This test verifies every field to ensure cross-platform compatibility (the formatted card should be readable by Windows, macOS, and Linux).

**WARNING:** This test erases all data on the card.

#### Test Groups

**Group 1: Format Execution** (1 test)
Runs the format utility and verifies it completes successfully.

**Group 2: MBR Verification** (5 tests)

| Test | Field | Expected | Why |
|------|-------|----------|-----|
| Boot signature | WORD at $1FE | $AA55 | Universal MBR marker |
| Partition 1 bootable flag | Byte at $1BE | $00 or $80 | Valid bootable indicator |
| Partition 1 type | Byte at $1C2 | $0C (FAT32 LBA) | Correct partition type for SDHC/SDXC |
| Partition 1 start sector | LONG at $1C6 | 8192 | 4MB-aligned for performance |
| Partition 1 size | LONG at $1CA | > 0 | Partition has data space |

**Group 3: VBR Verification** (19 tests)
Validates every critical field in the FAT32 Volume Boot Record:

| Test | Field | Expected | Why |
|------|-------|----------|-----|
| Jump instruction | Byte at $00 | $EB or $E9 | Required boot jump |
| Boot signature | WORD at $1FE | $AA55 | VBR signature |
| OEM name | Bytes at $03 | Printable ASCII | OEM identification |
| Bytes per sector | WORD at $0B | 512 | Standard sector size |
| Sectors per cluster | Byte at $0D | Power of 2 | Valid cluster size |
| Reserved sectors | WORD at $0E | 32 | Standard FAT32 reserved area |
| Number of FATs | Byte at $10 | 2 | Dual FAT for redundancy |
| Root entry count | WORD at $11 | 0 | FAT32 requirement (root is cluster chain) |
| Total sectors 16-bit | WORD at $13 | 0 | FAT32 uses 32-bit field |
| Media type | Byte at $15 | $F8 | Fixed disk media |
| FAT size 16-bit | WORD at $16 | 0 | FAT32 uses 32-bit field |
| Hidden sectors | LONG at $1C | Partition start | Offset matches MBR |
| Total sectors 32-bit | LONG at $20 | > 0 | Total filesystem size |
| FAT32 sectors per FAT | LONG at $24 | > 0 | FAT computed correctly |
| Root cluster | LONG at $2C | 2 | Root at standard cluster 2 |
| FSInfo sector | WORD at $30 | 1 | FSInfo at partition+1 |
| Backup boot sector | WORD at $32 | 6 | Backup at partition+6 |
| Extended boot sig | Byte at $42 | $29 | Extended signature present |
| FS type label | Bytes at $52 | "FAT32   " | Filesystem identification |

**Group 4: Backup VBR** (1 test)
Byte-for-byte comparison of backup VBR (sector partition+6) against primary VBR — they must be identical for recovery.

**Group 5: FSInfo Verification** (6 tests)

| Test | Field | Expected | Why |
|------|-------|----------|-----|
| Lead signature | LONG at $000 | $41615252 (RRaA) | FSInfo identification |
| Structure signature | LONG at $1E4 | $61417272 (rrAa) | Structure marker |
| Trail signature | LONG at $1FC | $AA550000 | End marker |
| Free cluster count | LONG at $1E8 | Non-zero or $FFFFFFFF | Free space initialized |
| Next free hint | LONG at $1EC | 3 or $FFFFFFFF | First free after root |
| Backup FSInfo matches | Sector partition+7 | Identical to primary | Backup integrity |

**Group 6: FAT Table Verification** (6 tests)

| Test | FAT Entry | Expected | Why |
|------|-----------|----------|-----|
| FAT[0] | Media type | $0FFFFFF8 | Standard media marker |
| FAT[1] | EOC marker | $0FFFFFFF | End of chain |
| FAT[2] | Root dir EOC | $0FFFFFFF | Root directory terminator |
| FAT[3] | First free | $00000000 | Available for allocation |
| FAT2 mirrors FAT1 | Compare sectors | Identical | Redundancy validation |
| Second sectors zeroed | FAT sectors | All $00 | Clean initialization |

**Group 7: Root Directory** (4 tests)
Volume label entry, label name, entry sequence, unused space zeroed.

**Group 8: Mount and Usability** (3 tests)
Mount the freshly formatted card, read volume label, check free space — confirms the formatted card is immediately usable.

---

### 4.11 SD_RT_read_write_tests.spin2 — Large File Multi-Cluster Addition (+9 tests)

**Purpose:** Extend the existing read/write tests with large file verification (128KB and 256KB) that exercises FAT chain traversal across many clusters.

**Why we test this:** The original tests maxed out at 64KB with a single repeated pattern. Real applications create files spanning dozens of clusters. These tests write uniquely-identifiable 2KB chunks (each with a different pattern start value), then verify random access across cluster boundaries — catching FAT chain following bugs, stale cache issues, and backward-seek failures in long chains.

#### Test Group: Large File Multi-Cluster Verification

| Test | File Size | What We Verify | Why |
|------|-----------|----------------|-----|
| Create 128KB file | 128KB (256 sectors, 16 clusters) | Size == 131072, 64 unique chunks written | Multi-cluster write chain allocation |
| Verify first chunk | Read pos 0 | Pattern(0) matches | Start of chain correct |
| Verify middle chunk | Seek to 65536, read | Pattern(256) matches | Mid-chain seek + read |
| Verify last chunk | Seek to 129024, read | Pattern(504) matches | End-of-chain seek + read |
| Sequential read all 128KB | Read 64 chunks | All 64 patterns match | Complete chain traversal |
| Create 256KB file | 256KB (512 sectors, 32 clusters) | Size == 262144 | Longer chain allocation |
| Random access across clusters | 4 seeks: 0, 32768, 131072, 260096 | All patterns match | Non-sequential cluster chain following |
| Backward seek in large file | Read near end, seek to 0, read | Both reads correct | Backward seek re-traverses chain |
| Delete reclaims space | Delete 256KB, check freeSpace | ~512 sectors reclaimed | FAT chain deallocation |

---

### 4.12 SD_RT_dirhandle_tests.spin2 (~22 tests)

**Purpose:** Validate the V3 directory handle enumeration API — `openDirectory()`, `readDirectoryHandle()`, `closeDirectoryHandle()` — including path handling, error conditions, and handle pool interaction.

**Why we test this:** The directory handle API is the recommended way to enumerate directory contents in the V3 API. Directory handles share the same pool as file handles (MAX_OPEN_FILES=6), so interaction between file and directory handles must be correct. These tests verify enumeration works for root, subdirectories, empty directories, and absolute paths, while also testing error cases like opening a file as a directory.

#### Pre-Test Setup
Creates a test directory structure:
```
/DHTDIR1/DH1.TXT, DH2.TXT, DH3.TXT, DHSUB1/DHSUB.TXT
/DHTEMPTY/   (empty directory)
```

#### Test Groups

**Group 1: Basic Enumeration** (5 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| openDirectory(".") | `openDirectory(@".")` | Handle >= 0, entries found | Current directory enumeration |
| openDirectory("") | `openDirectory(@dhEmpty)` | Handle >= 0, entries found | Empty string = current dir |
| openDirectory("DHTDIR1") | `openDirectory(@dhTestDir)` | >= 4 entries found | Named directory enumeration |
| closeDirectoryHandle releases | Close, reopen | Second open succeeds | Slot recycled |
| Enumerate finds all items | Count files and dirs | 3 files + 1 subdir | Complete enumeration |

**Group 2: Entry Inspection** (4 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| fileName() returns names | `fileName()` per entry | All non-empty | Name extraction works |
| attributes() file vs dir | `attributes()` | Files and dirs distinguished | Attribute byte correct |
| Empty dir has no entries | Enumerate DHTEMPTY | 0 entries (dots skipped) | readDirectoryHandle skips dot entries |
| Subdirectory enumeration | openDirectory("/DHTDIR1/DHSUB1") | Found >= 1 file | Nested path enumeration |

**Group 3: Error Conditions** (5 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Non-existent dir | `openDirectory(@"NXDIR999")` | E_FILE_NOT_FOUND (-40) | Missing directory handled |
| File as directory | `openDirectory(@"DH1.TXT")` | E_NOT_A_DIR (-43) | File/dir type checked |
| Invalid handle | `readDirectoryHandle(-1)` | Returns 0 | Negative handle rejected |
| File handle to readDirHandle | Use file handle with readDirectoryHandle | Returns 0 | Handle type checked |
| closeDirectoryHandle(-1) | Close invalid | No crash | Graceful error handling |

**Group 4: Handle Pool Interaction** (4 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| 5 files + 1 dir = full pool | Open 5 files + 1 dir, try 7th | E_TOO_MANY_FILES (-90) | Dir handles share pool |
| Multiple dir handles | 2 openDirectory() calls | Both valid, different | Concurrent enumeration |
| File + dir coexist | Open file + open dir | Both usable | Mixed handle types |
| Restart requires close+reopen | Partial read, close, reopen | Starts from beginning | No restart API |

**Group 5: Path Handling** (4 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| openDirectory("/") | Root path | Entries found | Root enumeration via path |
| Absolute path | openDirectory("/DHTDIR1") | Entries found | Absolute path works |
| After changeDirectory | Change to subdir, openDirectory(".") | Reflects new CWD | CWD-relative enumeration |
| openDirectory doesn't change CWD | Open DHTDIR1, verify still at root | CWD unchanged | Read-only operation |

---

### 4.13 SD_RT_volume_tests.spin2 (~20 tests)

**Purpose:** Validate volume-level operations — volume label get/set, VBR raw read, syncAllHandles, legacy sync, and setDate timestamp functionality.

**Why we test this:** These APIs affect the filesystem metadata layer. `setVolumeLabel()` modifies both the BPB and root directory label entry. `readVBRRaw()` exposes the boot sector for diagnostics. `syncAllHandles()` is used for safety checkpoints. `setDate()` controls file/directory timestamps. Bugs here cause cross-platform incompatibility or data loss.

**Pragma:** `#PRAGMA EXPORTDEF SD_INCLUDE_REGISTERS` (for readVBRRaw)

#### Test Groups

**Group 1: setVolumeLabel** (5 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Set new label | `setVolumeLabel(@"TESTLABEL")` | Returns true | Label write succeeds |
| Read back new label | `volumeLabel()` | Matches "TESTLABEL" | Label persisted in memory |
| Max length (11 chars) | `setVolumeLabel(@"12345678901")` | Returns true | Full 11-char label works |
| Persists through remount | Unmount, remount, read label | Matches "12345678901" | Written to card, not just cached |
| Restore original | `setVolumeLabel(@origLabel)` | Returns true | Cleanup works |

**Group 2: readVBRRaw** (4 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Returns valid data | `readVBRRaw(@vbrBuf)` | Returns true | VBR sector read works |
| Boot signature $AA55 | WORD at $1FE | == $AA55 | Valid boot sector |
| Bytes per sector == 512 | WORD at $0B | == 512 | Standard sector size |
| OEM name readable | Bytes at $03 | Printable ASCII | Metadata intact |

**Group 3: syncAllHandles** (4 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| No handles open | `syncAllHandles()` | Returns 0 | Safe with empty pool |
| Single write handle | Write, syncAll | Returns 0, file writable after | Flush without close |
| Multiple write handles | 2 write handles, syncAll | Returns 0 | Batch flush works |
| Mixed read+write | 1 read + 1 write, syncAll | Returns 0 | Only write handles flushed |

**Group 4: sync (legacy)** (2 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Flush legacy write | `sync()` after `writeString()` | Returns true | Legacy API works |
| No file open | `sync()` | Returns true | Safe when no file |

**Group 5: setDate** (5 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Timestamp on new file | Set date, create file | wrtDate/wrtTime match, year=46 | Date encoding correct |
| Midnight Jan 1, 2000 | `setDate(2000,1,1,0,0,0)` | year=20, time=0 | Epoch boundary |
| End-of-day Dec 31 | `setDate(2025,12,31,23,59,58)` | year=45, month=12, hour=23 | Date range boundary |
| V3 createFileNew timestamp | Set date, `createFileNew()` | year=46, month=6 | V3 path uses date |
| Timestamp on new directory | Set date, `newDirectory()` | year=46, month=3 | Directories get timestamps |

---

### 4.14 SD_RT_register_tests.spin2 (~10 tests)

**Purpose:** Validate CSD register access and derived timeout values — ensuring the raw CSD read works, the version and capacity fields are correct, and timeout values are reasonable.

**Why we test this:** The CSD register controls timing parameters (TRAN_SPEED, read/write timeouts) and reports card capacity. Incorrect parsing produces wrong timeout values (causing command timeouts) or wrong capacity (causing out-of-bounds sector access).

**Pragmas:** `SD_INCLUDE_REGISTERS`, `SD_INCLUDE_RAW`, `SD_INCLUDE_SPEED`

#### Test Groups

**Group 1: readCSDRaw** (6 tests)

| Test | What We Verify | Why |
|------|----------------|-----|
| readCSDRaw() returns data | Returns true, buffer filled | Raw read works |
| CSD version valid (0 or 1) | CSD_STRUCTURE bits | SDSC=0, SDHC/SDXC=1 |
| TRAN_SPEED in range ($32-$5A) | Byte 3 of CSD | $32=25MHz, $5A=50MHz |
| Capacity > 0 | `cardSizeSectors()` | Card has space |
| CSD capacity matches cardSizeSectors() | C_SIZE calculation vs API | Both paths agree |
| Works via initCardOnly path | Unmount, initCardOnly, readCSD | Register access without filesystem |

**Group 2: Timeout Values** (4 tests)

| Test | What We Verify | Why |
|------|----------------|-----|
| getReadTimeout() 50-500ms | Reasonable range | Not too fast or slow |
| getWriteTimeout() 100-1000ms | Reasonable range | Write needs more time |
| Write timeout >= read timeout | writeTimeout >= readTimeout | Spec requirement |
| TRAN_SPEED matches getCardMaxSpeed() | Cross-check CSD byte vs API | Parsing consistency |

---

### 4.15 SD_RT_speed_tests.spin2 (~14 tests)

**Purpose:** Validate the speed control and CMD6 high-speed mode APIs — SPI frequency management, card speed detection, and high-speed mode switching.

**Why we test this:** The speed API controls the SPI clock frequency and enables 50 MHz high-speed mode via CMD6. Incorrect frequency calculation produces communication failures. CMD6 mode switching is a complex protocol that can leave the card in an inconsistent state if not done correctly.

**Pragmas:** `SD_INCLUDE_SPEED`, `SD_INCLUDE_REGISTERS`

#### Test Groups

**Group 1: Always-Available Speed** (5 tests)

| Test | What We Verify | Why |
|------|----------------|-----|
| getSPIFrequency() ~25MHz after mount | 20-30 MHz range | Default speed correct |
| getCardMaxSpeed() 25M-50M | Valid range | CSD TRAN_SPEED parsed |
| isHighSpeedActive() false at 25MHz | Returns false | Not in HS mode yet |
| setSPISpeed() changes frequency | Set 20MHz, verify | Frequency update works |
| Data integrity at 20MHz | Write+read pattern at 20MHz | No corruption at non-default speed |

**Group 2: CMD6/High-Speed** (5 tests)

| Test | What We Verify | Why |
|------|----------------|-----|
| checkCMD6Support() returns boolean | true or false (not error) | API doesn't crash |
| checkHighSpeedCapability() returns boolean | true or false | Card capability query works |
| attemptHighSpeed() consistent with isHighSpeedActive() | State matches result | No inconsistency |
| Data integrity after HS attempt | Write+read pattern | No corruption from mode switch |
| getSPIFrequency() reflects HS state | >25MHz if HS, <=30MHz if not | Frequency matches mode |

**Group 3: Speed Boundaries** (4 tests)

| Test | What We Verify | Why |
|------|----------------|-----|
| setSPISpeed(400_000) init speed | 300-500 kHz range | Low speed for card init |
| setSPISpeed(25_000_000) standard | 20-30 MHz range | Standard speed restore |
| getReadTimeout() reasonable | 50-500 ms | Timeout from CSD valid |
| getWriteTimeout() reasonable | 100-1000 ms | Write timeout valid |

---

### 4.16 SD_RT_crc_diag_tests.spin2 (~14 tests)

**Purpose:** Validate the CRC diagnostic API — match/mismatch/retry counters, CRC value inspection, validation toggle, and CMD13 status diagnostics.

**Why we test this:** CRC validation is the primary data integrity mechanism for SD SPI communication. The diagnostic counters allow detection of marginal cards (high mismatch rates), flaky connections, or timing issues. The `setCRCValidation()` toggle allows disabling CRC for performance testing. These APIs must work correctly for the driver's self-healing retry mechanism.

**Pragma:** `#PRAGMA EXPORTDEF SD_INCLUDE_DEBUG`

#### Test Groups

**Group 1: CRC Counter Initial State** (4 tests)

| Test | What We Verify | Why |
|------|----------------|-----|
| Match count > 0 after mount | `getCRCMatchCount()` > 0 | Mount reads sectors, generating CRC matches |
| Mismatch count == 0 | `getCRCMismatchCount()` == 0 | Healthy card has no mismatches |
| Retry count == 0 | `getCRCRetryCount()` == 0 | No retries needed on healthy card |
| lastReceivedCRC != 0 | `getLastReceivedCRC()` != 0 | Mount generated CRC values |

**Group 2: CRC Values After Operations** (4 tests)

| Test | What We Verify | Why |
|------|----------------|-----|
| Match count increases after reads | Count before < count after | Read operations check CRC |
| lastCalculatedCRC != 0 | Non-zero after reads | Local CRC computed |
| lastSentCRC != 0 after write | Non-zero after write | Write CRC generated |
| Counters after remount | > 0 after fresh mount | Reset and re-accumulate |

**Group 3: setCRCValidation Toggle** (4 tests)

| Test | What We Verify | Why |
|------|----------------|-----|
| Enabled: count increases on read | Match count grows | CRC checked when enabled |
| Disabled: count unchanged on read | Match count stable | CRC skipped when disabled |
| Reads work with CRC disabled | Data pattern matches | No corruption without CRC |
| Reads work with CRC re-enabled | Data pattern matches | Toggle is reversible |

**Group 4: CMD13 Diagnostic** (2 tests)

| Test | What We Verify | Why |
|------|----------------|-----|
| getLastCMD13() valid | Returns accessible value | R2 response captured |
| getLastCMD13Error() == 0 | No error on healthy card | Error tracking works |

---

### 4.17 SD_RT_subdir_ops_tests.spin2 (18 tests)

**Purpose:** Validate file operations within subdirectories with emphasis on cross-buffer cache coherence, empty file handling, rename operations, and directory navigation round-trips.

**Why we test this:** The driver uses three independent sector caches (BUF_DIR, BUF_FAT, BUF_DATA) that can hold the same physical sector. When `createFileNew()` writes a directory entry via BUF_DIR, the BUF_DATA cache may still hold stale data for that same sector. If `readDirectoryHandle()` subsequently reads via BUF_DATA, it gets a cache hit on stale data and misses the newly created file. This test suite specifically targets this cross-buffer cache coherence scenario, which was the root cause of the "dir shows empty after touch" bug fixed in commit 2062590.

Additionally, earlier regression tests operated primarily in the root directory. Subdirectory operations exercise different code paths (directory entry search in non-root clusters, `.`/`..` navigation, cross-cluster directory enumeration) that root-only tests miss.

#### Test Groups

**Group 1: Empty File Operations (Root)** (4 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| createFileNew() empty file | `createFileNew()` + immediate `closeFileHandle()` | Handle >= 0 | 0-byte file creation works |
| Empty file has size 0 | `openFileRead()` + `fileSizeHandle()` | Size == 0 | Empty file metadata correct |
| deleteFile() empty file | `deleteFile()` | Returns true | Deleting 0-byte file succeeds |
| openFileRead() after delete | `openFileRead()` | Returns E_FILE_NOT_FOUND | Deletion is effective |

**Group 2: Dir After Create (Cache Coherence)** (2 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Dir sees file immediately | `createFileNew()` then `openDirectory()` + enumerate | Count >= 1 | BUF_DATA not stale after BUF_DIR write |
| Second create visible without re-mount | Create two files, enumerate between | Count >= 2 | Repeated cache invalidation works |

**Group 3: Subdirectory File Operations** (5 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| mkdir and cd into subdirectory | `newDirectory()` + `changeDirectory()` | Both succeed | Subdir creation and navigation |
| createFileNew() in subdirectory | `createFileNew()` in non-root dir | Handle >= 0 | File creation in subdir clusters |
| Dir sees file in subdirectory | `openDirectory(@".")` + enumerate | Count >= 3 (., .., file) | Cross-buffer coherence in subdir |
| Second file visible in subdir | Create + enumerate | Count >= 4 | Multi-file subdir enumeration |
| Dir-Create-Dir cache invalidation | Dir, create, dir again | New count > old count | The specific BUF_DATA stale-cache scenario |

**Group 4: Delete in Subdirectory** (4 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Delete empty file in subdir | `deleteFile()` | Returns true | Delete works in non-root dir |
| Deleted file not found | `openFileRead()` | Returns E_FILE_NOT_FOUND | Deletion visible in subdir |
| Delete file with data | `deleteFile()` on file with content | Returns true | Data file deletion in subdir |
| Dir after delete correct count | Enumerate after deletes | Count == 3 (., .., remaining) | Deletion reflected in dir listing |

**Group 5: Rename in Subdirectory** (2 tests)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| Create then rename in subdir | `createFileNew()` + `rename()` | Both succeed | Rename works in non-root dir |
| Renamed file accessible | Old name E_FILE_NOT_FOUND, new name opens | Both conditions | Rename atomicity in subdir |

**Group 6: Cross-Directory Operations** (1 test)

| Test | API Under Test | What We Verify | Why |
|------|---------------|----------------|-----|
| cd .. then cd back preserves contents | `changeDirectory(@"..")` + `changeDirectory(@testdir)` + enumerate | Count >= 3 | Directory context survives navigation round-trip |

---

### 4.18 Supplementary Tests (not in core count)

#### SD_RT_error_handling_tests.spin2

Focused testing of error conditions and edge cases:
- `readHandle(99)` returns E_INVALID_HANDLE
- Read past EOF returns partial data then 0
- `newDirectory()` on existing directory returns false
- `changeDirectory()` to non-existent directory returns false
- Handle slot reuse after close
- Same file open for write AND read simultaneously

#### SD_RT_card_info_tests.spin2

Certification test for struct-based register access — verifies that `sd.cid_t` and `sd.scr_t` struct fields match raw byte access at the same offsets. Tests both unmounted (`initCardOnly`) and mounted paths. Also tests OCR, card size, SPI frequency, MBR read, and ACMD13 SD Status decode (speed class, UHS grade, video class).

#### SD_RT_card_display_test.spin2

End-to-end test of the card info display path as used by the demo shell. Exercises fstr output formatting with real register data.

---

## 5. API Coverage Matrix

This matrix maps every public driver API method to the test file(s) that exercise it.

### 5.1 Lifecycle & Mount

| API Method | mount | file_ops | rw | dir | seek | mcog | mhand | mblk | raw | fmt | subdir | Notes |
|------------|:-----:|:--------:|:--:|:---:|:----:|:----:|:-----:|:----:|:---:|:---:|:------:|-------|
| `start()` | **Y** | | | | | **Y** | | | | | | Singleton verified in mount+mcog |
| `mount()` | **Y** | **Y** | **Y** | **Y** | **Y** | **Y** | **Y** | | | **Y** | **Y** | Every filesystem test |
| `unmount()` | **Y** | | | | | | | | | | | Only mount_tests |
| `initCardOnly()` | | | | | | | | | **Y** | **Y** | | Raw-mode tests |
| `error()` | **Y** | | | | | **Y** | | | | | | Pre-mount + per-cog |

### 5.2 Legacy File Operations

| API Method | mount | file_ops | rw | dir | seek | mcog | mhand | subdir | Notes |
|------------|:-----:|:--------:|:--:|:---:|:----:|:----:|:-----:|:------:|-------|
| `openFile()` | **Y** | **Y** | **Y** | | **Y** | **Y** | | | Multiple test files |
| `newFile()` | **Y** | **Y** | **Y** | **Y** | **Y** | | | | File creation path |
| `closeFile()` | | **Y** | **Y** | | **Y** | **Y** | | | Close + flush |
| `read()` | | **Y** | **Y** | | **Y** | **Y** | | | Core read path |
| `write()` | | **Y** | **Y** | | **Y** | | | | Core write path |
| `readByte()` | | | | | **Y** | | | | Direct position read |
| `writeByte()` | | | **Y** | | | | | | Single byte write |
| `writeString()` | | | **Y** | | | | | | String write |
| `seek()` | | | | | **Y** | | | | Core seek path |
| `fileSize()` | | **Y** | **Y** | | **Y** | | | | Size verification |
| `deleteFile()` | | **Y** | | **Y** | | | | **Y** | File removal (incl. subdir) |
| `rename()` | | **Y** | | | | | | **Y** | Name change (incl. subdir) |
| `moveFile()` | | **Y** | | | | | | | Cross-directory move |

### 5.3 V3 Handle-Based Operations

| API Method | file_ops | rw | mhand | err | vol | subdir | Notes |
|------------|:--------:|:--:|:-----:|:---:|:---:|:------:|-------|
| `openFileRead()` | | **Y** | **Y** | **Y** | | **Y** | Multiple readers, subdir verify |
| `openFileWrite()` | | | **Y** | **Y** | | | Single-writer policy |
| `createFileNew()` | **Y** | **Y** | **Y** | **Y** | **Y** | **Y** | V3 creation (incl. subdir) |
| `closeFileHandle()` | **Y** | **Y** | **Y** | **Y** | **Y** | **Y** | Handle close + flush |
| `readHandle()` | | **Y** | **Y** | **Y** | | | Handle-based read |
| `writeHandle()` | **Y** | **Y** | **Y** | **Y** | **Y** | | Handle-based write |
| `seekHandle()` | | **Y** | **Y** | | | | Handle-based seek |
| `tellHandle()` | | | **Y** | | | | Position query |
| `eofHandle()` | | | **Y** | | | | EOF detection |
| `fileSizeHandle()` | | **Y** | **Y** | | | **Y** | Size via handle (incl. subdir) |
| `syncHandle()` | | | **Y** | | | | Flush without close |
| `syncAllHandles()` | | | | | **Y** | | Bulk flush all write handles |

### 5.4 Directory Operations

| API Method | dir | mhand | err | dirh | vol | subdir | Notes |
|------------|:---:|:-----:|:---:|:----:|:---:|:------:|-------|
| `newDirectory()` | **Y** | | **Y** | | **Y** | **Y** | Directory creation (incl. subdir) |
| `changeDirectory()` | **Y** | | **Y** | **Y** | | **Y** | Navigation (incl. subdir round-trip) |
| `readDirectory()` | **Y** | | | | **Y** | | Legacy enumeration |
| `openDirectory()` | | | | **Y** | | **Y** | V3 handle enum (incl. subdir cache) |
| `readDirectoryHandle()` | | | | **Y** | | **Y** | V3 entry iteration (incl. subdir) |
| `closeDirectoryHandle()` | | | | **Y** | | **Y** | V3 handle release |

### 5.5 Card Info

| API Method | mount | card_info | vol | reg | Notes |
|------------|:-----:|:---------:|:---:|:---:|-------|
| `cardSizeSectors()` | **Y** | **Y** | | **Y** | Size in sectors |
| `volumeLabel()` | **Y** | | **Y** | | Label string |
| `setVolumeLabel()` | | | **Y** | | Set volume label |
| `freeSpace()` | **Y** | | | | Free sector count |
| `getSPIFrequency()` | **Y** | **Y** | | | SPI clock readback |
| `getManufacturerID()` | | **Y** | | | CID.MID |
| `getOCR()` | | **Y** | | | OCR register |

### 5.6 Register Access [SD_INCLUDE_REGISTERS]

| API Method | card_info | reg | vol | Notes |
|------------|:---------:|:---:|:---:|-------|
| `readCIDRaw()` | **Y** | | | CID into struct |
| `readCSDRaw()` | | **Y** | | CSD register access |
| `readSCRRaw()` | **Y** | | | SCR into struct |
| `readSDStatusRaw()` | **Y** | | | ACMD13 64-byte status |
| `readVBRRaw()` | | | **Y** | Volume Boot Record read |

### 5.7 Raw Sector Operations [SD_INCLUDE_RAW]

| API Method | mblk | raw | fmt | Notes |
|------------|:----:|:---:|:---:|-------|
| `readSectorRaw()` | **Y** | **Y** | **Y** | Single sector read |
| `writeSectorRaw()` | **Y** | **Y** | | Single sector write |
| `readSectorsRaw()` | **Y** | | | Multi-block read (CMD18) |
| `writeSectorsRaw()` | **Y** | | | Multi-block write (CMD25) |

### 5.8 Speed & High-Speed Mode [SD_INCLUDE_SPEED]

| API Method | speed | reg | Notes |
|------------|:-----:|:---:|-------|
| `attemptHighSpeed()` | **Y** | | HS mode switch with verification |
| `setSPISpeed()` | **Y** | | Frequency change + data integrity check |
| `getSPIFrequency()` | **Y** | | Tested in mount, card_info, speed |
| `getCardMaxSpeed()` | **Y** | **Y** | CSD TRAN_SPEED cross-check |
| `isHighSpeedActive()` | **Y** | | HS state query |
| `checkCMD6Support()` | **Y** | | CMD6 availability check |
| `checkHighSpeedCapability()` | **Y** | | HS capability query |
| `getReadTimeout()` | **Y** | **Y** | Timeout from CSD |
| `getWriteTimeout()` | **Y** | **Y** | Timeout from CSD |

### 5.9 State Management

| API Method | vol | Notes |
|------------|:---:|-------|
| `setDate()` | **Y** | Timestamp on files and directories |
| `sync()` | **Y** | Legacy flush API |
| `syncDirCache()` | **Y** | Used implicitly in file_ops, dir tests |

### 5.10 Diagnostic Methods [SD_INCLUDE_DEBUG]

| API Method | crc | Notes |
|------------|:---:|-------|
| `getLastCMD13()` | **Y** | R2 status response |
| `getLastCMD13Error()` | **Y** | Last non-zero error |
| `getLastReceivedCRC()` | **Y** | CRC from card |
| `getLastCalculatedCRC()` | **Y** | CRC computed locally |
| `getLastSentCRC()` | **Y** | CRC sent to card |
| `getCRCMatchCount()` | **Y** | Successful matches |
| `getCRCMismatchCount()` | **Y** | Failed matches |
| `getCRCRetryCount()` | **Y** | Retry count |
| `setCRCValidation()` | **Y** | Enable/disable toggle |
| `getWriteDiag()` | | Debug-only; tested manually |
| `debugDumpRootDir()` | | Debug utility — not testable |
| `debugClearRootDir()` | **Y** | Used in test setup |

---

## 6. Coverage Gap Analysis

### 6.1 Critical Gaps — RESOLVED

All critical gaps identified in the original analysis have been addressed:

| Gap | Resolution | Test File |
|-----|-----------|-----------|
| **V3 Directory Handle API** | ~22 tests covering enumeration, handle limits, error cases, path handling | `SD_RT_dirhandle_tests.spin2` |
| **syncAllHandles()** | 4 tests: no handles, single write, multiple writes, mixed read/write | `SD_RT_volume_tests.spin2` |
| **setVolumeLabel()** | 5 tests: set, read back, max length, persist through remount, restore | `SD_RT_volume_tests.spin2` |
| **readCSDRaw()** | 6 tests: raw read, version, TRAN_SPEED, capacity, cross-check, initCardOnly path | `SD_RT_register_tests.spin2` |
| **readVBRRaw()** | 4 tests: read, boot signature, bytes-per-sector, OEM name | `SD_RT_volume_tests.spin2` |

### 6.2 Important Gaps — RESOLVED

| Gap | Resolution | Test File |
|-----|-----------|-----------|
| **Speed/CMD6 API** | ~14 tests: frequency get/set, CMD6 query, HS mode, data integrity, boundaries | `SD_RT_speed_tests.spin2` |
| **setDate()** | 5 tests: timestamp on file, epoch boundary, end-of-day, V3 path, directory | `SD_RT_volume_tests.spin2` |
| **sync() (legacy)** | 2 tests: flush legacy write, no file open | `SD_RT_volume_tests.spin2` |
| **CRC diagnostic API** | ~14 tests: counters, CRC values, validation toggle, CMD13 | `SD_RT_crc_diag_tests.spin2` |
| **Large file multi-cluster** | 9 tests: 128KB, 256KB, seek across clusters, backward seek, delete reclaims | `SD_RT_read_write_tests.spin2` |

### 6.3 Remaining Low Priority Gaps

| Gap | Missing Coverage | Notes |
|-----|-----------------|-------|
| **getWriteDiag()** | Write operation diagnostic | Debug-only; tested manually during development |
| **Long Filename (LFN) support** | Driver doesn't support LFN | Not a gap — feature not implemented |
| **File attributes (read-only, hidden)** | `attributes()` partially tested | Low priority — 8.3 FAT32 attributes rarely used on embedded |

### 6.4 Structural Gaps

| Area | Current State | Improvement |
|------|---------------|-------------|
| **Error recovery** | Tests verify error codes are returned but don't test recovery paths (retry, remount after error) | Add test: force error condition, verify driver recovers |
| **Concurrent write safety** | Multi-handle tests verify single-writer policy, but don't test what happens if policy is bypassed | Low risk — policy is enforced at API level |
| **Card ejection** | No hot-plug testing | Hardware-dependent; manual test only |
| **Filesystem corruption tolerance** | No tests for mounting a corrupted card | Could add test: write corrupt VBR, verify mount fails gracefully |

---

## 7. Test Count Summary

### 7.1 Original Core Suite (236 tests — verified passing)

| Test File | Tests | Status |
|-----------|:-----:|:------:|
| SD_RT_mount_tests | 21 | 21 pass |
| SD_RT_file_ops_tests | 22 | 22 pass |
| SD_RT_read_write_tests | 29 | 29 pass |
| SD_RT_directory_tests | 28 | 28 pass |
| SD_RT_seek_tests | 37 | 37 pass |
| SD_RT_multicog_tests | 14 | 14 pass |
| SD_RT_multihandle_tests | 19 | 19 pass |
| SD_RT_multiblock_tests | 6 | 6 pass |
| SD_RT_raw_sector_tests | 14 | 14 pass |
| SD_RT_format_tests | 46 | 46 pass |
| **Subtotal** | **236** | **236 pass** |

### 7.2 New Coverage Gap Tests (est. ~89 tests — pending hardware verification)

| Test File | Est. Tests | Status |
|-----------|:----------:|:------:|
| SD_RT_read_write_tests (+large file) | +9 | Compiles, pending run |
| SD_RT_dirhandle_tests | ~22 | Compiles, pending run |
| SD_RT_volume_tests | ~20 | Compiles, pending run |
| SD_RT_register_tests | ~10 | Compiles, pending run |
| SD_RT_speed_tests | ~14 | Compiles, pending run |
| SD_RT_crc_diag_tests | ~14 | Compiles, pending run |
| **Subtotal** | **~89** | **pending** |

### 7.3 Combined Total

| | Tests | Status |
|--|:-----:|:------:|
| **Grand Total** | **~325** | **236 verified + ~89 pending** |

*Supplementary: error_handling, card_info, card_display tests provide additional coverage outside the core count.*

---

## 8. Running the Tests

All tests run from the `tools/` directory:

```bash
cd /path/to/P2-uSD-Study/tools

# Original core tests
./run_test.sh ../regression-tests/SD_RT_mount_tests.spin2
./run_test.sh ../regression-tests/SD_RT_file_ops_tests.spin2
./run_test.sh ../regression-tests/SD_RT_read_write_tests.spin2
./run_test.sh ../regression-tests/SD_RT_directory_tests.spin2
./run_test.sh ../regression-tests/SD_RT_seek_tests.spin2
./run_test.sh ../regression-tests/SD_RT_multicog_tests.spin2 -t 120
./run_test.sh ../regression-tests/SD_RT_multihandle_tests.spin2
./run_test.sh ../regression-tests/SD_RT_multiblock_tests.spin2
./run_test.sh ../regression-tests/SD_RT_raw_sector_tests.spin2
./run_test.sh ../regression-tests/SD_RT_format_tests.spin2 -t 300   # WARNING: erases card

# New coverage gap tests
./run_test.sh ../regression-tests/SD_RT_dirhandle_tests.spin2
./run_test.sh ../regression-tests/SD_RT_volume_tests.spin2 -t 180
./run_test.sh ../regression-tests/SD_RT_register_tests.spin2
./run_test.sh ../regression-tests/SD_RT_speed_tests.spin2
./run_test.sh ../regression-tests/SD_RT_crc_diag_tests.spin2

# Supplementary tests
./run_test.sh ../regression-tests/SD_RT_error_handling_tests.spin2
./run_test.sh ../regression-tests/SD_RT_card_info_tests.spin2
./run_test.sh ../regression-tests/SD_RT_card_display_test.spin2
```

**Requirements:**
- P2 Edge board connected via PropPlug USB
- SD card inserted in P2 Edge SD slot
- `pnut-ts` and `pnut-term-ts` installed and on PATH
- Format tests require a disposable card (all data erased)
- Multicog tests need `-t 120` (2-minute timeout for worker cog synchronization)

---

*Document updated: 2026-02-18*
*Based on: micro_sd_fat32_fs.spin2 (100+ public methods, 46 worker cog commands)*
*Test suite: 15 core files, ~325 assertions, 3 supplementary files*
