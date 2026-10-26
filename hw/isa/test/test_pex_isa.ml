open! Base
open Stdio
open Pex_isa

let%test "exhaustive canonical round trip" =
  List.for_all (List.init 65536 ~f:Fn.id) ~f:(fun w ->
    match decode w with
    | None -> true
    | Some i -> [%equal: (int, string) Result.t] (encode i) (Ok w))
;;

let max_samples =
  let regs = [ R0; R1; R2; R3 ] in
  List.concat
    [ List.concat_map regs ~f:(fun r -> [ Ldi (r, 0); Ldi (r, 255); Cmpi (r, 255) ])
    ; List.concat_map
        [ Mov; Add; Sub; And; Or; Xor; Cmp ]
        ~f:(fun a -> List.concat_map regs ~f:(fun d -> List.map regs ~f:(fun s -> Alu (a, d, s))))
    ; List.concat_map
        [ Shl; Shr ]
        ~f:(fun a -> List.map regs ~f:(fun d -> Alu (a, d, R0)))
    ; List.map [ Always; Z; Nz; C; Nc; Call; To; Nto ] ~f:(fun c -> Jump (c, 255))
    ; List.map regs ~f:(fun r -> Djnz (r, 255))
    ; List.concat_map [ Out; Oe; Mask ] ~f:(fun f ->
        Stg_imm (f, 255) :: List.map regs ~f:(fun r -> Stg_reg (f, r)))
    ; List.concat_map [ (fun j -> Outb j); (fun j -> Outl j); (fun j -> Inb j); (fun j -> Inr j) ]
        ~f:(fun mk -> [ mk 0; mk 7 ])
    ; List.concat_map regs ~f:(fun r -> [ Ldsr r; Stsr r; Push r; Pull r ])
    ; [ Ssl; Ssr; Wait; Sync; Ret; Halt; Wait_imm 4095; Wait_param 3 ]
    ; List.concat_map [ true; false ] ~f:(fun sample ->
        [ At_imm { sample; offset = 2047 }; At_param { sample; p = 3 } ])
    ; [ Arm (0, Disarm) ]
    ; List.concat_map [ Rise; Fall; Either; High; Low ] ~f:(fun e ->
        [ Arm (0, e); Arm (7, e) ])
    ; [ Fault 15; Mark 255 ]
    ; List.concat_map [ Lo; Hi ] ~f:(fun h -> [ Ldp (R3, 3, h); Ldp (R0, 0, h) ])
    ]
;;

let%test "every constructor encodes then decodes" =
  List.for_all max_samples ~f:(fun i ->
    match encode i with
    | Error _ -> false
    | Ok w -> [%equal: t option] (decode w) (Some i))
;;

let%expect_test "range errors" =
  List.iter
    [ At_imm { sample = false; offset = 2048 }
    ; Ldi (R0, 256)
    ; Outb 8
    ; Jump (Always, 256)
    ; Fault 16
    ; Wait_imm (-1)
    ; Wait_imm 4096
    ; Cmpi (R0, 256)
    ; Djnz (R0, 256)
    ; Stg_imm (Out, 256)
    ; Mark 256
    ; Outl 8
    ; Inb 8
    ; Inr 8
    ; At_param { sample = false; p = 4 }
    ; Arm (1, Disarm)
    ; Wait_param 4
    ; Arm (8, Rise)
    ; Ldp (R0, 4, Lo)
    ; Alu (Shl, R1, R2)
    ]
    ~f:(fun i -> print_s [%sexp (encode i : (int, string) Result.t)]);
  [%expect {|
    (Error "at: offset 2048 out of range 0..2047")
    (Error "ldi: imm 256 out of range 0..255")
    (Error "outb: j 8 out of range 0..7")
    (Error "jump: addr 256 out of range 0..255")
    (Error "fault: code 16 out of range 0..15")
    (Error "wait: t -1 out of range 0..4095")
    (Error "wait: t 4096 out of range 0..4095")
    (Error "cmpi: imm 256 out of range 0..255")
    (Error "djnz: addr 256 out of range 0..255")
    (Error "stg: imm 256 out of range 0..255")
    (Error "mark: imm 256 out of range 0..255")
    (Error "outl: j 8 out of range 0..7")
    (Error "inb: j 8 out of range 0..7")
    (Error "inr: j 8 out of range 0..7")
    (Error "at: p 4 out of range 0..3")
    (Error "arm: j must be 0 when edge is none")
    (Error "wait: p 4 out of range 0..3")
    (Error "arm: j 8 out of range 0..7")
    (Error "ldp: p 4 out of range 0..3")
    (Error "shl: rs must be r0 (single-operand shift)")
    |}]
