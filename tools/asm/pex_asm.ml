open! Base
module I = Pex_isa

type image =
  { words : int array
  ; entry : int * int
  ; labels : (string * int) list
  }

let max_words = 256

type symbol =
  | Equ of int
  | Label of int

type stmt =
  { line : int
  ; mnemonic : string
  ; args : string list
  }

(* ---- lexing ---------------------------------------------------------- *)

(* Tabs are normalised to spaces so every later split on ' ' sees them. *)
let strip_comment s =
  String.tr ~target:'\t' ~replacement:' ' (List.hd_exn (String.split s ~on:';'))
;;

let is_ident s =
  (not (String.is_empty s))
  && (not (Char.is_digit s.[0]))
  && String.for_all s ~f:(fun c -> Char.is_alphanum c || Char.equal c '_')
;;

(* Splits "label: stmt" into the optional label and the remaining text. *)
let split_label s =
  match String.lsplit2 s ~on:':' with
  | Some (l, rest) when is_ident (String.strip l) -> Some (String.strip l), String.strip rest
  | _ -> None, s
;;

let parse_stmt ~line s =
  let mnemonic, rest =
    match String.lsplit2 s ~on:' ' with
    | Some (m, r) -> m, String.strip r
    | None -> s, ""
  in
  let args =
    if String.is_empty rest then [] else List.map (String.split rest ~on:',') ~f:String.strip
  in
  { line; mnemonic; args }
;;

(* ---- operands -------------------------------------------------------- *)

let ( let* ) = Result.( >>= )

let parse_int s = Option.try_with (fun () -> Int.of_string s)

(* [r]/[p] followed by digits only. *)
let prefixed_index prefix s =
  match String.chop_prefix s ~prefix with
  | Some d when (not (String.is_empty d)) && String.for_all d ~f:Char.is_digit ->
    parse_int d
  | _ -> None
;;

let reg s =
  match prefixed_index "r" s with
  | Some 0 -> Ok I.R0
  | Some 1 -> Ok I.R1
  | Some 2 -> Ok I.R2
  | Some 3 -> Ok I.R3
  | _ -> Error (Printf.sprintf "expected register r0..r3, got %S" s)
;;

let param s =
  match prefixed_index "p" s with
  | Some n -> Ok n
  | None -> Error (Printf.sprintf "expected parameter register pN, got %S" s)
;;

let lookup_name table what s =
  match List.Assoc.find table s ~equal:String.equal with
  | Some v -> Ok v
  | None -> Error (Printf.sprintf "unknown %s %S" what s)
;;

let alus =
  [ "mov", I.Mov; "add", Add; "sub", Sub; "and", And; "or", Or; "xor", Xor; "cmp", Cmp ]
;;

let shifts = [ "shl", I.Shl; "shr", Shr ]

let conds =
  [ "jmp", I.Always
  ; "jz", Z
  ; "jnz", Nz
  ; "jc", C
  ; "jnc", Nc
  ; "call", Call
  ; "jto", To
  ; "jnto", Nto
  ]
;;

let fields = [ "out", I.Out; "oe", Oe; "mask", Mask ]
let edges = [ "rise", I.Rise; "fall", Fall; "either", Either; "high", High; "low", Low ]
let halves = [ "lo", I.Lo; "hi", Hi ]

(* ---- instruction construction --------------------------------------- *)

(* [num ~addr_ok s]: a literal, an [.equ] name, or (if [addr_ok]) a label. *)
let num symbols ~addr_ok s =
  match parse_int s with
  | Some n -> Ok n
  | None ->
    (match Hashtbl.find symbols s with
     | Some (Equ n) -> Ok n
     | Some (Label a) when addr_ok -> Ok a
     | Some (Label _) -> Error (Printf.sprintf "label %S used where a number is expected" s)
     | None ->
       if is_ident s
       then Error (Printf.sprintf "undefined symbol %S" s)
       else Error (Printf.sprintf "bad number %S" s))
