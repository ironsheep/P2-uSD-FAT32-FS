# Defragmentation Feasibility Analysis

**Date**: 2026-03-24
**Status**: Implemented in v1.4.1 (2026-03-25) — Approaches 2A, 2B, 3 + Decisions 1, 2, 3, 5, 6
**Scope**: Three approaches — full defrag utility, contiguous-write mode, single-file defrag method

---

## Background

FAT32 fragmentation occurs when a file's cluster chain is non-contiguous on disk. Our driver uses first-fit linear scan allocation (`allocateCluster()` starts at cluster 2 every time), which means files created after deletions will fill gaps, fragmenting across the disk. The `fsi_nxt_free` hint is read at mount but **never used** as an allocation starting point.

Fragmentation has two costs:
1. **Read/write throughput**: CMD18/CMD25 multi-block transfers only work on contiguous sector ranges. Fragmented files require per-cluster CMD17/CMD24 single-block operations (~30% slower)
2. **Seek cost**: Walking a fragmented FAT chain requires 1 FAT sector read per 128 clusters traversed

---

## What We Have Today

| Capability | Available? | Notes |
|-----------|-----------|-------|
| Read arbitrary sectors | Yes | `readSectorsRaw()`, CMD18 multi-block |
| Write arbitrary sectors | Yes | `writeSectorsRaw()`, CMD25 multi-block |
| Read FAT entries | Yes | `readFat()`, single-sector cache |
| Modify FAT entries | Yes | `allocateCluster()` does this |
| Walk FAT chains | Yes | Used by seek, open-write, readNextSector |
| Read/modify directory entries | Yes | `searchDirectory()`, `dirEntSetStartClus()` |
| Multi-handle concurrent I/O | Yes | 6 handles, independent buffers |
| Hardware CRC validation | Yes | GETCRC on all reads/writes |
| Raw multi-sector DMA | Yes | Streamer-based, ~1.0-1.4 MB/s |
| Journaling / transaction log | No | Sector writes are atomic; multi-sector ops are not |
| Free cluster bitmap | No | Only FSInfo hint + linear scan |
| Background task scheduler | No | Worker cog runs one command at a time |

---

## Approach 1: Full Defrag Utility

**Goal**: Compact all fragmented files on the volume into contiguous cluster chains.

### Algorithm

1. Walk the entire directory tree (recursive), build a list of files with fragment count > 1
2. Sort by fragment count (most fragmented first) or by size (largest first)
3. For each fragmented file:
   a. Count clusters in its chain (walk FAT)
   b. Find a contiguous run of N free clusters
   c. Copy data from old clusters to new clusters (sector by sector)
   d. Rewrite FAT: new chain is contiguous, old clusters marked free
   e. Update directory entry's first-cluster field
4. Update FSInfo sector with corrected free count

### What It Takes

**RAM budget**: The hard constraint. P2 has 512 KB hub RAM. Driver uses ~23 KB. A practical application leaves ~400 KB.

- **File list**: Need to store `{first_cluster, cluster_count, fragment_count, dir_sector, dir_offset}` per file. At 16 bytes/entry, 1000 files = 16 KB. Manageable.
- **Contiguous-run finder**: Must scan FAT for runs of N consecutive free clusters. This requires reading the entire FAT sequentially (for a 32 GB card, `sec_per_fat` ~16K sectors, ~8 MB of FAT data). At ~1 MB/s SPI throughput, that's **~8 seconds per full FAT scan**.
- **No bitmap needed** if we scan FAT linearly looking for runs. A bitmap would be faster for repeated lookups but costs 1 bit per cluster (32 GB / 4 KB clusters = 8M clusters = 1 MB — too large).

**Atomicity and failure recovery**: This is the biggest risk.

Each file relocation involves:
1. Write data to new clusters (many sectors)
2. Update FAT entries (multiple FAT sectors)
3. Update directory entry (one sector)

If power fails between steps 2 and 3, the old directory entry still points to old clusters (now freed), causing data loss. Mitigations:

- **Copy-then-free**: Write new chain first, update directory entry, THEN free old clusters. If power fails after step 3, old clusters are "lost" (orphaned) but the file is intact at the new location. FSCK can recover the orphaned clusters.
- **Defrag marker**: Write a special marker to a hidden file (e.g., `DEFRAG.LOG`) recording `{filename, old_first_cluster, new_first_cluster}` before each move. On next mount, if the marker exists, complete or roll back the interrupted move.

