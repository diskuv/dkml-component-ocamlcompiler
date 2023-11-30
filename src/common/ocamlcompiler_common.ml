(** This package is a temporary home for functions that really belong in
    a standalone repository. *)

module Os = struct
  module Windows = struct
    open Bos

    let find_powershell () =
      let ( let* ) = Result.bind in
      let* pwsh_opt = OS.Cmd.find_tool Cmd.(v "pwsh") in
      match pwsh_opt with
      | Some pwsh -> Ok pwsh
      | None -> OS.Cmd.get_tool Cmd.(v "powershell")

    (**

    print_endline @@ Result.get_ok @@ get_dos83_short_path "Z:/Temp" ;;
    Z:\Temp

    print_endline @@ Result.get_ok @@ get_dos83_short_path "." ;;
    Z:\source\dkml-component-ocamlcompiler

    print_endline @@ Result.get_ok @@ get_dos83_short_path "C:\\Program Files\\Adobe" ;;
    C:\PROGRA~1\Adobe
    *)
    let get_dos83_short_path pth =
      let ( let* ) = Result.bind in
      let* cmd_exe = OS.Env.req_var "COMSPEC" in
      (* DOS variable expansion prints the short 8.3 style file name. *)
      OS.Cmd.run_out
        Cmd.(
          v cmd_exe % "/C" % "for" % "%i" % "in" % "("
          (* Fpath, as desired, prints out in Windows (long) format *)
          % Fpath.to_string pth
          % ")" % "do" % "@echo" % "%~si")
      |> OS.Cmd.to_string ~trim:true
  end
end

(* Remove the subdirectories and whitelisted files of the installation
   directory.

   * We don't uninstall the entire installation directory because on
     Windows we can't uninstall the uninstall.exe itself (while it is running).
   * We don't uninstall bin/ because other components place binaries there.
     Instead the other components should uninstall themselves.
   * We don't uninstall usr/bin/ completely but use a whitelist just in
     case some future component places binaries here.
*)
let uninstall_controldir ~control_dir =
  List.iter
    (fun reldirname ->
      let program_dir = Fpath.(control_dir // v reldirname) in
      Dkml_install_api.uninstall_directory_onerror_exit ~id:"8ae095b1"
        ~dir:program_dir ~wait_seconds_if_stuck:300.)
    [
      (* Legacy blue-green deployment slot 0 *)
      "0";
      (* Ordinary opam installed directories except bin/ *)
      "doc";
      "lib";
      "man";
      "share";
      "src";
      "tools/inotify-win";
      (* Legacy. Only present with legacy setup-userprofile.ps1 -VcpkgCompatibility *)
      "tools/ninja";
      "tools/cmake";
      (* DKML custom opam repositories *)
      "repos";
      (* The 'dkml' tools switch *)
      "dkml";
    ];
  let root_files =
    [
      "app.ico";
      "deploy-state-v1.json.bak";
      "deploy-state-v1.json.old";
      "dkmlvars.cmake";
      "dkmlvars.cmd";
      "dkmlvars.ps1";
      "dkmlvars.sh";
      "dkmlvars-v2.sexp";
      "vsstudio.cmake_generator.txt";
      "vsstudio.dir.txt";
      "vsstudio.json";
      "vsstudio.msvs_preference.txt";
      "vsstudio.vcvars_ver.txt";
      "vsstudio.winsdk.txt";
    ]
  in
  (* Native code created on-demand by [dkml init --system] and [with-dkml] *)
  let nativecode_ocaml_binaries =
    let e s = if Sys.win32 then s ^ ".exe" else s in
    [
      e "ocaml";
      e "ocamlc.byte";
      e "ocamlc";
      e "ocamlc.opt";
      e "ocamlcmt";
      e "ocamlcp.byte";
      e "ocamlcp";
      e "ocamlcp.opt";
      e "ocamldebug";
      e "ocamldep.byte";
      e "ocamldep";
      e "ocamldep.opt";
      e "ocamldoc";
      e "ocamldoc.opt";
      e "ocamllex.byte";
      e "ocamllex";
      e "ocamllex.opt";
      e "ocamlmklib.byte";
      e "ocamlmklib";
      e "ocamlmklib.opt";
      e "ocamlmktop.byte";
      e "ocamlmktop";
      e "ocamlmktop.opt";
      e "ocamlobjinfo.byte";
      e "ocamlobjinfo";
      e "ocamlobjinfo.opt";
      e "ocamlopt.byte";
      e "ocamlopt";
      e "ocamlopt.opt";
      e "ocamloptp.byte";
      e "ocamloptp";
      e "ocamloptp.opt";
      e "ocamlprof.byte";
      e "ocamlprof";
      e "ocamlprof.opt";
      e "ocamlrun";
      e "ocamlrund";
      e "ocamlruni";
      e "ocamlyacc";
      e "ocamlnat";
    ]
  in
  let nativecode_ocaml_win32_binaries =
    if Sys.win32 then
      [
        "flexdll_initer_msvc64.obj";
        "flexdll_initer_msvc.obj";
        "default_amd64.manifest";
        "default.manifest";
        "flexdll_msvc64.obj";
        "flexdll_msvc.obj";
        "flexlink.byte.exe";
        "flexlink.opt.exe";
        "flexlink.exe";
      ]
    else []
  in
  let nativecode_bin_files =
    List.map
      (fun s -> "bin/" ^ s)
      (nativecode_ocaml_binaries @ nativecode_ocaml_win32_binaries)
  in
  let files = root_files @ nativecode_bin_files in
  List.iter
    (fun relname ->
      let ( let* ) = Result.bind in
      let open Bos in
      let filenm = Fpath.(control_dir // v relname) in
      let sequence =
        let* exists = OS.File.exists filenm in
        if exists then
          (* With Windows cannot delete the file using OS.File.delete if it
             is readonly *)
          let* () = OS.Path.Mode.set filenm 0o644 in
          OS.File.delete filenm
        else Ok ()
      in
      match sequence with
      | Error msg ->
          Dkml_install_api.Forward_progress.stderr_fatallog ~id:"514cf711"
            (Fmt.str "Could not delete %a. %a" Fpath.pp filenm Rresult.R.pp_msg
               msg);
          exit
            (Dkml_install_api.Forward_progress.Exit_code.to_int_exitcode
               Exit_transient_failure)
      | Ok () -> ())
    files
