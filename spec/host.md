# PEX host SPI interface (candidate, freeze at G2)

Generated from `hw/host_proto/pex_host_proto.ml`; do not edit. Spec sections 4.5, 4.6, 5, 6.

## Framing

SPI mode 0, MSB first. A frame is `cmd, addr hi, addr lo, [turnaround,] data...` while CS_n is low. The address is 16 bits, big-endian. A partial byte at CS rising is discarded; only complete bytes (and, for memory, complete words) take effect. A frame cut short before its address is complete has no effect and sets no error. Multi-byte register fields are little-endian.

MISO is 0 during the command and address bytes. Every read command (Read_mem, Read_cfg, Read_status, Fifo_pop, Trace_pop) has exactly one dummy turnaround byte after the address, during which MISO is 0 (it gives the core time to fetch the first data); data follows.

An invalid command byte: the whole frame is ignored and the host error flag is set.

Reserved bits (bits of a mapped byte not in any field, and unmapped bytes inside the address ranges below) are ignored on write and read as 0.

## Commands

Instruction memory depth is `IMEM_DEPTH` words, where IMEM_DEPTH = 256 (fixed at G1: 256, or 128 if G1 picks the flip-flop fallback). It bounds the Write_mem/Read_mem word address.

| Byte | Command | Address | Data |
|---|---|---|---|
| `0x10` | Write_mem | word address 0..IMEM_DEPTH-1 | 2 bytes per word, low byte first; word address auto-increments per word |
| `0x11` | Read_mem | word address 0..IMEM_DEPTH-1 | turnaround, then 2 bytes per word, low byte first; auto-increment per word |
| `0x20` | Write_cfg | cfg byte address | one byte per register; auto-increment per byte |
| `0x21` | Read_cfg | cfg byte address | turnaround, then as Write_cfg, read |
| `0x30` | Read_status | status byte address | turnaround, then as Read_cfg, status space |
| `0x40` | Ctrl | addr hi = 0, addr lo = context mask (bit0 ctx0, bit1 ctx1) | exactly one control byte (see Ctrl); extra bytes are ignored without error |
| `0x50`+ctx | Fifo_push | ignored (send 0) | each byte is pushed to the context's RX FIFO, which firmware reads with PULL (PULL blocks when empty); no auto-increment |
| `0x60`+ctx | Fifo_pop | ignored | turnaround, then each byte is popped from the context's TX FIFO, which firmware fills with PUSH; no auto-increment |
| `0x70`+ctx | Trace_pop | ignored | turnaround, then 4 bytes per entry, oldest first: tag, time[7:0], time[15:8], time[23:16] (the 32-bit entry `{time[23:0], tag[7:0]}` little-endian) |

Direction summary: Fifo_push writes the context's RX FIFO, which firmware reads with PULL (PULL blocks when empty). Firmware PUSH writes the context's TX FIFO, which the host drains with Fifo_pop.

Errors: a memory address at or past IMEM_DEPTH, or a write to an unmapped or read-only register, sets the host error flag; the offending byte and the rest of the frame are ignored. Reads of unmapped addresses return 0x00 and set nothing. A rejected read (Read_mem while running) returns 0x00 data bytes and sets the host error flag. Fifo_push to a full FIFO drops the byte and sets `host_push_overflow`.

Pop side effects happen on byte completion. A Fifo_pop byte is consumed when its 8th bit has been shifted out. A Trace_pop entry is consumed only after all 4 of its bytes complete; if CS rises mid-entry the entry is not consumed and the next Trace_pop restarts it. Pop on an empty FIFO returns 0x00, consumes nothing, and (Fifo_pop) sets `host_pop_underflow`; Trace_pop on empty sets no flag.

Write_mem and Read_mem are halted-only (instruction memory is never read by the host while a core fetches); Write_cfg is halted-only for every cfg register. Each is rejected while any context runs and sets the host error flag. Read_cfg, Read_status, Ctrl, Fifo_* and Trace_pop work at any time. There are no RW-any registers in v1.

## Ctrl

The frame carries one data byte, applied to every context in the mask (addr lo). mask = 0 is a no-op with no error. Mask bits 2..7 set, or addr hi nonzero: frame ignored and host error set. An invalid data byte: frame ignored and host error set.

