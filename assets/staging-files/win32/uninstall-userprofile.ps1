<#
.Synopsis
    Uninstalls OCaml.
.Description
    Uninstall OCaml from the installation directory, and removes
    the installation from the User's PATH environment variable,
    and removes the DiskuvOCaml* environment variables.
.Parameter InstallationPrefix
    The installation directory. Defaults to
    $env:LOCALAPPDATA\Programs\DiskuvOCaml on Windows. On macOS and Unix,
    defaults to $env:XDG_DATA_HOME/diskuv-ocaml if XDG_DATA_HOME defined,
    otherwise $env:HOME/.local/share/diskuv-ocaml.
.Parameter NoDeploymentSlot
    Do not use deployment slot subdirectories. Instead assume the install was
    done with -NoDeploymentSlot which directly installs into the installation
    prefix.
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
$ProgressTotalSteps = 6
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

if ($NoDeploymentSlot) {
    $ProgramPath = $InstallationPrefix
} else {
    $FixedSlotIdx = 0
    $ProgramPath = Join-Path -Path $InstallationPrefix -ChildPath $FixedSlotIdx
}

$ProgramRelGeneralBinDir = "usr\bin"
$ProgramGeneralBinDir = "$ProgramPath\$ProgramRelGeneralBinDir"
$ProgramRelEssentialBinDir = "bin"
$ProgramEssentialBinDir = "$ProgramPath\$ProgramRelEssentialBinDir"

# END Start uninstall
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# Enhanced Progress Reporting

$AuditLog = Join-Path -Path $InstallationPrefix -ChildPath "uninstall-userprofile.full.log"
if (Test-Path -Path $AuditLog) {
    # backup the original
    Rename-Item -Path $AuditLog -NewName "uninstall-userprofile.backup.$(Get-CurrentEpochMillis).log"
} elseif (!(Test-Path -Path $InstallationPrefix)) {
    # Create the installation directory because that is where the audit log
    # will go.
    #
    # Why not exit immediately if there is no installation directory?
    # Because there are non-directory resources that may need to be uninstalled
    # like Windows registry items (ex. PATH environment variable edits).
    New-Item -Path $InstallationPrefix -ItemType Directory | Out-Null
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
            Remove-Item -Force -Recurse -Path $Path
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
    1..6 | % { Get-Process | ?{$_.path -and (Test-SubPath "$env:LOCALAPPDATA\opam" $_.path)} | Stop-Process -Force; Start-Sleep 1 }
    1..6 | % { Get-Process | ?{$_.path -and (Test-SubPath "$ProgramPath" $_.path)} | Stop-Process -Force; Start-Sleep 1 }
    1..6 | % { Get-Process | ?{$_.path -and (Test-SubPath "$DkmlLegacyParentHomeDir" $_.path)} | Stop-Process -Force; Start-Sleep 1 }
    1..6 | % { Get-Process | ?{$_.path -and (Test-SubPath "$DkmlParentNativeDir" $_.path)} | Stop-Process -Force; Start-Sleep 1 }

    # END Stop OCaml
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Remove playground switch

    $global:ProgressActivity = "Remove playground switch"
    Write-ProgressStep

    Remove-ItemQuietly -Path "$env:LOCALAPPDATA\opam\playground"

    # END Remove playground switch
    # ----------------------------------------------------------------

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

    # Remove usr\bin\ entries in the User's PATH
    $userpathentries = $userpathentries | Where-Object {$_ -ne $ProgramGeneralBinDir}
    $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $ProgramGeneralBinDir)}
    $PossibleDirs = Get-PossibleSlotPaths -ParentPath $InstallationPrefix -SubPath $ProgramRelGeneralBinDir
    foreach ($possibleDir in $PossibleDirs) {
        $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
        $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $possibleDir)}
    }
    $PossibleDirs = Get-PossibleSlotPaths -ParentPath $DkmlParentHomeDir -SubPath $ProgramRelGeneralBinDir
    foreach ($possibleDir in $PossibleDirs) {
        $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
        $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $possibleDir)}
    }
    $PossibleDirs = Get-PossibleSlotPaths -ParentPath $DkmlLegacyParentHomeDir -SubPath $ProgramRelGeneralBinDir
    foreach ($possibleDir in $PossibleDirs) {
        $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
        $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $possibleDir)}
    }

    # Remove bin\ entries in the User's PATH
    $userpathentries = $userpathentries | Where-Object {$_ -ne $ProgramEssentialBinDir}
    $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $ProgramEssentialBinDir)}
    $PossibleDirs = Get-PossibleSlotPaths -ParentPath $InstallationPrefix -SubPath $ProgramRelEssentialBinDir
    foreach ($possibleDir in $PossibleDirs) {
        $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
        $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $possibleDir)}
    }
    $PossibleDirs = Get-PossibleSlotPaths -ParentPath $DkmlParentHomeDir -SubPath $ProgramRelEssentialBinDir
    foreach ($possibleDir in $PossibleDirs) {
        $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
        $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $possibleDir)}
    }
    $PossibleDirs = Get-PossibleSlotPaths -ParentPath $DkmlLegacyParentHomeDir -SubPath $ProgramRelEssentialBinDir
    foreach ($possibleDir in $PossibleDirs) {
        $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
        $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $possibleDir)}
    }

    # modify PATH
    Set-UserEnvironmentVariable -Name "PATH" -Value ($userpathentries -join $splitter)

    # END Modify User's environment variables
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Remove legacy DiskuvOCaml

    $global:ProgressActivity = "Remove legacy DiskuvOCaml"
    Write-ProgressStep

    Remove-ItemQuietly -Path "$DkmlLegacyParentHomeDir"

    # END Remove legacy DiskuvOCaml
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

    Remove-ItemQuietly -Path "$DkmlParentHomeDir\deploy-state-v1.json"

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

Write-Information ""
Write-Information ""
Write-Information ""
Write-Information "Thanks for using DkML!"
Write-Information ""
Write-Information ""
Write-Information ""
