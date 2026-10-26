open! Base
open Hardcaml
open Signal

module I = struct
  type 'a t =
    { ui_in : 'a [@bits 8]
    ; uio_in : 'a [@bits 8]
    ; ena : 'a
    ; clk : 'a
    ; rst_n : 'a
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { uo_out : 'a [@bits 8]
    ; uio_out : 'a [@bits 8]
    ; uio_oe : 'a [@bits 8]
    }
  [@@deriving hardcaml]
end

let create (_ : Scope.t) (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clk ~clear:~:(i.rst_n) () in
  let counter = reg_fb spec ~enable:i.ena ~width:8 ~f:(fun d -> d +:. 1) in
  { O.uo_out = counter; uio_out = zero 8; uio_oe = zero 8 }
;;
