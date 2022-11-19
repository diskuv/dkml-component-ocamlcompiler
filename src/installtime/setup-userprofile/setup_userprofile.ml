(* Cmdliner 1.0 -> 1.1 deprecated a lot of things. But until Cmdliner 1.1
   is in common use in Opam packages we should provide backwards compatibility.
   In fact, Diskuv OCaml is not even using Cmdliner 1.1. *)
[@@@alert "-deprecated"]

open Bos
open Dkml_install_api
module Arg = Cmdliner.Arg
module Term = Cmdliner.Term

(* Call the PowerShell (legacy!) setup-userprofile.ps1 script *)
let setup_remainder_res ~scripts_dir ~dkml_dir ~temp_dir ~abi ~prefix_dir
    ~msys2_dir ~opam_exe ~vcpkg =
  let ( let* ) = Result.bind in
  (* We cannot directly call PowerShell because we likely do not have
     administrator rights.

     BUT BUT this is a Windows batch file that will not handle spaces
     as it translates its command line arguments into PowerShell arguments.
     So any path arguments should have `cygpath -ad` performed on them
     so there are no spaces. *)
  let setup_bat = Fpath.(v scripts_dir / "setup-userprofile.bat") in
  let to83 = Ocamlcompiler_common.Os.Windows.get_dos83_short_path in
  let* prefix_dir_83 = to83 prefix_dir in
  let* msys2_dir_83 = to83 msys2_dir in
  let* opam_exe_83 = to83 opam_exe in
  let* dkml_path_83 = to83 dkml_dir in
  let* temp_dir_83 = to83 temp_dir in
  let cmd =
    Cmd.(
      v (Fpath.to_string setup_bat)
      % "-AllowRunAsAdmin" % "-InstallationPrefix" % prefix_dir_83 % "-MSYS2Dir"
      % msys2_dir_83 % "-OpamExe" % opam_exe_83 % "-DkmlPath" % dkml_path_83
      % "-NoDeploymentSlot" % "-DkmlHostAbi"
      % Context.Abi_v2.to_canonical_string abi
      % "-TempParentPath" % temp_dir_83 % "-SkipProgress")
  in
  let cmd = if vcpkg then Cmd.(cmd % "-VcpkgCompatibility") else cmd in
  Logs.info (fun l ->
      l "Installing Git, OCaml and other tools with@ @[%a@]" Cmd.pp cmd);
  log_spawn_onerror_exit ~id:"a0d16230" cmd;
  Ok ()

let setup_res ~scripts_dir ~dkml_dir ~temp_dir ~abi ~prefix_dir ~msys2_dir
    ~opam_exe ~vcpkg =
  (* Install opam *)
  Dkml_install_api.Forward_progress.lift_result __POS__ Fmt.lines
    Dkml_install_api.Forward_progress.stderr_fatallog
  @@ Rresult.R.reword_error (Fmt.str "%a" Rresult.R.pp_msg)
  @@
  let ( let* ) = Rresult.R.bind in
  let* cygpath_opt = OS.Cmd.find_tool (Cmd.v "cygpath") in
  let* () =
    match cygpath_opt with
    | None -> Ok ()
    | Some x ->
        Rresult.R.error_msgf
          "Detected that the setup program has been called inside a Cygwin or \
           MSYS2 environment. In particular, %a was available in the PATH. \
           Since the setup program uses its own MSYS2 environment, and since \
           MSYS2 does not support one MSYS2 or Cygwin environment calling \
           another MSYS2 environment, it is highly probable the installation \
           will fail. Please rerun the setup program directly from a Command \
           Prompt, PowerShell, the File Explorer or directly from the browser \
           Downloads if you downloaded it. Do not use Git Bash (part of Git \
           for Windows) or anything else that contains an MSYS2 environment."
          Fpath.pp x
  in
  let* prefix_dir = Fpath.of_string prefix_dir in
  let* temp_dir = Fpath.of_string temp_dir in
  let* dkml_dir = Fpath.of_string dkml_dir in
  let* msys2_dir = Fpath.of_string msys2_dir in
  setup_remainder_res ~scripts_dir ~dkml_dir ~temp_dir ~abi ~prefix_dir
    ~msys2_dir ~opam_exe ~vcpkg

let setup (_ : Log_config.t) scripts_dir dkml_dir temp_dir abi prefix_dir
    msys2_dir opam_exe vcpkg =
  match
    setup_res ~scripts_dir ~dkml_dir ~temp_dir ~abi ~prefix_dir ~msys2_dir
      ~opam_exe ~vcpkg
  with
  | Completed | Continue_progress ((), _) -> ()
  | Halted_progress ec ->
      exit (Dkml_install_api.Forward_progress.Exit_code.to_int_exitcode ec)

let scripts_dir_t =
  Arg.(required & opt (some dir) None & info [ "scripts-dir" ])

let dkml_dir_t = Arg.(required & opt (some dir) None & info [ "dkml-dir" ])

let tmp_dir_t = Arg.(required & opt (some dir) None & info [ "temp-dir" ])

let prefix_dir_t =
  Arg.(required & opt (some string) None & info [ "prefix-dir" ])

let msys2_dir_t = Arg.(required & opt (some dir) None & info [ "msys2-dir" ])

let opam_exe_t =
  let u = Arg.(required & opt (some file) None & info [ "opam-exe" ]) in
  Term.(const Fpath.v $ u)

let abi_t =
  let open Context.Abi_v2 in
  let l =
    List.map (fun v -> (to_canonical_string v, v)) Context.Abi_v2.values
  in
  Arg.(required & opt (some (enum l)) None & info [ "abi" ])

let vcpkg_t = Arg.(value & flag & info [ "vcpkg" ])

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
    Term.
      ( const setup $ setup_log_t $ scripts_dir_t $ dkml_dir_t $ tmp_dir_t
        $ abi_t $ prefix_dir_t $ msys2_dir_t $ opam_exe_t $ vcpkg_t,
        info "setup-userprofile.bc"
          ~doc:
            "Install Git for Windows and Opam, compiles OCaml and install \
             several useful OCaml programs" )
  in
  Term.(exit @@ eval t)
