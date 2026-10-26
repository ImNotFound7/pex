(** The user-facing description of one PEX run: firmware image, chip
    configuration, parameters and host script (spec section 10a).

    Draft v0, freeze at G2.  The JSON form ([to_json] / [of_json]) is an
    interface read by independent implementations; it is documented in
    [spec/experiment.md], generated from this module. *)

open! Base

type owner =
  | Unowned
  | Ctx0
  | Ctx1
[@@deriving sexp_of, equal]

type mode =
  | Push_pull
  | Open_drain
[@@deriving sexp_of, equal]

type out_pin =
  { owner : owner
  ; logical : int (** 0..7 *)
  ; mode : mode
  ; idle : bool
  }
[@@deriving sexp_of, equal]

type trace_mode =
  | Mark
  | Events
  | Commits
[@@deriving sexp_of, equal]

type config =
  { outputs : out_pin array
    (** Exactly 15: index 0-7 = [uio[0..7]], 8-14 = [uo_out[1..7]]. *)
  ; input_map : int array array
    (** [input_map.(ctx).(j)], 2x8, each 0..12: physical input 0-7 =
        [uio_in[0..7]], 8-12 = [ui_in[3..7]]. *)
  ; trace_mode : trace_mode
  ; entry : int * int (** Host-written start address of ctx0, ctx1. *)
  }
[@@deriving sexp_of, equal]

type step =
  | Push of int * int (** context, byte 0..255 *)
  | Expect_pop of int * int (** context, expected byte 0..255 *)
  | Run_cycles of int
  | Expect_no_fault
[@@deriving sexp_of, equal]

type t =
  { name : string
  ; image : Yojson.Safe.t (** A [pex-image-v0] object as produced by pexasm. *)
  ; config : config
  ; params : int array array (** 2x4, each 0..0xFFFF *)
  ; experiment_id : int (** 0..0xFFFF *)
  ; script : step list
  }
[@@deriving sexp_of, equal]

(** The [entry] field of an image, as [(ctx0, ctx1)]. *)
val entry_of_image : Yojson.Safe.t -> (int * int, string) Result.t

(** All violations, each naming the field, index and allowed range. *)
val validate : t -> (unit, string list) Result.t

val to_json : t -> Yojson.Safe.t

(** Rejects unknown and missing fields.  Does not call [validate]. *)
val of_json : Yojson.Safe.t -> (t, string) Result.t
