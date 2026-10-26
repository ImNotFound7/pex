(** PEX top level, wired to the Tiny Tapeout user-project pins. *)

open! Base
open Hardcaml

module I : sig
  type 'a t =
    { ui_in : 'a
    ; uio_in : 'a
    ; ena : 'a
    ; clk : 'a
    ; rst_n : 'a
    }
  [@@deriving hardcaml]
end

module O : sig
  type 'a t =
    { uo_out : 'a
    ; uio_out : 'a
    ; uio_oe : 'a
    }
  [@@deriving hardcaml]
end

(** Stub: an 8-bit counter on [uo_out] that advances while [ena] is high and
    clears synchronously while [rst_n] is low. All [uio] pins are inputs. *)
val create : Scope.t -> Signal.t I.t -> Signal.t O.t
