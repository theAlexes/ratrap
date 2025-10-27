#!/usr/bin/env ocaml
#use "topfind"
#require "topkg"
open Topkg

let () =
  Pkg.describe "ratrap" @@ fun c ->
  Ok [ Pkg.bin "src/ratrap";
       Pkg.test "test/test"; ]
