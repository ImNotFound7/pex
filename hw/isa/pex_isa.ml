open! Base

type reg =
  | R0
  | R1
  | R2
  | R3
[@@deriving sexp, equal, enumerate]

type field =
  | Out
  | Oe
  | Mask
[@@deriving sexp, equal, enumerate]

type alu =
  | Mov
  | Add
  | Sub
  | And
  | Or
  | Xor
  | Cmp
  | Shl
  | Shr
[@@deriving sexp, equal, enumerate]

type cond =
  | Always
  | Z
  | Nz
  | C
  | Nc
  | Call
  | To
  | Nto
[@@deriving sexp, equal, enumerate]

type edge =
  | Disarm
  | Rise
  | Fall
  | Either
  | High
  | Low
[@@deriving sexp, equal, enumerate]

type half =
  | Lo
  | Hi
[@@deriving sexp, equal, enumerate]

type t =
  | Ldi of reg * int
  | Cmpi of reg * int
  | Alu of alu * reg * reg
  | Jump of cond * int
  | Djnz of reg * int
  | Stg_imm of field * int
  | Stg_reg of field * reg
  | Outb of int
  | Outl of int
  | Inb of int
  | Inr of int
  | Ldsr of reg
  | Stsr of reg
  | Ssl
  | Ssr
  | At_imm of
      { sample : bool
      ; offset : int
      }
  | At_param of
      { sample : bool
      ; p : int
      }
  | Wait
  | Wait_imm of int
  | Wait_param of int
  | Sync
  | Arm of int * edge
  | Ret
  | Halt
  | Fault of int
  | Push of reg
  | Pull of reg
  | Ldp of reg * int * half
  | Mark of int
[@@deriving sexp, equal]

(* Enum values are the index in declaration order; the name lists below are in
   the same order (checked by the tests via the JSON-only decoder). *)
let alu_names = [ "mov"; "add"; "sub"; "and"; "or"; "xor"; "cmp"; "shl"; "shr" ]
let cond_names = [ "jmp"; "jz"; "jnz"; "jc"; "jnc"; "call"; "jto"; "jnto" ]
let edge_names = [ "none"; "rise"; "fall"; "either"; "high"; "low" ]
let field_names = [ "out"; "oe"; "mask" ]
let half_names = [ "lo"; "hi" ]

let to_int equal all x = fst (List.findi_exn all ~f:(fun _ y -> equal x y))
let reg_i = to_int equal_reg all_of_reg
let field_i = to_int equal_field all_of_field
let alu_i = to_int equal_alu all_of_alu
let cond_i = to_int equal_cond all_of_cond
let edge_i = to_int equal_edge all_of_edge
let half_i = to_int equal_half all_of_half
let name_of names i = List.nth_exn names i

(* ---------------------------------------------------------------- encode *)

let chk what operand v max =
  if v >= 0 && v <= max
  then Ok v
  else Error (Printf.sprintf "%s: %s %d out of range 0..%d" what operand v max)
;;

let word op sub rest = (op lsl 12) lor (sub lsl 8) lor rest

