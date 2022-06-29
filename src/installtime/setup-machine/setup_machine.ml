open Bos
open Cmdliner

let setup_res ~scripts_dir ~dkml_dir ~temp_dir ~vcpkg =
  let ( let* ) = Result.bind in
  (* We can directly call PowerShell because we have administrator rights.
     But for consistency we will call the .bat like in
     network_ocamlcompiler.ml and setup_userprofile.ml.

     BUT BUT this is a Windows batch file that will not handle spaces
     as it translates its command line arguments into PowerShell arguments.
     So any path arguments should have `cygpath -ad` performed on them
     so there are no spaces. *)
  let setup_machine_bat = Fpath.(v scripts_dir / "setup-machine.bat") in
  let to83 = Ocamlcompiler_common.Os.Windows.get_dos83_short_path in
  Dkml_install_api.Forward_progress.lift_result __POS__ Fmt.lines
    Dkml_install_api.Forward_progress.stderr_fatallog
  @@ Rresult.R.reword_error (Fmt.str "%a" Rresult.R.pp_msg)
  @@ let* dkml_path_83 = to83 (Fpath.v dkml_dir) in
     let* temp_dir_83 = to83 (Fpath.v temp_dir) in
     let cmd =
       Cmd.(
         v (Fpath.to_string setup_machine_bat)
         % "-DkmlPath" % dkml_path_83 % "-TempParentPath" % temp_dir_83
         % "-SkipProgress" % "-AllowRunAsAdmin")
     in
     let cmd = if vcpkg then Cmd.(cmd % "-VcpkgCompatibility") else cmd in
     Logs.info (fun l -> l "Installing Visual Studio with@ @[%a@]" Cmd.pp cmd);
     Dkml_install_api.log_spawn_onerror_exit ~id:"118acf2a" cmd;
     Ok ()

let setup (_ : Dkml_install_api.Log_config.t) scripts_dir dkml_dir temp_dir
    vcpkg =
  match setup_res ~scripts_dir ~dkml_dir ~temp_dir ~vcpkg with
  | Completed | Continue_progress _ -> ()
  | Halted_progress ec ->
      exit (Dkml_install_api.Forward_progress.Exit_code.to_int_exitcode ec)

let scripts_dir_t =
  Arg.(required & opt (some string) None & info [ "scripts-dir" ])

let dkml_dir_t = Arg.(required & opt (some string) None & info [ "dkml-dir" ])

let tmp_dir_t = Arg.(required & opt (some string) None & info [ "temp-dir" ])

let vcpkg_t = Arg.(value & flag & info [ "vcpkg" ])

let setup_log style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter (Logs_fmt.reporter ());
  Dkml_install_api.Log_config.create ?log_config_style_renderer:style_renderer
    ?log_config_level:level ()

let setup_log_t =
  Term.(const setup_log $ Fmt_cli.style_renderer () $ Logs_cli.level ())

let () =
  let t =
    Term.
      ( const setup $ setup_log_t $ scripts_dir_t $ dkml_dir_t $ tmp_dir_t
        $ vcpkg_t,
        info "setup-machine.bc" ~doc:"Install Visual Studio" )
  in
  Term.(exit @@ eval t)