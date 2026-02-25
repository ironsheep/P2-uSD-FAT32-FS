# FAT32 File System API Concepts Reference

**Source:** External documentation on standard FAT32 APIs (FatFs, POSIX-style wrappers)
**Purpose:** Reference material showing generic FAT32 operations and concepts
**Date Captured:** January 2026

---

## Overview

Most widely used FAT32 APIs (FatFs, POSIX-style wrappers, etc.) all expose the same logical model: you open directories, iterate entries to walk the tree, then open files and read/write by byte count while the implementation hides the cluster/FAT work.

---

## High-Level Objects and Handles

Most common APIs give you three core handle types:

| Handle Type | Description | Example |
|-------------|-------------|---------|
| **Volume / drive** | Often implicit (e.g. "0:", "/mnt/sd"), selected by mounting | Drive letter or mount point |
| **Directory handle** | Used to enumerate entries in one directory | `DIR*` |
| **File handle** | Used to read/write a specific file | `FIL*` or POSIX `int fd` |

### Typical Internal Structures

**Directory object** holds:
- Current directory cluster
- Current offset within directory
- Sector/cluster buffers

**File object** holds:
- Current file position (byte offset)
- Starting cluster
- Current cluster
- File size
- Sector buffer
- Read/write/dirty flags

---

## Directory Layout and Lookup

### On-Disk Structure

Each directory is a sequence of 32-byte directory entries stored in one or more clusters.

A "normal" (short) directory entry contains:
- 11-byte short name (8.3 format)
- Attributes (directory, system, hidden, etc.)
- Timestamps
- High 16 bits of first cluster
- Low 16 bits of first cluster
- File size

Long file names are stored as one or more special "LFN" entries preceding the short entry.

### Directory Enumeration

To enumerate a directory in a typical API:

1. `opendir(path, &dir)` – resolves path (like "/logs/2026") to a directory cluster and initializes an iterator
2. `readdir(&dir, &info)` – returns one entry at a time (name, size, attributes, start cluster, timestamps)
3. Stop when the returned name is empty / end-of-directory flag

### What readdir Does Internally

For each step:
1. Compute `sector = FirstSectorOfCluster(dir_cluster) + (offset / bytes_per_sector)`
2. Read that sector into a buffer if not already present
3. Index the 32-byte entry inside the sector (`offset % 512` for typical SD)
4. Skip unused/erased entries, assemble long file name if present, return a logical entry

---

## Walking the Directory Tree

To resolve a path like `/foo/bar/baz.txt`:

1. Start at root directory cluster (from boot sector; on FAT32 root is just another cluster chain, typically starting at cluster 2)
2. Split path into components: "foo", "bar", "baz.txt"
3. For "foo":
   - Enumerate root with readdir until you find an entry whose name matches "foo" and has directory attribute set
   - Take its first cluster as the new current directory cluster
4. Repeat for "bar"
5. For "baz.txt": enumerate "bar" directory until you find the file entry, then use its first cluster and size to open a file object

In an embedded-style API this is usually wrapped in `f_open("/foo/bar/baz.txt", flags)` which performs this tree walk internally.

---

## Searching for a Directory or File

### Typical Operations

**Search for a directory "logs" in the root:**
```
opendir("/")
Loop readdir until info.name == "logs" and info.attr & ATTR_DIR
```

**Search for a file "today.log" in "/logs":**
```
opendir("/logs")
Loop readdir until info.name == "today.log" and it is not a directory
```

**Search recursively (e.g. find "config.ini" anywhere):**
- Write a recursive (or stack-based) function
- For each directory, enumerate entries
- For each subdirectory (excluding "." and "..") recurse
- When you hit a matching file name, stop or record the path

### Parameter Shapes

| Operation | Signature |
|-----------|-----------|
| Directory open | `(const char* path, DIR* dir)` or `(DIR* dir, const char* path)` |
| Directory read | `(DIR* dir, FILINFO* info)` where info has `char fname[]`, `DWORD fsize`, `BYTE fattrib`, timestamps |

---

## Mapping to Clusters and the FAT

Once you have a directory entry for a file:

```
first_cluster = (high16 << 16) | low16
```

