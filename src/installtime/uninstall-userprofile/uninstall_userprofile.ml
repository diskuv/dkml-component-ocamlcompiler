(* Cmdliner 1.0 -> 1.1 deprecated a lot of things. But until Cmdliner 1.1
   is in common use in Opam packages we should provide backwards compatibility.
   In fact, Diskuv OCaml is not even using Cmdliner 1.1. *)
[@@@alert "-deprecated"]

open Bos
open Dkml_install_api
module Arg = Cmdliner.Arg
module Term = Cmdliner.Term

(* Call the PowerShell (legacy!) uninstall-userprofile.ps1 script *)
let uninstall_start_res ~scripts_dir ~prefix_dir ~is_audit =
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
      % "-InstallationPrefix" % prefix_dir_83 % "-NoDeploymentSlot"
      % "-SkipProgress")
  in
  let cmd = if is_audit then Cmd.(cmd % "-AuditOnly") else cmd in
  Logs.info (fun l -> l "Uninstalling OCaml with@ @[%a@]" Cmd.pp cmd);
  log_spawn_onerror_exit ~id:"a0d16230" cmd;
  Ok ()

(* Remove the subdirectories of the installation directory. We don't
   uninstall the entire installation directory because on Windows
   we can't uninstall the uninstall.exe itself (while it is running). *)
let uninstall_programdir_res ~prefix_dir =
  List.iter
    (fun i ->
      let program_dir = Fpath.(prefix_dir / i) in
      Dkml_install_api.uninstall_directory_onerror_exit ~id:"8ae095b1"
        ~dir:program_dir ~wait_seconds_if_stuck:300.)
    [
      (* Legacy blue-green deployment slot 0 *)
      "0";
      (* Ordinary opam installed directories *)
      "bin";
      "doc";
      "lib";
      "man";
      "share";
      "src";
      "usr";
      (* Other components install into tools (although ideally they should
         uninstall themselves!) *)
      "tools";
      (* DKML custom opam repositories *)
      "repos";
      (* The 'dkml' tools switch *)
      "dkml";
      (* The 'playground' switch *)
      "playground"
    ]

let uninstall_res ~scripts_dir ~prefix_dir ~is_audit =
  Dkml_install_api.Forward_progress.lift_result __POS__ Fmt.lines
    Dkml_install_api.Forward_progress.stderr_fatallog
  @@ Rresult.R.reword_error (Fmt.str "%a" Rresult.R.pp_msg)
  @@
  let ( let* ) = Rresult.R.bind in
  let* prefix_dir = Fpath.of_string prefix_dir in
  let* () = uninstall_start_res ~scripts_dir ~prefix_dir ~is_audit in
  uninstall_programdir_res ~prefix_dir;
  Ok ()

let uninstall (_ : Log_config.t) scripts_dir prefix_dir is_audit =
  match uninstall_res ~scripts_dir ~prefix_dir ~is_audit with
  | Completed | Continue_progress ((), _) -> ()
  | Halted_progress ec ->
      exit (Dkml_install_api.Forward_progress.Exit_code.to_int_exitcode ec)

let scripts_dir_t =
  Arg.(required & opt (some dir) None & info [ "scripts-dir" ])

let prefix_dir_t =
  Arg.(required & opt (some string) None & info [ "prefix-dir" ])

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
    Term.
      ( const uninstall $ uninstall_log_t $ scripts_dir_t $ prefix_dir_t
        $ is_audit_t,
        info "uninstall-userprofile.bc" ~doc:"Uninstall OCaml" )
  in
  Term.(exit @@ eval t)
