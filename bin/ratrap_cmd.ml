open Cmdliner
open Cmdliner.Term.Syntax

let bind_port =
  let doc = "Use this port for HTTP service and blocklist control." in
  Arg.(value & opt int 60666 & info ["p"; "port"] ~doc ~docv:"PORT")

let action =
  let doc = "Specify the blocklist action sent to blocklist_sa_r(3)" in
  let open Blocklist in
  let actions = Arg.enum [
                    ("abusive",  Abusive)
                  ; ("bad-user", Bad_User)
                  ; ("fail",     Fail)
                  ]
  in
  Arg.(value & opt actions Abusive & info ["a"; "action"] ~doc ~docv:"ACTION")

let cmd =
  let man = [
      `S "DESCRIPTION";
      `P "$(tname) passes the addresses it gets from X-Forwarded-For to libblocklist with the provided action.";
      `S "BUGS";
      `P "Report them to the author by whatever means necessary."
    ]
  in
  let version = "1.6" in
  let doc = "a blocklisting http stub" in
  Cmd.make (Cmd.info "ratrap" ~version ~doc ~man) @@
  let+ bind_port and+ action in
  Ratrap.ratrap bind_port action

let () =
  if not !Sys.interactive then
    exit @@ Cmdliner.Cmd.eval_result cmd
