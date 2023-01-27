let test_contains ~part ~target_abi ~ocaml_ver ~contains () =
  Alcotest.(check (list string))
    "list contains" [ contains ]
    (Ocamlcompiler_common.get_install_files ~part ~target_abi ~ocaml_ver
    |> List.filter (String.equal contains))

let test_not_contains ~part ~target_abi ~ocaml_ver ~contains () =
  Alcotest.(check (list string))
    "list does not contain" []
    (Ocamlcompiler_common.get_install_files ~part ~target_abi ~ocaml_ver
    |> List.filter (String.equal contains))

let () =
  let open Alcotest in
  run "ocamlcompiler_common"
    [
      (* Same tests exist in ListingParser.Tests.ps1 *)
      ( "get_install_files",
        [
          test_case "ocaml-darwin_x86_64-includes-ocamlc.opt" `Quick
            (test_contains ~part:"ocaml" ~target_abi:Darwin_x86_64
               ~ocaml_ver:"y" ~contains:"ocamlc.opt");
          test_case "ocaml-darwin_x86_64-includes-ocamlc.opt" `Quick
            (test_not_contains ~part:"ci" ~target_abi:Darwin_x86_64
               ~ocaml_ver:"y" ~contains:"ocamlc.opt");
          test_case "ocaml-windows_x86_64-includes-ocamlc.opt.exe" `Quick
            (test_contains ~part:"ocaml" ~target_abi:Windows_x86_64
               ~ocaml_ver:"y" ~contains:"ocamlc.opt.exe");
        ] );
    ]