;;

let build symbols { mnemonic; args; _ } =
  let imm = num symbols ~addr_ok:false in
  let addr = num symbols ~addr_ok:true in
  let sample = function
    | [] -> Ok false
    | [ "sample" ] -> Ok true
    | _ -> Error "expected ', sample' or nothing"
  in
  (* "+N" (immediate offset) or "pN" (parameter register). *)
  let offset_or_param s ~imm_ctor ~param_ctor =
    match String.chop_prefix s ~prefix:"+" with
    | Some n ->
      let* n = imm (String.strip n) in
      Ok (imm_ctor n)
    | None ->
      let* p = param s in
      Ok (param_ctor p)
  in
  let bad () =
    Error
      (Printf.sprintf "unknown mnemonic or wrong operands for %S (%d given)" mnemonic
         (List.length args))
  in
  match mnemonic, args with
  | "ldi", [ r; i ] ->
    let* r = reg r in
    let* i = imm i in
    Ok (I.Ldi (r, i))
  | "cmpi", [ r; i ] ->
    let* r = reg r in
    let* i = imm i in
    Ok (I.Cmpi (r, i))
  | m, [ rd; rs ] when List.Assoc.mem alus m ~equal:String.equal ->
    let* a = lookup_name alus "alu op" m in
    let* rd = reg rd in
    let* rs = reg rs in
    Ok (I.Alu (a, rd, rs))
  | m, [ rd ] when List.Assoc.mem shifts m ~equal:String.equal ->
    let* a = lookup_name shifts "shift" m in
    let* rd = reg rd in
    Ok (I.Alu (a, rd, R0))
  | m, [ a ] when List.Assoc.mem conds m ~equal:String.equal ->
    let* c = lookup_name conds "condition" m in
    let* a = addr a in
    Ok (I.Jump (c, a))
  | "djnz", [ r; a ] ->
    let* r = reg r in
    let* a = addr a in
    Ok (I.Djnz (r, a))
  | "stg", [ f; v ] ->
    let* f = lookup_name fields "field" f in
    (match reg v with
     | Ok r -> Ok (I.Stg_reg (f, r))
     | Error _ ->
       let* i = imm v in
       Ok (I.Stg_imm (f, i)))
  | "outb", [ j ] ->
    let* j = imm j in
    Ok (I.Outb j)
  | "outl", [ j ] ->
    let* j = imm j in
    Ok (I.Outl j)
  | "inb", [ j ] ->
    let* j = imm j in
    Ok (I.Inb j)
  | "inr", [ j ] ->
    let* j = imm j in
    Ok (I.Inr j)
  | "ldsr", [ r ] ->
    let* r = reg r in
    Ok (I.Ldsr r)
  | "stsr", [ r ] ->
    let* r = reg r in
    Ok (I.Stsr r)
  | "ssl", [] -> Ok I.Ssl
  | "ssr", [] -> Ok I.Ssr
  | "at", t :: rest ->
    let* sample = sample rest in
    offset_or_param t
      ~imm_ctor:(fun offset -> I.At_imm { sample; offset })
      ~param_ctor:(fun p -> I.At_param { sample; p })
  | "wait", [] -> Ok I.Wait
  | "wait", [ t ] ->
    offset_or_param t ~imm_ctor:(fun n -> I.Wait_imm n) ~param_ctor:(fun p -> I.Wait_param p)
  | "sync", [] -> Ok I.Sync
  | "arm", [ "none" ] -> Ok (I.Arm (0, Disarm))
  | "arm", [ _; "none" ] -> Error "disarm is spelled 'arm none' (no input)"
  | "arm", [ j; e ] ->
    let* j = imm j in
    let* e = lookup_name edges "edge" e in
    Ok (I.Arm (j, e))
  | "ret", [] -> Ok I.Ret
  | "halt", [] -> Ok I.Halt
  | "fault", [ c ] ->
    let* c = imm c in
    Ok (I.Fault c)
  | "push", [ r ] ->
    let* r = reg r in
    Ok (I.Push r)
  | "pull", [ r ] ->
    let* r = reg r in
    Ok (I.Pull r)
  | "ldp", [ r; ph ] ->
    let* r = reg r in
    let* p, h =
      match String.lsplit2 ph ~on:'.' with
      | Some (p, h) -> Ok (p, h)
      | None -> Error (Printf.sprintf "expected pN.lo or pN.hi, got %S" ph)
    in
    let* p = param p in
    let* h = lookup_name halves "half" h in
    Ok (I.Ldp (r, p, h))
  | "mark", [ i ] ->
    let* i = imm i in
    Ok (I.Mark i)
  | _ -> bad ()
