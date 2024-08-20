<#
.Synopsis
    Install DkML configuration profile and optionally MSYS2.
.Description
    Install DkML configuration profile and optionally MSYS2. It also modifies PATH
    and sets DiskuvOCaml* environment variables.

    Interactive Terminals
    ---------------------

    If you are running from within a continuous integration (CI) scenario you may
    encounter `Exception setting "CursorPosition"`. That means a command designed
    for user interaction was run in this script; use -SkipProgress to disable
    the need for an interactive terminal.

    MSYS2
    -----

    After the script completes, you can launch MSYS2 directly with:

    & $env:DiskuvOCamlHome\tools\MSYS2\msys2_shell.cmd
.Parameter InstallationPrefix
    The installation directory. Defaults to
    $env:LOCALAPPDATA\Programs\DkML on Windows. On macOS and Unix,
    defaults to $env:XDG_DATA_HOME/dkml if XDG_DATA_HOME defined,
    otherwise $env:HOME/.local/share/dkml.

    If this parameter is set, the DkML variables files (ex. dkmlvars-v2.sexp)
    will still be placed in the default installation directory so that
    programs like with-dkml.exe can locate the custom installation
    directory.
.Parameter Flavor
    Which type of installation to perform.

    The `CI` flavor:
    * Does not modify the User environment variables.
    * Does not do a system upgrade of MSYS2

    Choose the `CI` flavor if you have continuous integration tests.
.Parameter Offline
    Setup the OCaml system in offline mode. Will not install MSYS2.
.Parameter MSYS2Dir
    The MSYS2 installation directory. MSYS2Dir is required when not Offline
    but on a Win32 machine.
.Parameter DkmlHostAbi
    Install a `windows_x86` or `windows_x86_64` distribution.

    Defaults to windows_x86_64 if the machine is 64-bit, otherwise windows_x86.
.Parameter DkmlPath
    The directory containing .dkmlroot
.Parameter TempParentPath
    Temporary directory. A subdirectory will be created within -TempParentPath.
    Defaults to $env:temp\diskuvocaml\setupuserprofile
.Parameter ParentProgressId
    The PowerShell progress identifier. Optional, defaults to -1.
    Use when embedding this script within another setup program
    that reports its own progress.
.Parameter AllowRunAsAdmin
    When specified you will be allowed to run this script using
    Run as Administrator.
    We do not recommend you do this unless you are in continuous
    integration (CI) scenarios.
.Parameter SkipProgress
    Do not use the progress user interface.
.Parameter SkipMSYS2Update
    Do not update MSYS2 system or packages.
.Parameter OnlyOutputCacheKey
    Only output the userprofile cache key. The cache key is 1-to-1 with
    the version of the Diskuv OCaml distribution.
.Parameter NoDeploymentSlot
    Do not use deployment slot subdirectories. Instead the install will
    go directly into the installation prefix. Useful in CI situations
.Parameter IncrementalDeployment
    Advanced.

    Tries to continue from where the last deployment finished. Never continues
    when the version number that was last deployed differs from the version
    number of the current installation script.
.Parameter AuditOnly
    Advanced.

    When specified the PATH and any other environment variables are not set.
    The installation prefix is still removed or modified (depending on
    -IncrementalDeployment), so this is best
    used in combination with a unique -InstallationPrefix.
.Example
    PS> vendor\diskuv-ocaml\installtime\windows\setup-userprofile.ps1

.Example
    PS> $global:SkipMSYS2Setup = $true ; $global:SkipMobyDownload = $true ; $global:SkipMobyFixup = $true ; $global:SkipOpamSetup = $true; $global:SkipOcamlSetup = $true
    PS> vendor\diskuv-ocaml\installtime\windows\setup-userprofile.ps1
#>

