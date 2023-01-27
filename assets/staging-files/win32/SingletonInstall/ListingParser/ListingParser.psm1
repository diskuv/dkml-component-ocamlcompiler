function Test-InstallationBinary {
    param (
        [Parameter(Mandatory)]
        $Line,
        $Abi = "any",
        $OCamlVer = "any"
    )
    $Terms = $Line -split "`t"
    if ($Terms.Length -ne 3) {
        throw "The installation binary line must have three terms"
    }
    else {
        if ($Abi -notmatch "^$($Terms[1])`$") {
            ""
        }
        elseif ($OCamlVer -notmatch "^$($Terms[2])`$") {
            ""
        }
        else {
            $Terms[0]
        }
    }
}
Export-ModuleMember -Function Test-InstallationBinary

function Get-InstallationBinaries {
    param (
        [Parameter(Mandatory)]
        $ListingPath,
        [Parameter(Mandatory)]
        $Part,
        [Parameter(Mandatory)]
        $Abi,
        [Parameter(Mandatory)]
        $OCamlVer
    )
    if ($Abi -match "^windows_") {
        $exeExt = ".exe"
    } else {
        $exeExt = ""
    }
    $results = @()
    Get-Content (Join-Path $ListingPath -ChildPath "$Part.install") | ForEach-Object {
        if($_ -and ($_ -notmatch "^#")){
            # Not a comment line. Parse it
            $binary = Test-InstallationBinary -Line $_ -Abi $Abi -OCamlVer $OCamlVer
            if ($binary) {
                $results += "$binary$exeExt"
            }
        }
    }
    $results
}
Export-ModuleMember -Function Get-InstallationBinaries