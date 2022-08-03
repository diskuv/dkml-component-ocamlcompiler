<#
.Synopsis
    Uninstall OCaml from programs and data folders in $env:USERPROFILE.
.Description
    Uninstalls OCaml programs.
.Parameter AuditOnly
    Use when you want to see what would happen, but don't actually perform
    the commands.
.Parameter ParentProgressId
    The PowerShell progress identifier. Optional, defaults to -1.
    Use when embedding this script within another uninstall program
    that reports its own progress.
.Parameter SkipProgress
    Do not use the progress user interface.
.Example
    PS> vendor\diskuv-ocaml\installtime\windows\uninstall-userprofile.ps1 -AuditOnly
#>

[CmdletBinding()]
param (
    [switch]
    $AuditOnly,
    [string]
    $DkmlPath,
    [int]
    $ParentProgressId = -1,
    # We will use the same standard established by C:\Users\<user>\AppData\Local\Programs\Microsoft VS Code
    [string]
    $InstallationPrefix = "$env:LOCALAPPDATA\Programs\DiskuvOCaml",
    [switch]
    $SkipProgress
)

$ErrorActionPreference = "Stop"

$HereScript = $MyInvocation.MyCommand.Path
$HereDir = (get-item $HereScript).Directory

# Match set_dkmlparenthomedir() in crossplatform-functions.sh
if ($env:LOCALAPPDATA) {
    $DkmlParentHomeDir = "$env:LOCALAPPDATA\Programs\DiskuvOCaml"
} elseif ($env:XDG_DATA_HOME) {
    $DkmlParentHomeDir = "$env:XDG_DATA_HOME/diskuv-ocaml"
} elseif ($env:HOME) {
    $DkmlParentHomeDir = "$env:HOME/.local/share/diskuv-ocaml"
}

$PSDefaultParameterValues = @{'Out-File:Encoding' = 'utf8'} # for Tee-Object. https://stackoverflow.com/a/58920518

$dsc = [System.IO.Path]::DirectorySeparatorChar
$env:PSModulePath += "$([System.IO.Path]::PathSeparator)$HereDir${dsc}SingletonInstall"
Import-Module Deployers

# Older versions of PowerShell and Windows Server use SSL 3 / TLS 1.0 while our sites
# (especially gitlab assets) may require the use of TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ----------------------------------------------------------------
# Progress declarations

$global:ProgressStep = 0
$global:ProgressActivity = $null
$ProgressTotalSteps = 3
if ($VcpkgCompatibility) {
    $ProgressTotalSteps = $ProgressTotalSteps + 2
}
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

$global:ProgressStatus = "Starting uninstall"

$FixedSlotIdx = 0
$ProgramPath = Join-Path -Path $InstallationPrefix -ChildPath $FixedSlotIdx

$ProgramRelGeneralBinDir = "usr\bin"
$ProgramGeneralBinDir = "$ProgramPath\$ProgramRelGeneralBinDir"
$ProgramRelEssentialBinDir = "bin"
$ProgramEssentialBinDir = "$ProgramPath\$ProgramRelEssentialBinDir"

# END Start uninstall
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# Enhanced Progress Reporting

$AuditLog = Join-Path -Path $InstallationPrefix -ChildPath "uninstall-userprofile-$FixedSlotIdx.full.log"
if (Test-Path -Path $AuditLog) {
    # backup the original
    Rename-Item -Path $AuditLog -NewName "uninstall-userprofile-$FixedSlotIdx.backup.$(Get-CurrentEpochMillis).log"
}

