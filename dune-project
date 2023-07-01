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
  (dkml-runtime-common (>= 1.0.2~prerel9))
  (diskuvbox (>= 0.1.0))))