(lang dune 3.6)

(name dkml-component-ocamlcompiler)
(version 4.14.0~v2.0.1)

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
 (name dkml-component-ocamlcompiler-common)
 (synopsis "DkML common code for ocamlcompiler")
 (depends
  dkml-component-staging-dkmlconfdir
  (dkml-install                      (>= 0.2.0))
  (crunch                            (>= 3.3.1))
  (re                                (>= 1.10.0))
  (alcotest                          (and (>= 1.4.0) :with-test))))

(package
 (name dkml-component-ocamlcompiler-network)
 (synopsis "DkML network staging component for ocamlcompiler")
 (description
  "Network installed component for OCaml bytecode and native compiler")
 (depends
  (dkml-install (>= 0.2.0))
  (diskuvbox (>= 0.1.0))
  (dkml-component-ocamlcompiler-common (= :version))
  (dkml-component-offline-unixutils  (>= 0.1.0))
  (dkml-component-staging-ocamlrun   (>= 4.12.1~))
  (dkml-component-staging-dkmlconfdir     (>= 0.1.0))
  ; The hole carved to exclude ~dkml is so that we use the unmodified, compiled-from-master-branch
  ; of opam with versions that aligns both the semver (needed for winget among others) and the
  ; Debian-based opam version. [~dkml] predates the [~alpha0~20221104, etc.] adjustment.
  (dkml-component-offline-opamshim   (and (>= 2.2.0~) (or (< 2.2.0~dkml20220000) (> 2.2.0~dkml99999999))))
  (base64                            (>= 3.5.0))
  (diskuvbox                         (>= 0.1.0))
  (dkml-runtime-common               (>= 1.0.2~prerel9))
  (dkml-runtime-distribution         (>= 1.0.2~prerel9)))
 (depopts
  dkml-compiler-src
  dkml-option-vcpkg)
)

(package
 (name dkml-component-ocamlcompiler-offline)
 (synopsis "DkML offline staging component for ocamlcompiler")
 (description
  "Offline installed component for OCaml bytecode and native compiler")
 (depends
  (dkml-install (>= 0.2.0))
  (diskuvbox (>= 0.1.0))
  (dkml-component-ocamlcompiler-common (= :version))
  (dkml-component-offline-unixutils  (>= 0.1.0))
  (dkml-component-staging-ocamlrun   (>= 4.12.1~))
  (dkml-component-staging-dkmlconfdir     (>= 0.1.0))
  ; The hole carved to exclude ~dkml is so that we use the unmodified, compiled-from-master-branch
  ; of opam with versions that aligns both the semver (needed for winget among others) and the
  ; Debian-based opam version. [~dkml] predates the [~alpha0~20221104, etc.] adjustment.
  (dkml-component-offline-opamshim   (and (>= 2.2.0~) (or (< 2.2.0~dkml20220000) (> 2.2.0~dkml99999999))))
  (base64                            (>= 3.5.0))
  (diskuvbox                         (>= 0.1.0))
  (dkml-runtime-common               (>= 1.0.2~prerel9))
  (dkml-runtime-distribution         (>= 1.0.2~prerel9)))
 (depopts
  dkml-compiler-src
  dkml-option-vcpkg)
)
