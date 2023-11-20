# enduser-ocamlcompiler

The ocamlcompiler component installs an OCaml compiler in the end-user
installation directory.

These are components that can be used with [dkml-install-api](https://diskuv.github.io/dkml-install-api/index.html)
to generate installers.

## Testing Locally

FIRST, make sure any changes are committed with `git commit`.

SECOND,

On Windows, assuming you already have installed a DKML distribution, run:

```powershell
# Use an Opam install which will download supporting files
opam install ./dkml-component-network-ocamlcompiler.opam
opam pin dkml-component-staging-desktop-full git+https://gitlab.com/dkml/components/dkml-component-desktop.git --yes
opam pin dkml-component-staging-withdkml git+https://gitlab.com/dkml/components/dkml-component-desktop.git --yes

# Set vars we will use below
$ocshare = opam var dkml-component-network-ocamlcompiler:share
$op32share = opam var dkml-component-staging-opam32:share
$op64share = opam var dkml-component-staging-opam64:share
$fullshare = opam var dkml-component-staging-desktop-full:share
$withdkmlshare = opam var dkml-component-staging-withdkml:share
$confshare = opam var dkml-component-staging-dkmlconfdir:share
& $env:DiskuvOCamlHome\dkmlvars.ps1

# Print Help
& "$ocshare/staging-files/generic/setup_machine.bc.exe" --help
& "$ocshare/staging-files/generic/setup_userprofile.bc.exe" --help

# Same help if you build directly
dune build
& "_build\default\src\installtime\setup-userprofile\setup_userprofile.exe" --help

# After opam install we mimic the placing of binaries that
# dkml-component-offline-desktop-full does

with-dkml install -d "$env:TEMP\ocamlcompiler-t" "$env:TEMP\ocamlcompiler-up"
opam exec -- diskuvbox copy-dir `
    "$withdkmlshare\staging-files\windows_x86_64" `
    "$fullshare\staging-files\windows_x86_64" `
    "$env:TEMP\ocamlcompiler-up"
opam exec -- diskuvbox copy-file `
    "$fullshare\staging-files\windows_x86_64\bin\dkml-fswatch.exe" `
    "$env:TEMP\ocamlcompiler-up\tools\fswatch\fswatch.exe"

# After opam install that you can run either of them properly ...

opam exec -- dune build src/installtime/setup-userprofile/setup_userprofile.exe
_build/default/src/installtime/setup-userprofile/setup_userprofile.exe `
    --scripts-dir=assets\staging-files\win32 `
    --dkml-confdir-exe="$confshare\staging-files\windows_x86_64\bin\dkml-confdir.exe" `
    --control-dir="$env:TEMP\ocamlcompiler-up" `
    --temp-dir="$env:TEMP\ocamlcompiler-t" `
    --dkml-dir "$ocshare\staging-files\windows_x86_64\dkmldir" `
    --target-abi windows_x86_64 `
    --msys2-dir "$env:DiskuvOCamlMSYS2Dir" `
    --opam-exe "$op64share\staging-files\windows_x86_64\bin\opam.exe" `
    -v -v

opam exec -- dune build src/installtime/uninstall-userprofile/uninstall_userprofile.exe
_build/default/src/installtime/uninstall-userprofile/uninstall_userprofile.exe `
    --audit-only `
    --target-abi windows_x86_64 `
    --scripts-dir=assets/staging-files/win32 `
    --control-dir="$env:TEMP\ocamlcompiler-up" `
    -v -v
```

## Contributing

See [the Contributors section of dkml-install-api](https://github.com/diskuv/dkml-install-api/blob/main/contributors/README.md).

## Status

[![Syntax check](https://github.com/diskuv/dkml-component-ocamlcompiler/actions/workflows/syntax.yml/badge.svg)](https://github.com/diskuv/dkml-component-ocamlcompiler/actions/workflows/syntax.yml)
