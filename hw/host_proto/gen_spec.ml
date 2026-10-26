open! Base
open Stdio

let () =
  match Sys.get_argv () with
  | [| _; "json" |] ->
    print_endline (Yojson.Safe.pretty_to_string (Pex_host_proto.spec_json ()))
  | [| _; "md" |] -> print_string (Pex_host_proto.spec_markdown ())
  | _ -> failwith "usage: gen_spec (json|md)"
;;