**Cache coherency**: All open handles must be closed or invalidated before defrag. The three DAT caches (`dir_buf`, `fat_buf`, `buf`) plus per-handle buffers all need flushing. Safest approach: require `unmount()` first, then run defrag as a standalone utility (separate `.spin2` program using raw sector access).

**Estimated complexity**: ~600-800 lines of Spin2, plus a standalone utility program.

**Estimated performance**: A 1 GB card with 100 fragmented files averaging 1 MB each = ~100 MB of data movement = ~100 seconds. A 32 GB card could take 15-30 minutes depending on fragmentation level.

### Verdict

**Feasible as a standalone utility program** (not an in-driver method). Would run with the filesystem unmounted, using raw sector access. Similar in concept to running `chkdsk /defrag` — an offline maintenance operation.

**Pros**: Complete solution, handles all files, can optimize cluster layout
**Cons**: Offline operation (filesystem unavailable during defrag), complex failure recovery, long runtime on large cards, significant code investment

---

## Approach 2: Contiguous-Write Mode (Fragmentation Prevention)

**Goal**: When writing a new file, allocate all clusters contiguously so the file is never fragmented.

### Two Sub-Approaches

#### 2A: Pre-allocate contiguous chain (size known in advance)

**API concept**:
```spin2
PUB createFileContiguous(p_path, file_size) : handle
  '' Create a file with a pre-allocated contiguous cluster chain
  '' Fails with E_NO_CONTIGUOUS_SPACE if no run of sufficient length exists
```

**Algorithm**:
1. Calculate clusters needed: `cluster_count := (file_size + bytes_per_cluster - 1) / bytes_per_cluster`
2. Scan FAT for a contiguous run of `cluster_count` free clusters
3. Allocate the entire chain at once (mark all clusters, link them sequentially)
4. Create directory entry with first cluster pointing to the run
5. Subsequent `writeHandle()` calls fill the pre-allocated space — no new allocation needed

**What it takes**:
- **New method**: `findContiguousRun(cluster_count) : first_cluster` — linear FAT scan looking for N consecutive free entries. ~50 lines.
- **New method**: `allocateContiguousChain(first_cluster, count)` — mark N clusters as a linked chain in one pass. ~40 lines.
- **Modified createFileNew path**: Add a `contiguous` variant that pre-allocates. ~30 lines.
- **Modified writeHandle path**: When the handle was created with pre-allocation, skip `allocateCluster()` on cluster boundaries — just advance to the next sequential cluster. ~10 lines of condition check.

**Constraint**: Caller must know the file size in advance. This is common for embedded use cases (sensor logs with fixed record counts, firmware images, configuration blocks).

**Failure mode**: `E_NO_CONTIGUOUS_SPACE` if the volume is too fragmented to find a long enough run. The caller can fall back to normal (possibly fragmented) write.

**Estimated complexity**: ~150 lines of new Spin2, touches 3-4 existing methods.

#### 2B: Best-fit allocation (reduce fragmentation without guaranteeing contiguous)

**Algorithm change**: Modify `allocateCluster()` to prefer the cluster immediately following the previous allocation (next-fit / sequential allocation).

**What it takes**: One change to `allocateCluster()`:
```spin2
PRI allocateCluster(cluster) : result | fat_idx, ...
  ' Instead of always starting at cluster 2:
  if cluster > 0
    fat_idx := (cluster + 1) << 2    ' Start scanning from cluster+1
  else
    fat_idx := 8                      ' Start at cluster 2 for first allocation
```

This is **6 lines of change**. If cluster N is allocated, the next scan starts at N+1. If N+1 is free, the chain stays contiguous automatically. If not, it falls through to the next free cluster (same as today).

**Impact**: Files written sequentially to a non-fragmented volume will get contiguous clusters. Files written to a fragmented volume still fragment, but less aggressively than today's always-start-at-2 approach.

**Risk**: Low. The only behavioral change is allocation order. All FAT invariants are preserved. The existing test suite would validate correctness.

### Verdict

