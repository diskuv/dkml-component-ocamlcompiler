# Upgrade Pester to be >= 4.6.0 using Administrator PowerShell:
#   Install-Module -Name Pester -Force -SkipPublisherCheck

# In VSCode just click "Run tests" below

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
     Justification='BeforeAll {} variables are visible in Describe {}',
     Target="ListingPath")]
[CmdletBinding()]
param()

BeforeAll { 
    $dsc = [System.IO.Path]::DirectorySeparatorChar
    if (Get-Module ListingParser) {
        Write-Host "Removing old ListingParser module from PowerShell session"
        Remove-Module ListingParser
    }
    $env:PSModulePath += "$([System.IO.Path]::PathSeparator)${PSCommandPath}${dsc}.."
    Import-Module ListingParser

    $ListingPath = Join-Path $PSScriptRoot -ChildPath "../files"
}

Describe 'Test-InstallationBinary -Line' {
    
    It 'Given [flexlink    windows_.*  .*] when -Abi=darwin_x86_64 then fails' {
        Test-InstallationBinary -Line "flexlink`twindows_.*`t.*" -Abi "darwin_x86_64" | Should -BeNullOrEmpty
    }
    It 'Given [flexlink    windows_.*  .*] when -Abi=windows_x86_64 then passes' {
        Test-InstallationBinary -Line "flexlink`twindows_.*`t.*" -Abi "windows_x86_64" | Should -Be "flexlink"
    }
    It 'Given [ocamlnat    .*  4[.]14[.].*|5[.].*] when -OCamlVer=4.12.1 then fails' {
        Test-InstallationBinary -Line "ocamlnat`t.*`t4[.]14[.].*|5[.].*" -OCamlVer "4.12.1" | Should -BeNullOrEmpty
    }
    It 'Given [ocamlnat    .*  4[.]14[.].*|5[.].*] when -OCamlVer=4.14.0 then passes' {
        Test-InstallationBinary -Line "ocamlnat`t.*`t4[.]14[.].*|5[.].*" -OCamlVer "4.14.0" | Should -Be "ocamlnat"
    }
    It 'Given [ocamlnat    .*  4[.]14[.].*|5[.].*] when -OCamlVer=5.0.0 then passes' {
        Test-InstallationBinary -Line "ocamlnat`t.*`t4[.]14[.].*|5[.].*" -OCamlVer "5.0.0" | Should -Be "ocamlnat"
    }
}

Describe 'Get-InstallationBinaries' {
    It 'Given -Part ocaml when -Abi darwin_x86_64 then includes ocamlc.opt' {
        Get-InstallationBinaries -Part ocaml -ListingPath $ListingPath -Abi "darwin_x86_64" -OCamlVer "y" | Should -Contain "ocamlc.opt"
    }
    It 'Given -Part ci when -Abi darwin_x86_64 then not includes ocamlc.opt' {
        Get-InstallationBinaries -Part ci -ListingPath $ListingPath -Abi "darwin_x86_64" -OCamlVer "y" | Should -Not -Contain "ocamlc.opt"
    }
    It 'Given -Part ocaml when -Abi windows_x86_64 then includes ocamlc.opt.exe' {
        Get-InstallationBinaries -Part ocaml -ListingPath $ListingPath -Abi "windows_x86_64" -OCamlVer "y" | Should -Contain "ocamlc.opt.exe"
    }
}