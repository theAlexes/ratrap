#!/usr/bin/env ocaml
#use "topfind"
#require "topkg"
open Topkg

let () =
  Pkg.describe "ratrap" @@ fun c ->
  let macosx = match Conf.OCaml.(find "system" @@ v c `Host_os) with
    | Some "macosx" -> true
    | _ -> false in
  Ok [ Pkg.clib "src/libblacklist.clib" ~cond:(macosx);
       Pkg.bin "src/ratrap";
       Pkg.test "test/test"; ]
