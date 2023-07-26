open Dkml_install_api
open Dkml_install_register
open Bos

type important_paths = {
  tmppath : Fpath.t;
  dkmlpath : Fpath.t;
  scriptsdir : Fpath.t;
}

let get_important_paths ctx =
  let tmppath = ctx.Context.path_eval "%{tmp}%" in
  let dkmlpath =
    ctx.Context.path_eval "%{ocamlcompiler-common:share-abi}%/dkmldir"
  in
  let scriptsdir = ctx.Context.path_eval "%{ocamlcompiler-common:share-abi}%" in
  { tmppath; dkmlpath; scriptsdir }

(** [do_needs_install_admin_on_windows] defaults to [false], but if and only if
    the command ["setup-machine.ps1 -SkipAutoInstallVsBuildTools"] returns exit
    code [17] then [needs_install_admin] gives [true]. *)
let do_needs_install_admin_on_windows ~ctx =
  let check_res ~scripts_dir ~dkml_dir ~temp_dir =
    (* We can't directly call PowerShell because we probably don't have
       administrator rights ... you can't use PowerShell directly without
       the user enabling it *)
    let setup_machine_bat = Fpath.(scripts_dir / "setup-machine.bat") in
    let normalized_dkml_path = Fpath.(dkml_dir |> to_string) in
    let cmd =
      Cmd.(
        v (Fpath.to_string setup_machine_bat)
        % "-DkmlPath" % normalized_dkml_path % "-TempParentPath"
        % Fpath.to_string temp_dir % "-SkipProgress" % "-AllowRunAsAdmin"
        % "-SkipAutoInstallVsBuildTools")
    in
    Logs.info (fun l ->
        l
          "Detecting whether administrator privileges are needed by running@ \
           @[%a@]"
          Cmd.pp cmd);
    OS.Cmd.run_status cmd
  in
  let important_paths = get_important_paths ctx in
  match
    check_res ~scripts_dir:important_paths.scriptsdir
      ~dkml_dir:important_paths.dkmlpath ~temp_dir:important_paths.tmppath
  with
  (* You may be tempted to default to asking for admin privileges. Don't! *)
  | Ok (`Exited 17) ->
      Logs.info (fun l ->
          l
            "Detected that no compatible Visual Studio has been installed; \
             will request administrator privileges");
      true
  | Ok (`Exited 0) ->
      Logs.info (fun l ->
          l
            "Detected that a compatible Visual Studio was already installed; \
             will not request administrator privileges");
      false
  | Ok (`Exited ec) ->
      Logs.warn (fun l ->
          l
            "setup-machine.ps1 had non-zero exit code %d, so not asking for \
             administrator privileges"
            ec);
      false
  | Ok (`Signaled sc) ->
      Logs.warn (fun l ->
          l
            "setup-machine.ps1 terminated with signal %d, so not asking for \
             administrator privileges"
            sc);
      false
  | Error msg ->
      Logs.warn (fun l ->
          l
            "We could not find out if administrator privileges are needed, so \
             not asking for administrator privileges: %a"
            Rresult.R.pp_msg msg);
      false

(** [execute_install_admin] will install Visual Studio on Windows, and do
    nothing on any other operating system. *)
let execute_install_admin ctx =
  match Context.Abi_v2.is_windows ctx.Context.target_abi_v2 with
  | true ->
      let important_paths = get_important_paths ctx in
      let bytecode =
        ctx.Context.path_eval
          "%{ocamlcompiler-common:share-generic}%/setup_machine.bc"
      in
      let cmd =
        Cmd.(
          v (Fpath.to_string bytecode)
          % "--dkml-dir"
          % Fpath.to_string important_paths.dkmlpath
          % "--temp-dir"
          % Fpath.to_string important_paths.tmppath
          % "--scripts-dir"
          % Fpath.to_string important_paths.scriptsdir
          %% of_list (Array.to_list (Log_config.to_args ctx.Context.log_config)))
      in
      let cmd =
        if Opts.option_vcpkg_available then Cmd.(cmd % "--vcpkg") else cmd
      in
      Staging_ocamlrun_api.spawn_ocamlrun ctx cmd
  | false -> ()

let execute_install_user ctx =
  match Context.Abi_v2.is_windows ctx.Context.target_abi_v2 with
  | true ->
      let important_paths = get_important_paths ctx in
      let bytecode =
        ctx.Context.path_eval
          "%{ocamlcompiler-common:share-generic}%/setup_userprofile.bc"
      in
      let cmd =
        Cmd.(
          v (Fpath.to_string bytecode)
          % "--control-dir"
          % Fpath.to_string (ctx.Context.path_eval "%{prefix}%")
          % "--msys2-dir"
          % Fpath.to_string (ctx.Context.path_eval "%{prefix}%/tools/MSYS2")
          % "--opam-exe"
          % Fpath.to_string
              (ctx.Context.path_eval "%{prefix}%/bin/opam-real.exe")
          % "--target-abi"
          % Context.Abi_v2.to_canonical_string ctx.Context.target_abi_v2
          % "--dkml-dir"
          % Fpath.to_string important_paths.dkmlpath
          % "--temp-dir"
          % Fpath.to_string important_paths.tmppath
          % "--scripts-dir"
          % Fpath.to_string important_paths.scriptsdir
          % "--dkml-confdir-exe"
          % Fpath.to_string (Staging_dkmlconfdir_api.dkml_confdir_exe ctx)
          % "--vc-redist-exe"
          % Fpath.to_string
              (ctx.Context.path_eval "%{archive}%/vc_redist.dkml-target-abi.exe")
          %% of_list (Array.to_list (Log_config.to_args ctx.Context.log_config)))
      in
      let cmd =
        if Opts.option_vcpkg_available then Cmd.(cmd % "--vcpkg") else cmd
      in
      Staging_ocamlrun_api.spawn_ocamlrun ctx cmd
  | false -> ()

let execute_uninstall_user ctx =
  match Context.Abi_v2.is_windows ctx.Context.target_abi_v2 with
  | true ->
      let important_paths = get_important_paths ctx in
      let bytecode =
        ctx.Context.path_eval
          "%{ocamlcompiler-common:share-generic}%/uninstall_userprofile.bc"
      in
      let cmd =
        Cmd.(
          v (Fpath.to_string bytecode)
          % "--control-dir"
          % Fpath.to_string (ctx.Context.path_eval "%{prefix}%")
          % "--scripts-dir"
          % Fpath.to_string important_paths.scriptsdir
          % "--target-abi"
          % Context.Abi_v2.to_canonical_string ctx.Context.target_abi_v2
          %% of_list (Array.to_list (Log_config.to_args ctx.Context.log_config)))
      in
      Staging_ocamlrun_api.spawn_ocamlrun ctx cmd
  | false -> ()

let register () =
  let reg = Component_registry.get () in
  Component_registry.add_component reg
    (module struct
      include Default_component_config

      (* Even though this is "network" the components are "offline".
         It is the setup-machine.ps1 and setup-userprofile.ps1 that download
         from the network. *)
      let component_name = "ocamlcompiler-network"

      let install_depends_on =
        [
          "staging-ocamlrun";
          "ocamlcompiler-common";
          "offline-unixutils";
          "offline-opamshim";
        ]

      let uninstall_depends_on = [ "staging-ocamlrun"; "ocamlcompiler-common" ]

      let needs_install_admin ~ctx =
        match Context.Abi_v2.is_windows ctx.Context.target_abi_v2 with
        | true -> do_needs_install_admin_on_windows ~ctx
        | _ -> false

      let install_admin_subcommand ~component_name:_ ~subcommand_name ~fl ~ctx_t
          =
        let doc =
          "Install Visual Studio on Windows, and install nothing on other \
           operating systems"
        in
        Dkml_install_api.Forward_progress.Continue_progress
          ( Cmdliner.Cmd.v
              (Cmdliner.Cmd.info subcommand_name ~doc)
              Cmdliner.Term.(const execute_install_admin $ ctx_t),
            fl )

      let install_user_subcommand ~component_name:_ ~subcommand_name ~fl ~ctx_t
          =
        let doc =
          "Install the OCaml compiler on Windows and install nothing on other \
           operating systems"
        in
        Dkml_install_api.Forward_progress.Continue_progress
          ( Cmdliner.Cmd.v
              (Cmdliner.Cmd.info subcommand_name ~doc)
              Cmdliner.Term.(const execute_install_user $ ctx_t),
            fl )

      let uninstall_user_subcommand ~component_name:_ ~subcommand_name ~fl
          ~ctx_t =
        let doc =
          "Uninstall the OCaml compiler on Windows, and uninstall nothing on \
           other operating systems"
        in
        Dkml_install_api.Forward_progress.Continue_progress
          ( Cmdliner.Cmd.v
              (Cmdliner.Cmd.info subcommand_name ~doc)
              Cmdliner.Term.(const execute_uninstall_user $ ctx_t),
            fl )
    end)
