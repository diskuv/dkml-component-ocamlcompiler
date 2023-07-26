open Dkml_install_api
module Arg = Cmdliner.Arg
module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term

let install_vc_redist ~vc_redist_exe =
  let cmd =
    Bos.Cmd.(v (Fpath.to_string vc_redist_exe) % "/install" % "/passive")
  in
  Logs.info (fun l ->
      l "Installing Visual C++ Redistributables with@ @[%a@]" Bos.Cmd.pp cmd);
  log_spawn_onerror_exit ~id:"61c89c1e" cmd;
  Ok ()

let setup (_ : Log_config.t) scripts_dir dkml_dir temp_dir target_abi offline
    control_dir msys2_dir_opt opam_exe_opt vcpkg dkml_confdir_exe
    vc_redist_exe_opt =
  let model_conf =
    Staging_dkmlconfdir_api.Conf_loader.create_from_system_confdir
      ~unit_name:"ocamlcompiler" ~dkml_confdir_exe
  in
  let res =
    Dkml_install_api.Forward_progress.lift_result __POS__ Fmt.lines
      Dkml_install_api.Forward_progress.stderr_fatallog
    @@ Rresult.R.reword_error (Fmt.str "%a" Rresult.R.pp_msg)
    @@
    let ( let* ) = Rresult.R.bind in
    let* () =
      match vc_redist_exe_opt with
      | None -> Ok ()
      | Some vc_redist_exe ->
          (* When we don't install Visual Studio (ex. Offline), we need
             to manually install Visual C++ Redistributables (in case the
             end-user has a new Windows PC). *)
          install_vc_redist ~vc_redist_exe
    in

    let* cygpath_opt = Bos.OS.Cmd.find_tool (Bos.Cmd.v "cygpath") in
    let* () =
      match cygpath_opt with
      | None -> Ok ()
      | Some x ->
          Rresult.R.error_msgf
            "Detected that the setup program has been called inside a Cygwin \
             or MSYS2 environment. In particular, %a was available in the \
             PATH. Since the setup program uses its own MSYS2 environment, and \
             since MSYS2 does not support one MSYS2 or Cygwin environment \
             calling another MSYS2 environment, it is highly probable the \
             installation will fail. Please rerun the setup program directly \
             from a Command Prompt, PowerShell, the File Explorer or directly \
             from the browser Downloads if you downloaded it. Do not use Git \
             Bash (part of Git for Windows) or anything else that contains an \
             MSYS2 environment."
            Fpath.pp x
    in
    let* control_dir = Fpath.of_string control_dir in
    let* temp_dir = Fpath.of_string temp_dir in
    let* dkml_dir = Fpath.of_string dkml_dir in
    (* Uninstall the old control directory. For now we don't have the
       formal concept of a data directory, although the default Opam root is
       the defacto data directory today. We do _not_ uninstall the
       data directory in the installer. That would only be done in
       the uninstaller, and we don't uninstall the default Opam root because
       it is too important.

       This procedure gives us a form of "upgrade" in addition to install.

       Things to consider:
       * Should MSYS2 be in a data directory? Basically, once it is installed,
         does MSYS2 ever need to change? Sadly it does ... when new MSYS2
         packages are introduced, MSYS2 must be upgraded. And while MSYS2
         has great upgrading ability, it has been quite troublesome to do that
         during an installation. Confer:
         https://github.com/diskuv/dkml-installer-ocaml/issues/25.
    *)
    Ocamlcompiler_common.uninstall_controldir ~control_dir ~target_abi;
    (* We cannot directly call PowerShell because we likely do not have
       administrator rights.

       BUT BUT this is a Windows batch file that will not handle spaces
       as it translates its command line arguments into PowerShell arguments.
       So any path arguments should have `cygpath -ad` performed on them
       so there are no spaces. *)
    let setup_bat = Fpath.(v scripts_dir / "setup-userprofile.bat") in
    let to83 = Ocamlcompiler_common.Os.Windows.get_dos83_short_path in
    let* cmd =
      (* Common setup-userprofile.bat arguments *)
      let* control_dir_83 = to83 control_dir in
      let* dkml_path_83 = to83 dkml_dir in
      let* temp_dir_83 = to83 temp_dir in
      Ok
        Bos.Cmd.(
          v (Fpath.to_string setup_bat)
          % "-AllowRunAsAdmin" % "-InstallationPrefix" % control_dir_83
          % "-OCamlLangVersion" % Ocamlcompiler_common.ocaml_ver % "-DkmlPath"
          % dkml_path_83 % "-NoDeploymentSlot" % "-DkmlHostAbi"
          % Context.Abi_v2.to_canonical_string target_abi
          % "-TempParentPath" % temp_dir_83 % "-SkipProgress"
          % "-SkipMSYS2Update")
    in
    let* cmd =
      (* Add -OpamExe *)
      match opam_exe_opt with
      | None -> Ok cmd
      | Some opam_exe ->
          let* opam_exe = Fpath.of_string opam_exe in
          let* opam_exe_83 = to83 opam_exe in
          Ok Bos.Cmd.(cmd % "-OpamExe" % opam_exe_83)
    in
    let* cmd =
      (* Add -MSYS2Dir *)
      match msys2_dir_opt with
      | None -> Ok cmd
      | Some msys2_dir ->
          let* msys2_dir = Fpath.of_string msys2_dir in
          let* msys2_dir_83 = to83 msys2_dir in
          Ok Bos.Cmd.(cmd % "-MSYS2Dir" % msys2_dir_83)
    in
    let cmd =
      (* Add -Offline *)
      if offline then Bos.Cmd.(cmd % "-Offline") else cmd
    in
    let cmd =
      (* Add -VcpkgCompatibility *)
      if vcpkg then Bos.Cmd.(cmd % "-VcpkgCompatibility") else cmd
    in
    let cmd =
      (* Add -ImpreciseC99FloatOps *)
      if Model_conf.feature_flag_imprecise_c99_float_ops model_conf then (
        Logs.info (fun l -> l "Using [feature_flag_imprecise_c99_float_ops]");
        Bos.Cmd.(cmd % "-ImpreciseC99FloatOps"))
      else cmd
    in
    Logs.info (fun l ->
        l "Installing %s with@ @[%a@]"
          (if offline then "OCaml" else "Git, OCaml and other tools")
          Bos.Cmd.pp cmd);
    log_spawn_onerror_exit ~id:"a0d16230" cmd;
    Ok ()
  in
  match res with
  | Completed | Continue_progress ((), _) -> ()
  | Halted_progress ec ->
      exit (Dkml_install_api.Forward_progress.Exit_code.to_int_exitcode ec)