;;

(* ---- the two passes -------------------------------------------------- *)

let assemble src =
  let errors = ref [] in
  let err line msg = errors := (line, msg) :: !errors in
  let symbols : (string, symbol) Hashtbl.t = Hashtbl.create (module String) in
  let def_line : (string, int) Hashtbl.t = Hashtbl.create (module String) in
  let define ~line name sym =
    match Hashtbl.find def_line name with
    | Some first ->
      err line (Printf.sprintf "duplicate definition of %S (first defined on line %d)" name first)
    | None ->
      Hashtbl.set def_line ~key:name ~data:line;
      Hashtbl.set symbols ~key:name ~data:sym
  in
  (* Pass 1: labels, .equ, and the instruction list with its addresses. *)
  let labels = ref [] in
  let stmts = ref [] in
  let count = ref 0 in
  List.iteri (String.split_lines src) ~f:(fun i raw ->
    let line = i + 1 in
    let label, rest = split_label (String.strip (strip_comment raw)) in
    Option.iter label ~f:(fun l ->
      define ~line l (Label !count);
      labels := (l, !count) :: !labels);
    if not (String.is_empty rest)
    then (
      let st = parse_stmt ~line rest in
      if String.equal st.mnemonic ".equ"
      then (
        match String.split rest ~on:' ' |> List.filter ~f:(Fn.non String.is_empty) with
        | [ _; name; value ] when is_ident name ->
          (match num symbols ~addr_ok:false value with
           | Ok v -> define ~line name (Equ v)
           | Error m -> err line m)
        | _ -> err line ".equ takes 'NAME value'")
      else (
        if !count = max_words
        then err line (Printf.sprintf "program exceeds %d words" max_words);
        Int.incr count;
        stmts := st :: !stmts)));
  (* Pass 2: encode. *)
  let words =
    List.rev_map !stmts ~f:(fun st ->
      let r =
        let* i = build symbols st in
        I.encode i
      in
      match r with
      | Ok w -> w
      | Error m ->
        err st.line m;
        0)
  in
  match List.sort !errors ~compare:[%compare: int * string] with
  | _ :: _ as es -> Error es
  | [] ->
    let labels = List.rev !labels in
    let entry name = List.Assoc.find labels name ~equal:String.equal |> Option.value ~default:0 in
    Ok { words = Array.of_list words; entry = entry "ctx0", entry "ctx1"; labels }
;;

(* ---- output ---------------------------------------------------------- *)

let image_to_json { words; entry = ctx0, ctx1; labels } : Yojson.Safe.t =
  `Assoc
    [ "format", `String "pex-image-v0"
    ; "words", `List (List.map (Array.to_list words) ~f:(fun w -> `Int w))
    ; "entry", `Assoc [ "ctx0", `Int ctx0; "ctx1", `Int ctx1 ]
    ; "labels", `Assoc (List.map labels ~f:(fun (l, a) -> l, `Int a))
    ]
;;

let listing { words; _ } =
  Array.foldi words ~init:"" ~f:(fun addr acc w ->
    let text = Option.value_map (I.decode w) ~default:"<illegal>" ~f:I.to_string in
    acc ^ Printf.sprintf "%02x: %04x  %s\n" addr w text)
;;
