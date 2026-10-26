open! Base
open Pex_experiment

let example =
  let image =
    `Assoc
      [ "format", `String "pex-image-v0"
      ; "words", `List [ `Int 0x1234; `Int 0xFFFF; `Int 0 ]
      ; "entry", `Assoc [ "ctx0", `Int 0; "ctx1", `Int 2 ]
      ; "labels", `Assoc [ "start", `Int 0 ]
      ]
  in
  let pin i =
    { owner = (if i = 0 then Ctx0 else if i = 8 then Ctx1 else Unowned)
    ; logical = (if i = 8 then 1 else 0)
    ; mode = (if i = 0 then Open_drain else Push_pull)
    ; idle = i = 8
    }
  in
  { name = "example"
  ; image
  ; config =
      { outputs = Array.init 15 ~f:pin
      ; input_map = [| Array.init 8 ~f:Fn.id; Array.init 8 ~f:(fun i -> 12 - i) |]
      ; trace_mode = Events
      ; entry = 0, 2
      }
  ; params = [| [| 1; 2; 3; 4 |]; [| 0; 0; 0xFFFF; 0 |] |]
  ; experiment_id = 7
  ; script = [ Push (0, 0xA5); Run_cycles 1000; Expect_pop (1, 0x5A); Expect_no_fault ]
  }
;;

let () =
  assert (Result.is_ok (validate example));
  Stdio.print_string
    {|# PEX experiment format (generated; do not edit)

**Draft v0, freeze at G2.** Generated from `host/experiment/pex_experiment.ml`
by `dune build @gen --auto-promote`. An experiment is the description of one run:
firmware image, chip configuration, parameters and host script. This file fully
specifies its JSON form (the `config` file read by other implementations).

## Conventions

- Every object is closed: unknown fields and missing fields are errors.
- "int" means a JSON integer (no fraction or exponent).
- Records are JSON objects keyed by the field names below.
- **Tuples** `(a, b)` are JSON arrays `[a, b]` of exactly that length.
- **Variants** are JSON arrays whose first element is the constructor name as a
  string, followed by the constructor's arguments in order: `["Unowned"]`,
  `["Push", 0, 165]`. Constructors without arguments are still one-element arrays.
- **Context** numbers are 0 or 1.
- Arrays are JSON arrays. Shapes (lengths) are given below and checked by validation.
- Parsing (shape, types, field names) and validation (ranges, lengths) are separate
  steps; a document must satisfy both.

## Top level object

| field | type | rule |
|---|---|---|
| `name` | string | free text |
| `image` | object | assembler output, see below |
| `config` | object | chip configuration, see below |
| `params` | int[2][4] | `params[ctx][i]` is parameter P_i of context ctx; each 0..65535 |
| `experiment_id` | int | 0..65535 |
| `script` | step[] | host script, executed in order, see below |

## `image`

The JSON written by `pexasm`: an object with `format` = `"pex-image-v0"`,
`words` (list of at most 256 ints, each 0..65535, the instruction words loaded
at address 0), `entry` (object `{"ctx0": int, "ctx1": int}`, the addresses the
assembler recorded), and optionally other fields (such as `labels`), which are
carried along and not interpreted. The `image` object is the only open object.

## `config`

| field | type | rule |
|---|---|---|
| `outputs` | out_pin[15] | exactly 15 pins, index convention below |
| `input_map` | int[2][8] | `input_map[ctx][j]` = physical input feeding logical input j of context ctx; each 0..12 |
| `trace_mode` | trace_mode | `["Mark"]`, `["Events"]` or `["Commits"]` |
| `entry` | [int, int] | host-written start address of ctx0 and ctx1; each must be below the number of image words. The default is the image's `entry` |

Physical input index: 0-7 = `uio_in[0..7]`, 8-12 = `ui_in[3..7]`.

Output pin index (the position in `outputs`): 0-7 = `uio[0..7]`, 8-14 = `uo_out[1..7]`.
`uo_out[0]` is the host MISO and is never ownable.

### `out_pin`

| field | type | rule |
|---|---|---|
| `owner` | owner | `["Unowned"]`, `["Ctx0"]` or `["Ctx1"]` |
| `logical` | int | logical output index, 0..7 |
| `mode` | mode | `["Push_pull"]` or `["Open_drain"]`; open-drain is forbidden on outputs 8..14 (the `uo_out` pins) |
| `idle` | bool | idle value shown while the context is halted, reset or faulted |

## `script` steps

| encoding | meaning |
|---|---|
| `["Push", ctx, byte]` | push `byte` (0..255) into the host-to-chip (TX) FIFO of context ctx |
| `["Expect_pop", ctx, byte]` | pop the chip-to-host (RX) FIFO of ctx (FIFOs are 8 bits wide) and expect `byte` (0..255) |
| `["Run_cycles", n]` | run n core cycles, n >= 0 |
| `["Expect_no_fault"]` | expect that no fault is set |

## Example

The `image` below is abbreviated to three words.

```json
|};
  Stdio.print_endline (Yojson.Safe.pretty_to_string (to_json example));
  Stdio.print_string "```\n"
;;
