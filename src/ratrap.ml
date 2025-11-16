(*---------------------------------------------------------------------------
   Copyright (c) 2025 Alex ␀ Maestas. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.


  ---------------------------------------------------------------------------*)

open Cohttp
open Cohttp_eio

let bind_port = ref 60666

let http_server net stream =
  let connection_close = Cohttp.Header.(of_list [("connection", "close")]) in
  let sip maxlen body =
    let buf = Cstruct.create maxlen in
    let len = try Eio.Flow.single_read body buf with
              | End_of_file | Unix.Unix_error _ -> 0
    in Cstruct.to_string ~len buf
  in
  let defang string =
    let buf = Buffer.create (String.length string) in
    let defang' c =
      let code = Char.code c in
      match c with
      | '\n' -> (* pass newlines through on their own*)
         Buffer.add_char buf '\n'
      | _ when code < 0x20 -> (* C0 controls become their control pictures *)
         Buffer.add_utf_8_uchar buf @@ Uchar.of_int (code lor 0x2400)
      | _ when code = 0x7f -> (* DEL has an out-of-sequence control picture *)
         Buffer.add_utf_8_uchar buf @@ Uchar.of_int 0x2421
      | _ when code > 0x7f -> (* bytes with their eighth bit set become C-hex *)
         Buffer.add_string buf (Fmt.str "\\x%.2x" code)
      | _ -> (* the rest of ASCII stays ASCII *)
         Buffer.add_char buf c
    in
    String.iter defang' string;
    Buffer.contents buf
  in
  let string_of_sockaddr = Fmt.str "%a" Eio.Net.Sockaddr.pp in
  let rec callback transport req body =
    let path = req |> Request.uri |> Uri.path_and_query
    and meth = req |> Request.meth |> Code.string_of_method
    and headers = req |> Request.headers
    and request_body = sip 240 body
    and ((_, conn), _) = transport in
    Logs.app (fun m ->
        m "Connection from %s\n%s %s\n%s\n\n%s"
          (string_of_sockaddr conn)
          meth (defang path)
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
    Eio.traceln "Blocklisting %s" xff;
    match Unix.inet_addr_of_string xff with
    | addr ->
       Eio.Stream.add stream addr
    | exception Failure _ ->
       Logs.app (fun m -> m "Address %s did not parse, skipping" xff)
  in
  let log_warning ex = Logs.warn (fun f -> f "%a" Eio.Exn.pp ex) in
  Eio.Switch.run ~name:"http" @@ fun sw ->
  let socket = Eio.Net.listen net ~sw
                 ~backlog:128 ~reuse_addr:true ~reuse_port:true
                 (`Tcp (Eio.Net.Ipaddr.V4.loopback, !bind_port))
  and server = Cohttp_eio.Server.make ~callback () in
  Logs.app (fun m -> m "---");
  Cohttp_eio.Server.run socket server ~on_error:log_warning

let blocklist_server stream () =
  let socklen_of_int x =
    Ctypes.(coerce uint32_t Posix_socket.socklen_t) (Unsigned.UInt32.of_int x)
  in
  let c_sockaddr_of_unix addr = Posix_socket.(
    from_unix_sockaddr (Unix.ADDR_INET (addr, !bind_port)))
  in
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
    let addr = Eio.Stream.take stream in
    let is_v6 = Unix.is_inet6_addr addr in
    let loopback = if is_v6 then v6 else v4 in
    Eio_unix.Fd.use loopback ~if_closed:ignore @@ fun fd ->
    Eio_unix.run_in_systhread ~label:"bl_systhread" @@ fun _ ->
      let sockaddr = c_sockaddr_of_unix addr in
      let socklen = socklen_of_int @@ Posix_socket.sockaddr_len sockaddr in
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
