open! Base

let sprintf = Printf.sprintf

type cmd =
  | Write_mem
  | Read_mem
  | Write_cfg
  | Read_cfg
  | Read_status
  | Ctrl
  | Fifo_push of int
  | Fifo_pop of int
  | Trace_pop of int
[@@deriving sexp_of, equal]

type ctrl =
  | Start
  | Halt
  | Step of int
  | Clear_faults
[@@deriving sexp_of, equal]

let check_ctx c = if c < 0 || c > 1 then raise_s [%message "context must be 0|1" (c : int)]

let cmd_byte = function
  | Write_mem -> 0x10
  | Read_mem -> 0x11
  | Write_cfg -> 0x20
  | Read_cfg -> 0x21
  | Read_status -> 0x30
  | Ctrl -> 0x40
  | Fifo_push c -> check_ctx c; 0x50 + c
  | Fifo_pop c -> check_ctx c; 0x60 + c
  | Trace_pop c -> check_ctx c; 0x70 + c
;;

let cmd_of_byte = function
  | 0x10 -> Some Write_mem
  | 0x11 -> Some Read_mem
  | 0x20 -> Some Write_cfg
  | 0x21 -> Some Read_cfg
  | 0x30 -> Some Read_status
  | 0x40 -> Some Ctrl
  | (0x50 | 0x51) as b -> Some (Fifo_push (b - 0x50))
  | (0x60 | 0x61) as b -> Some (Fifo_pop (b - 0x60))
  | (0x70 | 0x71) as b -> Some (Trace_pop (b - 0x70))
  | _ -> None
;;

let ctrl_byte = function
  | Start -> 0x01
  | Halt -> 0x02
  | Clear_faults -> 0x03
  | Step n ->
    if n < 0 || n > 127 then raise_s [%message "Step must be 0..127" (n : int)];
    0x80 lor n
;;

let ctrl_of_byte = function
  | 0x01 -> Some Start
  | 0x02 -> Some Halt
  | 0x03 -> Some Clear_faults
  | b when b >= 0x80 && b <= 0xFF -> Some (Step (b land 0x7F))
  | _ -> None
;;

let frame cmd ~addr ~bytes =
  if addr < 0 || addr > 0xFFFF then raise_s [%message "addr out of range" (addr : int)];
  List.iter bytes ~f:(fun b ->
    if b < 0 || b > 255 then raise_s [%message "data byte out of range" (b : int)]);
  cmd_byte cmd :: (addr lsr 8) :: (addr land 0xFF) :: bytes
;;

type space =
  | Cfg
  | Status
[@@deriving sexp_of, equal]

type access =
  | Rw_halted
  | Ro
  | Ro_sticky
[@@deriving sexp_of, equal]

type field =
  { name : string
  ; space : space
  ; addr : int
  ; lsb : int
  ; width : int
  ; access : access
  ; reset : int
  ; doc : string
  }
[@@deriving sexp_of]

let cfg name ~addr ?(lsb = 0) ~width doc =
  { name; space = Cfg; addr; lsb; width; access = Rw_halted; reset = 0; doc }
;;

let status name ~addr ?(lsb = 0) ~width ?(access = Ro) doc =
  { name; space = Status; addr; lsb; width; access; reset = 0; doc }
;;

let ctxs = [ 0; 1 ]

(* Config space.  Layout: 0x00 identity, 0x04 trace, 0x08 entries, 0x10 pins,
   0x30 input maps, 0x40 params.  Gaps are reserved for growth. *)
