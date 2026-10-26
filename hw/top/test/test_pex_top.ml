open! Base
open Hardcaml
module Sim = Cyclesim.With_interface (Pex_top.I) (Pex_top.O)

let%expect_test "stub counts on uo_out, uio released" =
  let sim = Sim.create (Pex_top.create (Scope.create ~flatten_design:true ())) in
  let inputs = Cyclesim.inputs sim in
  let outputs = Cyclesim.outputs sim in
  let cycle ~label ~rst_n ~ena =
    inputs.rst_n := Bits.of_bool rst_n;
    inputs.ena := Bits.of_bool ena;
    Cyclesim.cycle sim;
    Stdio.printf
      "%s uo_out=%02x uio_oe=%02x\n"
      label
      (Bits.to_int !(outputs.uo_out))
      (Bits.to_int !(outputs.uio_oe))
  in
  for _ = 1 to 2 do
    cycle ~label:"rst" ~rst_n:false ~ena:true
  done;
  for _ = 1 to 3 do
    cycle ~label:"run" ~rst_n:true ~ena:true
  done;
  [%expect
    {|
    rst uo_out=00 uio_oe=00
    rst uo_out=00 uio_oe=00
    run uo_out=01 uio_oe=00
    run uo_out=02 uio_oe=00
    run uo_out=03 uio_oe=00
    |}]
;;
