(** Interface to NetBSD/FreeBSD [libblocklist]

    This module uses {!Ctypes_foreign} to bind to
    {{:https://man.netbsd.org/blocklist.3} [libblocklist]}. It provides slightly
    enhanced OCaml equivalents to the corresponding C functions and values,
    using higher-level {!Unix} types, isolating the user from the internal
    [sockaddr]-and-[socklen_t] representation required by the underlying library
    interface. *)

(** {1 Blocklist} *)

(** OCaml type representing the C result of [blocklist_open]. *)
type handle

(** OCaml type representing the possible blocklist actions. *)
type action = OK | Fail | Abusive | Bad_User

(** Produce a connection to [blocklistd].

    @raise Stdlib.Out_of_memory if the underlying call returns [NULL], which it only
      does if its call to [calloc] fails.
 *)
val open' : unit -> handle

(** Close a given {!handle}. *)
val close : handle -> unit

(** Using the provided action and control-socket descriptor, blocklist the given
    {{!Unix.sockaddr}} with the given string message.

    @return [()] when the underlying call succeeds.
    @raise Failure when the underlying call returns nonzero but doesn't set
      [errno]. This should never happen.
    @raise Unix.Unix_error when the underlying call fails and sets [errno].
 *)
val sa : action -> Unix.file_descr -> Unix.sockaddr -> string
         -> unit

(** Same as {!sa}, but takes an additional {!handle} from {!open'}, which keeps
    an open connection to the service.

    @return [()] when the underlying call succeeds.
    @raise Failure when the underlying call returns nonzero but doesn't set
      [errno]. This should never happen.
    @raise Unix.Unix_error when the underlying call fails and sets [errno].
 *)
val sa_r : handle ->
           action -> Unix.file_descr -> Unix.sockaddr -> string
           -> unit
