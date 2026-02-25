# Chip Gracey — Streamer Input/Output Timing Advice

**Date**: 2026-02-23
**Context**: Investigating why external SD header fails at >22 MHz SPI on multi-block reads

## Conversation

**Stephen M Moraco:**
> re SPI clock for external uSD adapter, good hint! have to drop down to ~22MHz for reliable xfers with that eval board

**Chip Gracey:**
> There must be some setup/ hold problem, then. That is not that fast.
> I'm sure you can observe on the logic analyzer what the data out timing looks like but the data in timing is invisible because you are using the streamer and you might need to adjust a few clocks one way or another to make it work a lot better. This means the timing would be on the edge for what seems to be solid, as well.

**Stephen M Moraco:**
> now that the external board is reliable i can use the LA! set my sampling high and look for where edges are? oh, and more detail, it's only the multiblock transfers that fail for this board at higher SPI rates…

**Chip Gracey:**
> If you are resetting the smart pin that does the transition output for clock generation and you know the timing against the streamer for outputting data, then that is going to be clearly observable and should be consistent. The streamer inputting is another matter, though. The timing would certainly be offset from what output would look like.
> There could be maybe like a four or five or 6-clock difference between input timing and output timing relative to the streamer and the smart pin doing the transition output clock generation.
> Streamer inputting involves looking at States propagating forward from the past, while outputting means outputting bits which appear a few clocks later. Opposite timing offsets.

## Key Points

1. **Setup/hold problem** — at the SPI level, not a signal integrity issue
2. **Output (MOSI/write) timing is observable on LA** — streamer outputs bits that appear on pins a few clocks later
3. **Input (MISO/read) timing is NOT directly observable** — streamer reads "states propagating forward from the past"
4. **4-6 system-clock offset between input and output timing** relative to the SCK transition smart pin
5. **Opposite timing offsets** — output: data appears AFTER clock edge; input: data is sampled from BEFORE the current moment
6. **"Adjust a few clocks one way or another"** — the read path timing may need tuning independent of the write path