let cfg_fields =
  List.concat
    [ [ cfg "experiment_id" ~addr:0x00 ~width:16 "16-bit experiment ID, little-endian."
      ; cfg
          "trace_mode"
          ~addr:0x04
          ~width:2
          "Trace mode: 0 = MARK, 1 = EVENTS, 2 = COMMITS; 3 is illegal (HOST_CFG at START)."
      ]
    ; List.map ctxs ~f:(fun c ->
        cfg (sprintf "entry%d" c) ~addr:(0x08 + c) ~width:8 (sprintf "Start address (instruction word address) of ctx%d." c))
    ; List.concat_map (List.range 0 15) ~f:(fun p ->
        let addr = 0x10 + p
        and where = if p < 8 then sprintf "uio[%d]" p else sprintf "uo_out[%d]" (p - 7) in
        let n f = sprintf "out_pin%d.%s" p f in
        [ cfg (n "owner") ~addr ~lsb:0 ~width:2 (where ^ " owner: 0 none, 1 ctx0, 2 ctx1; 3 illegal.")
        ; cfg (n "logical") ~addr ~lsb:2 ~width:3 (where ^ " logical index 0..7.")
        ; cfg (n "mode") ~addr ~lsb:5 ~width:1 (where ^ " mode: 0 push-pull, 1 open-drain (illegal on uo_out).")
        ; cfg (n "idle") ~addr ~lsb:6 ~width:1 (where ^ " idle value.")
        ])
    ; List.concat_map ctxs ~f:(fun c ->
        List.map (List.range 0 8) ~f:(fun j ->
          cfg
            (sprintf "input_map%d.%d" c j)
            ~addr:(0x30 + (8 * c) + j)
            ~width:4
            (sprintf "ctx%d logical input %d -> physical input 0..12 (0-7 uio_in, 8-12 ui_in[3..7]); 13..15 illegal." c j)))
    ; List.concat_map ctxs ~f:(fun c ->
        List.map (List.range 0 4) ~f:(fun k ->
          cfg
            (sprintf "param%d.%d" c k)
            ~addr:(0x40 + (8 * c) + (2 * k))
            ~width:16
            (sprintf "ctx%d parameter register P%d, little-endian." c k)))
    ]
;;

(* Status space.  Layout: 0x00 run/host error, 0x08 faults, 0x10 flags,
   0x20 FIFO levels. *)
let status_fields =
  List.concat
    [ List.map ctxs ~f:(fun c ->
        status (sprintf "run.ctx%d" c) ~addr:0x00 ~lsb:c ~width:1 (sprintf "ctx%d running (1) or halted (0)." c))
    ; [ status
          "host_error"
          ~addr:0x01
          ~width:1
          ~access:Ro_sticky
          "Set by an invalid command byte, a rejected or malformed access, or an invalid Ctrl byte."
      ]
    ; List.map ctxs ~f:(fun c ->
        status
          (sprintf "fault.ctx%d" c)
          ~addr:(0x08 + c)
          ~width:2
          ~access:Ro_sticky
          (sprintf "ctx%d sticky fault: 0 none, 1 LATE, 2 ILLEGAL, 3 HOST_CFG." c))
    ; List.concat_map ctxs ~f:(fun c ->
        List.mapi
          [ "event_overrun", "event captured while the previous capture was unread"
          ; "trace_lost", "trace entry dropped, trace FIFO full"
          ; "host_push_overflow", "host Fifo_push to a full RX FIFO (firmware-PULL side); byte dropped"
          ; "host_pop_underflow", "host Fifo_pop from an empty TX FIFO (firmware-PUSH side); 0x00 returned"
          ]
          ~f:(fun i (n, d) ->
            status
              (sprintf "flag.ctx%d.%s" c n)
              ~addr:(0x10 + c)
              ~lsb:i
              ~width:1
              ~access:Ro_sticky
              (sprintf "ctx%d: %s." c d)))
    ; List.concat_map ctxs ~f:(fun c ->
        List.mapi
          [ "rx_level", "RX FIFO (host Fifo_push writes, firmware PULL reads)"
          ; "tx_level", "TX FIFO (firmware PUSH writes, host Fifo_pop drains)"
          ; "trace_level", "trace FIFO"
          ]
          ~f:(fun i (n, d) ->
          status
            (sprintf "%s.ctx%d" n c)
            ~addr:(0x20 + (4 * c) + i)
            ~width:8
            (sprintf "ctx%d entries currently in the %s." c d)))
    ]
;;

let fields = cfg_fields @ status_fields
let space_name = function Cfg -> "cfg" | Status -> "status"
let access_name = function Rw_halted -> "RW-halted" | Ro -> "RO" | Ro_sticky -> "RO-sticky"
let bytes_of f = (f.lsb + f.width + 7) / 8

let imem_depth = 256

