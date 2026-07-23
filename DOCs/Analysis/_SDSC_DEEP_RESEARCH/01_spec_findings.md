# SD Physical Layer Simplified Spec — SDSC SPI-Mode Findings

**Source:** SD Specifications Part 1, Physical Layer Simplified Specification, Version 9.10 (Dec 1, 2023).
**Chunks scanned:** `chunk_aa` … `chunk_ar` in `DOCs/Specs/Part1_chunks/`. Chapter 7 ("SPI Mode") lives in `chunk_an` (lines 1200–2000) and `chunk_ao` (lines 1–1378). Chapter 4 (functional description, state machine, CRC, timeouts) is in `chunk_ac` through `chunk_ag`. Power-up timing is in `chunk_an` Section 6.4.

**Important up-front caveat:** the *Simplified* Specification deliberately blanks the bus-timing detail section. Section 7.5 ("SPI Bus Timing Diagrams"), Figures 7-14…7-21, Table 7-7 ("Timing Values"), and the numeric definitions of Ncs / Ncr / Nec / Nwr / Nbr are **all "Removed in the Simplified Specification"** (chunk_ao lines 1327-1368). Anything Part 1 says about these timings is qualitative. Quantitative Ncs/Ncr/Nwr/Nec values are *not* present in the Simplified Spec. Those numbers live in the full (member-only) spec and in widely-circulated SanDisk/Samsung-derived community references; they are **not authoritative spec text from this document**.

---

## 1. SPI mode init sequence for SDSC (SDv1)

**CMD0 enters SPI mode (chunk_an §7.2.1, lines 1323-1330):**

> "The SD Card is powered up in the SD mode. It will enter SPI mode if the CS signal is asserted (negative) during the reception of the reset command (CMD0). If the card recognizes that the SD mode is required it will not respond to the command and remain in the SD mode. If SPI mode is required, the card will switch to SPI and respond with the SPI mode R1 response. **The only way to return to the SD mode is by entering the power cycle.** In SPI mode, the SD Card protocol state machine in SD mode is not observed. All the SD Card commands supported in SPI mode are always available."

**Pre-CMD0 clocking (chunk_an §6.4.1.1, lines 519-595):**

> "A device shall be ready to accept the first command within 1ms from detecting VDDmin. Device may use up to 74 clocks for preparation before receiving the first command. … The host shall supply power to the card so that the voltage is reached to Vdd_min within 250ms and start to supply at least 74 SD clocks to the SD card with keeping CMD line to high. **In case of SPI mode, CS shall be held to high during 74 clock cycles.**"

So the spec **mandates ≥74 SCK clocks with CS=HIGH and MOSI=HIGH (CMD line idle = high) before the first CMD0**. CMD0 itself is then sent with CS=LOW.

**CMD8 (legal SDv1 illegal-command response) — chunk_an §7.2.1 lines 1339-1341, and Table 7-5 (chunk_ao lines 821-886):**

> "If the card indicates an illegal command, the card is legacy and does not support CMD8."

Table 7-5 explicitly shows: when CMD index ≠ 8 (i.e., a legacy SDv1 card that does not recognize CMD8), `R1 = 09h` (in_idle_state=1 + illegal_command=1, i.e., 0x05+0x01=… actually 0x09 because illegal=bit2(=4) and idle=bit0(=1), plus presumably another bit; the simplified table cell shows `09h`). The **SDv1 path is "CMD8 returns illegal-command in R1"**, and the host MUST tolerate that.

Figure 7-2 (chunk_an lines 1452-1474) lays out the full init flow:
- CMD0 + CS asserted ("0")
- CMD8 → if illegal command, treat as SDv1 (Ver1.X) SDSC
- CMD58 (READ_OCR) — *not mandatory but recommended*
- ACMD41 with argument=0x0 (HCS bit is meaningful only if CMD8 was accepted; SDSC ignores HCS — chunk_an line 1460)
- Poll ACMD41 until `in_idle_state=0`
- CMD58 again to get CCS (CCS=0 means SDSC; CCS=1 means SDHC/SDXC) — chunk_an lines 1468-1474

