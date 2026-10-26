open! Base
open Hardcaml
open Signal

type kind =
  [ `Ff_128x16
  | `Sram_256x16
  ]

let words = function
  | `Ff_128x16 -> 128
  | `Sram_256x16 -> 256
;;

let address_bits kind = Int.ceil_log2 (words kind)
let data_bits = 16
let sram_instance = "sram"

(* Registered read address, asynchronous array read: the next-cycle output is
   the written word on a write (write-through), else the stored word. *)
let behavioural ~kind scope ~clock ~addr ~wdata ~we =
  let ( -- ) = Scope.naming scope in
  let raddr = reg (Reg_spec.create ~clock ()) addr -- "imem_raddr" in
  (multiport_memory
     (words kind)
     ~name:"imem_array"
     ~write_ports:
       [| { write_clock = clock
          ; write_address = addr
          ; write_enable = we
          ; write_data = wdata
          }
       |]
     ~read_addresses:[| raddr |]).(0)
  -- "imem_rdata"
;;

(* Pin ties per the macro datasheet (doc/RM_IHPSG13_1P_256x16_c2_bm_bist.txt):
   A_DLY must be 1; BIST disabled (A_BIST_EN=0) with all BIST inputs at 0;
   A_MEN and A_REN held at 1 so every cycle is a read, or a write-through when
   A_WEN=1; A_BM all ones (whole-word writes). *)
let sram ~clock ~addr ~wdata ~we =
  let outputs =
    Instantiation.create
      ()
      ~name:"RM_IHPSG13_1P_256x16_c2_bm_bist"
      ~instance:sram_instance
      ~inputs:
        [ "A_CLK", clock
        ; "A_MEN", vdd
        ; "A_WEN", we
        ; "A_REN", vdd
        ; "A_ADDR", addr
        ; "A_DIN", wdata
        ; "A_DLY", vdd
        ; "A_BM", ones data_bits
        ; "A_BIST_CLK", gnd
        ; "A_BIST_EN", gnd
        ; "A_BIST_MEN", gnd
        ; "A_BIST_WEN", gnd
        ; "A_BIST_REN", gnd
        ; "A_BIST_ADDR", zero 8
        ; "A_BIST_DIN", zero data_bits
        ; "A_BIST_BM", zero data_bits
        ]
      ~outputs:[ "A_DOUT", data_bits ]
  in
  Map.find_exn outputs "A_DOUT"
;;

let create ?(sim_model = false) ~kind scope ~clock ~addr ~wdata ~we =
  assert (width wdata = data_bits);
  let addr = sel_bottom addr (address_bits kind) in
  match kind with
  | `Sram_256x16 when not sim_model -> sram ~clock ~addr ~wdata ~we
  | `Ff_128x16 | `Sram_256x16 -> behavioural ~kind scope ~clock ~addr ~wdata ~we
;;
