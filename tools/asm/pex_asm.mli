(** Two-pass assembler for PEX assembly.  Every bad operand is a line-numbered
    error; operand range checks are delegated to [Pex_isa.encode]. *)

type image =
  { words : int array
  ; entry : int * int  (** addresses of the [ctx0:] and [ctx1:] labels; 0 if absent *)
  ; labels : (string * int) list  (** in definition order *)
  }

(** Errors are [(line, message)], sorted by line, one per offending line. *)
val assemble : string -> (image, (int * string) list) result

(** [{"format":"pex-image-v0","words":[..],"entry":{"ctx0":a,"ctx1":b},"labels":{..}}] *)
val image_to_json : image -> Yojson.Safe.t

(** One line per word: address, hex word, disassembly. *)
val listing : image -> string
