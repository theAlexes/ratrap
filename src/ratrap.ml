(*---------------------------------------------------------------------------
   Copyright (c) 2025 Alex ␀ Maestas. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.


  ---------------------------------------------------------------------------*)

open Cohttp
open Cohttp_eio
open Eio
open Saturn

module InetAddr = struct
  type t = Unix.inet_addr
  let equal = Stdlib.(=)
  let hash = Hashtbl.hash
end

let http_server ~sw ~bind_port ~(net:_ Net.t) ~(cl:_ Eio.Time.clock) ~(stream:Unix.inet_addr Stream.t) ?stop =
  let connection_close = Cohttp.Header.(of_list [("connection", "close")]) in
  let siplen = 240 in
  let sip maxlen body =
    let buf = Cstruct.create maxlen in
    let len = try Flow.single_read body buf with
              | End_of_file | Unix.Unix_error _ -> 0
    in Cstruct.to_string ~len buf
  in
  let defang string =
    let buf = Buffer.create @@ String.length string in
    let defang' c =
      let code = Char.code c in
      match c with
      | '\n' | '\x20'..'\x7e' -> (* pass newlines and printable ASCII through *)
         Buffer.add_char        buf c
      | '\x80'..'\xff'        -> (* bytes with their eighth bit set become C-hex *)
         Buffer.add_string      buf @@ Fmt.str "\\x%.2x" code
      | '\x00'..'\x1f'        -> (* C0 controls become their control pictures *)
         Buffer.add_utf_8_uchar buf @@ Uchar.of_int (code lor 0x2400)
      | '\x7f'                -> (* DEL has an out-of-sequence control picture *)
         Buffer.add_utf_8_uchar buf @@ Uchar.of_int 0x2421
    in
    String.iter defang' string;
    Buffer.contents buf
  in
  let string_of_sockaddr = Fmt.str "%a" Net.Sockaddr.pp in
  let recents = Htbl.create ~hashed_type:(module InetAddr) () in
  let rec maybe_add stream addr xff =
    let maybe_remove () =
      Time.sleep cl 5.0;
      traceln "Forgetting about %s" xff;
      Htbl.try_remove recents addr |> ignore
    in
    if Htbl.try_add recents addr ()
    then begin
        traceln "Blocklisting %s" xff;
        Stream.add stream addr;
        Fiber.fork ~sw maybe_remove
      end
    else traceln "Already blocked %s recently, skipping" xff
  and callback transport req body =
    let ((_, conn), _) = transport
    and path = req |> Request.uri |> Uri.path_and_query
    and meth = req |> Request.meth
    and headers = req |> Request.headers in
    let maxlen =
      match Header.get headers "content-length" with
      | Some cl -> min siplen (try int_of_string cl with _ -> siplen)
      | None -> siplen
    in
    let request_body =
      match meth with
      | `GET | `HEAD | `DELETE | `Other "PROPFIND" -> ""
      | _ -> sip maxlen body
    in
    Logs.app (fun m ->
        m "Connection from %s\n%s %s\n%s\n\n%s"
          (string_of_sockaddr conn)
          (Code.string_of_method meth) (defang path)
          (* we're on unix, don't put \r when displaying the headers *)
          (defang @@ String.concat "\n" @@ Header.to_frames headers)
          (defang request_body));
    let status = blocklist_of_headers headers stream in
    Logs.app (fun m -> m "---");
    Cohttp_eio.Server.respond_string ~headers:connection_close ~status ~body:"" ()
  and blocklist_of_headers h stream =
    match Header.get h "x-forwarded-for" with
    | Some xff -> blocklist (defang xff) stream;
                  `Not_found
    | None -> Logs.app (fun m -> m "Missing x-forwarded-for header, not blocklisting");
              `Internal_server_error
  and blocklist xff stream =
    match Unix.inet_addr_of_string xff with
    | addr ->
       maybe_add stream addr xff
    | exception Failure _ ->
       Logs.app (fun m -> m "Address %s did not parse, skipping" xff)
  in
  let log_warning ex = Logs.warn (fun f -> f "%a" Exn.pp ex) in
  Switch.run ~name:"http" @@ fun sw ->
  let socket = Net.listen net ~sw
                 ~backlog:128 ~reuse_addr:true ~reuse_port:true
                 (`Tcp (Net.Ipaddr.V4.loopback, bind_port))
  and server = Cohttp_eio.Server.make ~callback () in
  Logs.app (fun m -> m "--- (bind port %d)" bind_port);
  Cohttp_eio.Server.run socket server ~on_error:log_warning ?stop

let blocklist_server ~bind_port ~action ~(stream:Unix.inet_addr Stream.t) () =
  (* a regular Eio.Net.listen socket does not expose its FD to us,
     so we must construct a socket and bind it ourselves.
     i suppose we could use the `import_listening_socket` call, but
     we really aren't using it for anything other than its file descriptor. *)
  let control_socket ~sw bind_addr =
    let open Unix in
    let pf = Net.Ipaddr.fold bind_addr
               ~v4:Fun.(const PF_INET) ~v6:Fun.(const PF_INET6) in
    let listener = socket ~cloexec:true pf SOCK_STREAM 0 in
    setsockopt listener SO_REUSEADDR true;
    setsockopt listener SO_REUSEPORT true;
    bind listener @@ Eio_unix.Net.sockaddr_to_unix (`Tcp (bind_addr, bind_port));
    Eio_unix.Fd.of_unix ~sw ~close_unix:true listener
  in
  Switch.run ~name:"blocklist" @@ fun sw ->
  let bl = ref @@ Blocklist.open' () in
  Switch.on_release sw (fun _ -> Blocklist.close !bl);
  let v4, v6 =
    let bi f = Pair.map f f in
    bi (control_socket ~sw) Net.Ipaddr.(V4.loopback, V6.loopback)
  in
  let mutex = Eio.Mutex.create () in
  let reconnect () =
    Eio.Mutex.use_rw ~protect:false mutex @@
      fun () ->
      traceln "blocklistd connection was reset; reconnecting";
      let new_blocklist = Blocklist.open' () in
      traceln "new connection obtained, swapping out";
      ignore @@ Blocklist.close !bl;
      bl := new_blocklist
  in
  while true do
    let addr = Stream.take stream in
    let addr' = Unix.string_of_inet_addr addr in
    let loopback = if Unix.is_inet6_addr addr then v6 else v4 in
    (* fyi running this in a systhread means that if it throws, the only thing
       that dies is that thread. *)
    Eio_unix.run_in_systhread ~label:"bl_systhread" @@ fun _ ->
    Eio_unix.Fd.use loopback ~if_closed:ignore @@ fun fd ->
      let sockaddr = Unix.ADDR_INET (addr, bind_port) in
      (* this is kind of a mess, but is enough to make a blocklistd restart
         survivable without requiring a ratrap restart. not sure if a result type
         would improve the situation, though. *)
      match Blocklist.sa_r !bl action fd sockaddr "ratrap" with
      | () -> traceln "successfully blocklisted %s" addr'
      | exception Unix.(Unix_error (errno, _, _)) ->
         begin
          traceln "did not blocklist %s (%s), falling back to sa" addr' Unix.(error_message errno);
          match Blocklist.sa action fd sockaddr "ratrap" with
          | () ->
             traceln "fallback succeeded for %s" addr';
             if errno = Unix.ECONNRESET then reconnect ()
          | exception exn ->
             Fmt.failwith "double-failed on %s: Blocklist service errored, and did not respond to retries: %a" addr' Exn.pp exn
         end
      | exception exn -> traceln "failed to blocklist %s: %a" addr' Exn.pp exn
  done

let run ~bind_port ~action ~(net:_ Net.t) ~cl ?stop =
  Switch.run ~name:"ratrap" @@ fun sw ->
  let stream : Unix.inet_addr Stream.t = Stream.create 0 in
  Fiber.fork_daemon ~sw (blocklist_server ~bind_port ~action ~stream);
  http_server ~sw ~cl ~bind_port ~net ~stream ?stop

let ratrap ~bind_port ~action =
  Logs.set_reporter @@ Logs_fmt.reporter ();
  Eio_main.run @@ fun env ->
     let stop, stop' = Promise.create () in
     let handler _ = Promise.resolve_ok stop' () in
     let open Sys in
     List.iter
       (fun s -> set_signal s @@ Signal_handle handler)
       [ sighup ; sigint ; sigterm ; sigabrt ];
     try run ~bind_port ~action ~net:env#net ~cl:env#clock ~stop with
     | exn -> Fmt.error "%a" Exn.pp exn

(*---------------------------------------------------------------------------
   Copyright (c) 2025 Alex ␀ Maestas

   Permission to use, copy, modify, and/or distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
  ---------------------------------------------------------------------------*)
