open! Base
open Stdio

let words src =
  match Pex_asm.assemble src with
  | Ok img -> img.words
  | Error es -> failwith (String.concat ~sep:"; " (List.map es ~f:snd))
;;

let show_errors src =
  match Pex_asm.assemble src with
  | Ok _ -> print_endline "ok"
  | Error es -> List.iter es ~f:(fun (l, m) -> printf "%d: %s\n" l m)
;;

let%expect_test "assembles_uart_tx_snippet" =
  let src =
    {|; uart tx, one byte
.equ BIT 434
ctx0: ldi r0, 0x55
      ldsr r0      ; shift register
loop: at +BIT
      outb 0
      djnz r1, loop
      halt
|}
  in
  Array.iter (words src) ~f:(printf "0x%04x\n");
  [%expect {|
    0x0055
    0x6700
    0x71b2
    0x6300
    0x4402
    0x9600
    |}]
;;

let%expect_test "test_range_errors" =
  show_errors "at +2048\nldi r0, 256\noutb 8\njmp nowhere";
  [%expect {|
    1: at: offset 2048 out of range 0..2047
    2: ldi: imm 256 out of range 0..255
    3: outb: j 8 out of range 0..7
    4: undefined symbol "nowhere"
    |}]
;;

let%expect_test "more errors" =
  show_errors "frob r0\nldi r4, 1\nldi r0\nshl r0, r1\narm 3, none\narm none\nldi r0, BAD\nldi r0, lbl\nlbl: halt";
  [%expect {|
    1: unknown mnemonic or wrong operands for "frob" (1 given)
    2: expected register r0..r3, got "r4"
    3: unknown mnemonic or wrong operands for "ldi" (1 given)
    4: unknown mnemonic or wrong operands for "shl" (2 given)
    5: disarm is spelled 'arm none' (no input)
    7: undefined symbol "BAD"
    8: label "lbl" used where a number is expected
    |}]
;;

let%expect_test "duplicate_label" =
  show_errors "a: halt\nnop_pad: ssl\na: ret";
  [%expect {| 3: duplicate definition of "a" (first defined on line 1) |}]
;;

let%expect_test "overflow_257_words" =
  show_errors (String.concat (List.init 257 ~f:(fun _ -> "halt\n")));
  [%expect {| 257: program exceeds 256 words |}]
;;

let%expect_test "entry points" =
  let show src =
    match Pex_asm.assemble src with
    | Ok { entry = a, b; _ } -> printf "%d %d\n" a b
    | Error _ -> print_endline "error"
  in
  show "halt";
  show "ssl\nctx1: halt";
  show "ctx0: ssl\nctx1: halt";
  [%expect {|
    0 0
    0 1
    0 1
    |}]
;;

let%expect_test "json and listing" =
  match Pex_asm.assemble "ctx0: halt\nctx1: jmp ctx0" with
  | Error _ -> assert false
  | Ok img ->
    print_endline (Yojson.Safe.to_string (Pex_asm.image_to_json img));
    print_string (Pex_asm.listing img);
    [%expect {|
      {"format":"pex-image-v0","words":[38400,12288],"entry":{"ctx0":0,"ctx1":1},"labels":{"ctx0":0,"ctx1":1}}
      00: 9600  halt
      01: 3000  jmp 0x00
      |}]
;;

let%test "listing_round_trips" =
  let src =
    {|ctx0: ldi r3, 0xff
cmpi r1, 7
add r1, r2
shl r2
shr r3
jmp 0x10
call ctx0
jto 3
djnz r2, 5
stg out, 0x12
stg oe, r1
stg mask, r3
outb 7
outl 0
inb 3
inr 4
ldsr r1
stsr r2
ssl
ssr
at +2047, sample
at +0
at p3, sample
at p0
wait
wait +4095
wait p2
sync
arm 7, either
arm 0, low
arm none
ret
halt
fault 15
push r0
pull r3
ldp r2, p3.hi
ldp r0, p0.lo
mark 0xa5
|}
  in
  let w = words src in
  Array.length w > 30
  && Array.for_all w ~f:(fun x ->
    match Pex_isa.decode x with
    | None -> false
    | Some i -> Array.equal Int.equal (words (Pex_isa.to_string i)) [| x |])
;;