;;

let%expect_test "illegal opcodes" =
  print_s
    [%sexp
      (List.map
         [ 0xB000; 0xF123; 0x0100; 0x2900; 0x2770; 0x2710; 0x5C00; 0x600B; 0x6003; 0x6308
         ; 0x9B00; 0x9406; 0x9410; 0x9470; 0x9000 lor 0x20; -1; 0x10000 ]
         ~f:decode
       : t option list)];
  [%expect {| (() () () () () () () () () () () () () () () () ()) |}]
;;

let%expect_test "to_string" =
  List.iter
    [ At_imm { sample = false; offset = 434 }
    ; At_imm { sample = true; offset = 5 }
    ; At_param { sample = true; p = 0 }
    ; Arm (3, Fall)
    ; Arm (0, Disarm)
    ; Ldp (R1, 2, Hi)
    ; Stg_imm (Out, 0x55)
    ; Stg_reg (Oe, R2)
    ; Jump (Z, 0x12)
    ; Jump (Always, 3)
    ; Djnz (R3, 9)
    ; Alu (Add, R1, R2)
    ; Alu (Shl, R3, R0)
    ; Ldi (R0, 7)
    ; Wait_imm 100
    ; Wait_param 1
    ; Wait
    ; Fault 3
    ; Mark 200
    ]
    ~f:(fun i -> print_endline (to_string i));
  [%expect {|
    at +434
    at +5, sample
    at p0, sample
    arm 3, fall
    arm none
    ldp r1, p2.hi
    stg out, 0x55
    stg oe, r2
    jz 0x12
    jmp 0x03
    djnz r3, 0x09
    add r1, r2
    shl r3
    ldi r0, 0x07
    wait +100
    wait p1
    wait
    fault 3
    mark 0xc8
    |}]
;;

(* Independent decoder that uses ONLY the generated JSON, as the Python model will. *)
module J = Yojson.Safe.Util

let json = spec_json ()
let entries = json |> J.member "instructions" |> J.to_list
let int_of j k = j |> J.member k |> J.to_int

let table name =
  json |> J.member "tables" |> J.member name |> J.to_list
  |> List.map ~f:(fun e -> int_of e "value", e |> J.member "name" |> J.to_string)
;;

let field_ok w f =
  let hi = int_of f "hi" and lo = int_of f "lo" in
  let v = (w lsr lo) land ((1 lsl (hi - lo + 1)) - 1) in
  match f |> J.member "values" with
  | `Null -> v >= int_of f "min" && v <= int_of f "max"
  | l -> List.mem (J.to_list l |> List.map ~f:J.to_int) v ~equal:Int.equal
;;

let json_decode w =
  List.filter entries ~f:(fun e ->
    w land int_of e "match_mask" = int_of e "match_value"
    && w land int_of e "must_be_zero_mask" = 0
    && List.for_all (e |> J.member "fields" |> J.to_list) ~f:(field_ok w))
;;

let json_mnemonic w e =
  match e |> J.member "mnemonic_from" with
  | `Null -> e |> J.member "mnemonic" |> J.to_string
  | f ->
    let f = J.to_string f in
    let fld =
      List.find_exn (e |> J.member "fields" |> J.to_list) ~f:(fun x ->
        String.equal (x |> J.member "name" |> J.to_string) f)
    in
    let v = (w lsr int_of fld "lo") land ((1 lsl (int_of fld "hi" - int_of fld "lo" + 1)) - 1) in
    let tbl = table (fld |> J.member "table" |> J.to_string) in
    List.Assoc.find_exn tbl v ~equal:Int.equal
