open! Base
open Pex_experiment

let image =
  `Assoc
    [ "format", `String "pex-image-v0"
    ; "words", `List (List.init 4 ~f:(fun i -> `Int (i * 0x1111)))
    ; "entry", `Assoc [ "ctx0", `Int 0; "ctx1", `Int 2 ]
    ; "labels", `Assoc [ "start", `Int 0 ]
    ]
;;

let base =
  let pin i =
    { owner = (match i % 3 with 0 -> Unowned | 1 -> Ctx0 | _ -> Ctx1)
    ; logical = i % 8
    ; mode = (if i < 8 && i % 2 = 0 then Open_drain else Push_pull)
    ; idle = i % 2 = 1
    }
  in
  { name = "t"
  ; image
  ; config =
      { outputs = Array.init 15 ~f:pin
      ; input_map = [| Array.init 8 ~f:Fn.id; Array.init 8 ~f:(fun i -> 12 - i) |]
      ; trace_mode = Events
      ; entry = Result.ok_or_failwith (entry_of_image image)
      }
  ; params = Array.make_matrix ~dimx:2 ~dimy:4 0
  ; experiment_id = 0
  ; script = []
  }
;;

let edges =
  { base with
    params = Array.make_matrix ~dimx:2 ~dimy:4 0xFFFF
  ; experiment_id = 0xFFFF
  ; config = { base.config with trace_mode = Commits; entry = 3, 3 }
  ; script =
      [ Push (1, 0xFFFF); Expect_pop (0, 0); Run_cycles 1_000_000; Expect_no_fault ]
  }
;;

let%test "roundtrip edges" =
  List.for_all [ base; edges; { base with config = { base.config with trace_mode = Mark } } ]
    ~f:(fun x ->
      Result.equal equal String.equal (of_json (to_json x)) (Ok x)
      && Result.is_ok (validate x))
;;

let%test "roundtrip through text" =
  Result.equal equal String.equal
    (of_json (Yojson.Safe.from_string (Yojson.Safe.to_string (to_json edges))))
    (Ok edges)
;;

let replace_field j k v =
  match j with
  | `Assoc l -> `Assoc (List.map l ~f:(fun (k', v') -> if String.equal k k' then k, v else k', v'))
  | _ -> j
;;

let%test "rejects unknown field" =
  match to_json base with
  | `Assoc l -> Result.is_error (of_json (`Assoc (("extra", `Int 1) :: l)))
  | _ -> false
;;

let%test "rejects unknown nested field" =
  match to_json base with
  | `Assoc l ->
    let cfg =
      match List.Assoc.find_exn l ~equal:String.equal "config" with
      | `Assoc c -> `Assoc (("extra", `Int 1) :: c)
      | j -> j
    in
    Result.is_error (of_json (replace_field (`Assoc l) "config" cfg))
  | _ -> false
;;

let%test "rejects missing field" =
  match to_json base with
  | `Assoc l ->
    List.for_all l ~f:(fun (k, _) ->
      Result.is_error
        (of_json (`Assoc (List.filter l ~f:(fun (k', _) -> not (String.equal k k'))))))
  | _ -> false
;;

let%test "of_json rejects garbage without raising" =
  Result.is_error (of_json (`Int 1)) && Result.is_error (of_json (`Assoc []))
;;

let errors x = match validate x with Ok () -> [] | Error e -> e

let has x sub = List.exists (errors x) ~f:(fun e -> String.is_substring e ~substring:sub)

let with_out i f = { base with config = { base.config with outputs = Array.mapi base.config.outputs ~f:(fun j p -> if i = j then f p else p) } }

let%test "validate: open-drain on uo_out" =
  has (with_out 8 (fun p -> { p with mode = Open_drain })) "config.outputs[8]: open-drain"
  && not (has (with_out 7 (fun p -> { p with mode = Open_drain })) "open-drain")
;;

let%test "validate: logical" =
  has (with_out 3 (fun p -> { p with logical = 8 })) "config.outputs[3].logical = 8"
  && has (with_out 3 (fun p -> { p with logical = -1 })) "logical = -1"
;;

let with_map c j v = { base with config = { base.config with input_map = Array.mapi base.config.input_map ~f:(fun c' r -> if c = c' then Array.mapi r ~f:(fun j' x -> if j = j' then v else x) else r) } }

let%test "validate: input_map" =
  has (with_map 1 5 13) "config.input_map[1][5] = 13"
  && has (with_map 0 0 (-1)) "config.input_map[0][0] = -1"
  && Result.is_ok (validate (with_map 0 0 12))
;;

let%test "validate: params and id" =
  let p = Array.map base.params ~f:Array.copy in
  p.(1).(2) <- 0x10000;
  has { base with params = p } "params[1][2] = 65536"
  && has { base with experiment_id = 0x10000 } "experiment_id = 65536"
  && has { base with experiment_id = -1 } "experiment_id = -1"
;;

let%test "validate: shapes" =
  has { base with params = [| [| 0; 0; 0; 0 |] |] } "params: 1 rows"
  && has { base with params = [| [| 0 |]; [| 0; 0; 0; 0 |] |] } "params[0]: 1 entries"
  && has { base with config = { base.config with outputs = Array.sub base.config.outputs ~pos:0 ~len:14 } } "14 pins, expected 15"
  && has { base with config = { base.config with input_map = [| base.config.input_map.(0) |] } } "input_map: 1 rows"
  && has { base with config = { base.config with input_map = [| [| 0 |]; base.config.input_map.(1) |] } } "input_map[0]: 1 entries"
;;

let%test "validate: entry" =
  has { base with config = { base.config with entry = 4, 0 } } "config.entry.0 = 4"
  && has { base with config = { base.config with entry = 0, -1 } } "config.entry.1 = -1"
;;

let%test "validate: image" =
  let img l = { base with image = `Assoc l } in
  let ok = match image with `Assoc l -> l | _ -> [] in
  has { base with image = `Int 1 } "image: expected an object"
  && has (img (replace_field (`Assoc ok) "format" (`String "x") |> function `Assoc l -> l | _ -> [])) "image.format"
  && has (img (replace_field (`Assoc ok) "words" (`List [ `Int 0x10000; `String "a" ]) |> function `Assoc l -> l | _ -> [])) "image.words[0] = 65536"
  && has (img (replace_field (`Assoc ok) "words" (`List [ `Int 0; `String "a" ]) |> function `Assoc l -> l | _ -> [])) "image.words[1]: expected an int"
  && has (img (replace_field (`Assoc ok) "words" (`List (List.init 257 ~f:(fun _ -> `Int 0))) |> function `Assoc l -> l | _ -> [])) "257 words"
;;

let%test "validate: script" =
  has { base with script = [ Push (2, 0) ] } "script[0] context = 2"
  && has { base with script = [ Expect_no_fault; Expect_pop (0, 0x10000) ] } "script[1] word = 65536"
  && has { base with script = [ Run_cycles (-1) ] } "script[0] Run_cycles"
;;

let%test "validate collects all errors" =
  let x = { (with_out 8 (fun p -> { p with mode = Open_drain })) with experiment_id = -1 } in
  List.length (errors x) = 2
;;
