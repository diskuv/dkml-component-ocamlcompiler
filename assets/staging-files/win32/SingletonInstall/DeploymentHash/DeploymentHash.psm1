[CmdletBinding()]
param ()

# [Get-Sha256Hex16OfText -Text xyz] is HEX(SHA-256(xyz))[0:16]
function Get-Sha256Hex16OfText {
    param (
        $Text
    )
    $stringAsStream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.StreamWriter]::new($stringAsStream)
    $writer.write($Text)
    $writer.Flush()
    $stringAsStream.Position = 0
    (Get-FileHash -Algorithm SHA256 -InputStream $stringAsStream).Hash.Substring(0,16)
}
Export-ModuleMember -Function Get-Sha256Hex16OfText
