# PEX host SPI interface (candidate, freeze at G2)

Generated from `hw/host_proto/pex_host_proto.ml`; do not edit. Spec sections 4.5, 4.6, 5, 6.

## Framing

SPI mode 0, MSB first. A frame is `cmd, addr hi, addr lo, data...` while CS_n is low. The address is 16 bits, big-endian. Data auto-increments as described per command. A partial byte at CS rising is discarded; only complete bytes (and, for memory, complete words) take effect.

An invalid command byte: the whole frame is ignored and the host error flag is set. Every register field is little-endian where it spans bytes.

## Commands

| Byte | Command | Address | Data |
|---|---|---|---|
| `0x10` | Write_mem | word address 0..255 | 2 bytes per word, low byte first; address auto-increments per word |
| `0x11` | Read_mem | word address 0..255 | host clocks out 2 bytes per word, low byte first; auto-increment per word |
| `0x20` | Write_cfg | cfg byte address | one byte per register; auto-increment per byte |
| `0x21` | Read_cfg | cfg byte address | as Write_cfg, read |
| `0x30` | Read_status | status byte address | as Read_cfg, status space |
| `0x40` | Ctrl | addr hi = 0, addr lo = context mask (bit0 ctx0, bit1 ctx1) | one control byte per op, executed in order for each masked context |
| `0x50`+ctx | Fifo_push | ignored (send 0) | each byte pushed to the context's RX FIFO (firmware reads it); no auto-increment |
| `0x60`+ctx | Fifo_pop | ignored | each byte popped from the context's TX FIFO; no auto-increment |
| `0x70`+ctx | Trace_pop | ignored | 4 bytes per entry, popped oldest first: tag, time[7:0], time[15:8], time[23:16] (the 32-bit entry `{time[23:0], tag[7:0]}` little-endian) |

Instruction memory addresses past 255 (addr hi nonzero or lo beyond 255), or an unmapped or read-only register write, set the host error flag; the offending byte and the rest of the frame are ignored. Reads of unmapped addresses return 0x00 and set nothing. Fifo_push to a full FIFO drops the byte and sets `host_push_overflow`; Fifo_pop or Trace_pop from an empty FIFO returns 0x00 (Fifo_pop also sets `host_pop_underflow`).

Write_mem and Read_mem are halted-only (instruction memory is never read by the host while the core fetches); Write_cfg is halted-only for every cfg register; each is rejected while any context runs and sets the host error flag. Read_cfg, Read_status, Ctrl, Fifo_* and Trace_pop work at any time. There are no RW-any registers in v1.

## Ctrl bytes

| Byte | Meaning |
|---|---|
| `0x01` | Start: validate the configuration; on failure set `HOST_CFG` and do not start |
| `0x02` | Halt |
| `0x03` | Clear_faults: clears fault codes, sticky flags and the host error flag |
| `0x80`+n | Step n+1 slots (n 0..127) |

Any other Ctrl byte sets the host error flag. Status registers have no write path, so sticky bits are cleared by Clear_faults only (there is no W1C).

## Access codes

`RW-halted` writable only while halted. `RO` read-only. `RO-sticky` read-only, set by hardware, cleared by Clear_faults. All reset values are 0 unless listed.

## Config registers (Write_cfg / Read_cfg)

