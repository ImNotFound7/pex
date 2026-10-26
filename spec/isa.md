# PEX ISA v0 (candidate, freeze at G2)

Generated from `hw/isa/pex_isa.ml` by `gen_spec.exe`; do not edit. Machine-readable form: `spec/isa.json`.

A 16-bit word is legal iff exactly one instruction entry matches: (w & match_mask) == match_value, (w & must_be_zero_mask) == 0, and every field value is within its min..max (enum fields: within `values`). Everything else, including op 0xB-0xF and every unassigned enum value, is ILLEGAL. Field value = (w >> lo) & ((1 << (hi-lo+1)) - 1). When mnemonic_from is set the mnemonic is that field's enum table name.

## Instructions

| id | syntax | op | sub w[11:8] | fields | must-be-zero mask | semantics |
|---|---|---|---|---|---|---|
| ldi | `ldi r, imm` | 0x0 | - | r[11:10] (0..3), imm[7:0] (0..255) | 0x0300 | r <- imm. |
| cmpi | `cmpi r, imm` | 0x1 | - | r[11:10] (0..3), imm[7:0] (0..255) | 0x0300 | Sets Z and C as for sub (r - imm), without writing r. |
| alu | `<alu> rd, rs` | 0x2 | - | alu[11:8] (alu 0,1,2,3,4,5,6), rd[7:6] (0..3), rs[5:4] (0..3) | 0x000F | rd <- rd <alu> rs. cmp sets Z and C as for sub, without writing rd. |
| shift | `<shl|shr> rd` | 0x2 | - | alu[11:8] (alu 7,8), rd[7:6] (0..3) | 0x003F | shl: C <- rd[7], rd <- rd << 1. shr: C <- rd[0], rd <- rd >> 1. Bits 5:4 (rs) must be 0. |
| jump | `<cond> addr` | 0x3 | - | cond[10:8] (cond 0,1,2,3,4,5,6,7), addr[7:0] (0..255) | 0x0800 | Jump to addr if the condition holds; call also saves the return address (1-deep). |
| djnz | `djnz r, addr` | 0x4 | - | r[11:10] (0..3), addr[7:0] (0..255) | 0x0300 | r <- r - 1; jump to addr if the new r is non-zero. Flags unchanged. |
| stg_imm | `stg field, imm` | 0x5 | - | field[11:10] (field 0,1,2), imm[7:0] (0..255) | 0x0300 | Stage the out / oe / mask register from imm. No timing effect. |
| stg_reg | `stg field, r` | 0x6 | - | field[11:8] (field 0,1,2), r[7:6] (0..3) | 0x003F | Stage the out / oe / mask register from r. No timing effect. |
| outb | `outb j` | 0x6 | 3 | j[2:0] (0..7) | 0x00F8 | staged out[j] <- SR[7]; SR unchanged (no shift). |
| outl | `outl j` | 0x6 | 4 | j[2:0] (0..7) | 0x00F8 | staged out[j] <- SR[0]; SR unchanged (no shift). |
| inb | `inb j` | 0x6 | 5 | j[2:0] (0..7) | 0x00F8 | SR <- (SR << 1) | SAMPLE[j]. |
| inr | `inr j` | 0x6 | 6 | j[2:0] (0..7) | 0x00F8 | SR <- (SAMPLE[j] << 7) | (SR >> 1). |
| ldsr | `ldsr r` | 0x6 | 7 | r[7:6] (0..3) | 0x003F | SR <- r. |
| stsr | `stsr r` | 0x6 | 8 | r[7:6] (0..3) | 0x003F | r <- SR. |
| ssl | `ssl` | 0x6 | 9 | - | 0x00FF | SR <- SR << 1, zero fill. |
| ssr | `ssr` | 0x6 | 10 | - | 0x00FF | SR <- SR >> 1, zero fill. |
| at_imm | `at +n[, sample]` | 0x7 | - | sample[11] (0..1), offset[10:0] (0..2047) | 0x0000 | Timed action at REF + n (spec 4.2); sample flag loads SAMPLE on commit. |
| wait_imm | `wait +t` | 0x8 | - | t[11:0] (0..4095) | 0x0000 | Wait for the armed event with timeout T = REF + t (spec 4.4). |
| at_param | `at pN[, sample]` | 0x9 | 0 | sample[4] (0..1), p[1:0] (0..3) | 0x00EC | Timed action at REF + parameter register pN. |
| wait | `wait` | 0x9 | 1 | - | 0x00FF | Wait for the armed event, no timeout. |
| wait_param | `wait pN` | 0x9 | 2 | p[1:0] (0..3) | 0x00FC | Wait for the armed event with timeout REF + parameter register pN. |
| sync | `sync` | 0x9 | 3 | - | 0x00FF | REF <- execute cycle. |
| disarm | `arm none` | 0x9 | 4 | - | 0x00FF | Disarm the event condition. Bits 7:0 must be 0 (j = 0). |
| arm | `arm j, edge` | 0x9 | 4 | j[6:4] (0..7), edge[2:0] (edge 1,2,3,4,5) | 0x0088 | Arm the event condition on logical input j with the given edge/level. |
| ret | `ret` | 0x9 | 5 | - | 0x00FF | Return from call (1-deep). |
| halt | `halt` | 0x9 | 6 | - | 0x00FF | Halt the context. |
| fault | `fault c` | 0x9 | 7 | c[3:0] (0..15) | 0x00F0 | Raise fault code c. |
| push | `push r` | 0x9 | 8 | r[7:6] (0..3) | 0x003F | Push r to the host FIFO. |
| pull | `pull r` | 0x9 | 9 | r[7:6] (0..3) | 0x003F | Pull from the host FIFO into r (blocks). |
| ldp | `ldp r, pN.lo|hi` | 0x9 | 10 | r[7:6] (0..3), half[4] (half 0,1), p[1:0] (0..3) | 0x002C | r <- low or high byte of parameter register pN. |
| mark | `mark imm` | 0xA | - | imm[7:0] (0..255) | 0x0F00 | Trace marker imm. |

Op 0xB-0xF: ILLEGAL.

## alu

| value | name |
|---|---|
| 0 | mov |
| 1 | add |
| 2 | sub |
| 3 | and |
| 4 | or |
| 5 | xor |
| 6 | cmp |
| 7 | shl |
| 8 | shr |

## cond

| value | name |
|---|---|
| 0 | jmp |
| 1 | jz |
| 2 | jnz |
| 3 | jc |
| 4 | jnc |
| 5 | call |
| 6 | jto |
| 7 | jnto |

## edge

| value | name |
|---|---|
| 0 | none |
| 1 | rise |
| 2 | fall |
| 3 | either |
| 4 | high |
| 5 | low |

## field

| value | name |
|---|---|
| 0 | out |
| 1 | oe |
| 2 | mask |

## half

| value | name |
|---|---|
| 0 | lo |
| 1 | hi |

## SR semantics

- outb j: staged out[j] <- SR[7], no shift.
- outl j: staged out[j] <- SR[0], no shift.
- inb j: SR <- (SR << 1) | SAMPLE[j].
- inr j: SR <- (SAMPLE[j] << 7) | (SR >> 1).
- ssl / ssr: shift with a zero fill.

## ALU and flag semantics

- shl: C <- r[7], r <- r << 1.
- shr: C <- r[0], r <- r >> 1.
- cmp / cmpi: set Z and C as for sub, without writing.
- djnz: decrement r, jump if non-zero, flags unchanged.
