(** Host SPI command set and configuration/status register map (spec
    sections 5, 4.5, 4.6, 6).

    Candidate v1, freeze at G2.  This module is the single source for the
    RTL decoder constants and the host library framing; [spec/host.md] and
    [spec/host.json] are generated from it. *)

open! Base

type cmd =
  | Write_mem
  | Read_mem
  | Write_cfg
  | Read_cfg
  | Read_status
  | Ctrl
  | Fifo_push of int (** context 0 or 1 *)
  | Fifo_pop of int
  | Trace_pop of int
[@@deriving sexp_of, equal]

type ctrl =
  | Start
  | Halt
  | Step of int (** [Step n] advances [n+1] slots, [n] in 0..127. *)
  | Clear_faults
[@@deriving sexp_of, equal]

(** Raises on a context outside 0..1. *)
val cmd_byte : cmd -> int

(** [None] for every invalid command byte. *)
val cmd_of_byte : int -> cmd option

(** Raises on a [Step] outside 0..127. *)
val ctrl_byte : ctrl -> int

val ctrl_of_byte : int -> ctrl option

(** [cmd; addr hi; addr lo; data...].  Raises on an address outside 0..0xFFFF
    or a data byte outside 0..255. *)
val frame : cmd -> addr:int -> bytes:int list -> int list

(** Address spaces: [Cfg] is used by [Write_cfg]/[Read_cfg], [Status] by
    [Read_status]. *)
type space =
  | Cfg
  | Status
[@@deriving sexp_of, equal]

type access =
  | Rw_halted (** Writable only while halted; a write while running is rejected. *)
  | Ro (** Read-only; a write is rejected. *)
  | Ro_sticky (** Read-only, sticky; cleared by [Ctrl Clear_faults]. *)
[@@deriving sexp_of, equal]

(** A field occupies bits [lsb .. lsb+width-1] of the byte at [addr]; a field
    wider than 8 bits has [lsb = 0] and continues little-endian into
    [addr+1], ... *)
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

(** Every field, once.  The single list the map is built from. *)
val fields : field list

val spec_json : unit -> Yojson.Safe.t
val spec_markdown : unit -> string
