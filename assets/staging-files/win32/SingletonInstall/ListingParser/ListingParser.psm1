function Test-InstallationBinary {
    param (
        [Parameter(Mandatory)]
        $Line,
        $Abi = "any",
        $OCamlVer = "any"
    )
    $Terms = $Line -split "`t"
    if ($Terms.Length -ne 5) {
        $LinePipes = $Terms -join "|"
        throw "The installation binary line must have five terms, not: $LinePipes"
    }
    else {
        # Which extension do we use?
        if ($Abi -match "^windows_") {
            $Ext = $Terms[1]
        }
        else {
            $Ext = $Terms[2]
        }
        # Do checks on regex conditions
        if ($Abi -notmatch "^$($Terms[3])`$") {
            ""
        }
        elseif ($OCamlVer -notmatch "^$($Terms[4])`$") {
            ""
        }
        else {
            $Terms[0] + $Ext
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
    $results = @()
    Get-Content (Join-Path $ListingPath -ChildPath "$Part.install") | ForEach-Object {
        if($_ -and ($_ -notmatch "^#")){
            # Not a comment line. Parse it
            $binary = Test-InstallationBinary -Line $_ -Abi $Abi -OCamlVer $OCamlVer
            if ($binary) {
                $results += "$binary"
            }
        }
    }
    $results
}
Export-ModuleMember -Function Get-InstallationBinaries