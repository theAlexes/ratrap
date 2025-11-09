open Ctypes
open Foreign
open Posix_socket

type handle = unit ptr
let t : handle typ = ptr void

type action = OK | Fail | Abusive | Bad_User
let int_of_action = Obj.magic
let action_of_int = function
  | 0 -> OK
  | 1 -> Fail
  | 2 -> Abusive
  | 3 -> Bad_User
  | _ -> invalid_arg "unknown int_of_action"
let action_t : action typ = view ~read:action_of_int ~write:int_of_action int

let fd : Unix.file_descr typ = view ~read:Obj.magic ~write:Obj.magic int

let open' =
  foreign "blacklist_open" (void @-> returning t)
let close =
  foreign "blacklist_close" (t @-> returning void)
let sa =
  foreign "blacklist_sa" ~check_errno:true (
      action_t @-> fd @->
        (ptr sockaddr_t) @-> int @-> string @->
          returning int)
let sa_r =
  foreign "blacklist_sa_r" ~check_errno:true (
      t @-> action_t @-> fd @->
        (ptr sockaddr_t) @-> int @-> string @->
          returning int)
