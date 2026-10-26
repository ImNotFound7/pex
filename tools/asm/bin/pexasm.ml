open! Core

let () =
  Command.basic
    ~summary:"Assemble PEX assembly into a JSON program image"
    (let%map_open.Command input = anon ("input.s" %: string)
     and output = flag "-o" (required string) ~doc:"FILE write the image here"
     and listing = flag "--listing" no_arg ~doc:" print a listing to stderr" in
     fun () ->
       match Pex_asm.assemble (In_channel.read_all input) with
       | Error errors ->
         List.iter errors ~f:(fun (line, msg) -> eprintf "%s:%d: %s\n" input line msg);
         exit 1
       | Ok image ->
         Out_channel.write_all
           output
           ~data:(Yojson.Safe.to_string (Pex_asm.image_to_json image) ^ "\n");
         if listing then Out_channel.output_string stderr (Pex_asm.listing image))
  |> Command_unix.run