# [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
#     Justification='Conditional block based on Windows 32 vs 64-bit',
#     Target="CygwinPackagesArch")]
[CmdletBinding()]
param (
    [ValidateSet("Dune", "CI", "Full")]
    [string]
    $Flavor = 'Full',
    [ValidateSet("windows_x86", "windows_x86_64")]
    [string]
    $DkmlHostAbi,
    [string]
    $MSYS2Dir,
    [string]
    $DkmlPath,
    [string]
    $TempParentPath,
    [int]
    $ParentProgressId = -1,
    [string]
    $InstallationPrefix,
    [switch]
    $AllowRunAsAdmin,
    [switch]
    $Offline,
    [switch]
    $SkipProgress,
    [switch]
    $SkipMSYS2Update,
    [switch]
    $OnlyOutputCacheKey,
    [switch]
    $NoDeploymentSlot,
    [switch]
    $IncrementalDeployment,
    [switch]
    $AuditOnly
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

$HereScript = $MyInvocation.MyCommand.Path
$HereDir = (get-item $HereScript).Directory
if (!$DkmlPath) {
    $DkmlPath = $HereDir.Parent.Parent.FullName
}
if (!(Test-Path -Path $DkmlPath\.dkmlroot)) {
    throw "Could not locate the DKML scripts. Thought DkmlPath was $DkmlPath"
}
$DkmlProps = ConvertFrom-StringData (Get-Content $DkmlPath\.dkmlroot -Raw)
$dkml_root_version = $DkmlProps.dkml_root_version

$PSDefaultParameterValues = @{'Out-File:Encoding' = 'utf8'} # for Tee-Object. https://stackoverflow.com/a/58920518

$dsc = [System.IO.Path]::DirectorySeparatorChar
$env:PSModulePath += "$([System.IO.Path]::PathSeparator)$HereDir${dsc}SingletonInstall"
$env:PSModulePath += "$([System.IO.Path]::PathSeparator)$DkmlPath${dsc}vendor${dsc}drd${dsc}src${dsc}windows"
Import-Module Deployers
Import-Module UnixInvokers
Import-Module Machine
Import-Module DeploymentVersion
Import-Module DeploymentHash # for Get-Sha256Hex16OfText

# Make sure not Run as Administrator
if ([System.Environment]::OSVersion.Platform -eq "Win32NT") {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ((-not $AllowRunAsAdmin) -and $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "You are in an PowerShell Run as Administrator session. Please run $HereScript from a non-Administrator PowerShell session."
        exit 1
    }
}

# Older versions of PowerShell and Windows Server use SSL 3 / TLS 1.0 while our sites
# (especially gitlab assets) may require the use of TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ----------------------------------------------------------------
# Prerequisite Check

# A. 64-bit check
if (!$global:Skip64BitCheck -and ![Environment]::Is64BitOperatingSystem) {
    # This might work on 32-bit Windows, but that hasn't been tested.
    # One missing item is whether there are 32-bit Windows ocaml/opam Docker images
    throw "DkML is only supported on 64-bit Windows"
}

# B. Make sure OCaml variables not in Machine environment variables, which require Administrator access
# Confer https://gitlab.com/diskuv/diskuv-ocaml/-/issues/4 and https://github.com/diskuv/dkml-installer-ocaml/issues/13
$OcamlNonDKMLEnvKeys = @( "OCAMLLIB", "CAMLLIB" )
$OcamlNonDKMLEnvKeys | ForEach-Object {
    $x = [System.Environment]::GetEnvironmentVariable($_, "Machine")
    if (($null -ne $x) -and ("" -ne $x)) {
        Write-Error ("`n`nYou have a System Environment Variable named '$_' that must be removed before proceeding with the installation.`n`n" +
            "1. Press the Windows Key ⊞, type `"system environment variable`" and click Open.`n" +
            "2. Click the `"Environment Variables`" button.`n" +
            "3. In the bottom section titled `"System variables`" select the Variable '$_' and then press `"Delete`".`n" +
            "4. Restart the installation process.`n`n"
            )
        exit 1
    }
}

# C. MSYS2Dir is required when not Offline but on Win32
if($Offline) {
    $UseMSYS2 = $False
    $MSYS2Dir = $null
} elseif ([System.Environment]::OSVersion.Platform -eq "Win32NT") {
    $UseMSYS2 = $True
    if(-not $MSYS2Dir) {
        Write-Error ("`n`n-MSYS2Dir is required when not Offline but on Win32")
        exit 1
    }
} else {
    $UseMSYS2 = $False
    $MSYS2Dir = $null
}

# ----------------------------------------------------------------
# Calculate deployment id, and exit if -OnlyOutputCacheKey switch

# Magic constants that will identify new and existing deployments:

# Consolidate the magic constants into a single deployment id
$DeploymentId = "v-$dkml_root_version"
if ($UseMSYS2) {
    $AllMSYS2Packages = $DV_MSYS2Packages + (DV_MSYS2PackagesAbi -DkmlHostAbi $DkmlHostAbi)
    $MSYS2Hash = Get-Sha256Hex16OfText -Text ($AllMSYS2Packages -join ',')
    $DeploymentId += ";msys2-$MSYS2Hash"
}

if ($OnlyOutputCacheKey) {
    Write-Output $DeploymentId
    return
}

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
if (-not $InstallationPrefix) {
    $InstallationPrefix = $DkmlParentHomeDir
}

# Two birds with one stone:
# 1. Create installation directory (parts of this script assume the
#    directory exists).
# 2. PowerShell 5's [System.IO.File]::WriteAllText() requires an absolute
#    path. And getting an absolute path requires that the directory exist first.
if (!(Test-Path -Path $InstallationPrefix)) { New-Item -Path $InstallationPrefix -ItemType Directory | Out-Null }
if (!(Test-Path -Path $DkmlParentHomeDir)) { New-Item -Path $DkmlParentHomeDir -ItemType Directory | Out-Null }
$InstallationPrefix = (Resolve-Path -LiteralPath $InstallationPrefix).Path

# Make InstallationPrefix be a DOS 8.3 path if possible ... that reduces the
# risk when $env:DiskuvOCamlHome and other related paths are used. Some users
# have spaces in their username (ie. C:\Users\Jane Smith) which screws up many
# OCaml tools.
$InstallationPrefix = Get-Dos83ShortName $InstallationPrefix
$DkmlParentHomeDir = Get-Dos83ShortName $DkmlParentHomeDir

# ----------------------------------------------------------------
# Set path to DiskuvOCaml; exit if already current version already deployed

# Check if already deployed
$finished = Get-BlueGreenDeployIsFinished -ParentPath $InstallationPrefix -DeploymentId $DeploymentId
if (!$IncrementalDeployment -and $finished) {
    Write-Information "$DeploymentId already deployed."
    Write-Information ""
    Write-Information "Enjoy DkML!"
    Write-Information "  Documentation: https://diskuv.com/dkmlbook/"
    Write-Information "  Announcements: https://twitter.com/diskuv"
    Write-Information "  DkSDK:         https://diskuv.com/pricing"
    return
}

# ----------------------------------------------------------------
# Utilities

# PowerShell 5.1 (the default on Windows 10) writes UTF-8 with BOM.
# Confer: https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-content?view=powershell-5.1
# https://stackoverflow.com/a/5596984 is a solution.
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False

if($null -eq $DkmlHostAbi -or "" -eq $DkmlHostAbi) {
    if ([Environment]::Is64BitOperatingSystem) {
        $DkmlHostAbi = "windows_x86_64"
    } else {
        $DkmlHostAbi = "windows_x86"
    }
}

# ----------------------------------------------------------------
# Progress declarations

$global:ProgressStep = 0
$global:ProgressActivity = $null
$ProgressTotalSteps = 2
if ($Offline) {
    $ProgressTotalSteps = 1
}
if (-not $SkipMSYS2Update) {
    $ProgressTotalSteps = $ProgressTotalSteps + 1
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
function Write-ProgressCurrentOperation {
    param(
        [Parameter(Mandatory)]
        $CurrentOperation
    )
    if ($SkipProgress) {
        Write-Information "$(Get-CurrentTimestamp) $CurrentOperation"
    } else {
        Write-Progress -Id $ProgressId `
            -ParentId $ParentProgressId `
            -Activity $global:ProgressActivity `
            -Status $global:ProgressStatus `
            -CurrentOperation $CurrentOperation `
            -PercentComplete (100 * ($global:ProgressStep / $ProgressTotalSteps))
    }
}

function Write-Error($message) {
    # https://stackoverflow.com/questions/38064704/how-can-i-display-a-naked-error-message-in-powershell-without-an-accompanying
    [Console]::ForegroundColor = 'red'
    [Console]::Error.WriteLine($message)
    [Console]::ResetColor()
}

# ----------------------------------------------------------------
# BEGIN Start deployment

$global:ProgressStatus = "Starting Deployment"
if ($NoDeploymentSlot) {
    $ProgramPath = $InstallationPrefix
} else {
    $ProgramPath = Start-BlueGreenDeploy -ParentPath $InstallationPrefix `
        -DeploymentId $DeploymentId `
        -FixedSlotIdx:$null `
        -KeepOldDeploymentWhenSameDeploymentId:$IncrementalDeployment `
        -LogFunction ${function:\Write-ProgressCurrentOperation}
}

# We use "deployments" for any temporary directory we need since the
# deployment process handles an aborted setup and the necessary cleaning up of disk
# space (eventually).
if (!$TempParentPath) {
    $TempParentPath = "$Env:temp\dkml\setupuserprofile"
}
$TempPath = Start-BlueGreenDeploy -ParentPath $TempParentPath `
    -DeploymentId $DeploymentId `
    -KeepOldDeploymentWhenSameDeploymentId:$IncrementalDeployment `
    -LogFunction ${function:\Write-ProgressCurrentOperation}

$ProgramRelGeneralBinDir = "usr\bin"
$ProgramGeneralBinDir = Join-Path $ProgramPath -ChildPath $ProgramRelGeneralBinDir
$ProgramRelEssentialBinDir = "bin"
$ProgramEssentialBinDir = Join-Path $ProgramPath -ChildPath $ProgramRelEssentialBinDir

# END Start deployment
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# Enhanced Progress Reporting

$AuditLog = Join-Path -Path $ProgramPath -ChildPath "setup-userprofile.full.log"
if (Test-Path -Path $AuditLog) {
    # backup the original
    Rename-Item -Path $AuditLog -NewName "setup-userprofile.backup.$(Get-CurrentEpochMillis).log"
}

function Invoke-NativeCommandWithProgress {
    param (
        [Parameter(Mandatory=$true)]
        $FilePath,
        $ArgumentList
    )
    if ($null -eq $ArgumentList) {  $ArgumentList = @() }
    # Append what we will do into $AuditLog
    $Command = "$FilePath $($ArgumentList -join ' ')"
    $what = "$Command"
    Add-Content -Path $AuditLog -Value "$(Get-CurrentTimestamp) $what" -Encoding UTF8

    if ($SkipProgress) {
        Write-ProgressCurrentOperation -CurrentOperation $what
        $oldeap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        # `ForEach-Object ToString` so that System.Management.Automation.ErrorRecord are sent to Tee-Object as well
        & $FilePath @ArgumentList 2>&1 | ForEach-Object ToString | Tee-Object -FilePath $AuditLog -Append
        $ErrorActionPreference = $oldeap
        if ($LastExitCode -ne 0) {
            throw "Command failed! Exited with $LastExitCode. Command was: $Command."
        }
    } else {
        Write-Progress -Id $ProgressId `
            -ParentId $ParentProgressId `
            -Activity $global:ProgressActivity `
            -Status $what `
            -PercentComplete (100 * ($global:ProgressStep / $ProgressTotalSteps))

        $RedirectStandardOutput = New-TemporaryFile
        $RedirectStandardError = New-TemporaryFile
        try {
            $proc = Start-Process -FilePath $FilePath `
                -NoNewWindow `
                -RedirectStandardOutput $RedirectStandardOutput `
                -RedirectStandardError $RedirectStandardError `
                -ArgumentList $ArgumentList `
                -PassThru

            # cache proc.Handle https://stackoverflow.com/a/23797762/1479211
            $handle = $proc.Handle
            if ($handle) {} # remove warning about unused $handle

            while (-not $proc.HasExited) {
                if (-not $SkipProgress) {
                    $tail = Get-Content -Path $RedirectStandardOutput -Tail $InvokerTailLines -ErrorAction Ignore
                    if ($tail -is [array]) { $tail = $tail -join "`n" }
                    if ($null -ne $tail) {
                        Write-ProgressCurrentOperation $tail
                    }
                }
                Start-Sleep -Seconds $InvokerTailRefreshSeconds
            }
            $proc.WaitForExit()
            $exitCode = $proc.ExitCode
            if ($exitCode -ne 0) {
                $err = Get-Content -Path $RedirectStandardError -Raw -ErrorAction Ignore
                if ($null -eq $err -or "" -eq $err) { $err = Get-Content -Path $RedirectStandardOutput -Tail 5 -ErrorAction Ignore }
                throw "Command failed! Exited with $exitCode. Command was: $Command.`nError was: $err"
            }
        }
        finally {
            if ($null -ne $RedirectStandardOutput -and (Test-Path $RedirectStandardOutput)) {
                if ($AuditLog) { Add-Content -Path $AuditLog -Value (Get-Content -Path $RedirectStandardOutput -Raw) -Encoding UTF8 }
                Remove-Item $RedirectStandardOutput -Force -ErrorAction Continue
            }
            if ($null -ne $RedirectStandardError -and (Test-Path $RedirectStandardError)) {
                if ($AuditLog) { Add-Content -Path $AuditLog -Value (Get-Content -Path $RedirectStandardError -Raw) -Encoding UTF8 }
                Remove-Item $RedirectStandardError -Force -ErrorAction Continue
            }
        }
    }
}
function Invoke-GenericCommandWithProgress {
    param (
        [Parameter(Mandatory=$true)]
        $Command,
        [string[]]
        $ArgumentList,
        [switch]
        $ForceConsole,
        [switch]
        $IgnoreErrors
    )
    $OrigCommand = $Command
    $OrigArgumentList = $ArgumentList

    # 1. Add Git to path
    # 2. Use our temporary directory, which will get cleaned up automatically,
    #    as the parent temp directory for DKML (so it gets cleaned up automatically).
    # 3. Always use full path to MSYS2 env, because Scoop and Chocolately can
    #    add their own Unix executables to the PATH
    if($UseMSYS2) {
        $MSYS2Env = Join-Path (Join-Path (Join-Path $MSYS2Dir -ChildPath "usr") -ChildPath "bin") -ChildPath "env.exe"
        $MSYS2Cygpath = Join-Path (Join-Path (Join-Path $MSYS2Dir -ChildPath "usr") -ChildPath "bin") -ChildPath "cygpath.exe"
        if($Offline) {
            $PrePATH = ""
        } else {
            $GitMSYS2AbsPath = & $MSYS2Cygpath -au "$GitPath"
            $PrePATH = "${GitMSYS2AbsPath}:"
        }
        $TempMSYS2AbsPath = & $MSYS2Cygpath -au "$TempPath"
        $Command = $MSYS2Env
        $ArgumentList = @(
            "PATH=${PrePATH}$INVOKER_MSYSTEM_PREFIX/bin:/usr/bin:/bin"
            "DKML_TMP_PARENTDIR=$TempMSYS2AbsPath"
            ) + @( $OrigCommand ) + $OrigArgumentList
    } else {
        $Command = "env"
        if($Offline) {
            $PrePATH = ""
        } else {
            $PrePATH = "${GitPath}:"
        }
        $ArgumentList = @(
            "PATH=${PrePATH}/usr/bin:/bin"
            "DKML_TMP_PARENTDIR=$TempPath"
            ) + @( $OrigCommand ) + $OrigArgumentList
    }

    # Append what we will do into $AuditLog
    if($UseMSYS2) {
        $what = "[MSYS2] $OrigCommand $($OrigArgumentList -join ' ')"
    } else {
        $what = "$OrigCommand $($OrigArgumentList -join ' ')"
    }
    Add-Content -Path $AuditLog -Value "$(Get-CurrentTimestamp) $what" -Encoding UTF8

    if ($ForceConsole) {
        if (-not $SkipProgress) {
            Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $global:ProgressActivity -Completed
        }
        if($UseMSYS2) {
            Invoke-MSYS2Command -Command $Command -ArgumentList $ArgumentList `
                -MSYS2Dir $MSYS2Dir -IgnoreErrors:$IgnoreErrors
        } else {
            Invoke-NativeCommandWithProgress -FilePath $Command -ArgumentList $ArgumentList
        }
    } elseif ($SkipProgress) {
        Write-ProgressCurrentOperation -CurrentOperation "$what"
        if($UseMSYS2) {
            Invoke-MSYS2Command -Command $Command -ArgumentList $ArgumentList `
                -MSYS2Dir $MSYS2Dir -IgnoreErrors:$IgnoreErrors `
                -AuditLog $AuditLog
        } else {
            Invoke-NativeCommandWithProgress -FilePath $Command -ArgumentList $ArgumentList
        }
    } else {
        $global:ProgressStatus = $what
        Write-Progress -Id $ProgressId `
            -ParentId $ParentProgressId `
            -Activity $global:ProgressActivity `
            -Status $global:ProgressStatus `
            -CurrentOperation $Command `
            -PercentComplete (100 * ($global:ProgressStep / $ProgressTotalSteps))
        if($UseMSYS2) {
            Invoke-MSYS2Command -Command $Command `
                -ArgumentList $ArgumentList `
                -MSYS2Dir $MSYS2Dir `
                -AuditLog $AuditLog `
                -IgnoreErrors:$IgnoreErrors `
                -TailFunction ${function:\Write-ProgressCurrentOperation}
        } else {
            Invoke-NativeCommandWithProgress -FilePath $Command -ArgumentList $ArgumentList
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
    # BEGIN MSYS2

    if ($UseMSYS2) {
        $global:AdditionalDiagnostics += "[Advanced] MSYS2 commands can be run with: $MSYS2Dir\msys2_shell.cmd`n"

        # Always use full path to MSYS2 executables, because Scoop and Chocolately can
        # add their own Unix executables to the PATH
        $MSYS2UsrBin = Join-Path (Join-Path $MSYS2Dir -ChildPath "usr") -ChildPath "bin"
        $MSYS2Env = Join-Path $MSYS2UsrBin -ChildPath "env.exe"
        $MSYS2Bash = Join-Path $MSYS2UsrBin -ChildPath "bash.exe"
        $MSYS2Sed = Join-Path $MSYS2UsrBin -ChildPath "sed.exe"
        $MSYS2Pacman = Join-Path $MSYS2UsrBin -ChildPath "pacman.exe"
        $MSYS2Cygpath = Join-Path $MSYS2UsrBin -ChildPath "cygpath.exe"

        # Synchronize packages
        #
        if (-not $SkipMSYS2Update) {
            $global:ProgressActivity = "Update MSYS2"
            Write-ProgressStep

                # Create home directories and other files and settings
            # A: Use patches from https://patchew.org/QEMU/20210709075218.1796207-1-thuth@redhat.com/
            ((Get-Content -path $MSYS2Dir\etc\post-install\07-pacman-key.post -Raw) -replace '--refresh-keys', '--version') |
                Set-Content -Path $MSYS2Dir\etc\post-install\07-pacman-key.post # A
            #   the first time with a login will setup gpg keys but will exit with `mkdir: cannot change permissions of /dev/shm`
            #   so we do -IgnoreErrors but will otherwise set all the directories correctly
            Invoke-GenericCommandWithProgress -IgnoreErrors `
                -Command $MSYS2Bash -ArgumentList @("-lc", "true")
            Invoke-GenericCommandWithProgress `
                -Command $MSYS2Sed -ArgumentList @("-i", "s/^CheckSpace/#CheckSpace/g", "/etc/pacman.conf") # A

            if ($Flavor -ne "CI") {
                # Pacman does not update individual packages but rather the full system is upgraded. We _must_
                # upgrade the system before installing packages, except we allow CI systems to use whatever
                # system was installed as part of the CI. Confer:
                # https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported
                # One more edge case ...
                #   :: Processing package changes...
                #   upgrading msys2-runtime...
                #   upgrading pacman...
                #   :: To complete this update all MSYS2 processes including this terminal will be closed. Confirm to proceed [Y/n] SUCCESS: The process with PID XXXXX has been terminated.
                # ... when pacman decides to upgrade itself, it kills all the MSYS2 processes. So we need to run at least
                # once and ignore any errors from forcible termination.
                Invoke-GenericCommandWithProgress -IgnoreErrors `
                    -Command $MSYS2Pacman -ArgumentList @("-Syu", "--noconfirm")
                Invoke-GenericCommandWithProgress `
                    -Command $MSYS2Pacman -ArgumentList @("-Syu", "--noconfirm")
            }

            # Install new packages and/or full system if any were not installed ("--needed")
            Invoke-GenericCommandWithProgress `
                -Command $MSYS2Pacman -ArgumentList (
                    @("-S", "--needed", "--noconfirm") +
                    $AllMSYS2Packages)
        }

        $ProgramNormalPath = & $MSYS2Cygpath -au "$ProgramPath"
    } else {
        $ProgramNormalPath = "$ProgramPath"
    }

    # END MSYS2
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Define dkmlvars

    # dkmlvars.* (DiskuvOCaml variables) are scripts that set variables about the deployment.
    if($Offline) {
        $DiskuvOCamlMode = "byte"
    } else {
        $DiskuvOCamlMode = "native"
    }
    $UnixVarsArray = @(
        "DiskuvOCamlVarsVersion=2",
        "DiskuvOCamlDeploymentId='$DeploymentId'",
        "DiskuvOCamlVersion='$dkml_root_version'",
        "DiskuvOCamlMode='$DiskuvOCamlMode'"
        )
    if ($UseMSYS2) {
        $UnixVarsArray += @(
            "DiskuvOCamlHome='$ProgramNormalPath'",
            "DiskuvOCamlBinaryPaths='$ProgramNormalPath/usr/bin;$ProgramNormalPath/bin'",
            "DiskuvOCamlMSYS2Dir='/'"
        )
    } else {
        $DkmlUsrPath = Join-Path -Path $DkmlPath -ChildPath "usr"
        $DkmlUsrBinPath = Join-Path -Path $DkmlUsrPath -ChildPath "bin"
        $DkmlBinPath = Join-Path -Path $DkmlPath -ChildPath "bin"
        $UnixVarsArray += @(
            "DiskuvOCamlHome='$DkmlPath'",
            "DiskuvOCamlBinaryPaths='$DkmlUsrBinPath;$DkmlBinPath'"
        )
    }

    $UnixVarsContents = $UnixVarsArray -join [environment]::NewLine
    $ProgramUsrPath = Join-Path -Path $ProgramPath -ChildPath "usr"
    $ProgramUsrBinPath = Join-Path -Path $ProgramUsrPath -ChildPath "bin"
    $ProgramBinPath = Join-Path -Path $ProgramPath -ChildPath "bin"

    $ProgramPathDoubleSlashed = $ProgramPath.Replace('\', '\\')
    $ProgramUsrBinPathDoubleSlashed = $ProgramUsrBinPath.Replace('\', '\\')
    $ProgramBinPathDoubleSlashed = $ProgramBinPath.Replace('\', '\\')

    $PowershellVarsContents = @"
`$env:DiskuvOCamlVarsVersion = 2
`$env:DiskuvOCamlHome = '$ProgramPath'
`$env:DiskuvOCamlBinaryPaths = '$ProgramUsrBinPath;$ProgramBinPath'
`$env:DiskuvOCamlDeploymentId = '$DeploymentId'
`$env:DiskuvOCamlVersion = '$dkml_root_version'
`$env:DiskuvOCamlMode = '$DiskuvOCamlMode'

"@
    $CmdVarsContents = @"
`@SET DiskuvOCamlVarsVersion=2
`@SET DiskuvOCamlHome=$ProgramPath
`@SET DiskuvOCamlBinaryPaths=$ProgramUsrBinPath;$ProgramBinPath
`@SET DiskuvOCamlDeploymentId=$DeploymentId
`@SET DiskuvOCamlVersion=$dkml_root_version
`@SET DiskuvOCamlMode=$DiskuvOCamlMode

"@
    $CmakeVarsContents = @"
`set(DiskuvOCamlVarsVersion 2)
`cmake_path(SET DiskuvOCamlHome NORMALIZE [=====[$ProgramPath]=====])
`cmake_path(CONVERT [=====[$ProgramUsrBinPath;$ProgramBinPath]=====] TO_CMAKE_PATH_LIST DiskuvOCamlBinaryPaths)
`set(DiskuvOCamlDeploymentId [=====[$DeploymentId]=====])
`set(DiskuvOCamlVersion [=====[$dkml_root_version]=====])
`set(DiskuvOCamlMode [=====[$DiskuvOCamlMode]=====])

"@
    $SexpVarsContents = @"
`(
`("DiskuvOCamlVarsVersion" ("2"))
`("DiskuvOCamlHome" ("$ProgramPathDoubleSlashed"))
`("DiskuvOCamlBinaryPaths" ("$ProgramUsrBinPathDoubleSlashed" "$ProgramBinPathDoubleSlashed"))
`("DiskuvOCamlDeploymentId" ("$DeploymentId"))
`("DiskuvOCamlVersion" ("$dkml_root_version"))
`("DiskuvOCamlMode" ("$DiskuvOCamlMode"))

"@

    if($UseMSYS2) {
        $PowershellVarsContents += @"
`$env:DiskuvOCamlMSYS2Dir = '$MSYS2Dir'

"@
        $CmdVarsContents += @"
`@SET DiskuvOCamlMSYS2Dir=$MSYS2Dir

"@
        $CmakeVarsContents += @"
`cmake_path(SET DiskuvOCamlMSYS2Dir NORMALIZE [=====[$MSYS2Dir]=====])

"@
        $SexpVarsContents += @"
`("DiskuvOCamlMSYS2Dir" ("$($MSYS2Dir.Replace('\', '\\'))"))

"@
    }

    # end nesting
    $SexpVarsContents += @"
`)
"@

    # END Define dkmlvars
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Stop deployment. Write deployment vars.

    $global:ProgressActivity = "Finalize deployment"
    Write-ProgressStep

    if (-not $NoDeploymentSlot) {
        Stop-BlueGreenDeploy -ParentPath $InstallationPrefix -DeploymentId $DeploymentId -Success
    }
    if ($IncrementalDeployment) {
        Stop-BlueGreenDeploy -ParentPath $TempParentPath -DeploymentId $DeploymentId -Success # don't delete the temp directory
    } else {
        Stop-BlueGreenDeploy -ParentPath $TempParentPath -DeploymentId $DeploymentId # no -Success so always delete the temp directory
    }

    # dkmlvars.* (DiskuvOCaml variables)
    #
    # For files that will be seen in Unix (ex. MSYS2) we should be writing BOM-less UTF-8 files.
    # For .sh scripts, they need LF endings.
    $UnixVarsContents = $UnixVarsContents -replace "`r`n", "`n" # No CRLF (although WriteAllText does not inject CRLF)
    [System.IO.File]::WriteAllText("$DkmlParentHomeDir\dkmlvars.sh", "$UnixVarsContents", $Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText("$DkmlParentHomeDir\dkmlvars.cmd", "$CmdVarsContents", $Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText("$DkmlParentHomeDir\dkmlvars.cmake", "$CmakeVarsContents", $Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText("$DkmlParentHomeDir\dkmlvars-v2.sexp", "$SexpVarsContents", $Utf8NoBomEncoding)
    Set-Content -Path "$DkmlParentHomeDir\dkmlvars.ps1" -Value $PowershellVarsContents

    # END Stop deployment. Write deployment vars.
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Modify User's environment variables

    $global:ProgressActivity = "Modify environment variables"
    Write-ProgressStep

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

    if ($Flavor -eq "Full") {
        # DiskuvOCamlHome
        Set-UserEnvironmentVariable -Name "DiskuvOCamlHome" -Value "$ProgramPath"

        # DiskuvOCamlVersion
        # - used for VSCode's CMake Tools to set VCPKG_ROOT in cmake-variants.yaml
        Set-UserEnvironmentVariable -Name "DiskuvOCamlVersion" -Value "$dkml_root_version"

        # ---------------------------------------------
        # Remove any non-DKML OCaml environment entries
        # ---------------------------------------------

        $OcamlNonDKMLEnvKeys | ForEach-Object {
            $keytodelete = $_
            $uservalue = [Environment]::GetEnvironmentVariable($keytodelete, "User")
            if ($uservalue) {
                # TODO: It would be better to have a warning pop up. But most
                # modern installations are silent (ex. a silent option is required
                # by winget). So a warning during installation will be missed.
                # Perhaps we can have a first-run warning when the user first
                # runs either opam.exe or dune.exe.

                # Backup old User value
                $backupkey = $keytodelete + "_ORIG"
                Set-UserEnvironmentVariable -Name $backupkey -Value $uservalue

                # Erase User value
                Remove-UserEnvironmentVariable -Name $keytodelete
            }
        }

        # -----------
        # Modify PATH
        # -----------
        #
        # Want: usr\bin\ then bin\
        # Why? Because immediately after installation the usr\bin\ is populated with precompiled binaries
        #   like ocamlfind and ocamlc. Only after a [dkml init] or a [with-dkml] is bin\ filled with
        #   ocamlopt, ocamlc and the full OCaml distribution. Yep ... ocamlc is present in bin\ as well.
        #   Choose usr\bin\ocaml rather than bin\ocaml so the choice of [ocaml] is consistent before
        #   and after [dkml init].

        $splitter = [System.IO.Path]::PathSeparator # should be ';' if we are running on Windows (yes, you can run Powershell on other operating systems)

        $userpath = [Environment]::GetEnvironmentVariable("PATH", "User")
        $userpathentries = $userpath -split $splitter # all of the User's PATH in a collection

        # Prepend bin\ to the User's PATH
        #   remove any old deployments
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
        #   add new PATH entry
        $userpathentries = @( $ProgramEssentialBinDir ) + $userpathentries

        # Prepend usr\bin\ to the User's PATH
        #   remove any old deployments
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
        #   add new PATH entry
        $userpathentries = @( $ProgramGeneralBinDir ) + $userpathentries

        # Remove non-DKML OCaml installs "...\OCaml\bin" like C:\OCaml\bin from the User's PATH
        # Confer: https://gitlab.com/diskuv/diskuv-ocaml/-/issues/4
        $NonDKMLWildcards = @( "*\OCaml\bin" )
        foreach ($nonDkmlWildcard in $NonDKMLWildcards) {
            $userpathentries = $userpathentries | Where-Object {$_ -notlike $nonDkmlWildcard}
        }

        # modify PATH
        Set-UserEnvironmentVariable -Name "PATH" -Value ($userpathentries -join $splitter)
    }

    # END Modify User's environment variables
    # ----------------------------------------------------------------
}
catch {
    $ErrorActionPreference = 'Continue'
    Write-Error (
        "Setup did not complete because an error occurred.`n$_`n`n$($_.ScriptStackTrace)`n`n" +
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
Write-Information "Setup is complete. Congratulations!"
Write-Information ""
Write-Information "Enjoy DkML!"
Write-Information "  Documentation: https://diskuv.com/dkmlbook/"
Write-Information "  Announcements: https://twitter.com/diskuv"
Write-Information "  DkSDK:         https://diskuv.com/pricing"
Write-Information ""
Write-Information "You will need to log out and log back in"
Write-Information "-OR- (for advanced users) exit all of your Command Prompts, Windows Terminals,"
Write-Information "PowerShells and IDEs like Visual Studio Code"
Write-Information ""
Write-Information ""

exit 0
