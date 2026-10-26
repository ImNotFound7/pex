(** PEX ISA v0: 16-bit instruction words.  This module is the single source of
    truth for encodings; [spec_json] / [spec_markdown] are generated from it. *)

type reg =
  | R0
  | R1
  | R2
  | R3
[@@deriving sexp, equal, enumerate]

type field =
  | Out
  | Oe
  | Mask
[@@deriving sexp, equal, enumerate]

type alu =
  | Mov
  | Add
  | Sub
  | And
  | Or
  | Xor
  | Cmp
  | Shl
  | Shr
[@@deriving sexp, equal, enumerate]

type cond =
  | Always
  | Z
  | Nz
  | C
  | Nc
  | Call
  | To
  | Nto
[@@deriving sexp, equal, enumerate]

type edge =
  | Disarm
  | Rise
  | Fall
  | Either
  | High
  | Low
[@@deriving sexp, equal, enumerate]

type half =
  | Lo
  | Hi
[@@deriving sexp, equal, enumerate]

type t =
  | Ldi of reg * int
  | Cmpi of reg * int
  | Alu of alu * reg * reg
  | Jump of cond * int
  | Djnz of reg * int
  | Stg_imm of field * int
  | Stg_reg of field * reg
  | Outb of int
  | Outl of int
  | Inb of int
  | Inr of int
  | Ldsr of reg
  | Stsr of reg
  | Ssl
  | Ssr
  | At_imm of
      { sample : bool
      ; offset : int
      }
  | At_param of
      { sample : bool
      ; p : int
      }
  | Wait
  | Wait_imm of int
  | Wait_param of int
  | Sync
  | Arm of int * edge
  | Ret
  | Halt
  | Fault of int
  | Push of reg
  | Pull of reg
  | Ldp of reg * int * half
  | Mark of int
[@@deriving sexp, equal]

(** [Error] names the offending operand and its valid range; operands are never
    masked or truncated.  [Alu (Shl|Shr, _, rs)] requires [rs = R0]. *)
val encode : t -> (int, string) result

(** [None] means ILLEGAL: undefined opcode/sub-opcode/enum value, or any
    non-zero bit that the encoding does not name.  Words outside 0..0xFFFF are
    ILLEGAL. *)
val decode : int -> t option

(** Assembler syntax.  Jump/djnz addresses and 8-bit immediates print as 0x
    hex; counts, offsets, bit indices and parameter numbers print in decimal.
    [Arm (0, Disarm)] prints [arm none]; any other [Disarm] prints
    [arm J, none] so that no information is lost. *)
val to_string : t -> string

val spec_json : unit -> Yojson.Safe.t
val spec_markdown : unit -> string
