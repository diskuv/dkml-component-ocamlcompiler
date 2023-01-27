type conf = { feature_flag_imprecise_c99_float_ops : bool [@sexp.bool] }
[@@deriving sexp]

let feature_flag_imprecise_c99_float_ops
    (cl : Staging_dkmlconfdir_api.Conf_loader.t) =
  let { feature_flag_imprecise_c99_float_ops } = conf_of_sexp cl.sexp in
  feature_flag_imprecise_c99_float_ops