**2B (next-fit allocation) is a near-zero-cost improvement** — 6 lines of code, immediate benefit, no new API, no failure modes. Should be done regardless of anything else.

**2A (pre-allocate contiguous) is a clean, moderate-effort feature** for use cases where file size is known. ~150 lines, well-defined semantics, graceful failure.

**Pros**: Prevention > cure; no data movement; works online; 2B is nearly free
**Cons**: 2A requires knowing file size upfront; neither helps existing fragmented files

---

## Approach 3: Single-File Defrag Method

**Goal**: An in-driver public method that compacts one specific file into contiguous clusters.

### API Concept

```spin2
PUB compactFile(p_path) : result
  '' Relocate the named file's clusters into a contiguous chain.
  '' File must not be open (no active handles).
  '' Returns: SUCCESS, E_FILE_NOT_FOUND, E_NO_CONTIGUOUS_SPACE, E_FILE_OPEN, E_IO_ERROR

PUB fileFragments(p_path) : fragment_count
  '' Count the number of non-contiguous runs in a file's cluster chain.
  '' Returns: fragment count (1 = not fragmented), or negative error code
```

### Algorithm

```
compactFile("BIGLOG.TXT"):
  1. Verify file is not open (scan h_start_clus[] for match) → E_FILE_OPEN
  2. searchDirectory() to find file → get first_cluster, file_size, dir_sector, dir_offset
  3. Walk FAT chain, count clusters → cluster_count
  4. If already contiguous (fragment_count == 1) → return SUCCESS (no-op)
  5. findContiguousRun(cluster_count) → new_first_cluster, or E_NO_CONTIGUOUS_SPACE
  6. Copy data: for each old cluster, readSectorsRaw() from old, writeSectorsRaw() to new
  7. Build new FAT chain: link new clusters sequentially, mark with EOC at end
  8. Update directory entry: set first cluster to new_first_cluster
  9. Free old clusters: walk old chain, mark each entry as $0000_0000 in FAT
  10. Write FSInfo with updated free count
  11. Invalidate all caches (dir_buf, fat_buf, buf sector tracking vars)
```

### What It Takes

**New internal methods** (~200 lines total):

| Method | Purpose | Est. Lines |
|--------|---------|-----------|
| `findContiguousRun(count)` | Scan FAT for N consecutive free clusters | 50 |
| `allocateContiguousChain(first, count)` | Link N clusters as a chain in FAT | 40 |
| `freeClusterChain(first_cluster)` | Walk chain, mark all clusters free | 30 |
| `countFileFragments(first_cluster)` | Count non-contiguous runs | 25 |
| `copyClusterData(src_cluster, dst_cluster)` | Read+write one cluster's sectors | 20 |
| `invalidateAllCaches()` | Reset all cache tracking vars | 15 |

**New public methods** (~50 lines total):

| Method | Purpose | Est. Lines |
|--------|---------|-----------|
| `compactFile(p_path)` | Orchestrate single-file defrag | 40 |
| `fileFragments(p_path)` | Query fragmentation level | 10 |

**Conditional compilation**: Gate behind `SD_INCLUDE_DEFRAG` flag to keep core build small.

**Cache coherency**: Since the file must not be open, no handle buffers are at risk. The three DAT caches need invalidation after the operation (straightforward — set `*_sec_in_buf := -1`).

**Failure recovery strategy** (copy-then-free):
1. Steps 6-7: New data and new FAT chain written. Old chain still intact. If power fails here: two copies of data exist, old directory entry still valid. Orphaned new clusters recovered by FSCK.
2. Step 8: Directory entry updated. If power fails here: file points to new location, old clusters still allocated. FSCK marks old clusters as orphaned (lost chains).
3. Step 9: Old clusters freed. This is the safe final step — file is fully relocated.

At no point does the file become unreadable. The worst case is orphaned clusters (wasted space, not data loss), recoverable by FSCK.

**Performance**: A 10 MB file with 4 KB clusters = 2,560 clusters:
- FAT chain walk: ~20 FAT sector reads = ~50 ms
- Find contiguous run: 1 FAT scan pass = ~2-8 seconds (depends on card size)
- Data copy: 10 MB at ~1.2 MB/s = ~8 seconds
- FAT rewrite: ~20 sectors = ~50 ms
- **Total: ~10-16 seconds for a 10 MB file**