let encode t =
  let open Result.Let_syntax in
  match t with
  | Ldi (r, imm) ->
    let%map imm = chk "ldi" "imm" imm 255 in
    word 0x0 0 ((reg_i r lsl 10) lor imm)
  | Cmpi (r, imm) ->
    let%map imm = chk "cmpi" "imm" imm 255 in
    word 0x1 0 ((reg_i r lsl 10) lor imm)
  | Alu ((Shl | Shr) as a, rd, rs) ->
    if equal_reg rs R0
    then Ok (word 0x2 (alu_i a) (reg_i rd lsl 6))
    else Error (Printf.sprintf "%s: rs must be r0 (single-operand shift)" (name_of alu_names (alu_i a)))
  | Alu (a, rd, rs) -> Ok (word 0x2 (alu_i a) ((reg_i rd lsl 6) lor (reg_i rs lsl 4)))
  | Jump (c, addr) ->
    let%map addr = chk "jump" "addr" addr 255 in
    word 0x3 (cond_i c) addr
  | Djnz (r, addr) ->
    let%map addr = chk "djnz" "addr" addr 255 in
    word 0x4 0 ((reg_i r lsl 10) lor addr)
  | Stg_imm (f, imm) ->
    let%map imm = chk "stg" "imm" imm 255 in
    word 0x5 0 ((field_i f lsl 10) lor imm)
  | Stg_reg (f, r) -> Ok (word 0x6 (field_i f) (reg_i r lsl 6))
  | Outb j -> let%map j = chk "outb" "j" j 7 in word 0x6 3 j
  | Outl j -> let%map j = chk "outl" "j" j 7 in word 0x6 4 j
  | Inb j -> let%map j = chk "inb" "j" j 7 in word 0x6 5 j
  | Inr j -> let%map j = chk "inr" "j" j 7 in word 0x6 6 j
  | Ldsr r -> Ok (word 0x6 7 (reg_i r lsl 6))
  | Stsr r -> Ok (word 0x6 8 (reg_i r lsl 6))
  | Ssl -> Ok (word 0x6 9 0)
  | Ssr -> Ok (word 0x6 10 0)
  | At_imm { sample; offset } ->
    let%map offset = chk "at" "offset" offset 2047 in
    word 0x7 0 ((Bool.to_int sample lsl 11) lor offset)
  | Wait_imm t ->
    let%map t = chk "wait" "t" t 4095 in
    word 0x8 0 t
  | At_param { sample; p } ->
    let%map p = chk "at" "p" p 3 in
    word 0x9 0 ((Bool.to_int sample lsl 4) lor p)
  | Wait -> Ok (word 0x9 1 0)
  | Wait_param p ->
    let%map p = chk "wait" "p" p 3 in
    word 0x9 2 p
  | Sync -> Ok (word 0x9 3 0)
  | Arm (j, Disarm) ->
    if j = 0
    then Ok (word 0x9 4 0)
    else Error "arm: j must be 0 when edge is none"
  | Arm (j, e) ->
    let%map j = chk "arm" "j" j 7 in
    word 0x9 4 ((j lsl 4) lor edge_i e)
  | Ret -> Ok (word 0x9 5 0)
  | Halt -> Ok (word 0x9 6 0)
  | Fault c ->
    let%map c = chk "fault" "code" c 15 in
    word 0x9 7 c
  | Push r -> Ok (word 0x9 8 (reg_i r lsl 6))
  | Pull r -> Ok (word 0x9 9 (reg_i r lsl 6))
  | Ldp (r, p, h) ->
    let%map p = chk "ldp" "p" p 3 in
    word 0x9 10 ((reg_i r lsl 6) lor (half_i h lsl 4) lor p)
  | Mark imm ->
    let%map imm = chk "mark" "imm" imm 255 in
    word 0xA 0 imm
;;

(* ---------------------------------------------------------------- decode *)

let bits w hi lo = (w lsr lo) land ((1 lsl (hi - lo + 1)) - 1)
let reg_at w lo = List.nth_exn all_of_reg (bits w (lo + 1) lo)

let decode w =
  if w < 0 || w > 0xFFFF
  then None
  else (
    (* [z mask v]: [v] if every bit of [mask] is zero in [w], else ILLEGAL. *)
    let z mask v = if w land mask = 0 then Some v else None in
    let sub = bits w 11 8 in
    match bits w 15 12 with
    | 0x0 -> z 0x0300 (Ldi (reg_at w 10, bits w 7 0))
    | 0x1 -> z 0x0300 (Cmpi (reg_at w 10, bits w 7 0))
    | 0x2 ->
      if sub > 8
      then None
      else (
        let a = List.nth_exn all_of_alu sub in
        let rd = reg_at w 6 in
        match a with
        | Shl | Shr -> z 0x003F (Alu (a, rd, R0))
        | _ -> z 0x000F (Alu (a, rd, reg_at w 4)))
    | 0x3 -> z 0x0800 (Jump (List.nth_exn all_of_cond (bits w 10 8), bits w 7 0))
    | 0x4 -> z 0x0300 (Djnz (reg_at w 10, bits w 7 0))
    | 0x5 ->
      (match bits w 11 10 with
       | 3 -> None
       | f -> z 0x0300 (Stg_imm (List.nth_exn all_of_field f, bits w 7 0)))
    | 0x6 ->
      let j = bits w 2 0 in
      (match sub with
       | 0 | 1 | 2 -> z 0x003F (Stg_reg (List.nth_exn all_of_field sub, reg_at w 6))
       | 3 -> z 0x00F8 (Outb j)
       | 4 -> z 0x00F8 (Outl j)
       | 5 -> z 0x00F8 (Inb j)
       | 6 -> z 0x00F8 (Inr j)
       | 7 -> z 0x003F (Ldsr (reg_at w 6))
       | 8 -> z 0x003F (Stsr (reg_at w 6))
       | 9 -> z 0x00FF Ssl
       | 10 -> z 0x00FF Ssr
       | _ -> None)
    | 0x7 -> Some (At_imm { sample = bits w 11 11 = 1; offset = bits w 10 0 })
    | 0x8 -> Some (Wait_imm (bits w 11 0))
    | 0x9 ->
      (match sub with
       | 0 -> z 0x00EC (At_param { sample = bits w 4 4 = 1; p = bits w 1 0 })
       | 1 -> z 0x00FF Wait
       | 2 -> z 0x00FC (Wait_param (bits w 1 0))
       | 3 -> z 0x00FF Sync
       | 4 ->
         (match bits w 2 0 with
          | 0 -> z 0x00FF (Arm (0, Disarm))
          | e when e > 5 -> None
          | e -> z 0x0088 (Arm (bits w 6 4, List.nth_exn all_of_edge e)))
       | 5 -> z 0x00FF Ret
       | 6 -> z 0x00FF Halt
       | 7 -> z 0x00F0 (Fault (bits w 3 0))
       | 8 -> z 0x003F (Push (reg_at w 6))
       | 9 -> z 0x003F (Pull (reg_at w 6))
       | 10 ->
         z 0x002C (Ldp (reg_at w 6, bits w 1 0, List.nth_exn all_of_half (bits w 4 4)))
       | _ -> None)
    | 0xA -> z 0x0F00 (Mark (bits w 7 0))
    | _ -> None)
