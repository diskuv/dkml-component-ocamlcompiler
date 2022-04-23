open Bos
open Cmdliner
open Dkml_install_api

(* Copy the 32-bit and 64-bit Opam binaries (whichever is available, with preference to
   the 64-bit binaries) to a temporary directory. It would be nice if we could
   directly install into the installation prefix, but the legacy PowerShell scripts
   will delete the contents of the installation prefix. *)
let setup_opam_res ~temp_dir ~opam32_bindir_opt ~opam64_bindir_opt =
  let open Diskuvbox in
  let dst = Fpath.(temp_dir / "opam") in
  let copy_if_exists dir_opt =
    match dir_opt with
    | Some src -> (
        match OS.Dir.exists src with
        | Ok true -> copy_dir ~src ~dst ()
        | Ok false -> Result.ok ()
        | Error v -> Result.error (Fmt.str "%a" Rresult.R.pp_msg v))
    | None -> Result.ok ()
  in
  Rresult.R.error_to_msg ~pp_error:Fmt.string
    (let ( let* ) = Result.bind in
     let* () = copy_if_exists opam32_bindir_opt in
     let* () = copy_if_exists opam64_bindir_opt in
     Result.ok dst)

(* Call the PowerShell (legacy!) setup-userprofile.ps1 script *)
let setup_remainder_res ~scripts_dir ~dkml_dir ~temp_dir ~abi ~prefix_dir
    ~msys2_dir ~opam_dir =
  (* We cannot directly call PowerShell because we likely do not have
     administrator rights *)
  let setup_bat = Fpath.(v scripts_dir / "setup-userprofile.bat") in
  let normalized_dkml_path = Fpath.(dkml_dir |> to_string) in
  let cmd =
    Cmd.(
      v (Fpath.to_string setup_bat)
      % "-AllowRunAsAdmin" % "-InstallationPrefix" % Fpath.to_string prefix_dir
      % "-MSYS2Dir" % Fpath.to_string msys2_dir % "-OpamBinDir"
      % Fpath.to_string opam_dir % "-DkmlPath" % normalized_dkml_path
      % "-DkmlHostAbi"
      % Context.Abi_v2.to_canonical_string abi
      % "-TempParentPath" % Fpath.to_string temp_dir % "-SkipProgress")
  in
  Logs.info (fun l ->
      l "Installing Git, OCaml and other tools with@ @[%a@]" Cmd.pp cmd);
  Result.ok (log_spawn_and_raise cmd)

let setup_res ~scripts_dir ~dkml_dir ~temp_dir ~abi ~prefix_dir ~msys2_dir
    ~opam32_bindir_opt ~opam64_bindir_opt =
  (* Install opam *)
  let ( let* ) = Rresult.R.bind in
  let* prefix_dir = Fpath.of_string prefix_dir in
  let* temp_dir = Fpath.of_string temp_dir in
  let* dkml_dir = Fpath.of_string dkml_dir in
  let* msys2_dir = Fpath.of_string msys2_dir in
  let* opam_dir =
    setup_opam_res ~temp_dir ~opam32_bindir_opt ~opam64_bindir_opt
  in
  setup_remainder_res ~scripts_dir ~dkml_dir ~temp_dir ~abi ~prefix_dir
    ~msys2_dir ~opam_dir

let setup (_ : Log_config.t) scripts_dir dkml_dir temp_dir abi prefix_dir
    msys2_dir opam32_bindir_opt opam64_bindir_opt =
  match
    setup_res ~scripts_dir ~dkml_dir ~temp_dir ~abi ~prefix_dir ~msys2_dir
      ~opam32_bindir_opt ~opam64_bindir_opt
  with
  | Ok () -> ()
  | Error msg -> Logs.err (fun l -> l "%a" Rresult.R.pp_msg msg)

let scripts_dir_t =
  Arg.(required & opt (some dir) None & info [ "scripts-dir" ])

let dkml_dir_t = Arg.(required & opt (some dir) None & info [ "dkml-dir" ])

let tmp_dir_t = Arg.(required & opt (some dir) None & info [ "temp-dir" ])

let prefix_dir_t =
  Arg.(required & opt (some string) None & info [ "prefix-dir" ])

let msys2_dir_t = Arg.(required & opt (some dir) None & info [ "msys2-dir" ])

let opam32_bindir_opt_t =
  let v = Arg.(value & opt (some string) None & info [ "opam32-bindir" ]) in
  let u = function None -> None | Some x -> Some (Fpath.v x) in
  Term.(const u $ v)

let opam64_bindir_opt_t =
  let v = Arg.(value & opt (some string) None & info [ "opam64-bindir" ]) in
  let u = function None -> None | Some x -> Some (Fpath.v x) in
  Term.(const u $ v)

let abi_t =
  let open Context.Abi_v2 in
  let l =
    List.map (fun v -> (to_canonical_string v, v)) Context.Abi_v2.values
  in
  Arg.(required & opt (some (enum l)) None & info [ "abi" ])

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
        $ abi_t $ prefix_dir_t $ msys2_dir_t $ opam32_bindir_opt_t
        $ opam64_bindir_opt_t,
        info "setup-userprofile.bc"
          ~doc:
            "Install Git for Windows and Opam, compiles OCaml and install \
             several useful OCaml programs" )
  in
  Term.(exit @@ eval t)
