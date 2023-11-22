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
          % "--target-abi"
          % Context.Abi_v2.to_canonical_string ctx.Context.target_abi_v2
          % "--dkml-dir"
          % Fpath.to_string important_paths.dkmlpath
          % "--temp-dir"
          % Fpath.to_string important_paths.tmppath
          % "--scripts-dir"
          % Fpath.to_string important_paths.scriptsdir
          % "--vc-redist-exe"
          % Fpath.to_string
              (ctx.Context.path_eval "%{archive}%/vc_redist.dkml-target-abi.exe")
          %% of_list (Array.to_list (Log_config.to_args ctx.Context.log_config)))
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
         It is setup-userprofile.ps1 that downloads from the network. *)
      let component_name = "ocamlcompiler-network"

      let install_depends_on =
        [
          "staging-ocamlrun";
          "ocamlcompiler-common";
          "offline-unixutils";
          "offline-opamshim";
        ]

      let uninstall_depends_on = [ "staging-ocamlrun"; "ocamlcompiler-common" ]

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
