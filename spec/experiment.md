# PEX experiment format (generated; do not edit)

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
| `["Push", ctx, word]` | push `word` (0..65535) into the host-to-chip FIFO of context ctx |
| `["Expect_pop", ctx, word]` | pop the chip-to-host FIFO of ctx and expect `word` (0..65535) |
| `["Run_cycles", n]` | run n core cycles, n >= 0 |
| `["Expect_no_fault"]` | expect that no fault is set |

## Example

The `image` below is abbreviated to three words.

```json
{
  "name": "example",
  "image": {
    "format": "pex-image-v0",
    "words": [ 4660, 65535, 0 ],
    "entry": { "ctx0": 0, "ctx1": 2 },
    "labels": { "start": 0 }
  },
  "config": {
    "outputs": [
      {
        "owner": [ "Ctx0" ],
        "logical": 0,
        "mode": [ "Open_drain" ],
        "idle": false
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      },
      {
        "owner": [ "Ctx1" ],
        "logical": 1,
        "mode": [ "Push_pull" ],
        "idle": true
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      },
      {
        "owner": [ "Unowned" ],
        "logical": 0,
        "mode": [ "Push_pull" ],
        "idle": false
      }
    ],
    "input_map": [
      [ 0, 1, 2, 3, 4, 5, 6, 7 ], [ 12, 11, 10, 9, 8, 7, 6, 5 ]
    ],
    "trace_mode": [ "Events" ],
    "entry": [ 0, 2 ]
  },
  "params": [ [ 1, 2, 3, 4 ], [ 0, 0, 65535, 0 ] ],
  "experiment_id": 7,
  "script": [
    [ "Push", 0, 165 ],
    [ "Run_cycles", 1000 ],
    [ "Expect_pop", 1, 90 ],
    [ "Expect_no_fault" ]
  ]
}
```