;;

let idx all eq x = fst (List.findi_exn all ~f:(fun _ y -> eq x y))
let r = idx all_of_reg equal_reg

(* Entry id and field values that the JSON-extracted decode must report. *)
let expected = function
  | Ldi (x, i) -> "ldi", [ "r", r x; "imm", i ]
  | Cmpi (x, i) -> "cmpi", [ "r", r x; "imm", i ]
  | Alu ((Shl | Shr) as a, rd, _) -> "shift", [ "alu", idx all_of_alu equal_alu a; "rd", r rd ]
  | Alu (a, rd, rs) -> "alu", [ "alu", idx all_of_alu equal_alu a; "rd", r rd; "rs", r rs ]
  | Jump (c, a) -> "jump", [ "cond", idx all_of_cond equal_cond c; "addr", a ]
  | Djnz (x, a) -> "djnz", [ "r", r x; "addr", a ]
  | Stg_imm (f, i) -> "stg_imm", [ "field", idx all_of_field equal_field f; "imm", i ]
  | Stg_reg (f, x) -> "stg_reg", [ "field", idx all_of_field equal_field f; "r", r x ]
  | Outb j -> "outb", [ "j", j ]
  | Outl j -> "outl", [ "j", j ]
  | Inb j -> "inb", [ "j", j ]
  | Inr j -> "inr", [ "j", j ]
  | Ldsr x -> "ldsr", [ "r", r x ]
  | Stsr x -> "stsr", [ "r", r x ]
  | Ssl -> "ssl", []
  | Ssr -> "ssr", []
  | At_imm { sample; offset } -> "at_imm", [ "sample", Bool.to_int sample; "offset", offset ]
  | At_param { sample; p } -> "at_param", [ "sample", Bool.to_int sample; "p", p ]
  | Wait -> "wait", []
  | Wait_imm t -> "wait_imm", [ "t", t ]
  | Wait_param p -> "wait_param", [ "p", p ]
  | Sync -> "sync", []
  | Arm (_, Disarm) -> "disarm", []
  | Arm (j, e) -> "arm", [ "j", j; "edge", idx all_of_edge equal_edge e ]
  | Ret -> "ret", []
  | Halt -> "halt", []
  | Fault c -> "fault", [ "c", c ]
  | Push x -> "push", [ "r", r x ]
  | Pull x -> "pull", [ "r", r x ]
  | Ldp (x, p, h) -> "ldp", [ "r", r x; "half", idx all_of_half equal_half h; "p", p ]
  | Mark i -> "mark", [ "imm", i ]
;;

let json_fields w e =
  e |> J.member "fields" |> J.to_list
  |> List.map ~f:(fun x ->
    ( x |> J.member "name" |> J.to_string
    , (w lsr int_of x "lo") land ((1 lsl (int_of x "hi" - int_of x "lo" + 1)) - 1) ))
;;

let sort = List.sort ~compare:[%compare: string * int]

let%test "JSON-only decoder agrees with Pex_isa.decode on all 65536 words" =
  List.for_all (List.init 65536 ~f:Fn.id) ~f:(fun w ->
    match json_decode w, decode w with
    | [], None -> true
    | [ e ], Some i ->
      let id, ops = expected i in
      String.equal (json_mnemonic w e) (List.hd_exn (String.split (to_string i) ~on:' '))
      && String.equal id (e |> J.member "id" |> J.to_string)
      && [%equal: (string * int) list] (sort ops) (sort (json_fields w e))
    | _ -> false)
;;

let%expect_test "legal word count" =
  printf "%d\n" (List.count (List.init 65536 ~f:Fn.id) ~f:(fun w -> Option.is_some (decode w)));
  [%expect {| 14623 |}]
;;