To find the first data sector of that file:

```
first_sector = data_region_start + (first_cluster - 2) × sectors_per_cluster
```

Where `data_region_start` is computed from boot sector values: `reserved_sectors + FATs × sectors_per_FAT`

### The FAT Region

The FAT region is an array indexed by cluster number:
- `FAT[cluster]` gives the next cluster in the chain or an end-of-chain marker
- To follow a file: start at first_cluster, then repeatedly look up `cluster = FAT[cluster]` until you see EOC

In an API, this is hidden behind read/write calls and an internal cluster cache; you normally never touch the FAT directly.

---

## Logical Read of a File

Assume a 512-byte sector, 8 sectors per cluster (4 KiB clusters). Reading is logically "byte-based":

### Typical Function Shape

```
read(file_handle, void* buf, size_t bytes_to_read, size_t* bytes_read)
```

### Internal Process

For each read:
1. Use the file's current byte offset and cluster size to determine:
   - Which cluster in the chain holds that offset (by stepping through FAT if needed)
   - Which sector within the cluster and which byte offset within the sector
2. If reading less than a sector and the sector is not in RAM: read that sector into a sector buffer
3. Copy `min(remaining_bytes, remaining_in_sector)` from the sector buffer to user buffer
4. If more bytes remain, advance to next sector/cluster and repeat
5. Update file offset and return bytes_read

### Examples

**Read 100 bytes from the start:**
- Implementation reads one 512-byte sector from the first data sector
- Copies 100 bytes to user buffer
- Leaves 412 unused in the internal buffer

**Read 4 KiB + 200 bytes:**
- Implementation walks across one or more full clusters
- Often does full-sector transfers for the aligned portions
- Then a partial sector at the end

From your perspective, you only care about the byte count and the buffer; the library handles sector and cluster boundaries.

---

## Logical Write of a File

### Typical Function Shape

```
write(file_handle, const void* buf, size_t bytes_to_write, size_t* bytes_written)
```

### Common Behavior

For each write:
1. Locate current cluster/sector using file offset and follow FAT as needed
2. If writing full sectors aligned to sector boundaries, it can DMA straight from your buffer to the SD card (fast path)
3. If writing less than a sector (or unaligned):
   - Read the target sector into an internal buffer (if not already present)
   - Modify only the written bytes
   - Mark the buffer dirty
   - Later write back the modified sector to the card (on file close, explicit sync, or when evicting buffers)
4. If the write extends past current file size, it may need to allocate new clusters:
   - Find a free cluster in the FAT
   - Link it at the end of the chain
   - Clear its data to zero (or at least mark it allocated + EOC)
5. Update file size and timestamps
6. Ensure directory entry gets flushed by close or sync

Again, for you it's just: "write N bytes starting at current offset." File offset is often advanced automatically unless you use an explicit seek.

---

## Seeking and Random Access

### Typical API

```
seek(file_handle, new_offset) or lseek(fd, off_t, whence)
```

### Internal Behavior

- If `new_offset` is before current, it restarts at first cluster and walks forward again, counting bytes until reaching that offset
- If `new_offset` is after current, it continues following the FAT chain and counting bytes until the desired offset
- Sets internal state: current cluster, sector index within cluster, byte offset within sector
- You then call read or write as usual

---

## Typical Parameter "Shapes" and Buffers

Putting this into an abstract, language-neutral sketch:

### Mount
```
mount(volume_id, low_level_callbacks, &fs_object)
```
`low_level_callbacks` typically include:
- `read_sector(sector_number, *buf)`
- `write_sector(sector_number, *buf)`
- `get_time()`

### Open Directory
```
opendir(&dir, "/foo/bar")
```
Uses internal path parser and directory walker.

### Read Directory
```
readdir(&dir, &info)
```
Where `info` has:
- `string name`
- `uint32 size_bytes`
- `uint8 attributes` (directory, read-only, etc.)
- `uint32 first_cluster` (may or may not be exposed)
- `timestamps`

### Open File
```
open(&file, "/foo/bar.txt", flags)
```
Where `flags` include bits like READ, WRITE, CREATE_NEW, CREATE_ALWAYS, APPEND.

