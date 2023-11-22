open Dkml_install_api
module Arg = Cmdliner.Arg
module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term

(* Call the PowerShell (legacy!) uninstall-userprofile.ps1 script
   which uninstalls environment varibles. *)
let uninstall_env ~scripts_dir ~control_dir ~is_audit =
  let ( let* ) = Result.bind in
  (* We cannot directly call PowerShell because we likely do not have
     administrator rights.

     BUT BUT this is a Windows batch file that will not handle spaces
     as it translates its command line arguments into PowerShell arguments.
     So any path arguments should have `cygpath -ad` performed on them
     so there are no spaces. *)
  let uninstall_bat = Fpath.(v scripts_dir / "uninstall-userprofile.bat") in
  let to83 = Ocamlcompiler_common.Os.Windows.get_dos83_short_path in
  let* control_dir_83 = to83 control_dir in
  let cmd =
    Bos.Cmd.(
      v (Fpath.to_string uninstall_bat)
      % "-InstallationPrefix" % control_dir_83 % "-NoDeploymentSlot"
      % "-SkipProgress")
  in
  let cmd = if is_audit then Bos.Cmd.(cmd % "-AuditOnly") else cmd in
  Logs.info (fun l -> l "Uninstalling OCaml with@ @[%a@]" Bos.Cmd.pp cmd);
  log_spawn_onerror_exit ~id:"a0d16230" cmd;
  Ok ()

let do_uninstall ~scripts_dir ~control_dir ~is_audit =
  Dkml_install_api.Forward_progress.lift_result __POS__ Fmt.lines
    Dkml_install_api.Forward_progress.stderr_fatallog
  @@ Rresult.R.reword_error (Fmt.str "%a" Rresult.R.pp_msg)
  @@
  let ( let* ) = Rresult.R.bind in
  let* control_dir = Fpath.of_string control_dir in
  let* () = uninstall_env ~scripts_dir ~control_dir ~is_audit in
  Ocamlcompiler_common.uninstall_controldir ~control_dir;
  Ok ()

let uninstall (_ : Log_config.t) scripts_dir control_dir is_audit =
  match do_uninstall ~scripts_dir ~control_dir ~is_audit with
  | Completed | Continue_progress ((), _) -> ()
  | Halted_progress ec ->
      exit (Dkml_install_api.Forward_progress.Exit_code.to_int_exitcode ec)

let scripts_dir_t =
  Arg.(required & opt (some dir) None & info [ "scripts-dir" ])

let control_dir_t =
  Arg.(required & opt (some string) None & info [ "control-dir" ])

let is_audit_t = Arg.(value & flag & info [ "audit-only" ])

let uninstall_log style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter (Logs_fmt.reporter ());
  Log_config.create ?log_config_style_renderer:style_renderer
    ?log_config_level:level ()

let uninstall_log_t =
  Term.(const uninstall_log $ Fmt_cli.style_renderer () $ Logs_cli.level ())

let () =
  let t =
    Term.(
      const uninstall $ uninstall_log_t $ scripts_dir_t $ control_dir_t
      $ is_audit_t)
  in
  let info = Cmd.info "uninstall-userprofile.bc" ~doc:"Uninstall OCaml" in
  exit (Cmd.eval (Cmd.v info t))
