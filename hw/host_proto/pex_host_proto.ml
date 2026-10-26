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
        cfg (sprintf "entry%d" c) ~addr:(0x08 + c) ~width:8 "Start address of the context.")
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
          ; "host_push_overflow", "Fifo_push to a full RX FIFO; byte dropped"
          ; "host_pop_underflow", "Fifo_pop from an empty TX FIFO; 0x00 returned"
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
        List.mapi [ "rx_level"; "tx_level"; "trace_level" ] ~f:(fun i n ->
          status
            (sprintf "%s.ctx%d" n c)
            ~addr:(0x20 + (4 * c) + i)
            ~width:8
            (sprintf "ctx%d entries currently in the %s FIFO." c (String.chop_suffix_exn n ~suffix:"_level"))))
    ]
;;

let fields = cfg_fields @ status_fields
let space_name = function Cfg -> "cfg" | Status -> "status"
let access_name = function Rw_halted -> "RW-halted" | Ro -> "RO" | Ro_sticky -> "RO-sticky"
let bytes_of f = (f.lsb + f.width + 7) / 8

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
    ; "fields", `List (List.map fields ~f:field)
    ]
;;

let static_md =
  {|# PEX host SPI interface (candidate, freeze at G2)

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
  static_md
  ^ "## Config registers (Write_cfg / Read_cfg)\n\n" ^ header ^ table Cfg
  ^ "\n## Status registers (Read_status)\n\n" ^ header ^ table Status
;;