**Important constraint on the polling loop (chunk_an §7.2.1, lines 1464-1465):**

> "The host repeatedly issues ACMD41 until this bit is set to '0'. The card checks the HCS bit in the OCR only at the first ACMD41. **While repeating ACMD41, the host shall not issue another command except CMD0.**"

**CMD16 SET_BLOCKLEN for SDSC:**
- Table 7-3 (chunk_ao line 386-394): "In case of SDSC Card, block length is set by this command. In case of SDHC and SDXC Cards, block length of the memory access commands are fixed to 512 bytes."
- Section 4.3.3 (chunk_ad line 179): "Block Length set by CMD16 can be set up to 512 bytes regardless of READ_BL_LEN."
- Section 4.3.4 / Table 4-5 (chunk_ad lines 260-310): "A card supporting block write shall be required that Block Length set by CMD16 shall be 512 bytes regardless of WRITE_BL_LEN is set to 1k or 2k bytes. … If the current Blocklen is other than this value, the card indicates BLOCK_LEN_ERROR on the Write command response."

The spec is unambiguous: **for SDSC, the host shall issue CMD16=512 before block I/O**. Although a fresh SDSC card *typically* has block-len defaulted to its CSD's WRITE_BL_LEN (often 512), the spec only says the value used at write-time must be 512. After a power-on the default is "as specified in the CSD" (Table 7-3 footnote 2, chunk_ao line 631). So a host **must** issue CMD16=512 to be safe — and on a counterfeit whose CSD lies (e.g. WRITE_BL_LEN claims 1024 while the silicon only handles 512, or vice-versa), skipping CMD16 is a known footgun.

**CS / clock state during init:**
- CS=HIGH during the ≥74 dummy clocks before CMD0 (chunk_an line 594-595).
- CS=LOW (asserted) during CMD0 (chunk_an line 1324, "if the CS signal is asserted (negative) during the reception of the reset command").
- The spec is silent in Section 7 about whether host should re-raise CS between every command vs. hold low through the whole init sequence; but Section 7.2 (chunk_an line 1218-1224) says: "Every command or data block is built of 8-bit bytes and is byte aligned with the CS signal … The host starts every bus transaction by asserting the CS signal low."

---

## 2. CRC handling in SPI mode

**Default state and CMD0 CRC requirement (chunk_an §7.2.2, lines 1476-1493):**

> "The SPI interface is initialized in the CRC OFF mode in default. However, the RESET command (CMD0) that is used to switch the card to SPI mode, is received by the card while in SD mode and, therefore, shall have a valid CRC field. Since CMD0 has no arguments, the content of all the fields, including the CRC field, are constants and need not be calculated in run time. A valid reset command is: **0x40, 0x0, 0x0, 0x0, 0x0, 0x95**."
>
> "After the card is put into SPI mode, CRC check for all commands including CMD0 will be done according to CMD59 setting. The host can turn the CRC option on and off using the CRC_ON_OFF command (CMD59). **Host should enable CRC verification before issuing ACMD41.**"
>
> "**The CMD8 CRC verification is always enabled. The Host shall set correct CRC in the argument of CMD8.** If CRC error is detected, card returns CRC error in R1 response regardless of command index."

So the spec mandates:
- CMD0 CRC always required (constant 0x95).
- CMD8 CRC always required (the canonical value for arg 0x000001AA is 0x87).
- After CMD0, default is CRC-OFF for everything else; CMD59 can turn it on.
- Hosts SHOULD turn CRC on before ACMD41.

**Data-block CRC (chunk_an §7.2.3, line 1526):**

> "A valid data block is suffixed with a 16-bit CRC generated by the standard CCITT polynomial x16+x12+x5+1."

Section 4.5 (chunk_ae lines 1877-1899) confirms G(x)=x^16+x^12+x^5+1 (the reflected/standard CCITT 0x1021/0x8408 variant); known reference value: "512 bytes with 0xFF data → CRC16 = 0x7FA1" (chunk_ae line 1899).

**Is a "dummy" CRC of $0000 on a data block legal?**
Part 1 does **not** explicitly address this. The data-write description (chunk_an §7.2.4, lines 1654-1661) says:

