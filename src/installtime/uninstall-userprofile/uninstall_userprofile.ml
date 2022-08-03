open Bos
open Dkml_install_api
module Arg = Cmdliner.Arg
module Term = Cmdliner.Term

(* Call the PowerShell (legacy!) uninstall-userprofile.ps1 script *)
let uninstall_remainder_res ~scripts_dir ~prefix_dir =
  let ( let* ) = Result.bind in
  (* We cannot directly call PowerShell because we likely do not have
     administrator rights.

     BUT BUT this is a Windows batch file that will not handle spaces
     as it translates its command line arguments into PowerShell arguments.
     So any path arguments should have `cygpath -ad` performed on them
     so there are no spaces. *)
  let uninstall_bat = Fpath.(v scripts_dir / "uninstall-userprofile.bat") in
  let to83 = Ocamlcompiler_common.Os.Windows.get_dos83_short_path in
  let* prefix_dir_83 = to83 prefix_dir in
  let cmd =
    Cmd.(
      v (Fpath.to_string uninstall_bat)
      % "-AuditOnly" % "-InstallationPrefix" % prefix_dir_83 % "-SkipProgress")
  in
  Logs.info (fun l -> l "Uninstalling OCaml with@ @[%a@]" Cmd.pp cmd);
  log_spawn_onerror_exit ~id:"a0d16230" cmd;
  Ok ()

let uninstall_res ~scripts_dir ~prefix_dir =
  Dkml_install_api.Forward_progress.lift_result __POS__ Fmt.lines
    Dkml_install_api.Forward_progress.stderr_fatallog
  @@ Rresult.R.reword_error (Fmt.str "%a" Rresult.R.pp_msg)
  @@
  let ( let* ) = Rresult.R.bind in
  let* prefix_dir = Fpath.of_string prefix_dir in
  uninstall_remainder_res ~scripts_dir ~prefix_dir

let uninstall (_ : Log_config.t) scripts_dir prefix_dir =
  match uninstall_res ~scripts_dir ~prefix_dir with
  | Completed | Continue_progress ((), _) -> ()
  | Halted_progress ec ->
      exit (Dkml_install_api.Forward_progress.Exit_code.to_int_exitcode ec)

let scripts_dir_t =
  Arg.(required & opt (some dir) None & info [ "scripts-dir" ])

let prefix_dir_t =
  Arg.(required & opt (some string) None & info [ "prefix-dir" ])

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
    Term.
      ( const uninstall $ uninstall_log_t $ scripts_dir_t $ prefix_dir_t,
        info "uninstall-userprofile.bc" ~doc:"Uninstall OCaml" )
  in
  Term.(exit @@ eval t)