let scripts_dir_t =
  Arg.(required & opt (some dir) None & info [ "scripts-dir" ])

let dkml_dir_t = Arg.(required & opt (some dir) None & info [ "dkml-dir" ])
let tmp_dir_t = Arg.(required & opt (some dir) None & info [ "temp-dir" ])

let control_dir_t =
  Arg.(required & opt (some string) None & info [ "control-dir" ])

let msys2_dir_opt_t = Arg.(value & opt (some dir) None & info [ "msys2-dir" ])
let opam_exe_opt_t = Arg.(value & opt (some file) None & info [ "opam-exe" ])

let target_abi_t =
  let open Context.Abi_v2 in
  let l =
    List.map (fun v -> (to_canonical_string v, v)) Context.Abi_v2.values
  in
  Arg.(required & opt (some (enum l)) None & info [ "target-abi" ])

let vcpkg_t = Arg.(value & flag & info [ "vcpkg" ])
let offline_t = Arg.(value & flag & info [ "offline" ])

let dkml_confdir_exe_t =
  let doc = "The location of dkml-confdir.exe" in
  let v =
    Arg.(required & opt (some file) None & info ~doc [ "dkml-confdir-exe" ])
  in
  Term.(const Fpath.v $ v)

let vc_redist_exe_opt_t =
  let doc =
    "The location of Visual C++ Redistributables (vc_redist.x64.exe or a \
     similar name specific to this machine's architecture)"
  in
  let v_opt =
    Arg.(value & opt (some file) None & info ~doc [ "vc-redist-exe" ])
  in
  Term.(const (Option.map Fpath.v) $ v_opt)

let setup_log style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter (Logs_fmt.reporter ());
  Log_config.create ?log_config_style_renderer:style_renderer
    ?log_config_level:level ()

let setup_log_t =
  Term.(const setup_log $ Fmt_cli.style_renderer () $ Logs_cli.level ())

let () =
  let t =
    Term.(
      const setup $ setup_log_t $ scripts_dir_t $ dkml_dir_t $ tmp_dir_t
      $ target_abi_t $ offline_t $ control_dir_t $ msys2_dir_opt_t
      $ opam_exe_opt_t $ vcpkg_t $ dkml_confdir_exe_t $ vc_redist_exe_opt_t)
  in
  let info =
    Cmd.info "setup-userprofile.bc"
      ~doc:
        "Install Git for Windows and Opam, and compiles OCaml and some useful \
         OCaml programs"
  in
  exit (Cmd.eval (Cmd.v info t))