| Byte | Meaning |
|---|---|
| `0x01` | Start. Validates the shared pin configuration and the masked contexts' configuration; if invalid, no masked context starts and `HOST_CFG` is set on each masked context. Otherwise, if no context is running, NOW is reset to 0 at the first run cycle; if the other context is already running, starting this one does not reset NOW. Start on a running context is a no-op. Start on a context with an uncleared fault is rejected and sets host error. |
| `0x02` | Halt the masked contexts. |
| `0x03` | Clear_faults: clears faults and sticky flags of the masked contexts, and always clears the host error flag. |
| `0x80`+n | Step: allowed only when both contexts are halted (otherwise ignored and host error set). Runs the masked contexts for n+1 of their own slots (n 0..127), then halts them; NOW advances with them; unmasked contexts stay halted. |

Status registers have no write path, so sticky bits are cleared by Clear_faults only (there is no W1C).

## Access codes

`RW-halted` writable only while halted. `RO` read-only. `RO-sticky` read-only, set by hardware, cleared by Clear_faults. All reset values are 0.

## Config registers (Write_cfg / Read_cfg)

| Address | Name | Bits | Width | Access | Reset | Meaning |
|---|---|---|---|---|---|---|
| 0x00-0x01 | `experiment_id` | [15:0] | 16 | RW-halted | 0x0 | 16-bit experiment ID, little-endian. |
| 0x04 | `trace_mode` | [1:0] | 2 | RW-halted | 0x0 | Trace mode: 0 = MARK, 1 = EVENTS, 2 = COMMITS; 3 is illegal (HOST_CFG at START). |
| 0x08 | `entry0` | [7:0] | 8 | RW-halted | 0x0 | Start address (instruction word address) of ctx0. |
| 0x09 | `entry1` | [7:0] | 8 | RW-halted | 0x0 | Start address (instruction word address) of ctx1. |
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
| 0x10 | `flag.ctx0.host_push_overflow` | [2] | 1 | RO-sticky | 0x0 | ctx0: host Fifo_push to a full RX FIFO (firmware-PULL side); byte dropped. |
| 0x10 | `flag.ctx0.host_pop_underflow` | [3] | 1 | RO-sticky | 0x0 | ctx0: host Fifo_pop from an empty TX FIFO (firmware-PUSH side); 0x00 returned. |
| 0x11 | `flag.ctx1.event_overrun` | [0] | 1 | RO-sticky | 0x0 | ctx1: event captured while the previous capture was unread. |
| 0x11 | `flag.ctx1.trace_lost` | [1] | 1 | RO-sticky | 0x0 | ctx1: trace entry dropped, trace FIFO full. |
| 0x11 | `flag.ctx1.host_push_overflow` | [2] | 1 | RO-sticky | 0x0 | ctx1: host Fifo_push to a full RX FIFO (firmware-PULL side); byte dropped. |
| 0x11 | `flag.ctx1.host_pop_underflow` | [3] | 1 | RO-sticky | 0x0 | ctx1: host Fifo_pop from an empty TX FIFO (firmware-PUSH side); 0x00 returned. |
| 0x20 | `rx_level.ctx0` | [7:0] | 8 | RO | 0x0 | ctx0 entries currently in the RX FIFO (host Fifo_push writes, firmware PULL reads). |
| 0x21 | `tx_level.ctx0` | [7:0] | 8 | RO | 0x0 | ctx0 entries currently in the TX FIFO (firmware PUSH writes, host Fifo_pop drains). |
| 0x22 | `trace_level.ctx0` | [7:0] | 8 | RO | 0x0 | ctx0 entries currently in the trace FIFO. |
| 0x24 | `rx_level.ctx1` | [7:0] | 8 | RO | 0x0 | ctx1 entries currently in the RX FIFO (host Fifo_push writes, firmware PULL reads). |
| 0x25 | `tx_level.ctx1` | [7:0] | 8 | RO | 0x0 | ctx1 entries currently in the TX FIFO (firmware PUSH writes, host Fifo_pop drains). |
| 0x26 | `trace_level.ctx1` | [7:0] | 8 | RO | 0x0 | ctx1 entries currently in the trace FIFO. |
