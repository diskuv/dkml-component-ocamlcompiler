open Staging_dkmlconfdir_api.Conf_loader
open Model_conf

let sexp s = Sexplib.Sexp.of_string s

let test_empty () =
  Alcotest.(check bool)
    "same bools" false
    (feature_flag_imprecise_c99_float_ops (create_from_sexp (sexp "()")))

let test_feature_flag_imprecise_c99_float_ops () =
  Alcotest.(check bool)
    "same bools" true
    (feature_flag_imprecise_c99_float_ops
       (create_from_sexp (sexp {|((feature_flag_imprecise_c99_float_ops))|})))

let () =
  let open Alcotest in
  run "model_conf"
    [
      ( "feature_flag_imprecise_c99_float_ops",
        [
          test_case "empty" `Quick test_empty;
          test_case "on" `Quick test_feature_flag_imprecise_c99_float_ops;
        ] );
    ]
