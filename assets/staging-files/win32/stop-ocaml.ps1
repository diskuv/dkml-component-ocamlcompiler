<#
.Synopsis
    Stop OCaml processes.
.Parameter InstallationPrefix
    The installation directory. Defaults to
    $env:LOCALAPPDATA\Programs\DiskuvOCaml on Windows. On macOS and Unix,
    defaults to $env:XDG_DATA_HOME/diskuv-ocaml if XDG_DATA_HOME defined,
    otherwise $env:HOME/.local/share/diskuv-ocaml.
.Parameter NoDeploymentSlot
    Do not use deployment slot subdirectories. Instead assume the install was
    done with -NoDeploymentSlot which directly installs into the installation
    prefix.
.Parameter ParentProgressId
    The PowerShell progress identifier. Optional, defaults to -1.
    Use when embedding this script within another uninstall program
    that reports its own progress.
.Parameter SkipProgress
    Do not use the progress user interface.
.Example
    PS> vendor\diskuv-ocaml\installtime\windows\stop-ocaml.ps1
#>

[CmdletBinding()]
param (
    [int]
    $ParentProgressId = -1,
    [string]
    $InstallationPrefix,
    [switch]
    $NoDeploymentSlot,
    [switch]
    $SkipProgress
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

$HereScript = $MyInvocation.MyCommand.Path
$HereDir = (get-item $HereScript).Directory

$PSDefaultParameterValues = @{'Out-File:Encoding' = 'utf8'} # for Tee-Object. https://stackoverflow.com/a/58920518

$dsc = [System.IO.Path]::DirectorySeparatorChar
$env:PSModulePath += "$([System.IO.Path]::PathSeparator)$HereDir${dsc}SingletonInstall"
Import-Module Deployers

# Older versions of PowerShell and Windows Server use SSL 3 / TLS 1.0 while our sites
# (especially gitlab assets) may require the use of TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ----------------------------------------------------------------
# Installation prefix

# Match set_dkmlparenthomedir() in crossplatform-functions.sh
if ($env:LOCALAPPDATA) {
    $DkmlLegacyParentHomeDir = "$env:LOCALAPPDATA\Programs\DiskuvOCaml"
} elseif ($env:XDG_DATA_HOME) {
    $DkmlLegacyParentHomeDir = "$env:XDG_DATA_HOME/diskuv-ocaml"
} elseif ($env:HOME) {
    $DkmlLegacyParentHomeDir = "$env:HOME/.local/share/diskuv-ocaml"
}
if ($env:LOCALAPPDATA) {
    $DkmlParentHomeDir = "$env:LOCALAPPDATA\Programs\DkML"
} elseif ($env:XDG_DATA_HOME) {
    $DkmlParentHomeDir = "$env:XDG_DATA_HOME/dkml"
} elseif ($env:HOME) {
    $DkmlParentHomeDir = "$env:HOME/.local/share/dkml"
}
if ($env:LOCALAPPDATA) {
    $DkmlParentNativeDir = "$env:LOCALAPPDATA\Programs\DkMLNative"
} elseif ($env:XDG_DATA_HOME) {
    $DkmlParentNativeDir = "$env:XDG_DATA_HOME/dkml-native"
} elseif ($env:HOME) {
    $DkmlParentNativeDir = "$env:HOME/.local/share/dkml-native"
}
if (-not $InstallationPrefix) {
    $InstallationPrefix = $DkmlParentHomeDir
}

# ----------------------------------------------------------------
# Progress declarations

$global:ProgressStep = 0
$global:ProgressActivity = $null
$ProgressTotalSteps = 1
$ProgressId = $ParentProgressId + 1
$global:ProgressStatus = $null

function Write-ProgressStep {
    if (-not $SkipProgress) {
        Write-Progress -Id $ProgressId `
            -ParentId $ParentProgressId `
            -Activity $global:ProgressActivity `
            -PercentComplete (100 * ($global:ProgressStep / $ProgressTotalSteps))
    } else {
        Write-Host -ForegroundColor DarkGreen "[$(1 + $global:ProgressStep) of $ProgressTotalSteps]: $(Get-CurrentTimestamp) $($global:ProgressActivity)"
    }
    $global:ProgressStep += 1
}

function Write-Error($message) {
    # https://stackoverflow.com/questions/38064704/how-can-i-display-a-naked-error-message-in-powershell-without-an-accompanying
    [Console]::ForegroundColor = 'red'
    [Console]::Error.WriteLine($message)
    [Console]::ResetColor()
}

# ----------------------------------------------------------------
# BEGIN Start uninstall

$global:ProgressStatus = "Stopping OCaml"

if ($NoDeploymentSlot) {
    $ProgramPath = $InstallationPrefix
} else {
    $FixedSlotIdx = 0
    $ProgramPath = Join-Path -Path $InstallationPrefix -ChildPath $FixedSlotIdx
}

# END Start uninstall
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# Enhanced Progress Reporting

$AuditLog = Join-Path -Path $InstallationPrefix -ChildPath "stop-ocaml.full.log"
if (Test-Path -Path $AuditLog) {
    # backup the original
    Rename-Item -Path $AuditLog -NewName "stop-ocaml.backup.$(Get-CurrentEpochMillis).log"
} elseif (!(Test-Path -Path $InstallationPrefix)) {
    # Create the installation directory because that is where the audit log
    # will go.
    #
    # Why not exit immediately if there is no installation directory?
    # Because there are non-directory resources that may need to be uninstalled
    # like Windows registry items (ex. PATH environment variable edits).
    New-Item -Path $InstallationPrefix -ItemType Directory | Out-Null
}

function Test-SubPath( [string]$directory, [string]$subpath ) {
    $dPath = [IO.Path]::GetFullPath( $directory )
    $sPath = [IO.Path]::GetFullPath( $subpath )
    return $sPath.StartsWith( $dPath, [StringComparison]::OrdinalIgnoreCase )
}

$global:AdditionalDiagnostics = "`n`n"
try {
    # ----------------------------------------------------------------
    # BEGIN Stop OCaml
    #
    # Needed because in-use executables can't be deleted/replaced on Windows.

    $global:ProgressActivity = "Stop OCaml"
    Write-ProgressStep

    # We redo this six times because VSCode plugins (esp. OCaml plugin) will restart up to five times.
    1..6 | ForEach-Object { Get-Process | Where-Object {$_.path -and (Test-SubPath "$env:LOCALAPPDATA\opam" $_.path)} | Stop-Process -Force; Start-Sleep 1 }
    1..6 | ForEach-Object { Get-Process | Where-Object {$_.path -and (Test-SubPath "$ProgramPath" $_.path)} | Stop-Process -Force; Start-Sleep 1 }
    1..6 | ForEach-Object { Get-Process | Where-Object {$_.path -and (Test-SubPath "$DkmlLegacyParentHomeDir" $_.path)} | Stop-Process -Force; Start-Sleep 1 }
    1..6 | ForEach-Object { Get-Process | Where-Object {$_.path -and (Test-SubPath "$DkmlParentNativeDir" $_.path)} | Stop-Process -Force; Start-Sleep 1 }

    # END Stop OCaml
    # ----------------------------------------------------------------

}
catch {
    $ErrorActionPreference = 'Continue'
    Write-Error (
        "Stopping OCaml did not complete because an error occurred.`n$_`n`n$($_.ScriptStackTrace)`n`n" +
        "$global:AdditionalDiagnostics`n`n" +
        "Bug Reports can be filed at https://github.com/diskuv/dkml-installer-ocaml/issues`n" +
        "Please copy the error message and attach the log file available at`n  $AuditLog`n")
    exit 1
}

if (-not $SkipProgress) {
    Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $global:ProgressActivity -Completed
}

exit 0
