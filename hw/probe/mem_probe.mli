(** G1 memory probe: an [Imem] wired to the TT pins so the whole array is
    observable (and kept by synthesis).

    Load: while [ui_in[1]] is high, each clock shifts [ui_in[2]] into a 32-bit
    word [{we, addr[14:0], data[15:0]}], MSB first. The cycle after the 32nd
    bit, a word with [we] set is written. The memory reads the word's address
    every cycle; [uo_out] shows [rdata[7:0]], or [rdata[15:8]] when [ui_in[3]]
    is high. [uio] are inputs. [rst_n] low clears the shift state. *)

open! Base
open Hardcaml

val create
  :  ?sim_model:bool
  -> kind:Imem.kind
  -> Scope.t
  -> Signal.t Pex_top.I.t
  -> Signal.t Pex_top.O.t