function Remove-ItemQuietly {
    param(
        [Parameter(Mandatory=$true)]
        $Path
    )
    if (Test-Path -Path $Path) {
        # Append what we will do into $AuditLog
        $Command = "Remove-Item -Force -Path `"$Path`""
        $what = "[pwsh]$ $Command"
        Add-Content -Path $AuditLog -Value "$(Get-CurrentTimestamp) $what" -Encoding UTF8

        if (!$AuditOnly) {
            Remove-Item -Force -Path $Path
        }
    }
}
function Remove-UserEnvironmentVariable {
    param(
        [Parameter(Mandatory=$true)]
        $Name
    )
    if ($null -ne [Environment]::GetEnvironmentVariable($Name)) {
        # Append what we will do into $AuditLog
        $Command = "[Environment]::SetEnvironmentVariable(`"$Name`", `"`", `"User`")"
        $what = "[pwsh]$ $Command"
        Add-Content -Path $AuditLog -Value "$(Get-CurrentTimestamp) $what" -Encoding UTF8

        if (!$AuditOnly) {
            [Environment]::SetEnvironmentVariable($Name, "", "User")
        }
    }
}
function Set-UserEnvironmentVariable {
    param(
        [Parameter(Mandatory=$true)]
        $Name,
        [Parameter(Mandatory=$true)]
        $Value
    )
    $PreviousValue = [Environment]::GetEnvironmentVariable($Name, "User")
    if ($Value -ne $PreviousValue) {
        # Append what we will do into $AuditLog
        $now = Get-CurrentTimestamp
        $Command = "# Previous entry: [Environment]::SetEnvironmentVariable(`"$Name`", `"$PreviousValue`", `"User`")"
        $what = "[pwsh]$ $Command"
        Add-Content -Path $AuditLog -Value "$now $what" -Encoding UTF8

        $Command = "[Environment]::SetEnvironmentVariable(`"$Name`", `"$Value`", `"User`")"
        $what = "[pwsh]$ $Command"
        Add-Content -Path $AuditLog -Value "$now $what" -Encoding UTF8

        if (!$AuditOnly) {
            [Environment]::SetEnvironmentVariable($Name, $Value, "User")
        }
    }
}

# From here on we need to stuff $ProgramPath with all the binaries for the distribution
# VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV

# Notes:
# * Include lots of `TestPath` existence tests to speed up incremental deployments.

$global:AdditionalDiagnostics = "`n`n"
try {

    # ----------------------------------------------------------------
    # BEGIN Modify User's environment variables

    $global:ProgressActivity = "Modify environment variables"
    Write-ProgressStep

    # DiskuvOCamlHome
    Remove-UserEnvironmentVariable -Name "DiskuvOCamlHome"

    # DiskuvOCamlVersion
    Remove-UserEnvironmentVariable -Name "DiskuvOCamlVersion"

    # -----------
    # Modify PATH
    # -----------

    $splitter = [System.IO.Path]::PathSeparator # should be ';' if we are running on Windows (yes, you can run Powershell on other operating systems)

    $userpath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $userpathentries = $userpath -split $splitter # all of the User's PATH in a collection

    $PathModified = $false

    # Remove usr\bin\ entries in the User's PATH
    if ($userpathentries -contains $ProgramGeneralBinDir) {
        # remove any old deployments
        $PossibleDirs = Get-PossibleSlotPaths -ParentPath $InstallationPrefix -SubPath $ProgramRelGeneralBinDir
        foreach ($possibleDir in $PossibleDirs) {
            $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
            $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $possibleDir)}
        }
        $PathModified = $true
    }

    # Remove bin\ entries in the User's PATH
    if ($userpathentries -contains $ProgramEssentialBinDir) {
        # remove any old deployments
        $PossibleDirs = Get-PossibleSlotPaths -ParentPath $InstallationPrefix -SubPath $ProgramRelEssentialBinDir
        foreach ($possibleDir in $PossibleDirs) {
            $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
            $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $possibleDir)}
        }
        $PathModified = $true
    }

    if ($PathModified) {
        # modify PATH
        Set-UserEnvironmentVariable -Name "PATH" -Value ($userpathentries -join $splitter)
    }

    # END Modify User's environment variables
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Uninstall deployment vars.

    $global:ProgressActivity = "Uninstall deployment variables"
    Write-ProgressStep

    Remove-ItemQuietly -Path "$DkmlParentHomeDir\dkmlvars-v2.sexp"
    Remove-ItemQuietly -Path "$DkmlParentHomeDir\dkmlvars.cmake"
    Remove-ItemQuietly -Path "$DkmlParentHomeDir\dkmlvars.cmd"
    Remove-ItemQuietly -Path "$DkmlParentHomeDir\dkmlvars.sh"
    Remove-ItemQuietly -Path "$DkmlParentHomeDir\dkmlvars.ps1"

    # END Uninstall deployment vars.
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Visual Studio Setup PowerShell Module

    $global:ProgressActivity = "Uninstall Visual Studio Setup PowerShell Module"
    Write-ProgressStep

    Remove-ItemQuietly -Path "$DkmlParentHomeDir\vsstudio.cmake_generator.txt"
    Remove-ItemQuietly -Path "$DkmlParentHomeDir\vsstudio.dir.txt"
    Remove-ItemQuietly -Path "$DkmlParentHomeDir\vsstudio.json"
    Remove-ItemQuietly -Path "$DkmlParentHomeDir\vsstudio.msvs_preference.txt"
    Remove-ItemQuietly -Path "$DkmlParentHomeDir\vsstudio.vcvars_ver.txt"
    Remove-ItemQuietly -Path "$DkmlParentHomeDir\vsstudio.winsdk.txt"

    # END Visual Studio Setup PowerShell Module
    # ----------------------------------------------------------------
}
catch {
    $ErrorActionPreference = 'Continue'
    Write-Error (
        "Uninstall did not complete because an error occurred.`n$_`n`n$($_.ScriptStackTrace)`n`n" +
        "$global:AdditionalDiagnostics`n`n" +
        "Bug Reports can be filed at https://github.com/diskuv/dkml-installer-ocaml/issues`n" +
        "Please copy the error message and attach the log file available at`n  $AuditLog`n")
    exit 1
}

if (-not $SkipProgress) {
    Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $global:ProgressActivity -Completed
    Clear-Host
}

Write-Host ""
Write-Host ""
Write-Host ""
Write-Host "Uninstallation is complete! Thanks for using Diskuv OCaml."
Write-Host ""
Write-Host ""
Write-Host ""
