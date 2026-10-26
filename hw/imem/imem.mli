(** PEX instruction memory: single-port, synchronous, 1-cycle read.

    Every cycle reads [addr]; the word appears on the result one cycle later.
    A write ([we] high) stores [wdata] at [addr] and is also the word read back
    the next cycle (write-through), matching the SRAM macro with [A_REN] tied
    high. Only the low [address_bits kind] bits of [addr] are used. *)

open! Base
open Hardcaml

type kind =
  [ `Ff_128x16 (** flip-flop array, always-working fallback *)
  | `Sram_256x16 (** IHP macro [RM_IHPSG13_1P_256x16_c2_bm_bist] *)
  ]

val words : kind -> int
val address_bits : kind -> int

(** Name of the SRAM macro instance. It must match the instance name in
    [src/config.json] [MACROS] and [PDN_MACRO_CONNECTIONS]. *)
val sram_instance : string

(** [sim_model] (default [false]) only affects [`Sram_256x16]: [true] builds a
    behavioural RAM for Hardcaml simulation, [false] instantiates the macro as a
    blackbox. *)
val create
  :  ?sim_model:bool
  -> kind:kind
  -> Scope.t
  -> clock:Signal.t
  -> addr:Signal.t
  -> wdata:Signal.t
  -> we:Signal.t
  -> Signal.t
