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
   directory. We don't uninstall the entire installation directory because on
   Windows we can't uninstall the uninstall.exe itself (while it is running). *)
let uninstall_controldir ~control_dir =
  List.iter
    (fun i ->
      let program_dir = Fpath.(control_dir / i) in
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
    ];
  List.iter
    (fun basenm ->
      let filenm = Fpath.(control_dir / basenm) in
      match Bos.OS.File.delete filenm with
      | Error msg ->
          Logs.warn (fun l ->
              l "Could not delete %a. %a" Fpath.pp filenm Rresult.R.pp_msg msg)
      | Ok () -> ())
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