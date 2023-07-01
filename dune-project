(lang dune 3.6)

(name dkml-component-network-ocamlcompiler)
(version 1.2.1~prerel10)

(generate_opam_files true)

(source
 (uri "git+https://gitlab.com/diskuv-ocaml/components/dkml-component-ocamlcompiler.git"))
(homepage "https://gitlab.com/diskuv-ocaml/components/dkml-component-ocamlcompiler")
(documentation "https://gitlab.com/diskuv-ocaml/components/dkml-component-ocamlcompiler/-/blob/main/README.md")
(bug_reports "https://gitlab.com/diskuv-ocaml/components/dkml-component-ocamlcompiler/-/issues")
(license Apache-2.0)
(authors "Diskuv, Inc. <opensource+diskuv-ocaml@support.diskuv.com>")
(maintainers "opensource+diskuv-ocaml@support.diskuv.com")

(package
 (name dkml-component-network-ocamlcompiler)
 (synopsis "DkML staging component for ocamlcompiler")
 (description
  "Network installed component for OCaml bytecode and native compiler")
 (depends
  (dkml-install (>= 0.2.0))
  (diskuvbox (>= 0.1.0))
  (dkml-component-offline-unixutils  (>= 0.1.0))
  (dkml-component-staging-ocamlrun   (>= 4.12.1~))
  (dkml-component-staging-dkmlconfdir     (>= 0.1.0))
  ; The hole carved to exclude ~dkml is so that we use the unmodified, compiled-from-master-branch
  ; of opam with versions that aligns both the semver (needed for winget among others) and the
  ; Debian-based opam version. [~dkml] predates the [~alpha0~20221104, etc.] adjustment.
  (dkml-component-offline-opamshim   (and (>= 2.2.0~) (or (< 2.2.0~dkml20220000) (> 2.2.0~dkml99999999))))
  (dkml-install                      (>= 0.2.0))
  (base64                            (>= 3.5.0))
  (diskuvbox                         (>= 0.1.0))
  (dkml-runtime-common               (>= 1.0.2~prerel9))
  (dkml-runtime-distribution         (>= 1.0.2~prerel9))
  (crunch                            (>= 3.3.1))
  (alcotest                          (and (>= 1.4.0) :with-test))
  )
 (depopts dkml-option-vcpkg))