;;

(* ------------------------------------------------------------- to_string *)

let to_string t =
  let r x = Printf.sprintf "r%d" (reg_i x) in
  let hex n = Printf.sprintf "0x%02x" n in
  let sample s = if s then ", sample" else "" in
  let sprintf = Printf.sprintf in
  match t with
  | Ldi (x, i) -> sprintf "ldi %s, %s" (r x) (hex i)
  | Cmpi (x, i) -> sprintf "cmpi %s, %s" (r x) (hex i)
  | Alu (((Shl | Shr) as a), rd, _) -> sprintf "%s %s" (name_of alu_names (alu_i a)) (r rd)
  | Alu (a, rd, rs) -> sprintf "%s %s, %s" (name_of alu_names (alu_i a)) (r rd) (r rs)
  | Jump (c, a) -> sprintf "%s %s" (name_of cond_names (cond_i c)) (hex a)
  | Djnz (x, a) -> sprintf "djnz %s, %s" (r x) (hex a)
  | Stg_imm (f, i) -> sprintf "stg %s, %s" (name_of field_names (field_i f)) (hex i)
  | Stg_reg (f, x) -> sprintf "stg %s, %s" (name_of field_names (field_i f)) (r x)
  | Outb j -> sprintf "outb %d" j
  | Outl j -> sprintf "outl %d" j
  | Inb j -> sprintf "inb %d" j
  | Inr j -> sprintf "inr %d" j
  | Ldsr x -> sprintf "ldsr %s" (r x)
  | Stsr x -> sprintf "stsr %s" (r x)
  | Ssl -> "ssl"
  | Ssr -> "ssr"
  | At_imm { sample = s; offset } -> sprintf "at +%d%s" offset (sample s)
  | At_param { sample = s; p } -> sprintf "at p%d%s" p (sample s)
  | Wait -> "wait"
  | Wait_imm n -> sprintf "wait +%d" n
  | Wait_param p -> sprintf "wait p%d" p
  | Sync -> "sync"
  | Arm (_, Disarm) -> "arm none"
  | Arm (j, e) -> sprintf "arm %d, %s" j (name_of edge_names (edge_i e))
  | Ret -> "ret"
  | Halt -> "halt"
  | Fault c -> sprintf "fault %d" c
  | Push x -> sprintf "push %s" (r x)
  | Pull x -> sprintf "pull %s" (r x)
  | Ldp (x, p, h) -> sprintf "ldp %s, p%d.%s" (r x) p (name_of half_names (half_i h))
  | Mark i -> sprintf "mark %s" (hex i)
;;

(* ------------------------------------------------------------------ spec *)

type kind =
  | Reg
  | Param
  | Uimm
  | Flag
  | Enum of string * int list

type fld =
  { name : string
  ; hi : int
  ; lo : int
  ; kind : kind
  }

