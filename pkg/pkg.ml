#!/usr/bin/env ocaml
#use "topfind"
#require "topkg"
open Topkg

let () =
  Pkg.describe "ratrap" @@ fun c ->
  let system = Conf.OCaml.(find "system" @@ v c `Host_os) in
  let macosx = Option.value system ~default:"" = "macosx" in
  Ok [ Pkg.clib "src/libblacklist.clib" ~cond:(macosx);
       Pkg.mllib "src/ratrap.mllib";
       Pkg.bin "bin/ratrap_cmd" ~dst:"ratrap";
       Pkg.test "test/test"; ]