> "The only validation check performed on the data block, and communicated to the host via the data-response token, is the CRC and general Write Error indication."

And the data-response token (chunk_ao §7.3.3.1, lines 1037-1046):

> "`010` Data accepted. `101` Data rejected due to a CRC error. `110` Data Rejected due to a Write Error."

So the spec's *intent* is that the card validates CRC and rejects with `xxx0_0101_1` (i.e., `0x0B` or `0x05` masked) on CRC error. **The spec does not contain a clause saying "the card may accept CRC=$0000 as if CRC is off in the absence of CMD59"**. Strictly: if CMD59 was never sent (default CRC OFF for commands), the *command* CRCs are don't-care — but Part 1 nowhere extends "CRC OFF" to the *data block*. The "dummy CRC $0000 accepted" behavior some real cards exhibit is **not spec-mandated and is best treated as vendor-specific tolerance**.

**What is the host expected to do on CRC validation failure?**
The spec is mostly passive: card sets `COM_CRC_ERROR` in R1/R2 (chunk_ao §7.3.4 Table 7-6, line 1180), returns the data-response `101` for a write data-block CRC error. The host is expected to detect the rejection and retry. Section 4.6.1 (chunk_ae lines 1907-1913):

> "All commands are protected by CRC (cyclic redundancy check) bits. If the addressed card's CRC check fails, the card does not respond and the command is not executed. The card does not change its state, and COM_CRC_ERROR bit is set in the status register."