type entry =
  { id : string
  ; mnemonic_from : string option (* enum field whose table names the mnemonic *)
  ; syntax : string
  ; op : int
  ; sub : int option (* fixed value of w[11:8] *)
  ; fields : fld list
  ; semantics : string
  }

let f name hi lo kind = { name; hi; lo; kind }
let range a b = List.range a (b + 1)

let e ?mnemonic_from ?sub ?(semantics = "") id syntax op fields =
  { id; mnemonic_from; syntax; op; sub; fields; semantics }
;;

let mnemonic en =
  match en.mnemonic_from with
  | Some _ -> None
  | None -> List.hd (String.split en.syntax ~on:' ')
;;

let entries =
  let rd = f "r" 11 10 Reg in
  let imm8 = f "imm" 7 0 Uimm in
  let addr = f "addr" 7 0 Uimm in
  let r76 = f "r" 7 6 Reg in
  let j = [ f "j" 2 0 Uimm ] in
  let sys sub = e ~sub in
  [ e "ldi" "ldi r, imm" 0x0 [ rd; imm8 ] ~semantics:"r <- imm."
  ; e "cmpi" "cmpi r, imm" 0x1 [ rd; imm8 ]
      ~semantics:"Sets Z and C as for sub (r - imm), without writing r."
  ; e "alu" "<alu> rd, rs" 0x2 ~mnemonic_from:"alu"
      [ f "alu" 11 8 (Enum ("alu", range 0 6)); f "rd" 7 6 Reg; f "rs" 5 4 Reg ]
      ~semantics:"rd <- rd <alu> rs. cmp sets Z and C as for sub, without writing rd."
  ; e "shift" "<shl|shr> rd" 0x2 ~mnemonic_from:"alu"
      [ f "alu" 11 8 (Enum ("alu", range 7 8)); f "rd" 7 6 Reg ]
      ~semantics:
        "shl: C <- rd[7], rd <- rd << 1. shr: C <- rd[0], rd <- rd >> 1. Bits 5:4 (rs) \
         must be 0."
  ; e "jump" "<cond> addr" 0x3 ~mnemonic_from:"cond"
      [ f "cond" 10 8 (Enum ("cond", range 0 7)); addr ]
      ~semantics:"Jump to addr if the condition holds; call also saves the return address (1-deep)."
  ; e "djnz" "djnz r, addr" 0x4 [ rd; addr ]
      ~semantics:"r <- r - 1; jump to addr if the new r is non-zero. Flags unchanged."
  ; e "stg_imm" "stg field, imm" 0x5
      [ f "field" 11 10 (Enum ("field", range 0 2)); imm8 ]
      ~semantics:"Stage the out / oe / mask register from imm. No timing effect."
  ; e "stg_reg" "stg field, r" 0x6
      [ f "field" 11 8 (Enum ("field", range 0 2)); r76 ]
      ~semantics:"Stage the out / oe / mask register from r. No timing effect."
  ; e "outb" "outb j" 0x6 ~sub:3 j ~semantics:"staged out[j] <- SR[7]; SR unchanged (no shift)."
  ; e "outl" "outl j" 0x6 ~sub:4 j ~semantics:"staged out[j] <- SR[0]; SR unchanged (no shift)."
  ; e "inb" "inb j" 0x6 ~sub:5 j ~semantics:"SR <- (SR << 1) | SAMPLE[j]."
  ; e "inr" "inr j" 0x6 ~sub:6 j ~semantics:"SR <- (SAMPLE[j] << 7) | (SR >> 1)."
  ; e "ldsr" "ldsr r" 0x6 ~sub:7 [ r76 ] ~semantics:"SR <- r."
  ; e "stsr" "stsr r" 0x6 ~sub:8 [ r76 ] ~semantics:"r <- SR."
  ; e "ssl" "ssl" 0x6 ~sub:9 [] ~semantics:"SR <- SR << 1, zero fill."
  ; e "ssr" "ssr" 0x6 ~sub:10 [] ~semantics:"SR <- SR >> 1, zero fill."
  ; e "at_imm" "at +n[, sample]" 0x7 [ f "sample" 11 11 Flag; f "offset" 10 0 Uimm ]
      ~semantics:"Timed action at REF + n (spec 4.2); sample flag loads SAMPLE on commit."
  ; e "wait_imm" "wait +t" 0x8 [ f "t" 11 0 Uimm ]
      ~semantics:"Wait for the armed event with timeout T = REF + t (spec 4.4)."
  ; sys 0 "at_param" "at pN[, sample]" 0x9 [ f "sample" 4 4 Flag; f "p" 1 0 Param ]
      ~semantics:"Timed action at REF + parameter register pN."
  ; sys 1 "wait" "wait" 0x9 [] ~semantics:"Wait for the armed event, no timeout."
  ; sys 2 "wait_param" "wait pN" 0x9 [ f "p" 1 0 Param ]
      ~semantics:"Wait for the armed event with timeout REF + parameter register pN."
  ; sys 3 "sync" "sync" 0x9 [] ~semantics:"REF <- execute cycle."
  ; sys 4 "disarm" "arm none" 0x9 []
      ~semantics:"Disarm the event condition. Bits 7:0 must be 0 (j = 0)."
  ; sys 4 "arm" "arm j, edge" 0x9
      [ f "j" 6 4 Uimm; f "edge" 2 0 (Enum ("edge", range 1 5)) ]
      ~semantics:"Arm the event condition on logical input j with the given edge/level."
  ; sys 5 "ret" "ret" 0x9 [] ~semantics:"Return from call (1-deep)."
  ; sys 6 "halt" "halt" 0x9 [] ~semantics:"Halt the context."
  ; sys 7 "fault" "fault c" 0x9 [ f "c" 3 0 Uimm ] ~semantics:"Raise fault code c."
  ; sys 8 "push" "push r" 0x9 [ r76 ] ~semantics:"Push r to the host FIFO."
  ; sys 9 "pull" "pull r" 0x9 [ r76 ] ~semantics:"Pull from the host FIFO into r (blocks)."
  ; sys 10 "ldp" "ldp r, pN.lo|hi" 0x9
      [ r76; f "half" 4 4 (Enum ("half", range 0 1)); f "p" 1 0 Param ]
      ~semantics:"r <- low or high byte of parameter register pN."
  ; e "mark" "mark imm" 0xA [ imm8 ] ~semantics:"Trace marker imm."
  ]