| Address | Name | Bits | Width | Access | Reset | Meaning |
|---|---|---|---|---|---|---|
| 0x00-0x01 | `experiment_id` | [15:0] | 16 | RW-halted | 0x0 | 16-bit experiment ID, little-endian. |
| 0x04 | `trace_mode` | [1:0] | 2 | RW-halted | 0x0 | Trace mode: 0 = MARK, 1 = EVENTS, 2 = COMMITS; 3 is illegal (HOST_CFG at START). |
| 0x08 | `entry0` | [7:0] | 8 | RW-halted | 0x0 | Start address of the context. |
| 0x09 | `entry1` | [7:0] | 8 | RW-halted | 0x0 | Start address of the context. |
| 0x10 | `out_pin0.owner` | [1:0] | 2 | RW-halted | 0x0 | uio[0] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x10 | `out_pin0.logical` | [4:2] | 3 | RW-halted | 0x0 | uio[0] logical index 0..7. |
| 0x10 | `out_pin0.mode` | [5] | 1 | RW-halted | 0x0 | uio[0] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x10 | `out_pin0.idle` | [6] | 1 | RW-halted | 0x0 | uio[0] idle value. |
| 0x11 | `out_pin1.owner` | [1:0] | 2 | RW-halted | 0x0 | uio[1] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x11 | `out_pin1.logical` | [4:2] | 3 | RW-halted | 0x0 | uio[1] logical index 0..7. |
| 0x11 | `out_pin1.mode` | [5] | 1 | RW-halted | 0x0 | uio[1] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x11 | `out_pin1.idle` | [6] | 1 | RW-halted | 0x0 | uio[1] idle value. |
| 0x12 | `out_pin2.owner` | [1:0] | 2 | RW-halted | 0x0 | uio[2] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x12 | `out_pin2.logical` | [4:2] | 3 | RW-halted | 0x0 | uio[2] logical index 0..7. |
| 0x12 | `out_pin2.mode` | [5] | 1 | RW-halted | 0x0 | uio[2] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x12 | `out_pin2.idle` | [6] | 1 | RW-halted | 0x0 | uio[2] idle value. |
| 0x13 | `out_pin3.owner` | [1:0] | 2 | RW-halted | 0x0 | uio[3] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x13 | `out_pin3.logical` | [4:2] | 3 | RW-halted | 0x0 | uio[3] logical index 0..7. |
| 0x13 | `out_pin3.mode` | [5] | 1 | RW-halted | 0x0 | uio[3] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x13 | `out_pin3.idle` | [6] | 1 | RW-halted | 0x0 | uio[3] idle value. |
| 0x14 | `out_pin4.owner` | [1:0] | 2 | RW-halted | 0x0 | uio[4] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x14 | `out_pin4.logical` | [4:2] | 3 | RW-halted | 0x0 | uio[4] logical index 0..7. |
| 0x14 | `out_pin4.mode` | [5] | 1 | RW-halted | 0x0 | uio[4] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x14 | `out_pin4.idle` | [6] | 1 | RW-halted | 0x0 | uio[4] idle value. |
| 0x15 | `out_pin5.owner` | [1:0] | 2 | RW-halted | 0x0 | uio[5] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x15 | `out_pin5.logical` | [4:2] | 3 | RW-halted | 0x0 | uio[5] logical index 0..7. |
| 0x15 | `out_pin5.mode` | [5] | 1 | RW-halted | 0x0 | uio[5] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x15 | `out_pin5.idle` | [6] | 1 | RW-halted | 0x0 | uio[5] idle value. |
| 0x16 | `out_pin6.owner` | [1:0] | 2 | RW-halted | 0x0 | uio[6] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x16 | `out_pin6.logical` | [4:2] | 3 | RW-halted | 0x0 | uio[6] logical index 0..7. |
| 0x16 | `out_pin6.mode` | [5] | 1 | RW-halted | 0x0 | uio[6] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x16 | `out_pin6.idle` | [6] | 1 | RW-halted | 0x0 | uio[6] idle value. |
| 0x17 | `out_pin7.owner` | [1:0] | 2 | RW-halted | 0x0 | uio[7] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x17 | `out_pin7.logical` | [4:2] | 3 | RW-halted | 0x0 | uio[7] logical index 0..7. |
| 0x17 | `out_pin7.mode` | [5] | 1 | RW-halted | 0x0 | uio[7] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x17 | `out_pin7.idle` | [6] | 1 | RW-halted | 0x0 | uio[7] idle value. |
| 0x18 | `out_pin8.owner` | [1:0] | 2 | RW-halted | 0x0 | uo_out[1] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x18 | `out_pin8.logical` | [4:2] | 3 | RW-halted | 0x0 | uo_out[1] logical index 0..7. |
| 0x18 | `out_pin8.mode` | [5] | 1 | RW-halted | 0x0 | uo_out[1] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x18 | `out_pin8.idle` | [6] | 1 | RW-halted | 0x0 | uo_out[1] idle value. |
| 0x19 | `out_pin9.owner` | [1:0] | 2 | RW-halted | 0x0 | uo_out[2] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x19 | `out_pin9.logical` | [4:2] | 3 | RW-halted | 0x0 | uo_out[2] logical index 0..7. |
| 0x19 | `out_pin9.mode` | [5] | 1 | RW-halted | 0x0 | uo_out[2] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x19 | `out_pin9.idle` | [6] | 1 | RW-halted | 0x0 | uo_out[2] idle value. |
| 0x1A | `out_pin10.owner` | [1:0] | 2 | RW-halted | 0x0 | uo_out[3] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x1A | `out_pin10.logical` | [4:2] | 3 | RW-halted | 0x0 | uo_out[3] logical index 0..7. |
| 0x1A | `out_pin10.mode` | [5] | 1 | RW-halted | 0x0 | uo_out[3] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x1A | `out_pin10.idle` | [6] | 1 | RW-halted | 0x0 | uo_out[3] idle value. |
| 0x1B | `out_pin11.owner` | [1:0] | 2 | RW-halted | 0x0 | uo_out[4] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x1B | `out_pin11.logical` | [4:2] | 3 | RW-halted | 0x0 | uo_out[4] logical index 0..7. |
| 0x1B | `out_pin11.mode` | [5] | 1 | RW-halted | 0x0 | uo_out[4] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x1B | `out_pin11.idle` | [6] | 1 | RW-halted | 0x0 | uo_out[4] idle value. |
| 0x1C | `out_pin12.owner` | [1:0] | 2 | RW-halted | 0x0 | uo_out[5] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x1C | `out_pin12.logical` | [4:2] | 3 | RW-halted | 0x0 | uo_out[5] logical index 0..7. |
| 0x1C | `out_pin12.mode` | [5] | 1 | RW-halted | 0x0 | uo_out[5] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x1C | `out_pin12.idle` | [6] | 1 | RW-halted | 0x0 | uo_out[5] idle value. |
| 0x1D | `out_pin13.owner` | [1:0] | 2 | RW-halted | 0x0 | uo_out[6] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x1D | `out_pin13.logical` | [4:2] | 3 | RW-halted | 0x0 | uo_out[6] logical index 0..7. |
| 0x1D | `out_pin13.mode` | [5] | 1 | RW-halted | 0x0 | uo_out[6] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x1D | `out_pin13.idle` | [6] | 1 | RW-halted | 0x0 | uo_out[6] idle value. |
| 0x1E | `out_pin14.owner` | [1:0] | 2 | RW-halted | 0x0 | uo_out[7] owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal. |
| 0x1E | `out_pin14.logical` | [4:2] | 3 | RW-halted | 0x0 | uo_out[7] logical index 0..7. |
| 0x1E | `out_pin14.mode` | [5] | 1 | RW-halted | 0x0 | uo_out[7] mode: 0 push-pull, 1 open-drain (illegal on uo_out). |
| 0x1E | `out_pin14.idle` | [6] | 1 | RW-halted | 0x0 | uo_out[7] idle value. |
| 0x30 | `input_map0.0` | [3:0] | 4 | RW-halted | 0x0 | ctx0 logical input 0 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x31 | `input_map0.1` | [3:0] | 4 | RW-halted | 0x0 | ctx0 logical input 1 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x32 | `input_map0.2` | [3:0] | 4 | RW-halted | 0x0 | ctx0 logical input 2 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x33 | `input_map0.3` | [3:0] | 4 | RW-halted | 0x0 | ctx0 logical input 3 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x34 | `input_map0.4` | [3:0] | 4 | RW-halted | 0x0 | ctx0 logical input 4 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x35 | `input_map0.5` | [3:0] | 4 | RW-halted | 0x0 | ctx0 logical input 5 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x36 | `input_map0.6` | [3:0] | 4 | RW-halted | 0x0 | ctx0 logical input 6 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x37 | `input_map0.7` | [3:0] | 4 | RW-halted | 0x0 | ctx0 logical input 7 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x38 | `input_map1.0` | [3:0] | 4 | RW-halted | 0x0 | ctx1 logical input 0 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x39 | `input_map1.1` | [3:0] | 4 | RW-halted | 0x0 | ctx1 logical input 1 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x3A | `input_map1.2` | [3:0] | 4 | RW-halted | 0x0 | ctx1 logical input 2 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x3B | `input_map1.3` | [3:0] | 4 | RW-halted | 0x0 | ctx1 logical input 3 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x3C | `input_map1.4` | [3:0] | 4 | RW-halted | 0x0 | ctx1 logical input 4 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x3D | `input_map1.5` | [3:0] | 4 | RW-halted | 0x0 | ctx1 logical input 5 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x3E | `input_map1.6` | [3:0] | 4 | RW-halted | 0x0 | ctx1 logical input 6 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x3F | `input_map1.7` | [3:0] | 4 | RW-halted | 0x0 | ctx1 logical input 7 -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal. |
| 0x40-0x41 | `param0.0` | [15:0] | 16 | RW-halted | 0x0 | ctx0 parameter register P0, little-endian. |
| 0x42-0x43 | `param0.1` | [15:0] | 16 | RW-halted | 0x0 | ctx0 parameter register P1, little-endian. |
| 0x44-0x45 | `param0.2` | [15:0] | 16 | RW-halted | 0x0 | ctx0 parameter register P2, little-endian. |
| 0x46-0x47 | `param0.3` | [15:0] | 16 | RW-halted | 0x0 | ctx0 parameter register P3, little-endian. |
| 0x48-0x49 | `param1.0` | [15:0] | 16 | RW-halted | 0x0 | ctx1 parameter register P0, little-endian. |
| 0x4A-0x4B | `param1.1` | [15:0] | 16 | RW-halted | 0x0 | ctx1 parameter register P1, little-endian. |
| 0x4C-0x4D | `param1.2` | [15:0] | 16 | RW-halted | 0x0 | ctx1 parameter register P2, little-endian. |
| 0x4E-0x4F | `param1.3` | [15:0] | 16 | RW-halted | 0x0 | ctx1 parameter register P3, little-endian. |