### Read File
```
read(&file, void* buf, uint32 n, uint32* out_read)
```

### Write File
```
write(&file, const void* buf, uint32 n, uint32* out_written)
```

### Seek
```
seek(&file, uint32 offset) or seek(&file, int32 offset, ORIGIN_CURRENT/START/END)
```

### Close
```
close(&file)
```
Ensures directory entry and FAT are synced to disk.

### Data Buffers

Your code supplies the application buffer for file reads/writes (whatever size you choose).

The FAT32 layer manages:
- One or more 512-byte sector buffers for data region and FAT region
- Possibly separate buffers for directory sectors
- A cluster cache or FAT cache in RAM to avoid re-reading FAT sectors when following cluster chains

---

## Long File Name (LFN) Entries

FAT32 long file names are stored as one or more "LFN entries" immediately followed by a normal 8.3 entry; you reconstruct the name by walking those LFN entries in the right order and concatenating their UTF-16 character fields.

### LFN Entry Structure

Each LFN entry is a 32-byte directory entry with a special layout and attribute `0x0F` so old DOS code ignores it.

| Field | Offset | Description |
|-------|--------|-------------|
| LDIR_Ord | 0 | Sequence number (bits 0-5: order, bit 6: last segment flag) |
| LDIR_Name1 | 1-10 | 5 UTF-16 characters |
| LDIR_Attr | 11 | Must be 0x0F (marks as LFN) |
| LDIR_Type | 12 | 0 |
| LDIR_Chksum | 13 | Checksum of corresponding 8.3 short name |
| LDIR_Name2 | 14-25 | 6 UTF-16 characters |
| LDIR_FstClusLO | 26-27 | Always 0 |
| LDIR_Name3 | 28-31 | 2 UTF-16 characters |

Total: up to 13 UTF-16 characters per entry, padded with 0x0000 and 0xFFFF.

### LFN Assembly Algorithm

1. See an entry with attribute 0x0F → this is an LFN entry
2. Collect consecutive LFN entries until you reach a non-LFN entry (the short 8.3 entry)
3. Verify all LFN entries share the same checksum, matching the short entry's checksum
4. Use LDIR_Ord to place each 13-char segment into the correct position
5. Convert the composed UTF-16 string to your internal representation
6. If inconsistent, fall back to the 8.3 short name

---

## Directory Entry Structure (32 bytes)

| Field | Offset | Size | Description |
|-------|--------|------|-------------|
| Short Filename | 0x00 | 11 bytes | 8.3 format name |
| Attributes | 0x0B | 1 byte | File/directory flags |
| Reserved | 0x0C | 1 byte | Reserved for NT |
| Creation time (tenths) | 0x0D | 1 byte | 10ms units |
| Creation time | 0x0E | 2 bytes | Hour/min/sec |
| Creation date | 0x10 | 2 bytes | Year/month/day |
| Last access date | 0x12 | 2 bytes | Year/month/day |
| First cluster high | 0x14 | 2 bytes | High 16 bits |
| Write time | 0x16 | 2 bytes | Hour/min/sec |
| Write date | 0x18 | 2 bytes | Year/month/day |
| First cluster low | 0x1A | 2 bytes | Low 16 bits |
| File size | 0x1C | 4 bytes | Size in bytes |

### Attribute Byte Bits

| Bit | Name | Description |
|-----|------|-------------|
| 0 | Read-Only | Should not allow writing |
| 1 | Hidden | Should not show in directory listing |
| 2 | System | File is operating system |
| 3 | Volume ID | Filename is volume label |
| 4 | Directory | Is a subdirectory |
| 5 | Archive | Has been changed since last backup |
| 6 | Reserved | Should be zero |
| 7 | Reserved | Should be zero |

Note: When bits 0-3 are all set (`0x0F`), this indicates an LFN entry.

---

## First Byte of Directory Entry

The first byte of the short filename indicates the entry type:

| Value | Meaning |
|-------|---------|
| 0x00 | End of directory (no more entries follow) |
| 0xE5 | Entry is deleted/unused (can be reused) |
| 0x05 | First character is actually 0xE5 (Kanji lead byte) |
| Other | Normal entry |
