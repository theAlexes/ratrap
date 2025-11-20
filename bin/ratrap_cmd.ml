open Cmdliner
open Cmdliner.Term.Syntax

let bind_port =
  let doc = "Use this port for HTTP service and blocklist control." in
  Arg.(value & opt int 60666 & info ["p"; "port"] ~doc ~docv:"PORT")

let cmd =
  let man = [
      `S "DESCRIPTION";
      `P "$(tname) passes the addresses it gets from X-Forwarded-For to libblocklist.";
      `S "BUGS";
      `P "Report them to the author by whatever means necessary."
    ]
  in
  let version = "1" in
  let doc = "a blocklisting http stub" in
  Cmd.make (Cmd.info "ratrap" ~version ~doc ~man) @@
  let+ bind_port in
  Ratrap.ratrap bind_port

let () =
  if not !Sys.interactive then
    exit @@ Cmdliner.Cmd.eval_result cmd
