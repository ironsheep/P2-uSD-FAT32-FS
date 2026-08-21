# Research

Hardware investigations and compatibility research — findings that outlive this
driver and are meant to be useful to anyone working the same ground.

Distinct from `../Analysis/`, which holds working analyses of this driver's own
defects: repo-specific, frequently superseded, and deliberately left unedited.

The two case studies are enumerated in `release.yml` and ship with the driver;
the rest of this folder does not.

## Contents

| Document | Description |
|----------|-------------|
| [SD-CARD-WEDGE-CASE-STUDY.md](SD-CARD-WEDGE-CASE-STUDY.md) | Boot-time bus traffic on shared pins wedges microSD cards, and the one command that clears it |
| [SD-SOCKET-TIMING-CASE-STUDY.md](SD-SOCKET-TIMING-CASE-STUDY.md) | Two microSD sockets on one P2 characterized against each other; the read and write phase maps that came out of it |
| [CRC-ERROR-HANDLING-STUDY.md](CRC-ERROR-HANDLING-STUDY.md) | CRC error handling study |
| [CRC-INDUSTRY-PRACTICE.md](CRC-INDUSTRY-PRACTICE.md) | CRC error handling industry practice and host policy |
| [P2-SMARTPIN-LIVE-UPDATE-REFERENCE.md](P2-SMARTPIN-LIVE-UPDATE-REFERENCE.md) | P2 smart pin live update rules reference |
| [PNY-MICROSD-SPI-ISSUES.md](PNY-MICROSD-SPI-ISSUES.md) | PNY microSD SPI mode compatibility research |
