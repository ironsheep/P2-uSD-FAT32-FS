# Measuring Program Memory Consumption with pnut-ts

A practical guide to determining how much hub RAM your Spin2 program and its component objects consume -- code space, data space, variable space, and total runtime footprint -- using the pnut-ts compiler's `-m` (map) and `-l` (listing) output files.

- **Compiler**: pnut-ts v1.52.2+
- **Author**: Stephen M. Moraco, Iron Sheep Productions, LLC

---

## Table of Contents

1. [Background: P2 Hub RAM and Spin2 Object Layout](#1-background-p2-hub-ram-and-spin2-object-layout)
2. [Generating Map and Listing Files](#2-generating-map-and-listing-files)
3. [Reading the Map File](#3-reading-the-map-file)
4. [Reading the Listing File](#4-reading-the-listing-file)
5. [Calculating Total Runtime Hub RAM](#5-calculating-total-runtime-hub-ram)
6. [Comparing Build Configurations](#6-comparing-build-configurations)
7. [Analyzing a Multi-Object Program](#7-analyzing-a-multi-object-program)
8. [Sizing Audit Methodology](#8-sizing-audit-methodology)
9. [Quick Reference](#9-quick-reference)

---

## 1. Background: P2 Hub RAM and Spin2 Object Layout

The Propeller 2 has **512 KB of hub RAM**. Every Spin2 program must fit within this space along with its runtime data. Understanding what consumes that space is critical for larger projects.

A compiled Spin2 program consists of three memory regions loaded into hub RAM:

| Region | Contents | When Allocated |
|---|---|---|
| **Code/Data** | Method table + DAT sections + Spin2 bytecodes, for all objects | At load time (fixed) |
| **VAR** | Instance variables declared in `VAR` blocks, for all object instances | At load time (fixed) |
| **Stack** | Call stack for each running COG (not in the binary) | At runtime |

The **binary file** (.bin) includes the code/data region plus a ~6 KB P2 loader stub. The VAR region is not stored in the binary -- it is allocated in hub RAM at load time immediately following code/data.

### Object Structure Within Code/Data

Each Spin2 object occupies a contiguous block within the code/data region:

```
+-------------------+
| Method Table      |  N entries x 4 bytes (method count + 1 for header)
+-------------------+
| DAT Section       |  Static data: buffers, constants, PASM, state variables
+-------------------+
| Bytecodes         |  Compiled Spin2 method bodies
+-------------------+
```

Objects are concatenated in the binary in the order the compiler encounters them during OBJ resolution. The top-level object comes first, followed by its children recursively.

---

## 2. Generating Map and Listing Files

The pnut-ts compiler has two diagnostic output flags:

| Flag | Output File | Purpose |
|---|---|---|
| `-m` | `.map` | Memory map: object hierarchy, memory layout, per-object details (methods, DAT variables, VAR variables, sizes) |
| `-l` | `.lst` | Listing: symbol table (constants, method names, struct definitions with values) |

### Basic Usage

```bash
# Generate map file alongside the binary
pnut-ts -m my_program.spin2

# Generate both map and listing
pnut-ts -l -m my_program.spin2

# With include paths and preprocessor defines
pnut-ts -m -I ../src/ -I ../src/UTILS/ -D SD_INCLUDE_ALL my_program.spin2

# With debug enabled (adds debug records -- larger binary)
pnut-ts -m -d my_program.spin2
```

The output files are written next to the source file:
- `my_program.map`
- `my_program.lst`
- `my_program.bin`

### Analyzing a Driver or Library Object in Isolation

To measure a library object's footprint without any consumer program, compile it as top-level. Most library objects have a `PUB null()` placeholder method as entry point 0, which allows standalone compilation:

```bash
# Driver alone -- minimal build (no optional features)
pnut-ts -m src/micro_sd_fat32_fs.spin2

# Driver alone -- full build (all optional features)
pnut-ts -m -D SD_INCLUDE_ALL src/micro_sd_fat32_fs.spin2
```

This tells you the object's intrinsic size before any consumer adds its own code.

---

## 3. Reading the Map File

The map file (`.map`) is the primary tool for memory analysis. It has five sections.

### 3.1 Program Summary

```
=== PROGRAM SUMMARY ===

  Total Size:    28068 bytes (27896 code/data + 172 var bytes)
  Objects:       4
  Methods:       246
```

This is your top-level answer: **total hub RAM consumed** = code/data + VAR. The binary file will be larger than the code/data value because it includes the P2 loader stub (~6 KB).

### 3.2 Object Hierarchy

```
=== OBJECT HIERARCHY ===

  SD_RT_mount_tests  (1 methods)
      +-- SD : micro_sd_fat32_fs  (205 methods)
      |   \-- STACKUTILS : isp_rt_utilities  (30 methods)
      \-- UTILS : isp_stack_check  (10 methods)
```

This shows the tree of objects, their instance names, and how many methods each contributes. Use this to understand which objects are included and their nesting.

### 3.3 Memory Layout

```
=== MEMORY LAYOUT ===

  Start   End      Size  Object           Instance         Overrides
  ------  ------  -----  ---------------  ---------------  ---------
  $00000  $00D69   3434  SD_RT_mount_tests  (entry)
  $00D6C  $06817  23212  micro_sd_fat32_fs  SD
  $06818  $0693A    291  isp_stack_check  UTILS
  $0693C  $06CF7    956  isp_rt_utilities  STACKUTILS

    CODE/DATA TOTAL:   27896 bytes

  $06CF8  $06DA3    172  VAR SPACE        (runtime)

    PROGRAM TOTAL:     28068 bytes
```

This is the key table. It shows:
- **Address range** (`Start` to `End`) of each object within hub RAM
- **Size** of each object in bytes (code + DAT combined)
- The **VAR SPACE** line shows total runtime variable allocation across all objects

From this table you can immediately answer: "How much space does object X add to my program?" For example, the SD driver adds 23,212 bytes of code/data.

### 3.4 Object Details

Each object gets a detailed breakdown:

#### Methods Section

```
--- SD : micro_sd_fat32_fs ---
    Location: $00D6C-$06817 (23212 bytes)
    VAR Base: $06CFC
    Source:   micro_sd_fat32_fs.spin2

    Methods:
      NULL                  Entry $00002  ($00D6E)
      START                 Entry $00003  ($00D6F)
      STOP                  Entry $00004  ($00D70)
      MOUNT                 Entry $00005  ($00D71)
      ...
```

- **Location**: absolute address range and total size (code + DAT)
- **VAR Base**: where this object's VAR variables start in hub RAM
- **Entry numbers**: each method's index in the method table
- **Absolute addresses** (in parentheses): hub address of each method's entry in the table

#### DAT Section

```
    DAT:
      LONG      COG_ID                +$00340  ($010AC)
      LONG      API_LOCK              +$00344  ($010B0)
      BYTE      DIR_BUF               +$00773  ($014DF)
      BYTE      FAT_BUF               +$00973  ($016DF)
      BYTE      BUF                   +$00B73  ($018DF)
      BYTE      H_BUF                 +$00E47  ($01BB3)
      LONG      H_BUF_SECTOR          +$01A47  ($027B3)
```

Each DAT variable shows:
- **Type** (`LONG`, `WORD`, `BYTE`)
- **Name** (the label from your source code)
- **Relative offset** (`+$xxxx`) within the object
- **Absolute address** (`($xxxx)`) in hub RAM

To calculate the size of a DAT variable, subtract its offset from the next variable's offset. For arrays and buffers, this reveals their actual footprint:

```
H_BUF    at +$00E47
H_BUF_SECTOR at +$01A47
  => H_BUF size = $01A47 - $00E47 = $0C00 = 3,072 bytes (6 handles x 512 bytes)
```

#### VAR Section

```
--- STACKUTILS : isp_rt_utilities ---
    VAR:
      LONG      NUMBERTESTS           +$0004  ($063A4)
      LONG      SUBTESTPER            +$0008  ($063A8)
      LONG      PASSCOUNT             +$000C  ($063AC)
      LONG      FAILCOUNT             +$0010  ($063B0)
      BYTE      FILENAME              +$0020  ($063C0)
```

VAR variables use the same format as DAT. These consume runtime hub RAM but are NOT stored in the binary file.

#### Inline PASM Labels

```
    PASM Labels:
      ENTRY_BUFFER          COG $003  HUB $008D4

    Inline PASM:
      WAITRX'0100           +$00A  ($008F0)
```

If your object contains inline PASM (`org / end`), the map shows COG-space labels and inline PASM block locations. These don't add extra hub RAM -- the PASM is part of the bytecode/DAT already accounted for.

### 3.5 Address Index

```
=== ADDRESS INDEX ===

  Address  Type      Object           Name
  -------  --------  ---------------  ---------------
   $00000  CODE      SD_RT_mount_tests  (entry)
   $00000  METHOD    micro_sd_fat32_fs  NULL
   $00001  METHOD    micro_sd_fat32_fs  START
   ...
```

A cross-reference of every symbol by address. Useful for locating a specific symbol when you know its address from a crash dump or debug output, but not essential for sizing analysis.

---

## 4. Reading the Listing File

The listing file (`.lst`) contains the symbol table -- every named constant, method, structure, and object reference with its resolved value.

```
TYPE: CON_INT           VALUE: 14DC9380          NAME: _CLKFREQ
TYPE: CON_INT           VALUE: 0000003C          NAME: SD_CS
TYPE: OBJ               VALUE: 00000000          NAME: SD
TYPE: OBJ               VALUE: 01000001          NAME: UTILS
TYPE: OBJ_CON_INT       VALUE: 00000006          NAME: MAX_OPEN_FILES,01
TYPE: OBJ_CON_INT       VALUE: FFFFFFEC          NAME: E_NOT_MOUNTED,01
TYPE: OBJ_CON_STRUCT    VALUE: 00000003          NAME: DIR_ENTRY_T,01
TYPE: OBJ_PUB           VALUE: 00000013          NAME: MOUNT,01
TYPE: OBJ_PRI           VALUE: 0006F000          NAME: DO_MOUNT,01
```

### Symbol Types

| Type | Meaning |
|---|---|
| `CON_INT` | Integer constant defined in this object's CON block |
| `OBJ` | Child object reference (value encodes instance index) |
| `OBJ_CON_INT` | Constant exported from a child object (suffix `,01` = first child object) |
| `OBJ_CON_STRUCT` | Structure type defined in a child object |
| `OBJ_PUB` | Public method in a child object (value encodes method index + parameter info) |
| `OBJ_PRI` | Private method in a child object |

### When to Use the Listing File

The listing file is less useful for sizing analysis than the map file. Its primary uses are:

- **Verifying constant values**: confirming that preprocessor defines resolved correctly
- **Checking conditional compilation**: if `SD_INCLUDE_RAW` is not in the listing, those methods were excluded
- **Method index lookup**: confirming which method index corresponds to which name (useful when debugging method dispatch)

For memory sizing, the **map file is the primary tool**.

---

## 5. Calculating Total Runtime Hub RAM

The binary file size is NOT your runtime memory footprint. Runtime hub RAM usage is:

```
Runtime Hub RAM = Code/Data + VAR + Stacks
```

The map file gives you the first two directly from the PROGRAM SUMMARY line. Stacks must be accounted for separately.

### Stack Estimation

Every COG running Spin2 code needs a stack. The top-level COG uses the remainder of hub RAM above the program as its stack. Additional COGs launched with `cogspin()` use explicitly allocated stack buffers (typically declared in DAT or VAR).

Look for stack allocations in the map's DAT section:

```
LONG      COG_STACK             +$00328  ($00BF0)
LONG      COG_STACK_GUARD       +$005A8  ($00E70)
  => Stack size = $005A8 - $00328 = $0280 = 640 bytes (160 LONGs)
```

### Complete Accounting Example

For a program like `SD_format_card`:

```
Code/Data:           30,904 bytes   (from map: CODE/DATA TOTAL)
VAR:                 33,876 bytes   (from map: VAR SPACE size)
                    ---------
Program Total:       64,780 bytes

P2 Hub RAM:         524,288 bytes   (512 KB)
Available:          459,508 bytes   (for main COG stack + other uses)
```

The large VAR here comes from the format utility's 32 KB zero-fill buffer. This is why VAR analysis matters -- a single large buffer in VAR can dominate your memory budget.

---

## 6. Comparing Build Configurations

To measure the cost of optional features, generate map files for each configuration and compare:

```bash
# Minimal build
pnut-ts -m src/micro_sd_fat32_fs.spin2
# => Total Size: 20,816 bytes (20,812 code/data + 4 var bytes), 148 methods

# Full build
pnut-ts -m -D SD_INCLUDE_ALL src/micro_sd_fat32_fs.spin2
# => Total Size: 24,060 bytes (24,056 code/data + 4 var bytes), 222 methods
```

Comparison:

| | Minimal | Full | Delta |
|---|---|---|---|
| Methods | 148 | 222 | +74 |
| Code/Data | 20,812 B | 24,056 B | +3,244 B |
| VAR | 4 B | 4 B | +0 B |

The DAT section is identical in both builds (data doesn't change). Only method table entries and bytecodes are added by optional features. This tells you the conditional compilation gates affect only code, not static data.

---

## 7. Analyzing a Multi-Object Program

Real programs include multiple objects. The map file shows each object's contribution:

```
=== MEMORY LAYOUT ===

  Start   End      Size  Object             Instance
  ------  ------  -----  -----------------  ---------
  $00000  $00D69   3434  SD_RT_mount_tests  (entry)
  $00D6C  $06817  23212  micro_sd_fat32_fs  SD
  $06818  $0693A    291  isp_stack_check    UTILS
  $0693C  $06CF7    956  isp_rt_utilities   STACKUTILS

    CODE/DATA TOTAL:   27896 bytes

  $06CF8  $06DA3    172  VAR SPACE          (runtime)

    PROGRAM TOTAL:     28068 bytes
```

### Per-Object Breakdown

To understand where your memory is going, extract each object's contribution:

| Object | Code/Data | % of Total |
|---|---|---|
| SD_RT_mount_tests (top-level) | 3,434 B | 12.3% |
| micro_sd_fat32_fs (driver) | 23,212 B | 83.2% |
| isp_stack_check (stack checker) | 291 B | 1.0% |
| isp_rt_utilities (test framework) | 956 B | 3.4% |
| **Total** | **27,896 B** | **100%** |

This immediately shows that the driver dominates the code/data budget. If you need to reduce program size, the driver is where to look (or use a minimal build configuration).

### VAR Contributions

The Object Details section shows each object's VAR variables. To find which object owns the most VAR space, check the VAR Base addresses:

```
SD_RT_mount_tests:   VAR Base: $06CF8
micro_sd_fat32_fs:   VAR Base: $06CFC   (= $06CF8 + 4 bytes for top-level)
isp_stack_check:     VAR Base: $06D04   (= $06CFC + 8 bytes for driver)
isp_rt_utilities:    VAR Base: $06D04   (= $06D04 + 0 bytes for stack checker)
                     VAR End:  $06DA3   (= $06D04 + 160 bytes for utilities)
```

So: top-level = 4 B, driver = 8 B, stack checker = 0 B, utilities = 160 B of VAR.

---

## 8. Sizing Audit Methodology

This section describes the process used to produce the [Driver Memory Footprint Analysis](../Plans/DRIVER-MEMORY-FOOTPRINT.md) for this project. Follow this methodology to audit any Spin2 project.

### Step 1: Isolate the Object Under Study

Compile the object standalone (as top-level) to measure its intrinsic footprint without consumer overhead:

```bash
# Minimal configuration
pnut-ts -m my_driver.spin2

# Full configuration (all optional features)
pnut-ts -m -D MY_INCLUDE_ALL my_driver.spin2
```

Record from the PROGRAM SUMMARY:
- Total code/data size
- Method count
- VAR size

### Step 2: Extract Region Sizes from the Map

Open the map file and calculate each region's size from the Object Details section. For a single-object build, the regions within the object are:

- **Method table**: from `$00000` to the first DAT variable's offset. Size = first DAT offset.
- **DAT section**: from first DAT variable to start of bytecodes. Calculate by subtracting first DAT offset from the bytecode start (which is method table size + DAT size up to the object's Location end minus bytecodes).
- **Bytecodes**: the remainder of the object after method table + DAT.

For a more direct approach: since the map shows every DAT variable with its offset, the DAT section spans from the first DAT variable's offset to the last DAT variable's offset plus that variable's size. Method table size = first DAT offset. Bytecodes = object total - method table - DAT.

### Step 3: Itemize the DAT Section

Walk the DAT variables in the map file. For each variable, compute its size by subtracting its offset from the next variable's offset:

```
COG_STACK        +$00310
COG_STACK_GUARD  +$00510
  => COG_STACK is $0200 = 512 bytes
```

Group variables into logical categories (buffers, state, pin config, etc.) and total each category. This reveals which categories dominate.

### Step 4: Measure Real-World Programs

Compile several representative consumer programs that include the object and record their map summaries. This shows the object's impact in context:

```bash
pnut-ts -m -I ../src/ my_app.spin2
```

For each program, record:
- Total binary size (.bin file)
- Code/Data total (from map)
- VAR total (from map)
- Runtime hub RAM = Code/Data + VAR

### Step 5: Compare Configurations

If the object supports conditional compilation, compile each configuration and tabulate the differences. This answers: "What does enabling feature X cost?"

### Step 6: Automate for Repeatability

For projects with many programs, create a benchmark script that compiles all top-level files and records size, checksum, and compile time. See `tools/archive/compiler_benchmark.sh` in this project for a working example that benchmarks 34 programs across 5 categories.

The script pattern:

```bash
# For each source file:
pnut-ts [flags] "$filename"
size=$(wc -c < "$binfile")
md5=$(md5 -q "$binfile")    # or md5sum on Linux
```

This produces a repeatable baseline. When you upgrade the compiler or refactor code, re-run the benchmark and diff against the previous run to detect size changes or binary drift.

### Artifacts Produced by This Project's Audit

| Artifact | Location | Purpose |
|---|---|---|
| Memory footprint analysis | `DOCs/Plans/DRIVER-MEMORY-FOOTPRINT.md` | Complete driver sizing: regions, DAT breakdown, real-world programs |
| Compiler benchmark script | `tools/archive/compiler_benchmark.sh` | Automated sizing of all 34 project programs |
| Benchmark results (v1.52.2) | `tools/archive/compiler_benchmark_v1.52.2_260227-154237.txt` | Size + checksum + time for every program |
| Benchmark results (v1.52.1) | `tools/archive/compiler_benchmark_v1.52.1_260227-153636.txt` | Prior baseline for comparison |
| Compiler validation | `DOCs/Plans/COMPILER-BENCHMARK-VALIDATION.md` | Proof that v1.52.2 produces identical binaries 2x faster |
| Handle design exploration | `DOCs/Analysis/DESIGN-EXPLORATION-FILE-HANDLES.md` | Memory trade-off analysis for handle architecture |

---

## 9. Quick Reference

### Generate Files

```bash
pnut-ts -m program.spin2           # Map file only
pnut-ts -l -m program.spin2        # Map + listing
pnut-ts -m -D FLAG program.spin2   # Map with preprocessor define
pnut-ts -m -d program.spin2        # Map with debug enabled
```

### Key Map File Sections

| Section | What It Tells You |
|---|---|
| PROGRAM SUMMARY | Total size = code/data + VAR |
| OBJECT HIERARCHY | Which objects are included and their nesting |
| MEMORY LAYOUT | Per-object code/data size and address ranges |
| Object Details: Methods | Every method name and entry index |
| Object Details: DAT | Every DAT variable with offset and absolute address |
| Object Details: VAR | Every VAR variable with offset and absolute address |

### Size Formulas

```
Binary File Size    = Code/Data + P2 Loader Stub (~6 KB)
Runtime Hub RAM     = Code/Data + VAR + Stack allocations
Object Code/Data    = Method Table + DAT Section + Bytecodes
DAT Variable Size   = (next variable offset) - (this variable offset)
Available RAM       = 524,288 - Runtime Hub RAM
```

### What Lives Where

| Spin2 Block | Goes Into | In Binary? | In Map Section |
|---|---|---|---|
| `CON` | Resolved at compile time | No (inlined) | Listing file only |
| `OBJ` | Embedded as child objects | Yes | MEMORY LAYOUT + OBJECT HIERARCHY |
| `PUB` / `PRI` | Method table + bytecodes | Yes | Object Details: Methods |
| `DAT` | Static data in code/data region | Yes | Object Details: DAT |
| `VAR` | Allocated after code/data at load time | No | Object Details: VAR |