;;

let mask hi lo = ((1 lsl (hi - lo + 1)) - 1) lsl lo

(* Returns (match_mask, match_value, must_be_zero_mask). *)
let masks en =
  let sub_mask, sub_val =
    match en.sub with
    | None -> 0, 0
    | Some s -> mask 11 8, s lsl 8
  in
  let named =
    List.fold en.fields ~init:(0xF000 lor sub_mask) ~f:(fun m x -> m lor mask x.hi x.lo)
  in
  0xF000 lor sub_mask, (en.op lsl 12) lor sub_val, 0xFFFF land lnot named
;;

let kind_name = function
  | Reg -> "reg"
  | Param -> "param"
  | Uimm -> "uimm"
  | Flag -> "flag"
  | Enum _ -> "enum"
;;

let field_range x =
  match x.kind with
  | Enum (_, vs) -> List.hd_exn vs, List.last_exn vs
  | Reg | Param -> 0, 3
  | Uimm | Flag -> 0, (1 lsl (x.hi - x.lo + 1)) - 1
;;

let tables =
  [ "alu", alu_names; "cond", cond_names; "edge", edge_names; "field", field_names
  ; "half", half_names ]
;;

let sr_semantics =
  [ "outb j: staged out[j] <- SR[7], no shift."
  ; "outl j: staged out[j] <- SR[0], no shift."
  ; "inb j: SR <- (SR << 1) | SAMPLE[j]."
  ; "inr j: SR <- (SAMPLE[j] << 7) | (SR >> 1)."
  ; "ssl / ssr: shift with a zero fill."
  ]
;;

let alu_semantics =
  [ "shl: C <- r[7], r <- r << 1."
  ; "shr: C <- r[0], r <- r >> 1."
  ; "cmp / cmpi: set Z and C as for sub, without writing."
  ; "djnz: decrement r, jump if non-zero, flags unchanged."
  ]
;;

let decode_rule =
  "A 16-bit word is legal iff exactly one instruction entry matches: (w & match_mask) == \
   match_value, (w & must_be_zero_mask) == 0, and every field value is within its \
   min..max (enum fields: within `values`). Everything else, including op 0xB-0xF and \
   every unassigned enum value, is ILLEGAL. Field value = (w >> lo) & ((1 << (hi-lo+1)) \
   - 1). When mnemonic_from is set the mnemonic is that field's enum table name."
