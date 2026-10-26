(* Prints the Verilog for the TT user project to stdout. [dune build @gen]
   diffs it against the committed [src/project.v]; add [--auto-promote] to
   refresh that file. *)

open! Base
open Hardcaml
module Circuit = Circuit.With_interface (Pex_top.I) (Pex_top.O)

(* The circuit emitted as the top module. Change only this to emit a
   different circuit. *)
let top = Mem_probe.create ~kind:`Sram_256x16

let () =
  let scope = Scope.create ~flatten_design:true () in
  Rtl.print Verilog (Circuit.create_exn ~name:"tt_um_imnotfound7_pex" (top scope))
;;