### Verdict

**Highly feasible and the best bang-for-buck option.** ~250 lines of new code, clean API, safe failure mode, works with the filesystem mounted (just not with the target file open). Pairs naturally with the `fileFragments()` query so users can check before deciding to compact.

---

## Comparison Matrix

| Criterion | Full Defrag Utility | Contiguous Write (2A+2B) | Single-File Defrag |
|-----------|-------------------|------------------------|-------------------|
| **Code complexity** | ~800 lines + utility program | ~150 lines (2A) + ~6 lines (2B) | ~250 lines |
| **Handles existing fragmentation** | Yes (all files) | No (prevention only) | Yes (one file at a time) |
| **Prevents future fragmentation** | No | Yes | No |
| **Requires filesystem offline** | Yes (unmount first) | No | No (file must not be open) |
| **RAM overhead** | ~16 KB file list | None | None |
| **Failure recovery complexity** | High (needs defrag log) | None | Low (copy-then-free) |
| **Runtime** | Minutes to hours | Zero overhead | Seconds per file |
| **New conditional flag** | N/A (standalone utility) | None (2B) / `SD_INCLUDE_DEFRAG` (2A) | `SD_INCLUDE_DEFRAG` |
| **User must know file size** | No | Yes (2A) / No (2B) | No |
| **Testing complexity** | High | Low | Medium |

---

## Recommendations

### Do First: Approach 2B (next-fit allocation fix)

Six lines of code. Immediate improvement to allocation locality. No new API, no new flags, no risk. This should go in regardless — it's a bug fix more than a feature (the current always-start-at-cluster-2 behavior is unnecessarily pessimal).

### Do Second: Approach 3 (single-file defrag)

Best cost/benefit ratio. ~250 lines, clean API, safe failure semantics. Gives users a tool to fix fragmentation on specific files that matter to them (large log files, frequently-rewritten configs). Gate behind `SD_INCLUDE_DEFRAG`.

### Do Third (if needed): Approach 2A (contiguous pre-allocation)

Worth adding if users have the "write a known-size file" pattern. Shares infrastructure with Approach 3 (`findContiguousRun`, `allocateContiguousChain`). Low incremental cost once Approach 3 is done.

### Defer: Approach 1 (full defrag utility)

High effort, offline-only, complex failure recovery. The combination of 2B + 3 covers most practical needs. A full defrag utility is a separate project, not a driver feature.

---

## Dominant Use Case

**Boot file defragmentation**: The P2 boot ROM requires the boot file (`_BOOT_P2.BIX` or similar) to be stored in contiguous sectors on the SD card. After replacing a boot file (e.g., firmware update), the new file may land in fragmented clusters, causing boot failure. The user needs a way to ensure the boot file is contiguous after replacement.

This makes `compactFile()` the critical feature — called on the boot file after each firmware update to guarantee contiguous storage.

---

## Decisions (2026-03-24)

1. **`compactFile()` runs as a worker-cog command.** Keeps SPI ownership clean. Blocking the caller during compaction is acceptable — this is a maintenance operation, not a hot path.

2. **Add `fileFragments()` to the FSCK audit.** The audit already walks all FAT chains, so fragmentation counting is nearly free. Useful diagnostic output.

3. **Persist the next-fit hint across mount/unmount.** Update `fsi_nxt_free` in FSInfo at unmount time. Currently read but never written back.

4. **Minimum fragment threshold: TBD.** Leave this open for now. The boot file use case always wants fragment_count == 1 regardless of how many fragments exist, so any fragmentation warrants compaction for that case.

---

## Decisions (continued)

5. **`compactFile()` must verify data integrity after relocation.** Read-back and compare after the move. A corrupted boot file bricks the device — the cost of doubling I/O time is nothing compared to that risk. This is not optional; it runs every time.

6. **Add `isFileContiguous(p_path)` convenience method.** Returns TRUE/FALSE. Implemented as `fileFragments(p_path) == 1`. Clean API for the boot file check pattern:
   ```spin2
   if not sd.isFileContiguous(@bootFileName)
     sd.compactFile(@bootFileName)
   ```