;;

let spec_json () =
  let ints l = `List (List.map l ~f:(fun i -> `Int i)) in
  let field x =
    let min, max = field_range x in
    `Assoc
      ([ "name", `String x.name; "hi", `Int x.hi; "lo", `Int x.lo
       ; "kind", `String (kind_name x.kind); "min", `Int min; "max", `Int max ]
       @
       match x.kind with
       | Enum (t, vs) -> [ "table", `String t; "values", ints vs ]
       | _ -> [])
  in
  let instr en =
    let mm, mv, mz = masks en in
    `Assoc
      [ "id", `String en.id
      ; ( "mnemonic"
        , Option.value_map (mnemonic en) ~default:`Null ~f:(fun s -> `String s) )
      ; ( "mnemonic_from"
        , Option.value_map en.mnemonic_from ~default:`Null ~f:(fun s -> `String s) )
      ; "syntax", `String en.syntax
      ; "op", `Int en.op
      ; ( "sub"
        , Option.value_map en.sub ~default:`Null ~f:(fun s ->
            `Assoc [ "hi", `Int 11; "lo", `Int 8; "value", `Int s ]) )
      ; "fields", `List (List.map en.fields ~f:field)
      ; "match_mask", `Int mm
      ; "match_value", `Int mv
      ; "must_be_zero_mask", `Int mz
      ; "semantics", `String en.semantics
      ]
  in
  let table (n, names) =
    ( n
    , `List
        (List.mapi names ~f:(fun i s -> `Assoc [ "value", `Int i; "name", `String s ])) )
  in
  let strs l = `List (List.map l ~f:(fun s -> `String s)) in
  `Assoc
    [ "version", `String "v0"
    ; "word_bits", `Int 16
    ; "decode_rule", `String decode_rule
    ; "illegal_ops", ints (range 0xB 0xF)
    ; "instructions", `List (List.map entries ~f:instr)
    ; "tables", `Assoc (List.map tables ~f:table)
    ; "sr_semantics", strs sr_semantics
    ; "alu_semantics", strs alu_semantics
    ]
;;

let spec_markdown () =
  let b = Buffer.create 4096 in
  let line fmt = Printf.ksprintf (fun s -> Buffer.add_string b s; Buffer.add_char b '\n') fmt in
  line "# PEX ISA v0 (candidate, freeze at G2)";
  line "";
  line "Generated from `hw/isa/pex_isa.ml` by `gen_spec.exe`; do not edit. Machine-readable \
        form: `spec/isa.json`.";
  line "";
  line "%s" decode_rule;
  line "";
  line "## Instructions";
  line "";
  line "| id | syntax | op | sub w[11:8] | fields | must-be-zero mask | semantics |";
  line "|---|---|---|---|---|---|---|";
  List.iter entries ~f:(fun en ->
    let _, _, mz = masks en in
    let fields =
      String.concat ~sep:", "
        (List.map en.fields ~f:(fun x ->
           let lo, hi = x.lo, x.hi in
           let pos = if hi = lo then Printf.sprintf "[%d]" hi else Printf.sprintf "[%d:%d]" hi lo in
           let mn, mx = field_range x in
           let rng =
             match x.kind with
             | Enum (t, vs) ->
               Printf.sprintf "%s %s" t (String.concat ~sep:"," (List.map vs ~f:Int.to_string))
             | _ -> Printf.sprintf "%d..%d" mn mx
           in
           Printf.sprintf "%s%s (%s)" x.name pos rng))
    in
    line "| %s | `%s` | 0x%X | %s | %s | 0x%04X | %s |" en.id en.syntax en.op
      (Option.value_map en.sub ~default:"-" ~f:Int.to_string)
      (if String.is_empty fields then "-" else fields)
      mz en.semantics);
  line "";
  line "Op 0xB-0xF: ILLEGAL.";
  List.iter tables ~f:(fun (n, names) ->
    line "";
    line "## %s" n;
    line "";
    line "| value | name |";
    line "|---|---|";
    List.iteri names ~f:(fun i s -> line "| %d | %s |" i s));
  line "";
  line "## SR semantics";
  line "";
  List.iter sr_semantics ~f:(line "- %s");
  line "";
  line "## ALU and flag semantics";
  line "";
  List.iter alu_semantics ~f:(line "- %s");
  Buffer.contents b
;;
