(*---------------------------------------------------------------------------
   Copyright (c) 2025 Alex ␀ Maestas. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.


  ---------------------------------------------------------------------------*)

open Cohttp
open Cohttp_eio

let bind_port = ref 60666
let string_of_sockaddr = Fmt.str "%a" Eio.Net.Sockaddr.pp
let connection_close = Some Cohttp.Header.(of_list [("connection", "close")])
let log_warning ex = Logs.warn (fun f -> f "%a" Eio.Exn.pp ex)
let c_sockaddr_of_unix addr = Posix_socket.(
    from_unix_sockaddr (Unix.ADDR_INET (addr, !bind_port)))

let http_server net stream =
  let rec callback transport req body =
    let path = req |> Request.uri |> Uri.path_and_query
    and meth = req |> Request.meth |> Code.string_of_method
    and headers = req |> Request.headers
    and request_body = Eio.Buf_read.(parse_exn take_all) body ~max_size:240
    and ((_, conn), _) = transport in
    Logs.app (fun m ->
        m "Connection from %s\n%s %s\n%s%s"
          (string_of_sockaddr conn)
          meth path
          (Header.to_string headers)
          request_body);
    let status = blocklist_of_headers headers stream in
    Logs.app (fun m -> m "---");
    Cohttp_eio.Server.respond_string ?headers:connection_close ~status ~body:"" ()
  and blocklist_of_headers h stream =
    match Header.get h "x-forwarded-for" with
    | Some xff -> blocklist xff stream;
                  `Not_found
    | None -> Logs.app (fun m -> m "Missing x-forwarded-for header, not blocklisting");
              `Internal_server_error
  and blocklist xff stream =
    Eio.traceln "Blocklisting %s" xff;
    match Unix.inet_addr_of_string xff with
    | addr ->
       Eio.Stream.add stream @@ (Unix.is_inet6_addr addr, c_sockaddr_of_unix addr)
    | exception Failure _ ->
       Logs.app (fun m -> m "Address %s did not parse, skipping" xff)
  in
  Eio.Switch.run ~name:"http" @@ fun sw ->
  let socket = Eio.Net.listen net ~sw
                 ~backlog:128 ~reuse_addr:true ~reuse_port:true
                 (`Tcp (Eio.Net.Ipaddr.V4.loopback, !bind_port))
  and server = Cohttp_eio.Server.make ~callback () in
  Logs.app (fun m -> m "---");
  Cohttp_eio.Server.run socket server ~on_error:log_warning

let blocklist_server stream () =
  (* a regular Eio.Net.listen socket does not expose its FD to us,
     so we must construct a socket and bind it ourselves.
     i suppose we could use the `import_listening_socket` call, but
     we really aren't using it for anything other than its file descriptor. *)
  let control_socket ~sw bind_addr =
    let pf = Eio.Net.Ipaddr.fold bind_addr
               ~v4:(fun _ -> Unix.PF_INET) ~v6:(fun _ -> Unix.PF_INET6) in
    let listener = Unix.(socket ~cloexec:true pf SOCK_STREAM 0) in
    let open Unix in
    setsockopt listener SO_REUSEADDR true;
    setsockopt listener SO_REUSEPORT true;
    bind listener @@ Eio_unix.Net.sockaddr_to_unix (`Tcp (bind_addr, !bind_port));
    Eio_unix.Fd.of_unix ~sw ~close_unix:true listener
  in
  Eio.Switch.run ~name:"blocklist" @@ fun sw ->
  let bl = ref @@ Blocklist.open' () in
  Eio.Switch.on_release sw (fun _ -> Blocklist.close !bl);
  let open Eio.Net.Ipaddr in
  let v4 = control_socket ~sw V4.loopback
  and v6 = control_socket ~sw V6.loopback in
  let reconnect () =
    let new_blocklist = Blocklist.open' () in
    if new_blocklist = Ctypes.null then
      failwith "Can't reconnect, blocklist returned null"
    else begin
        ignore @@ Blocklist.close !bl;
        bl := new_blocklist
      end
  in
  while true do
    let is_v6, sockaddr = Eio.Stream.take stream in
    let loopback = if is_v6 then v6 else v4 in
    Eio_unix.Fd.use loopback ~if_closed:ignore @@ fun fd ->
    Eio_unix.run_in_systhread ~label:"bl_systhread" @@ fun _ ->
        let socklen = Posix_socket.sockaddr_len sockaddr in
        match Blocklist.sa_r !bl Blocklist.Abusive fd sockaddr socklen "lol" with
        | 0 -> Eio.traceln "successfully blocklisted"
        | x -> Eio.traceln "did not blocklist, but also did not errno, rv %d" x
        | exception Unix.(Unix_error (ECONNRESET, _, _)) ->
           Eio.traceln "did not blocklist, connection reset, falling back to _sa";
           if Blocklist.sa Blocklist.Abusive fd sockaddr socklen "lol" = 0 then begin
               Eio.traceln "fallback succeeded; reconnecting"; reconnect ()
             end
           else failwith "Blocklist service reset and did not respond to retries"
        | exception exn -> Eio.traceln "failed to blocklist: %a" Eio.Exn.pp exn
  done

let () =
  Logs.set_reporter (Logs_fmt.reporter ());
  Eio_main.run @@ fun env ->
    Eio.Switch.run ~name:"main" @@ fun sw ->
    let stream = Eio.Stream.create 0 in
    Eio.Fiber.fork ~sw (blocklist_server stream);
    http_server env#net stream

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
