open Ctypes
open Foreign
open Posix_socket

type handle = unit ptr
let t : handle typ = ptr void

let cast t ptr = from_voidp t (to_voidp ptr)

type action = OK | Fail | Abusive | Bad_User
let action_to_int = function
  | OK       -> 0
  | Fail     -> 1
  | Abusive  -> 2
  | Bad_User -> 3
let int_to_action = function
  | 0 -> OK
  | 1 -> Fail
  | 2 -> Abusive
  | 3 -> Bad_User
  | _ -> invalid_arg "unknown int_of_action"
let action_t : action typ = view ~read:int_to_action ~write:action_to_int int

let fd : Unix.file_descr typ = view ~read:(fun x : Unix.file_descr -> Obj.magic x) ~write:(fun x : int -> Obj.magic x) int

let open' =
  foreign "blacklist_open" (void @-> returning t)
let close =
  foreign "blacklist_close" (t @-> returning void)
let sa_r =
  foreign "blacklist_sa_r" ~check_errno:true (
      t @-> action_t @-> fd @->
        (ptr sockaddr_t) @-> socklen_t @-> string @->
          returning int)
