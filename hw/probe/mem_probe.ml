open! Base
open Hardcaml
open Signal

let create ?sim_model ~kind scope (i : _ Pex_top.I.t) =
  let ( -- ) = Scope.naming scope in
  let spec = Reg_spec.create ~clock:i.clk ~clear:~:(i.rst_n) () in
  let shift = i.ui_in.:(1) in
  let load_word =
    reg_fb spec ~enable:shift ~width:32 ~f:(fun w -> lsbs w @: i.ui_in.:(2))
    -- "load_word"
  in
  let load_count =
    reg_fb spec ~enable:shift ~width:5 ~f:(fun c -> c +:. 1) -- "load_count"
  in
  let word_ready = reg spec (shift &: (load_count ==:. 31)) -- "word_ready" in
  let rdata =
    Imem.create
      ?sim_model
      ~kind
      scope
      ~clock:i.clk
      ~addr:load_word.:[30, 16]
      ~wdata:load_word.:[15, 0]
      ~we:(word_ready &: msb load_word)
  in
  { Pex_top.O.uo_out = mux2 i.ui_in.:(3) rdata.:[15, 8] rdata.:[7, 0]
  ; uio_out = zero 8
  ; uio_oe = zero 8
  }
;;
