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
with-dkml opam install ./dkml-component-network-ocamlcompiler.opam

# Set vars we will use below
$ocshare = opam var dkml-component-network-ocamlcompiler:share
$op32share = opam var dkml-component-staging-opam32:share
$op64share = opam var dkml-component-staging-opam64:share
& $env:DiskuvOCamlHome\..\dkmlvars.ps1

# Print Help
& "$ocshare/staging-files/generic/setup_machine.bc.exe"
& "$ocshare/staging-files/generic/setup_userprofile.bc.exe"

# Same help if you build directly
with-dkml dune build
& "_build\default\src\installtime\setup-machine\setup_machine.exe"
& "_build\default\src\installtime\setup-userprofile\setup_userprofile.exe"

# After opam install that you can run either of them properly ...

with-dkml install -d "$env:TEMP\ocamlcompiler-t"

with-dkml dune exec -- src/installtime/setup-machine/setup_machine.exe `
    --scripts-dir assets/staging-files/win32 `
    --temp-dir "$env:TEMP\ocamlcompiler-t" `
    --dkml-dir "$ocshare\staging-files\windows_x86_64\dkmldir" `
    -v -v

with-dkml dune exec -- src/installtime/setup-userprofile/setup_userprofile.exe `
    --scripts-dir=assets\staging-files\win32 `
    --prefix-dir="$env:TEMP\ocamlcompiler-up" `
    --temp-dir="$env:TEMP\ocamlcompiler-t" `
    --dkml-dir "$ocshare\staging-files\windows_x86_64\dkmldir" `
    --abi windows_x86_64 `
    --msys2-dir "$env:DiskuvOCamlMSYS2Dir" `
    --opam64-bindir "$op64share\staging-files\windows_x86_64\bin" `
    -v -v

with-dkml dune exec -- src/installtime/uninstall-userprofile/uninstall_userprofile.exe `
    --audit-only `
    --scripts-dir=assets/staging-files/win32 `
    --prefix-dir="$env:TEMP\ocamlcompiler-up" -v -v    
```

For Unix operating systems, including macOS, run:

```bash
# Use an Opam install which include supporting files
opam install ./dkml-component-network-ocamlcompiler.opam
"$(opam var dkml-component-network-ocamlcompiler:share)"/staging-files/generic/install.bc.exe

# Directly run without any supporting files
dune exec -- src/installtime/setup-machine/setup_machine.exe \
    --scripts-dir assets/staging-files/win32 \
    --temp-dir /tmp/ocamlcompiler \
    --dkml-dir {specify a DKML directory containing .dkmlroot}
```

## Contributing

See [the Contributors section of dkml-install-api](https://github.com/diskuv/dkml-install-api/blob/main/contributors/README.md).

## Status

[![Syntax check](https://github.com/diskuv/dkml-component-ocamlcompiler/actions/workflows/syntax.yml/badge.svg)](https://github.com/diskuv/dkml-component-ocamlcompiler/actions/workflows/syntax.yml)
