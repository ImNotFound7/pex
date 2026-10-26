open! Base
open Hardcaml

let writes = [ 0x1234, 0; 0xBEEF, 1; 0x0001, 127; 0xFFFF, 64 ]

let kinds =
  [ "ff", `Ff_128x16; "sram", `Sram_256x16 ]

(* [Imem] alone: data written at an address comes out exactly one cycle after
   the address is presented. The last write (0xffff at 64) is also read back on
   its own write cycle (write-through, as the SRAM macro does with REN=1). *)
let%expect_test "imem: writes_then_reads_4_addresses, 1-cycle read" =
  List.iter kinds ~f:(fun (label, kind) ->
    let clock = Signal.input "clock" 1 in
    let rdata =
      Imem.create
        ~sim_model:true
        ~kind
        (Scope.create ~flatten_design:true ())
        ~clock
        ~addr:(Signal.input "addr" 8)
        ~wdata:(Signal.input "wdata" 16)
        ~we:(Signal.input "we" 1)
    in
    let sim =
      Cyclesim.create
        (Circuit.create_exn ~name:"imem" [ Signal.output "rdata" rdata ])
    in
    let port = Cyclesim.in_port sim in
    let rdata = Cyclesim.out_port sim "rdata" in
    let rdata_before_edge = Cyclesim.out_port ~clock_edge:Before sim "rdata" in
    List.iter writes ~f:(fun (data, addr) ->
      port "we" := Bits.vdd;
      port "addr" := Bits.of_int ~width:8 addr;
      port "wdata" := Bits.of_int ~width:16 data;
      Cyclesim.cycle sim);
    port "we" := Bits.gnd;
    port "wdata" := Bits.zero 16;
    let got =
      List.map writes ~f:(fun (_, addr) ->
        port "addr" := Bits.of_int ~width:8 addr;
        Cyclesim.cycle sim;
        (* Before the edge the output still shows the previous read; the new
           address's data appears only after the edge. *)
        Printf.sprintf
          "%d:%04x->%04x"
          addr
          (Bits.to_int !rdata_before_edge)
          (Bits.to_int !rdata))
    in
    Stdio.printf "%s %s\n" label (String.concat ~sep:" " got));
  [%expect
    {|
    ff 0:ffff->1234 1:1234->beef 127:beef->0001 64:0001->ffff
    sram 0:ffff->1234 1:1234->beef 127:beef->0001 64:0001->ffff
    |}]
;;

module Sim = Cyclesim.With_interface (Pex_top.I) (Pex_top.O)

(* Same four writes through the probe's pins: shift [{we, addr[14:0],
   data[15:0]}] MSB first on ui_in[2] while ui_in[1] is high, then read each
   address back on uo_out with ui_in[3] selecting the byte. *)
let%expect_test "mem_probe: writes_then_reads_4_addresses via pins" =
  List.iter kinds ~f:(fun (label, kind) ->
    let sim =
      Sim.create
        (Mem_probe.create ~sim_model:true ~kind (Scope.create ~flatten_design:true ()))
    in
    let i = Cyclesim.inputs sim in
    let o = Cyclesim.outputs sim in
    let ui ~shift ~bit ~hi =
      i.ui_in
      := Bits.of_int
           ~width:8
           ((Bool.to_int shift lsl 1) lor (Bool.to_int bit lsl 2) lor (Bool.to_int hi lsl 3))
    in
    i.ena := Bits.vdd;
    i.rst_n := Bits.gnd;
    Cyclesim.cycle sim;
    i.rst_n := Bits.vdd;
    let send ~we ~addr ~data =
      let word = (Bool.to_int we lsl 31) lor (addr lsl 16) lor data in
      for b = 31 downto 0 do
        ui ~shift:true ~bit:((word lsr b) land 1 = 1) ~hi:false;
        Cyclesim.cycle sim
      done;
      ui ~shift:false ~bit:false ~hi:false;
      Cyclesim.cycle sim
    in
    List.iter writes ~f:(fun (data, addr) -> send ~we:true ~addr ~data);
    let got =
      List.map writes ~f:(fun (_, addr) ->
        send ~we:false ~addr ~data:0;
        let byte hi =
          ui ~shift:false ~bit:false ~hi;
          Cyclesim.cycle sim;
          Bits.to_int !(o.uo_out)
        in
        let lo = byte false in
        let hi = byte true in
        Printf.sprintf "%d:%02x%02x" addr hi lo)
    in
    Stdio.printf
      "%s %s uio_oe=%02x\n"
      label
      (String.concat ~sep:" " got)
      (Bits.to_int !(o.uio_oe)));
  [%expect
    {|
    ff 0:1234 1:beef 127:0001 64:ffff uio_oe=00
    sram 0:1234 1:beef 127:0001 64:ffff uio_oe=00
    |}]
;;
