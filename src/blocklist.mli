(** Interface to NetBSD/FreeBSD [libblocklist]


    Uses {!Ctypes_foreign} to bind to {{:https://man.netbsd.org/blocklist.3} [libblocklist]}.

    This module provides direct OCaml equivalents to the corresponding C functions and values.
 *)

(** {1 Blocklist} *)

(** OCaml type representing the C result of [blocklist_open], which we treat as an abstract pointer. *)
type handle = unit Ctypes.ptr

(** OCaml type representing the possible blocklist actions. *)
type action = OK | Fail | Abusive | Bad_User

(** Produce a connection to [blocklistd], or {!Ctypes.null} on failure. *)
val open' : unit -> handle
(** Close a given {!handle}. *)
val close : handle -> unit

(** Using the provided action and control-socket descriptor, blocklist the given
    {{!Posix_socket.sockaddr}} and string message. The length value is currently required.

    @return 0 when the underlying call succeeds.
    @raise Unix.Unix_error when the underlying call fails.
 *)
val sa : action -> Unix.file_descr
         -> Posix_socket.sockaddr Ctypes.ptr -> Posix_socket.socklen_t
         -> string
         -> int

(** Same as {!sa}, but takes an additional {!handle} from {!open'}, which keeps
    an open connection to the service.

    @return 0 when the underlying call succeeds.
    @raise Unix.Unix_error when the underlying call fails.
 *)
val sa_r : handle -> action -> Unix.file_descr
           -> Posix_socket.sockaddr Ctypes.ptr -> Posix_socket.socklen_t
           -> string
           -> int