let spec_json () =
  let field f =
    `Assoc
      [ "name", `String f.name
      ; "space", `String (space_name f.space)
      ; "addr", `Int f.addr
      ; "lsb", `Int f.lsb
      ; "width", `Int f.width
      ; "access", `String (access_name f.access)
      ; "reset", `Int f.reset
      ; "doc", `String f.doc
      ]
  in
  let cmds =
    [ Write_mem; Read_mem; Write_cfg; Read_cfg; Read_status; Ctrl; Fifo_push 0; Fifo_push 1
    ; Fifo_pop 0; Fifo_pop 1; Trace_pop 0; Trace_pop 1 ]
  in
  `Assoc
    [ "format", `String "pex-host-v1"
    ; "status", `String "candidate, freeze at G2"
    ; ( "commands"
      , `List
          (List.map cmds ~f:(fun c ->
             `Assoc
               [ "name", `String (Sexp.to_string (sexp_of_cmd c))
               ; "byte", `Int (cmd_byte c)
               ])) )
    ; ( "ctrl"
      , `List
          (List.map [ Start; Halt; Clear_faults; Step 0; Step 127 ] ~f:(fun c ->
             `Assoc
               [ "name", `String (Sexp.to_string (sexp_of_ctrl c)); "byte", `Int (ctrl_byte c) ])) )
    ; "imem_depth", `Int imem_depth
    ; "fields", `List (List.map fields ~f:field)
    ]
;;

let static_md =
  {|# PEX host SPI interface (candidate, freeze at G2)

Generated from `hw/host_proto/pex_host_proto.ml`; do not edit. Spec sections 4.5, 4.6, 5, 6.

## Framing

SPI mode 0, MSB first. A frame is `cmd, addr hi, addr lo, [turnaround,] data...` while CS_n is low. The address is 16 bits, big-endian. A partial byte at CS rising is discarded; only complete bytes (and, for memory, complete words) take effect. A frame cut short before its address is complete has no effect and sets no error. Multi-byte register fields are little-endian.

MISO is 0 during the command and address bytes. Every read command (Read_mem, Read_cfg, Read_status, Fifo_pop, Trace_pop) has exactly one dummy turnaround byte after the address, during which MISO is 0 (it gives the core time to fetch the first data); data follows.

An invalid command byte: the whole frame is ignored and the host error flag is set.

Reserved bits (bits of a mapped byte not in any field, and unmapped bytes inside the address ranges below) are ignored on write and read as 0.

## Commands

Instruction memory depth is `IMEM_DEPTH` words, where IMEM_DEPTH = __DEPTH__ (fixed at G1: 256, or 128 if G1 picks the flip-flop fallback). It bounds the Write_mem/Read_mem word address.

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

|}
;;

let spec_markdown () =
  let table space =
    let rows =
      List.filter fields ~f:(fun f -> equal_space f.space space)
      |> List.sort ~compare:(fun a b -> [%compare: int * int] (a.addr, a.lsb) (b.addr, b.lsb))
      |> List.map ~f:(fun f ->
        let bits =
          if f.width > 8 then sprintf "[%d:0]" (f.width - 1)
          else if f.width = 1 then sprintf "[%d]" f.lsb
          else sprintf "[%d:%d]" (f.lsb + f.width - 1) f.lsb
        in
        let addr =
          if bytes_of f > 1 then sprintf "0x%02X-0x%02X" f.addr (f.addr + bytes_of f - 1)
          else sprintf "0x%02X" f.addr
        in
        sprintf "| %s | `%s` | %s | %d | %s | 0x%X | %s |" addr f.name bits f.width
          (access_name f.access) f.reset f.doc)
    in
    String.concat ~sep:"\n" rows ^ "\n"
  in
  let header = "| Address | Name | Bits | Width | Access | Reset | Meaning |\n|---|---|---|---|---|---|---|\n" in
  String.substr_replace_all static_md ~pattern:"__DEPTH__" ~with_:(Int.to_string imem_depth)
  ^ "## Config registers (Write_cfg / Read_cfg)\n\n" ^ header ^ table Cfg
  ^ "\n## Status registers (Read_status)\n\n" ^ header ^ table Status
;;