(That's for SD bus mode; in SPI per §7.2.2, the card always responds and signals via R1 bit 3.)

---

## 3. CMD24 (WRITE_BLOCK) single-block protocol

**Spec narrative (chunk_an §7.2.4, lines 1609-1662):**

> "The SPI mode supports single block and multiple block write commands. Upon reception of a valid write command (CMD24 or CMD25 in the SD Memory Card protocol), the card will respond with a response token and will wait for a data block to be sent from the host. … Every data block has a prefix of 'Start Block' token (one byte). After a data block has been received, the card will respond with a data-response token. If the data block has been received without errors, it will be programmed. As long as the card is busy programming, a continuous stream of busy tokens will be sent to the host (effectively holding the DataOut line low). Once the programming operation is completed, the host should check the results of the programming using the SEND_STATUS command (CMD13)."

**Start Block token for single-block / multiple-block-read = `0xFE`** (chunk_ao §7.3.3.2, lines 1056-1062): "First byte: Start Block, `1 1 1 1 1 1 1 0`" (0xFE). For Multi-Block-Write blocks the token is `0xFC`, with Stop-Tran token `0xFD` (chunk_ao lines 1063-1075).

**Data response token** (chunk_ao §7.3.3.1, lines 1037-1046):
- One byte: `x x x 0 Status 1` where Status is 3 bits.
- `010` = data accepted (full byte typically `0xE5` after masking, but only bits 4-0 are spec-defined; bits 7-5 are 'x').
- `101` = CRC error.
- `110` = write error.

**Min/max time between R1 and the data start token:**
Part 1 (Simplified) **does NOT specify a numeric Nwr (CMD24 R1→data token gap)**. The spec sentence is just:

> "the card will respond with a response token and will wait for a data block to be sent from the host." (chunk_an line 1611)

It does require a one-byte minimum gap implicit in the byte-alignment rule (§7.2, line 1219-1221, "the length is a multiple of 8 clock cycles … Every command or data token shall be aligned with 8-clock cycle boundary"). The simplified spec gives no upper bound. The full spec defines Nwr (host-to-card min gap between command response and data token, typically 1 byte) and Nbr (block response time after the card receives the data CRC), but those numbers are in the removed Table 7-7 (chunk_ao line 1368: "Table 7-7 : Timing Values (Removed in the Simplified Specification)").

**Max time between CRC and data response token:**
Again, Part 1 Simplified gives no numeric bound; this is the "data-response latency" Nbr/N-cr-class quantity in the removed Table 7-7. Empirically (and per the unsimplified spec) this is ≤8 bytes (i.e., the response appears within 0-8 byte-times of the trailing CRC). The spec text just says the card "will respond with a data-response token."

**Is MOSI required to be HIGH during the wait-for-data-response window?**
Part 1 doesn't state this explicitly anywhere in Chapter 7. Section 7.2 (line 1224) says: "The selected card always responds to the command…". The MOSI-idle-HIGH convention is industry practice (driving 0xFF == "not transmitting anything") consistent with §7.3.1.1 Table 7-1 (chunk_an line 1855-1888) which defines a command's start bit as `0` — so an idle line of all-1s guarantees no false start-bit detection. **The spec does not formally mandate MOSI=HIGH during card-talking windows in the Simplified version**, but it is the only safe default and is implied by Figure 7-1 / 7-2 and "Every command or data token shall be aligned with 8-clock cycle boundary" (chunk_an line 1221).

**Sequence:** CMD bytes (6) → response window (poll for first byte with MSB=0, that is R1) → ≥1 byte gap (Nwr) → 0xFE start token → 512 data bytes → 2 CRC16 bytes → response window for data response token (Nbr) → busy (MISO held LOW) until release.

---

## 4. Busy signaling

**Mechanism (chunk_an §7.2.4, lines 1654-1661):**

> "As long as the card is busy programming, a continuous stream of busy tokens will be sent to the host (effectively holding the DataOut line low)."

**Busy-clear detection — chunk_ao §7.3.2.2 (R1b format), lines 928-930:**

> "This response token is identical to the R1 format with the optional addition of the busy signal. **The busy signal token can be any number of bytes. A zero value indicates card is busy. A non-zero value indicates the card is ready for the next command.**"

So **the spec defines "busy released" as the first non-zero byte read** (i.e., the first 0xFF). Part 1 (Simplified) does **not** require N consecutive 0xFF bytes — one is enough per the literal text. (The 8-clocks-after rule below adds an aftercare requirement.)

**The "8 clocks after" requirement (chunk_ae §4.4, lines 1821-1828):**

> "It is an obvious requirement that the clock shall be running for the card to output data or response tokens. After the last SD Memory Card bus transaction, the host is required, to provide 8 (eight) clock cycles for the card to complete the operation before shutting down the clock. … A write data transaction. 8 clocks after the CRC status token."

So **after the data-response token / after busy release, the host must provide at least 8 SCK before the next bus transaction or clock shutdown**.

**What if the host issues another command while MISO is still LOW?**
chunk_an §7.2.4, lines 1717-1722:

> "While the card is busy, resetting the CS signal will not terminate the programming process. The card will release the DataOut line (tri-state) and continue with programming. **If the card is reselected before the programming is finished, the DataOut line will be forced back to low and all commands will be rejected.** Resetting a card (using CMD0 for SD memory card) will terminate any pending or active programming operation. This may destroy the data formats on the card."

And §7.2.8 (lines 1788-1798): "A command may be rejected in any one of the following cases: … It is sent while the card is in Busy."

**So issuing CMD24 (or anything else) while the card is still busy from a prior write is spec-defined to cause command rejection.** Whether the rejection produces an R1 response with some error bit (Illegal Command? Communication CRC error?) or whether the busy-low simply continues without R1 emission is *not* explicitly described. The spec only says "all commands will be rejected" — without specifying *how* the rejection presents on the wire. The natural interpretation is "no R1 — MISO stays LOW until busy ends."

CMD0 during busy: "will terminate any pending or active programming operation. **This may destroy the data formats on the card.**"

---

## 5. Card state machine in SPI mode

**Figure 7-1 — chunk_an lines 1240-1321** shows the SPI-mode state diagram. It is much simpler than the SD-mode one (Figure 4-13, chunk_ad). The SPI-mode states explicitly named in Figure 7-1 are:
- **SPI Operation Mode** (entry from any state on CMD0 + CS=0)
- **Idle State**
- **card-identification mode**
- **data-transfer mode**

The SD-mode states (`stby`, `tran`, `data`, `rcv`, `prg`, `dis`, `ina`) are deliberately NOT enforced in SPI mode. From §7.2.1 line 1328-1330:

> "**In SPI mode, the SD Card protocol state machine in SD mode is not observed.** All the SD Card commands supported in SPI mode are always available."

That said, the *underlying* card *does* still have internal states corresponding to `prg`/busy, and §7.2.8 (lines 1788-1798) acknowledges that commands can be rejected while the card is "in read operation" or "in Busy."

**After CMD24 data accepted → busy → busy released:** The card returns to the conceptual `tran`-equivalent state in SPI ("ready for new command"). The spec does not give it a name in §7 — it just says (line 1657-1659): "Once the programming operation is completed, the host should check the results of the programming using the SEND_STATUS command (CMD13)." So CMD13 is expected to work after busy release.

**Does CMD13 work in all states?** Per SD-mode Table 4-35 (chunk_ag lines 460): CMD13 has "no state transition in data-transfer-mode" and is legal from all data-transfer states. The SPI command-class table (chunk_an line 1962-1972) lists CMD13 as Mandatory Class 0.

**R2 meaning** (chunk_ao §7.3.2.3, lines 937-975): R2 is 2 bytes. First byte = R1 (idle/erase_reset/illegal/CRC/erase_seq/address/parameter, MSB=0). Second byte covers: `Card is locked`, `wp erase skip | lock/unlock cmd failed`, `error`, `CC error`, `card ecc failed`, `wp violation`, `erase param`, `out of range | csd overwrite`.

**R2 = $0000 means: all of those bits are clear** — i.e., R1's seven error bits all zero, and the second byte's eight bits all zero. It explicitly does NOT report:
- the SPI-mode `READY_FOR_DATA` equivalent (that lives in SD-mode R1's bit 8, which is not part of SPI R1/R2);
- the current internal state (the SD-mode `CURRENT_STATE` 4-bit nibble in SD R1 is not in SPI R1 either);
- anything FAT/filesystem related;
- physical-block remap / wear / ECC-recovered counts (those are in SD Status, ACMD13, not R2).

So **R2 = $0000 is the spec's "clean status" report**, but it explicitly does *not* prove the card is in `tran` state or that the card will accept the next write. It just means no sticky error bit is set.

---

## 6. Inter-command timing — Ncs, Ncr, Nec, Nwr

**Critical:** Part 1 (Simplified) **does not give numeric values** for any of these. §7.5.4 ("Timing Values") and Table 7-7 are explicitly **"Removed in the Simplified Specification"** (chunk_ao lines 1367-1368). The only timing-related text in the simplified spec is:

- "Every command or data token shall be aligned with 8-clock cycle boundary" (chunk_an §7.2, line 1221) — implies all gaps are multiples of 8 clocks.
- "The standard response timeout value (NCR) is used for read latency of the CSD register" (chunk_an line 1771) — NCR is *mentioned by name* but never numbered.
- §4.4 (chunk_ae lines 1821-1828): "After the last SD Memory Card bus transaction, the host is required to provide 8 (eight) clock cycles for the card to complete the operation before shutting down the clock."
- §4.6.2.2 Write timeout (chunk_ae lines 1937-1980): For SDSC, "either 100 times longer than the typical program times for these operations … or 250 ms (the lower of the two)." For SDHC: "maximum length of busy is defined as 250ms for all write operation." Application note: **"It is strongly recommended for hosts to implement more than 500ms timeout value even if the card indicates the 250ms maximum busy length."**

The familiar community values (Ncs=0, Ncr=1-8 bytes, Nbr=0-1 byte, Nwr≥1 byte, Nec=0) are NOT present in Part 1 Simplified — they live in the full member-only spec.

---

## 7. CMD25 → CMD24 transition / pre-erase counts

**STOP_TRANSMISSION for multi-block writes is via the Stop-Tran TOKEN (`0xFD`), not CMD12** — chunk_an §7.2.4 lines 1662-1670:

> "In a Multiple Block write operation, **the stop transmission will be done by sending 'Stop Tran' token instead of 'Start Block' token at the beginning of the next block.** In case of Write Error indication (on the data response) the host shall use SEND_NUM_WR_BLOCKS (ACMD22) in order to get the number of well written write blocks."

(In SD mode, CMD12 is used. In SPI mode, the in-stream Stop-Tran token is the mechanism.)

The Multi-Block-Write Figure 7-7 (chunk_an line 1672-1716) ends with: "data_response busy / busy / new command from host." So after the Stop-Tran token, the card goes busy, then accepts a new command — there's no separate CMD12 step required in SPI for clean Multi-Block-Write closure.

**ACMD23 pre-erase count — chunk_ad §4.3.4 (lines 348-361):**

> "Setting a number of write blocks to be pre-erased (ACMD23) will make a following Multiple Block Write operation faster compared to the same operation without preceding ACMD23. … **This number will be reset to the default (=1) value after Multiple Blocks Write operation.** … Note that the host should send ACMD23 just before WRITE command if the host wants to use the pre-erased feature. **If not, pre-erase-count might be cleared automatically when another commands (ex: Security Application Commands) are executed.**"

So an ACMD23 set BEFORE a CMD25 burst is auto-cleared after that CMD25 burst completes — it should not leak into a subsequent CMD24. **No spec text says "lingering pre-erase from a previous CMD25 affects subsequent CMD24."** Footnote (2) to Table 7-4 (chunk_ao line 811-812) also confirms: "Stop Tran Token shall be used to stop the transmission in Write Multiple Block whether the pre-erase (ACMD23) feature is used or not."

---

## 8. SDSC byte-addressing vs SDHC block-addressing quirks

**Table 7-3 footnote 10 (chunk_ao line 644-645):**

> "SDSC Card (CCS=0) uses byte unit address and SDHC and SDXC Cards (CCS=1) use block unit address (512 bytes unit)."

**§4.3.14 (chunk_ae lines 1740-1768):**

> "SDSC uses the 32-bit argument of memory access commands as byte address format. Block length is determined by CMD16."
> "(a) Argument 0001h is byte address 0001h in the SDSC and 0001h block in SDHC and SDXC"
> "(b) Argument 0200h is byte address 0200h in the SDSC and 0200h block in SDHC and SDXC"
> "**SDHC, SDXC and SDUC disable Partial access and Misalign access (crossing physical block boundary) as the block address is used.** Access is only granted based on block addressing."

§4.3.3 / Table 4-4 (chunk_ad lines 197-243):

> "If the host uses partial blocks whose accumulated length is not block aligned and block misalignment is not allowed, the card shall detect a block misalignment at the beginning of the first misaligned block, set the ADDRESS_ERROR error bit in the status register, abort transmission and wait in the Data State for a stop command."

**§4.3.4 / Table 4-5 (chunk_ad lines 260-329)** for write:

> "If start address is other than [n*512 bytes (n: Integer)], the card will send ADDRESS_ERROR on the Write command response."

So a CMD24 to an SDSC card whose 32-bit argument is not a multiple of 512 (e.g., argument=`sector` instead of `sector*512`) triggers ADDRESS_ERROR. **This is the single most common driver bug for SDSC silicon.** The spec is explicit.

CSD parameters that govern partial-block writes: `WRITE_BL_PARTIAL` (enables sub-512 writes), `WRITE_BLK_MISALIGN` (allows misaligned writes within a physical block). For a 512-byte WRITE_BL_LEN card these should be 0/0.

---

## 9. What the spec says about counterfeit/non-conforming behaviors

The spec is a contract; deviations are NOT documented. But the spec's *requirements* enumerate exactly what a counterfeit might short-circuit. Top candidates that map to the symptom "write #1 OK → write #2 silently refuses tokens → write #3+ no R1":

1. **Failure to honor the 8-clocks-after rule (§4.4 line 1821-1828, applied to SPI-mode by §7.2 / §7.8)** — if the silicon's internal "end-of-write" handshake needs those 8 clocks to fully release internal flags and the driver omits them, the next CMD24 may find the card in an undefined state.

2. **Incomplete busy-release detection** — spec says "any non-zero byte" indicates ready (chunk_ao line 929). A counterfeit might bring MISO HIGH transiently (one 0xFF byte) and then dip LOW again as the FTL completes housekeeping. If the host reads exactly one 0xFF and immediately starts CMD24, the subsequent command lands while the card is *still actually* in the conceptual `prg` state — and §7.2.8 says "command may be rejected … in Busy."

3. **CRC-mode drift after CMD0** — §7.2.2 says default after CMD0 is CRC-OFF for commands. If the counterfeit toggles its internal CRC-ON/OFF differently than a real card (e.g., latches CRC-on after the first valid CRC even without CMD59), then a subsequent CMD24 with a bad/stale CRC field would be rejected with COM_CRC_ERROR — and the spec says "If CRC error is detected, card returns CRC error in R1 response regardless of command index" (line 1493). But if the card *only* fails-silent (instead of returning the spec'd R1=CRC-error), that's a counterfeit deviation.

4. **State machine inversion / "stuck in prg"** — a counterfeit FTL might not return to the SPI-equivalent of `tran` after the first programming completes; subsequent CMD24 would be rejected per §7.2.8. The spec says CMD0 will "terminate any pending or active programming … This may destroy the data formats." Counterfeits often refuse to honor CMD0 cleanly mid-busy and need a power cycle (§7.2.1 line 1328: "The only way to return to the SD mode is by entering the power cycle").

5. **CMD16 default mismatch** — spec says block length defaults to CSD's WRITE_BL_LEN. If a counterfeit's CSD says one thing but its firmware silently expects another, the first write may work (because we set CMD16=512 ourselves) but a stale internal counter could mis-track on subsequent writes. The spec mandates CMD16 = 512 for SDSC writes (§4.3.4) — host responsibility.

6. **Data-response token mis-emission** — spec mandates `010` for accept, `101` for CRC error, `110` for write error (chunk_ao §7.3.3.1). A counterfeit could silently never emit a data-response token (and just go to busy-low, or just hold MOSI/MISO indeterminate), which is non-spec-compliant and silent-fails the host's polling loop.

7. **Default block length resets to non-512 on SDSC** — Table 7-3 footnote 2 (chunk_ao line 631) says "The default block length is as specified in the CSD." If after a CMD24 the silicon resets internal block-length to CSD-WRITE_BL_LEN (which on a 1GB SDSC is *usually* 512, but on a malformed counterfeit could be 1024 or 2048), subsequent CMD24 would BLOCK_LEN_ERROR. **The spec does NOT say "block length set by CMD16 persists across writes," only that it's "set by this command."** Most real cards do persist it; a deviant counterfeit may not.

---

## 10. Reset / recovery from a wedged state

**The spec offers very limited recovery paths:**

- **CMD0 mid-busy**: §7.2.4 line 1720-1721 — "Resetting a card (using CMD0 for SD memory card) will terminate any pending or active programming operation. This may destroy the data formats on the card. It is in the responsibility of the host to prevent this for occurring." So CMD0 *can* be sent, but it's destructive in the middle of a write.
- **CMD12 STOP_TRANSMISSION**: Per Table 7-3 (chunk_ao line 376-378), CMD12 is mandatory and legal in SPI; primarily used to stop a multi-block read. For writes, the stop is via Stop-Tran token, not CMD12. CMD12 is R1b (line 634): "R1 response with an optional trailing busy signal."
- **Re-entry to SPI from SD**: §7.2.1 line 1328-1329 — "The only way to return to the SD mode is by entering the power cycle." Conversely, once in SPI mode the card *stays* in SPI; you cannot leave SPI without a power cycle.
- **CMD0 reset clocking requirement (chunk_an §6.4.1.1, lines 519-595)**: At power-on, ≥74 SCK clocks with CS=HIGH (and CMD-line/MOSI=HIGH) are MANDATORY before the first CMD0. The spec does NOT explicitly require 74 dummy clocks before a *mid-session* CMD0 reset (e.g., to attempt recovery from a wedge without power-cycling), but the conservative-correct sequence is to repeat the power-up clocking pattern: drop CS, raise CS+MOSI, issue ≥74 dummy clocks, then CS=LOW + CMD0.
- **Power cycle**: §6.4.1.5 (chunk_an lines 672-679) — VDD must be held below 0.5V for ≥1ms during power-down. Below 0.5V "for a minimum period of 1ms" is the mandated power-cycle condition. Anything less and the card may not actually reset internally.

**No softer recovery is offered.** The spec assumes that a card in a wedged state is recovered by (a) CMD0 (destructive), (b) power-cycle, or (c) — if just busy — waiting longer (timeout recommendation §4.6.2.2 line 1976 is "more than 500ms").

---

## Cross-reference: items NOT covered in Part 1

The following topics are NOT in Part 1 Simplified (or are listed as removed):

- **Quantitative Ncs, Ncr, Nbr, Nwr, Nec values**: removed (§7.5.4, Table 7-7).
- **SPI bus timing diagrams** (Figures 7-14 through 7-21): all removed (§7.5).
- **Exact electrical characteristics for SPI specifically beyond "identical to SD mode"**: §7.6 / §7.7 / §7.8 just say "identical to SD mode" and "Bus timing is identical to SD mode."
- **CSD register field definitions and bit-by-bit detail**: outside the SPI chapter; mostly in §5.3 (not scanned in detail above), but the access mechanism (CMD9 read) is in §7.2.6.
- **CMD8 R7 detailed bit-by-bit definition for SPI**: §7.3.2.6 (chunk_ao lines 1001-1027) refers back to §4.9 for SD-mode R7 and just says the first byte is R1 and the next 4 bytes carry the OCR-style fields.
- **The exact wire-level "CRC error → R1 returned with which bits set"**: §7.2.2 says "card returns CRC error in R1 response regardless of command index" — implying R1 bit 3 (com_crc_error) is set. Spec doesn't say whether the card *also* sets illegal_command or other bits.

---

## Summary — most spec-relevant suspect mechanisms for the symptom progression

The symptom is: **write #1 fully succeeds (data accepted + busy + busy released) → write #2 silently refuses to produce data-block tokens → writes #3+ silently never produce an R1 to CMD24**.

The spec text most likely to be implicated:

1. **The "8 clocks after CRC status token" rule (§4.4 line 1821-1828).** If the driver issues CMD24's bytes immediately after observing the first non-zero (0xFF) on MISO without supplying 8 more SCK to let the card complete its internal "end-of-write" handshake, the card may legitimately reject the next command per §7.2.8 ("It is sent while the card is in Busy"). On a real card, the FTL is fast enough that this rarely matters; on a counterfeit with a slow internal FTL, it does.
2. **Busy-release detection latitude (§7.3.2.2 line 928-930).** Spec accepts a *single* non-zero byte as "ready." A counterfeit whose MISO bounces (one 0xFF then back LOW for residual housekeeping) is not in violation of §7.3.2.2 wording, but its internal state isn't actually ready. The driver needs to require N≥1 (and ideally several) consecutive 0xFF bytes to be robust against this — though the spec only mandates one.
3. **CMD-during-busy rejection mechanics (§7.2.8 line 1793, §7.2.4 line 1719).** "If the card is reselected before the programming is finished … all commands will be rejected." Spec does NOT say *how* rejection presents — silent-no-R1 is consistent with "MISO stays held LOW until busy ends, host's R1 wait times out." So the second write's CMD24 may have been issued while the card was still actually busy; from then on the card stays in its rejection mode until power-cycle.
4. **State-machine drift after partial-spec-violation.** Once a CMD24 is sent while busy, the spec offers no graceful recovery: "all commands will be rejected." The host's next CMD24 (write #3) likewise. CMD0 mid-busy is the only spec-defined escape, and it's marked destructive. **A power cycle is the spec-clean reset, period.**

If write #1 works fully but write #2 silently fails to emit a Start-Block-Token, the most natural spec-anchored explanation is **the second CMD24 reached the card before the first write's full "end-of-transaction + 8 SCK + busy fully released" sequence completed**, putting the card in the "command rejected while busy" state from which §7.2.4/7.2.8 say all further commands are rejected. Counterfeit SDSC silicon — with slower internal FTL and looser tolerance margins — is far more likely to require strict post-busy timing than real-spec silicon, where typical FTL completion is fast enough to hide host sloppiness.