## Status registers (Read_status)

| Address | Name | Bits | Width | Access | Reset | Meaning |
|---|---|---|---|---|---|---|
| 0x00 | `run.ctx0` | [0] | 1 | RO | 0x0 | ctx0 running (1) or halted (0). |
| 0x00 | `run.ctx1` | [1] | 1 | RO | 0x0 | ctx1 running (1) or halted (0). |
| 0x01 | `host_error` | [0] | 1 | RO-sticky | 0x0 | Set by an invalid command byte, a rejected or malformed access, or an invalid Ctrl byte. |
| 0x08 | `fault.ctx0` | [1:0] | 2 | RO-sticky | 0x0 | ctx0 sticky fault: 0 none, 1 LATE, 2 ILLEGAL, 3 HOST_CFG. |
| 0x09 | `fault.ctx1` | [1:0] | 2 | RO-sticky | 0x0 | ctx1 sticky fault: 0 none, 1 LATE, 2 ILLEGAL, 3 HOST_CFG. |
| 0x10 | `flag.ctx0.event_overrun` | [0] | 1 | RO-sticky | 0x0 | ctx0: event captured while the previous capture was unread. |
| 0x10 | `flag.ctx0.trace_lost` | [1] | 1 | RO-sticky | 0x0 | ctx0: trace entry dropped, trace FIFO full. |
| 0x10 | `flag.ctx0.host_push_overflow` | [2] | 1 | RO-sticky | 0x0 | ctx0: Fifo_push to a full RX FIFO; byte dropped. |
| 0x10 | `flag.ctx0.host_pop_underflow` | [3] | 1 | RO-sticky | 0x0 | ctx0: Fifo_pop from an empty TX FIFO; 0x00 returned. |
| 0x11 | `flag.ctx1.event_overrun` | [0] | 1 | RO-sticky | 0x0 | ctx1: event captured while the previous capture was unread. |
| 0x11 | `flag.ctx1.trace_lost` | [1] | 1 | RO-sticky | 0x0 | ctx1: trace entry dropped, trace FIFO full. |
| 0x11 | `flag.ctx1.host_push_overflow` | [2] | 1 | RO-sticky | 0x0 | ctx1: Fifo_push to a full RX FIFO; byte dropped. |
| 0x11 | `flag.ctx1.host_pop_underflow` | [3] | 1 | RO-sticky | 0x0 | ctx1: Fifo_pop from an empty TX FIFO; 0x00 returned. |
| 0x20 | `rx_level.ctx0` | [7:0] | 8 | RO | 0x0 | ctx0 entries currently in the rx FIFO. |
| 0x21 | `tx_level.ctx0` | [7:0] | 8 | RO | 0x0 | ctx0 entries currently in the tx FIFO. |
| 0x22 | `trace_level.ctx0` | [7:0] | 8 | RO | 0x0 | ctx0 entries currently in the trace FIFO. |
| 0x24 | `rx_level.ctx1` | [7:0] | 8 | RO | 0x0 | ctx1 entries currently in the rx FIFO. |
| 0x25 | `tx_level.ctx1` | [7:0] | 8 | RO | 0x0 | ctx1 entries currently in the tx FIFO. |
| 0x26 | `trace_level.ctx1` | [7:0] | 8 | RO | 0x0 | ctx1 entries currently in the trace FIFO. |
