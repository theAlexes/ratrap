open Ctypes
open Foreign
open Posix_socket

type handle = unit ptr
let t : handle typ = ptr void

type action = OK | Fail | Abusive | Bad_User
let int_of_action : (action -> int) = Obj.magic
let action_of_int = function
  | 0 -> OK
  | 1 -> Fail
  | 2 -> Abusive
  | 3 -> Bad_User
  | _ -> invalid_arg "unknown action_of_int"
let action_t : action typ = view ~read:action_of_int ~write:int_of_action int

let fd : Unix.file_descr typ = view ~read:Obj.magic ~write:Obj.magic int

let open_ =
  foreign "blacklist_open" (void @-> returning t)

let open' () =
  let handle = open_ () in
  if Ctypes.is_null handle then
    raise Out_of_memory
  else handle

let close =
  foreign "blacklist_close" (t @-> returning void)


let posix_sockaddr_of_unix_addr addr =
  let socklen_of_int x =
    Ctypes.(coerce uint32_t Posix_socket.socklen_t) (Unsigned.UInt32.of_int x)
  in
  let sockaddr = Posix_socket.from_unix_sockaddr addr in
  let socklen = socklen_of_int @@ Posix_socket.sockaddr_len sockaddr in
  sockaddr, socklen

let sa' =
  foreign "blacklist_sa" ~check_errno:true (
      action_t @-> fd @->
        (ptr sockaddr_t) @-> socklen_t @-> string @->
          returning int)

let sa action fd addr msg =
  let sockaddr, socklen = posix_sockaddr_of_unix_addr addr in
  match sa' action fd sockaddr socklen msg with
  | 0 -> ()
  | x -> Fmt.failwith "blocklist_sa returned %d" x

let sa_r' =
  foreign "blacklist_sa_r" ~check_errno:true (
      t @-> action_t @-> fd @->
        (ptr sockaddr_t) @-> socklen_t @-> string @->
          returning int)

let sa_r handle action fd addr msg =
  let sockaddr, socklen = posix_sockaddr_of_unix_addr addr in
  match sa_r' handle action fd sockaddr socklen msg with
  | 0 -> ()
  | x -> Fmt.failwith "blocklist_sa_r returned %d" x
