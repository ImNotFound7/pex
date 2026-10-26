open! Base
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Json = struct
  type t = Yojson.Safe.t

  let t_of_yojson x = x
  let yojson_of_t x = x
  let sexp_of_t x = Sexp.Atom (Yojson.Safe.to_string x)
  let equal = Yojson.Safe.equal
end

type owner =
  | Unowned
  | Ctx0
  | Ctx1
[@@deriving sexp_of, equal, yojson]

type mode =
  | Push_pull
  | Open_drain
[@@deriving sexp_of, equal, yojson]

type out_pin =
  { owner : owner
  ; logical : int
  ; mode : mode
  ; idle : bool
  }
[@@deriving sexp_of, equal, yojson]

type trace_mode =
  | Mark
  | Events
  | Commits
[@@deriving sexp_of, equal, yojson]

type config =
  { outputs : out_pin array
  ; input_map : int array array
  ; trace_mode : trace_mode
  ; entry : int * int
  }
[@@deriving sexp_of, equal, yojson]

type step =
  | Push of int * int
  | Expect_pop of int * int
  | Run_cycles of int
  | Expect_no_fault
[@@deriving sexp_of, equal, yojson]

type t =
  { name : string
  ; image : Json.t
  ; config : config
  ; params : int array array
  ; experiment_id : int
  ; script : step list
  }
[@@deriving sexp_of, equal, yojson]

let to_json = yojson_of_t

let of_json j =
  try Ok (t_of_yojson j) with
  | Ppx_yojson_conv_lib.Yojson_conv.Of_yojson_error (exn, _) ->
    Error (Exn.to_string exn)
  | exn -> Error (Exn.to_string exn)
;;

let image_words j =
  match j with
  | `Assoc fields ->
    (match List.Assoc.find fields ~equal:String.equal "format" with
     | Some (`String "pex-image-v0") ->
       (match List.Assoc.find fields ~equal:String.equal "words" with
        | Some (`List ws) -> Ok ws
        | _ -> Error "image.words: expected a list")
     | _ -> Error "image.format: expected \"pex-image-v0\"")
  | _ -> Error "image: expected an object"
;;

let entry_of_image j =
  match j with
  | `Assoc fields ->
    (match List.Assoc.find fields ~equal:String.equal "entry" with
     | Some (`Assoc e) ->
       (match
          ( List.Assoc.find e ~equal:String.equal "ctx0"
          , List.Assoc.find e ~equal:String.equal "ctx1" )
        with
        | Some (`Int a), Some (`Int b) -> Ok (a, b)
        | _ -> Error "image.entry: expected ints ctx0 and ctx1")
     | _ -> Error "image.entry: expected an object")
  | _ -> Error "image: expected an object"
;;

let validate t =
  let errs = ref [] in
  let err fmt = Printf.ksprintf (fun s -> errs := s :: !errs) fmt in
  let range name lo hi v = if v < lo || v > hi then err "%s = %d: out of range %d..%d" name v lo hi in
  let nwords =
    match image_words t.image with
    | Error e -> err "%s" e; None
    | Ok ws ->
      let n = List.length ws in
      if n > 256 then err "image.words: %d words, at most 256" n;
      List.iteri ws ~f:(fun i w ->
        match w with
        | `Int v -> range (Printf.sprintf "image.words[%d]" i) 0 0xFFFF v
        | _ -> err "image.words[%d]: expected an int" i);
      Some n
  in
  range "experiment_id" 0 0xFFFF t.experiment_id;
  if Array.length t.params <> 2
  then err "params: %d rows, expected 2" (Array.length t.params);
  Array.iteri t.params ~f:(fun c row ->
    if Array.length row <> 4
    then err "params[%d]: %d entries, expected 4" c (Array.length row);
    Array.iteri row ~f:(fun i v -> range (Printf.sprintf "params[%d][%d]" c i) 0 0xFFFF v));
  let outs = t.config.outputs in
  if Array.length outs <> 15
  then err "config.outputs: %d pins, expected 15" (Array.length outs);
  Array.iteri outs ~f:(fun i p ->
    range (Printf.sprintf "config.outputs[%d].logical" i) 0 7 p.logical;
    match p.mode with
    | Open_drain when i >= 8 ->
      err "config.outputs[%d]: open-drain not allowed on uo_out pins (outputs 8..14)" i
    | _ -> ());
  let im = t.config.input_map in
  if Array.length im <> 2 then err "config.input_map: %d rows, expected 2" (Array.length im);
  Array.iteri im ~f:(fun c row ->
    if Array.length row <> 8
    then err "config.input_map[%d]: %d entries, expected 8" c (Array.length row);
    Array.iteri row ~f:(fun j v ->
      range (Printf.sprintf "config.input_map[%d][%d]" c j) 0 12 v));
  let e0, e1 = t.config.entry in
  Option.iter nwords ~f:(fun n ->
    List.iter [ "config.entry.0", e0; "config.entry.1", e1 ] ~f:(fun (name, v) ->
      if v < 0 || v >= n then err "%s = %d: out of range 0..%d (image words)" name v (n - 1)));
  List.iteri t.script ~f:(fun i s ->
    let ctx v = range (Printf.sprintf "script[%d] context" i) 0 1 v in
    let byte v = range (Printf.sprintf "script[%d] byte" i) 0 0xFF v in
    match s with
    | Push (c, w) | Expect_pop (c, w) -> ctx c; byte w
    | Run_cycles n -> if n < 0 then err "script[%d] Run_cycles = %d: must be >= 0" i n
    | Expect_no_fault -> ());
  if List.is_empty !errs then Ok () else Error (List.rev !errs)
;;
