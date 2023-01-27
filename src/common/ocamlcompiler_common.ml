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

let ocaml_ver = "4.14.0"

let get_exe_ext target_abi =
  if Dkml_install_api.Context.Abi_v2.is_windows target_abi then ".exe" else ""

let get_install_files ~part ~target_abi ~ocaml_ver =
  match Installation_files.read (part ^ ".install") with
  | None ->
      raise
        (Invalid_argument
           (Printf.sprintf "The installation files did not have %s.install" part))
  | Some contents ->
      let open Astring in
      let target_abi_string =
        Dkml_install_api.Context.Abi_v2.to_canonical_string target_abi
      in
      let lines = String.cuts ~sep:"\n" contents in
      let lines_lf =
        (* Remove CR from line endings (and incidentally beginnings) if
           present *)
        List.map
          (fun line ->
            String.trim ~drop:(function '\r' -> true | _ -> false) line)
          lines
      in
      let lines_non_empty =
        (* Remove empty lines *)
        List.filter (fun line -> String.length line > 0) lines_lf
      in
      let lines_no_comments =
        (* Remove lines that start with # *)
        List.filter
          (fun line -> not (String.is_prefix ~affix:"#" line))
          lines_non_empty
      in
      let list_of_tuples =
        (* Convert lines into (binary, abi regex, version regex) *)
        List.map
          (fun line ->
            match String.cuts ~sep:"\t" line with
            | [ binary; abi_regex; version_regex ] ->
                ( binary,
                  Re.Posix.compile_pat ("^" ^ abi_regex ^ "$"),
                  Re.Posix.compile_pat ("^" ^ version_regex ^ "$") )
            | _ ->
                raise
                  (Invalid_argument
                     (Printf.sprintf "Invalid .install line: %s" line)))
          lines_no_comments
      in
      let exe_ext = get_exe_ext target_abi in
      let matching_binaries =
        List.filter_map
          (fun (binary, abi_regex, version_regex) ->
            match
              ( Re.execp abi_regex target_abi_string,
                Re.execp version_regex ocaml_ver )
            with
            | true, true -> Some (binary ^ exe_ext)
            | _ -> None)
          list_of_tuples
      in
      matching_binaries

(* Remove the subdirectories and whitelisted files of the installation
   directory.

   * We don't uninstall the entire installation directory because on
     Windows we can't uninstall the uninstall.exe itself (while it is running).
   * We don't uninstall bin/ because other components place binaries there.
     Instead the other components should uninstall themselves.
   * We don't uninstall usr/bin/ completely but use a whitelist just in
     case some future component places binaries here.
*)
let uninstall_controldir ~control_dir ~target_abi =
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
      (* Only present with setup-userprofile.ps1 -VcpkgCompatibility *)
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
  let ocaml_files = get_install_files ~part:"ocaml" ~target_abi ~ocaml_ver in
  let full_files = get_install_files ~part:"full" ~target_abi ~ocaml_ver in
  let usr_bin_files =
    List.map (fun s -> "usr/bin/" ^ s) (ocaml_files @ full_files)
  in
  let files = root_files @ usr_bin_files in
  List.iter
    (fun relname ->
      let filenm = Fpath.(control_dir // v relname) in
      match Bos.OS.File.delete filenm with
      | Error msg ->
          Logs.warn (fun l ->
              l "Could not delete %a. %a" Fpath.pp filenm Rresult.R.pp_msg msg)
      | Ok () -> ())
    files
