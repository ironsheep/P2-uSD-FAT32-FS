# Example Programs

Compilable, self-contained examples demonstrating common SD card driver operations. Each example can be compiled and run directly on P2 hardware.

## Building

From this `EXAMPLES/` directory:

```bash
pnut-ts -I .. SD_example_read_write.spin2
pnut-term-ts -r SD_example_read_write.bin
```

The `-I ..` flag tells the compiler to find `micro_sd_fat32_fs.spin2` in the parent directory.

## Examples

| Program | Description |
|---------|-------------|
| **SD_example_read_write.spin2** | Basic file create, write, read-back, and delete — the "hello world" |
| **SD_example_data_logger.spin2** | Append-mode logging with periodic sync for power-fail safety |
| **SD_example_directory_walk.spin2** | Directory listing, subdirectory creation, file delete and rename |
| **SD_example_multicog.spin2** | Two cogs accessing different files concurrently |

## Pin Configuration

All examples default to the P2 Edge Module SD card slot (base pin 56). To use a different 8-pin header group, change `SD_BASE` in the `CON` section. See [SD-CARD-DRIVER-TUTORIAL.md](../../SD-CARD-DRIVER-TUTORIAL.md) for the complete header group reference table.

---

*Part of the [P2 SD Card Driver](../README.md) package — Iron Sheep Productions*
