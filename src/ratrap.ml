(*---------------------------------------------------------------------------
   Copyright (c) 2025 Alex ␀ Maestas. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.


  ---------------------------------------------------------------------------*)

open Cohttp
open Cohttp_eio
open Ctypes
open Foreign

type blocklist_handle = unit ptr
let blocklist_t : blocklist_handle typ = ptr void

let blocklist_open = foreign "blacklist_open" (void @-> returning blocklist_t)
let blocklist_close = foreign "blacklist_close" (blocklist_t @-> returning void)

let string_of_sockaddr = Fmt.str "%a" Eio.Net.Sockaddr.pp
let connection_close = Some Cohttp.Header.(of_list [("connection", "close")])

let blocklist xff =
  Logs.app (fun m -> m "Blocklisting %s" xff)

let blocklist_of_headers h =
  match Header.get h "x-forwarded-for" with
  | Some xff -> blocklist xff; `Code 444
  | None -> Logs.app (fun m -> m "Missing x-forwarded-for header, not blocklisting"); `Internal_server_error

let callback transport req body =
  let path = req |> Request.uri |> Uri.path_and_query in
  let meth = req |> Request.meth |> Code.string_of_method in
  let headers = req |> Request.headers in
  let headers_string = headers |> Header.to_string in
  let request_body = Eio.Buf_read.(parse_exn take_all) body ~max_size:240 in
  let ((_, conn), _) = transport in
  Logs.app (fun m -> m "Connection from %s\n%s %s\n%s%s" (string_of_sockaddr conn) meth path headers_string request_body);
  let status = blocklist_of_headers headers in
  Logs.app (fun m -> m "---");
  Cohttp_eio.Server.respond_string ?headers:connection_close ~status ~body:"" ()

let log_warning ex = Logs.warn (fun f -> f "%a" Eio.Exn.pp ex)

let http_server net =
  Eio.Switch.run ~name:"http" @@ fun sw ->
  let socket =
    Eio.Net.listen net ~sw ~backlog:128
      (`Tcp (Eio.Net.Ipaddr.V4.loopback, 8000))
  and server = Cohttp_eio.Server.make ~callback () in
  Logs.app (fun m -> m "---");
  Cohttp_eio.Server.run socket server ~on_error:log_warning

let () =
  Logs.set_reporter (Logs_fmt.reporter ());
  let handle = blocklist_open () in
  Eio_main.run @@ (fun env -> http_server env#net);
  blocklist_close handle;
  ()


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
