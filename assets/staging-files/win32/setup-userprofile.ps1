<#
.Synopsis
    Install OCaml.
.Description
    Installs Git for Windows 2.36.1, compiles OCaml and install several useful
    OCaml programs. It also modifies PATH and sets DiskuvOCaml* environment
    variables.

    Interactive Terminals
    ---------------------

    If you are running from within a continuous integration (CI) scenario you may
    encounter `Exception setting "CursorPosition"`. That means a command designed
    for user interaction was run in this script; use -SkipProgress to disable
    the need for an interactive terminal.

    Blue Green Deployments
    ----------------------

    OCaml package directories, C header "include" directories and other critical locations are hardcoded
    into essential OCaml executables like `ocamlc.exe` during `opam switch create` and `opam install`.
    We are forced to create the opam switch in its final resting place. But now we have a problem since
    we can never install a new opam switch; it would have to be on top of the existing "final" opam switch, right?
    Wrong, as long as we have two locations ... one to compile any new opam switch and another to run
    user software; once the compilation is done we can change the PATH, OPAMSWITCH, etc. to use the new opam switch.
    That old opam switch can still be used; in fact OCaml applications like the OCaml Language Server may still
    be running. But once you logout all new OCaml applications will be launched using the new PATH environment
    variables, and it is safe to use that old location for the next compile.
    The technique above where we swap locations is called Blue Green deployments.

    We would use Blue Green deployments even if we didn't have that hard requirement because it is
    safe for you (the system is treated as one atomic whole).

    A side benefit is that the new system can be compiled while you are still working. Since
    new systems can take hours to build this is an important benefit.

    One last complication. opam global switches are subdirectories of the opam root; we cannot change their location
    use the swapping Blue Green deployment technique. So we _do not_ use an opam global switch for `dkml`.
    We use external (aka local) opam switches instead.

    MSYS2
    -----

    After the script completes, you can launch MSYS2 directly with:

    & $env:DiskuvOCamlHome\tools\MSYS2\msys2_shell.cmd
.Parameter InstallationPrefix
    The installation directory. Defaults to
    $env:LOCALAPPDATA\Programs\DiskuvOCaml on Windows. On macOS and Unix,
    defaults to $env:XDG_DATA_HOME/diskuv-ocaml if XDG_DATA_HOME defined,
    otherwise $env:HOME/.local/share/diskuv-ocaml.
.Parameter Flavor
    Which type of installation to perform.

    The `CI` flavor:
    * Installs the minimal applications that are necessary
    for a functional (though limited) Diskuv OCaml system. Today that is
    only `dune` and `opam`, but that may change in the future.
    * Does not modify the User environment variables.
    * Does not do a system upgrade of MSYS2

    Choose the `CI` flavor if you have continuous integration tests.

    The `Full` flavor installs everything, including human-centric applications
    like `utop`.
.Parameter OCamlLangVersion
    Either `4.12.1` or `4.13.1`.

    Defaults to 4.12.1
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
.Parameter SkipAutoUpgradeGitWhenOld
    Ordinarily if Git for Windows is installed on the machine but
    it is less than version 1.7.2 then Git for Windows 2.36.1 is
    installed which will replace the old version.

    Git 1.7.2 includes supports for git submodules that are necessary
    for Diskuv OCaml to work.

    Git for Windows is detected by running `git --version` from the
    PATH and checking to see if the version contains ".windows."
    like "git version 2.32.0.windows.2". Without this switch
    this script may detect a Git installation that is not Git for
    Windows, and you will end up installing an extra Git for Windows
    2.36.1 installation instead of upgrading the existing Git for
    Windows to 2.36.1.

    Even with this switch is selected, Git 2.36.1 will be installed
    if there is no Git available on the PATH.
.Parameter AllowRunAsAdmin
    When specified you will be allowed to run this script using
    Run as Administrator.
    We do not recommend you do this unless you are in continuous
    integration (CI) scenarios.
.Parameter VcpkgCompatibility
    Install Ninja and CMake to accompany Microsoft's
    vcpkg (the C package manager).
.Parameter SkipProgress
    Do not use the progress user interface.
.Parameter OnlyOutputCacheKey
    Only output the userprofile cache key. The cache key is 1-to-1 with
    the version of the Diskuv OCaml distribution.
.Parameter ForceDeploymentSlot0
    Forces the blue-green deployer to use slot 0. Useful in CI situations.
.Parameter MSYS2Dir
    When specified the specified MSYS2 installation directory will be used.
    Useful in CI situations.
.Parameter OpamBinDir
    When specified the specified opam binaries directory will be used that
    contains opam.exe, opam-installer.exe and opam-putenv.exe. The entire
    OpamBinDir, including subdirectories, will be copied to the installation
    so that any DLLs (if any) are available alongside opam.exe.
.Parameter IncrementalDeployment
    Advanced.

    Tries to continue from where the last deployment finished. Never continues
    when the version number that was last deployed differs from the version
    number of the current installation script.
.Example
    PS> vendor\diskuv-ocaml\installtime\windows\setup-userprofile.ps1

.Example
    PS> $global:SkipMSYS2Setup = $true ; $global:SkipMSYS2Update = $true ; $global:SkipMobyDownload = $true ; $global:SkipMobyFixup = $true ; $global:SkipOpamSetup = $true; $global:SkipOcamlSetup = $true
    PS> vendor\diskuv-ocaml\installtime\windows\setup-userprofile.ps1
#>

# [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
#     Justification='Conditional block based on Windows 32 vs 64-bit',
#     Target="CygwinPackagesArch")]
[CmdletBinding()]
param (
    [ValidateSet("CI", "Full")]
    [string]
    $Flavor = 'Full',
    [ValidateSet("4.12.1", "4.13.1")]
    [string]
    $OCamlLangVersion = "4.12.1",
    [ValidateSet("windows_x86", "windows_x86_64")]
    [string]
    $DkmlHostAbi,
    [string]
    $DkmlPath,
    [string]
    $TempParentPath,
    [int]
    $ParentProgressId = -1,
    [string]
    $MSYS2Dir,
    [string]
    $OpamBinDir,
    [string]
    $InstallationPrefix,
    [switch]
    $SkipAutoUpgradeGitWhenOld,
    [switch]
    $AllowRunAsAdmin,
    [switch]
    $VcpkgCompatibility,
    [switch]
    $SkipProgress,
    [switch]
    $OnlyOutputCacheKey,
    [switch]
    $ForceDeploymentSlot0,
    [switch]
    $IncrementalDeployment,
    [switch]
    $StopBeforeInitOpam,
    [switch]
    $StopBeforeInstallSystemSwitch
)

$ErrorActionPreference = "Stop"

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

# Match set_dkmlparenthomedir() in crossplatform-functions.sh
if (!$InstallationPrefix) {
    if ($env:LOCALAPPDATA) {
        $InstallationPrefix = "$env:LOCALAPPDATA\Programs\DiskuvOCaml"
    } elseif ($env:XDG_DATA_HOME) {
        $InstallationPrefix = "$env:XDG_DATA_HOME/diskuv-ocaml"
    } elseif ($env:HOME) {
        $InstallationPrefix = "$env:HOME/.local/share/diskuv-ocaml"
    }
}

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
    throw "DiskuvOCaml is only supported on 64-bit Windows"
}

# B. Make sure OCaml variables not in Machine environment variables, which require Administrator access
# Confer https://gitlab.com/diskuv/diskuv-ocaml/-/issues/4
$OcamlNonDKMLEnvKeys = @( "OCAMLLIB" )
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

# C. Make sure we know a git commit for the OCaml version
$OCamlLangGitCommit = switch ($OCamlLangVersion)
{
    "4.12.1" {"46c947827ec2f6d6da7fe5e195ae5dda1d2ad0c5"; Break}
    "4.13.1" {"ab626576eee205615a9d7c5a66c2cb2478f1169c"; Break}
    "5.00.0+dev0-2021-11-05" {"284834d31767d323aae1cee4ed719cc36aa1fb2c"; Break}
    default {
        Write-Error ("`n`nThe OCaml version $OCamlLangVersion is not supported")
        # exit 1
    }
}

# ----------------------------------------------------------------
# Calculate deployment id, and exit if -OnlyOutputCacheKey switch

# Magic constants that will identify new and existing deployments:
# * Immutable git
$NinjaVersion = "1.10.2"
$CMakeVersion = "3.21.1"
$InotifyTag = "36d18f3dfe042b21d7136a1479f08f0d8e30e2f9"
$OCamlBinaries = @(
    "flexlink.exe"
    "ocaml.exe"
    "ocamlc.byte.exe"
    "ocamlc.exe"
    "ocamlc.opt.exe"
    "ocamlcmt.exe"
    "ocamlcp.byte.exe"
    "ocamlcp.exe"
    "ocamlcp.opt.exe"
    "ocamldebug.exe"
    "ocamldep.byte.exe"
    "ocamldep.exe"
    "ocamldep.opt.exe"
    "ocamldoc.exe"
    "ocamldoc.opt.exe"
    "ocamllex.byte.exe"
    "ocamllex.exe"
    "ocamllex.opt.exe"
    "ocamlmklib.byte.exe"
    "ocamlmklib.exe"
    "ocamlmklib.opt.exe"
    "ocamlmktop.byte.exe"
    "ocamlmktop.exe"
    "ocamlmktop.opt.exe"
    "ocamlobjinfo.byte.exe"
    "ocamlobjinfo.exe"
    "ocamlobjinfo.opt.exe"
    "ocamlopt.byte.exe"
    "ocamlopt.exe"
    "ocamlopt.opt.exe"
    "ocamloptp.byte.exe"
    "ocamloptp.exe"
    "ocamloptp.opt.exe"
    "ocamlprof.byte.exe"
    "ocamlprof.exe"
    "ocamlprof.opt.exe"
    "ocamlrun.exe"
    "ocamlrund.exe"
    "ocamlruni.exe"
    "ocamlyacc.exe"
)
$CiFlavorBinaries = @(
    # ocamlfind
    "ocamlfind.exe"
    # ocaml
    $OCamlBinaries
)
$CiFlavorStubs = @(
    # Stubs are important if the binaries need them.
    #   C:\Users\you>utop
    #   Fatal error: cannot load shared library dlllambda_term_stubs
    #   Reason: The specified module could not be found.
)
$CiFlavorToplevels = @(
    # Special libs are important if the binaries need them.
    # For example, lib/ocaml/topfind has hardcoded paths and will be auto-installed if not present (so auto-install
    # can happen from a local project switch which hardcodes the system lib/ocaml/topfind to a local project
    # switch that may be deleted later).
    "topfind"
)
$FullFlavorBinaries = @(
    # ci
    $CiFlavorBinaries
    # full
    "utop.exe"
    "utop-full.exe")
$FullFlavorStubs = @(
    # Stubs are important if the binaries need them.
    #   C:\Users\you>utop
    #   Fatal error: cannot load shared library dlllambda_term_stubs
    #   Reason: The specified module could not be found.

    # ci
    $CiFlavorStubs

    # `utop` stubs
    "dlllambda_term_stubs.dll"
    "dlllwt_unix_stubs.dll"
)
$FullFlavorToplevels = @(
    # Toplevels are important if the binaries need them.

    # ci
    $CiFlavorToplevels
    # full
)
if ($Flavor -eq "Full") {
    $FlavorBinaries = $FullFlavorBinaries
    $FlavorStubs = $FullFlavorStubs
    $FlavorToplevels = $FullFlavorToplevels
} elseif ($Flavor -eq "CI") {
    $FlavorBinaries = $CiFlavorBinaries
    $FlavorStubs = $CiFlavorStubs
    $FlavorToplevels = $CiFlavorToplevels
}
$AllMSYS2Packages = $DV_MSYS2Packages + (DV_MSYS2PackagesAbi -DkmlHostAbi $DkmlHostAbi)

# Consolidate the magic constants into a single deployment id
$MSYS2Hash = Get-Sha256Hex16OfText -Text ($AllMSYS2Packages -join ',')
$DockerHash = Get-Sha256Hex16OfText -Text "$DV_WindowsMsvcDockerImage"
$BinHash = Get-Sha256Hex16OfText -Text ($FlavorBinaries -join ',')
$StubHash = Get-Sha256Hex16OfText -Text ($FlavorStubs -join ',')
$ToplevelsHash = Get-Sha256Hex16OfText -Text ($FlavorToplevels -join ',')
if ($null -ne $OpamBinDir -and "" -ne $OpamBinDir) {
    $OpamHash = (& "$OpamBinDir\opam.exe" --version)
} else {
    $OpamHash = $DV_AvailableOpamVersion
}
$DeploymentId = "v-$dkml_root_version;ocaml-$OCamlLangVersion;opam-$OpamHash;inotify-$InotifyTag;msys2-$MSYS2Hash;docker-$DockerHash;bins-$BinHash;stubs-$StubHash;toplevels-$ToplevelsHash"
if ($VcpkgCompatibility) {
    $DeploymentId += ";ninja-$NinjaVersion;cmake-$CMakeVersion"
}

if ($OnlyOutputCacheKey) {
    Write-Output $DeploymentId
    return
}

# ----------------------------------------------------------------
# Set path to DiskuvOCaml; exit if already current version already deployed

# Check if already deployed
$finished = Get-BlueGreenDeployIsFinished -ParentPath $InstallationPrefix -DeploymentId $DeploymentId
if (!$IncrementalDeployment -and $finished) {
    Write-Host "$DeploymentId already deployed."
    Write-Host "Enjoy Diskuv OCaml! Documentation can be found at https://diskuv.gitlab.io/diskuv-ocaml/#introduction"
    return
}

# ----------------------------------------------------------------
# Utilities

$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False

if($null -eq $DkmlHostAbi -or "" -eq $DkmlHostAbi) {
    if ([Environment]::Is64BitOperatingSystem) {
        $DkmlHostAbi = "windows_x86_64"
    } else {
        $DkmlHostAbi = "windows_x86"
    }
}

function Import-DiskuvOCamlAsset {
    param (
        [Parameter(Mandatory)]
        $PackageName,
        [Parameter(Mandatory)]
        $ZipFile,
        [Parameter(Mandatory)]
        $TmpPath,
        [Parameter(Mandatory)]
        $DestinationPath
    )
    try {
        $uri = "https://gitlab.com/api/v4/projects/diskuv%2Fdiskuv-ocaml/packages/generic/$PackageName/$dkml_root_version/$ZipFile"
        Write-ProgressCurrentOperation -CurrentOperation "Downloading asset $uri"
        Invoke-WebRequest -Uri "$uri" -OutFile "$TmpPath\$ZipFile"
    }
    catch {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        Write-ProgressCurrentOperation -CurrentOperation "HTTP ${StatusCode}: $uri"
        if ($StatusCode -ne 404) {
            throw
        }
        # 404 Not Found. The asset may not have been uploaded / built yet so this is not a fatal error.
        # HOWEVER ... there is a nasty bug for older PowerShell + .NET versions with incorrect escape encoding.
        # Confer: https://github.com/googleapis/google-api-dotnet-client/issues/643 and
        # https://stackoverflow.com/questions/25596564/percent-encoded-slash-is-decoded-before-the-request-dispatch
        function UrlFix([Uri]$url) {
            $url.PathAndQuery | Out-Null
            $m_Flags = [Uri].GetField("m_Flags", $([Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::NonPublic))
            if ($null -ne $m_Flags) {
                [uint64]$flags = $m_Flags.GetValue($url)
                $m_Flags.SetValue($url, $($flags -bxor 0x30))
            }
        }
        $fixedUri = New-Object System.Uri -ArgumentList ($uri)
        UrlFix $fixedUri
        try {
            Write-ProgressCurrentOperation -CurrentOperation "Downloading asset $fixedUri"
            Invoke-WebRequest -Uri "$fixedUri" -OutFile "$TmpPath\$ZipFile"
        }
        catch {
            $StatusCode = $_.Exception.Response.StatusCode.value__
            Write-ProgressCurrentOperation -CurrentOperation "HTTP ${StatusCode}: $fixedUri"
            if ($StatusCode -ne 404) {
                throw
            }
            # 404 Not Found. Not a fatal error
            return $false
        }
    }
    Expand-Archive -Path "$TmpPath\$ZipFile" -DestinationPath $DestinationPath -Force
    $true
}

# ----------------------------------------------------------------
# Progress declarations

$global:ProgressStep = 0
$global:ProgressActivity = $null
$ProgressTotalSteps = 13
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
function Write-ProgressCurrentOperation {
    param(
        [Parameter(Mandatory)]
        $CurrentOperation
    )
    if ($SkipProgress) {
        Write-Host "$(Get-CurrentTimestamp) $CurrentOperation"
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
# Initialize directories

if (!(Test-Path -Path $InstallationPrefix)) { New-Item -Path $InstallationPrefix -ItemType Directory | Out-Null }

# ----------------------------------------------------------------
# BEGIN Visual Studio Setup PowerShell Module

$global:ProgressActivity = "Install Visual Studio Setup PowerShell Module"
Write-ProgressStep

Import-VSSetup -TempPath "$env:TEMP\vssetup"
$CompatibleVisualStudios = Get-CompatibleVisualStudios -ErrorIfNotFound -VcpkgCompatibility:$VcpkgCompatibility
$ChosenVisualStudio = ($CompatibleVisualStudios | Select-Object -First 1)
$VisualStudioProps = Get-VisualStudioProperties -VisualStudioInstallation $ChosenVisualStudio
$VisualStudioDirPath = "$InstallationPrefix\vsstudio.dir.txt"
$VisualStudioJsonPath = "$InstallationPrefix\vsstudio.json"
$VisualStudioVcVarsVerPath = "$InstallationPrefix\vsstudio.vcvars_ver.txt"
$VisualStudioWinSdkVerPath = "$InstallationPrefix\vsstudio.winsdk.txt"
$VisualStudioMsvsPreferencePath = "$InstallationPrefix\vsstudio.msvs_preference.txt"
$VisualStudioCMakeGeneratorPath = "$InstallationPrefix\vsstudio.cmake_generator.txt"
[System.IO.File]::WriteAllText($VisualStudioDirPath, "$($VisualStudioProps.InstallPath)", $Utf8NoBomEncoding)
[System.IO.File]::WriteAllText($VisualStudioJsonPath, ($CompatibleVisualStudios | ConvertTo-Json -Depth 5), $Utf8NoBomEncoding)
[System.IO.File]::WriteAllText($VisualStudioVcVarsVerPath, "$($VisualStudioProps.VcVarsVer)", $Utf8NoBomEncoding)
[System.IO.File]::WriteAllText($VisualStudioWinSdkVerPath, "$($VisualStudioProps.WinSdkVer)", $Utf8NoBomEncoding)
[System.IO.File]::WriteAllText($VisualStudioMsvsPreferencePath, "$($VisualStudioProps.MsvsPreference)", $Utf8NoBomEncoding)
[System.IO.File]::WriteAllText($VisualStudioCMakeGeneratorPath, "$($VisualStudioProps.CMakeGenerator)", $Utf8NoBomEncoding)

# END Visual Studio Setup PowerShell Module
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# BEGIN Git for Windows

# Git is _not_ part of the Diskuv OCaml distribution per se; it is
# is a prerequisite that gets auto-installed. Said another way,
# it does not get a versioned installation like the rest of Diskuv
# OCaml. So we explicitly do version checks during the installation of
# Git.

$global:ProgressActivity = "Install Git for Windows"
Write-ProgressStep

$GitWindowsSetupAbsPath = "$env:TEMP\gitwindows"

$GitOriginalVersion = @(0, 0, 0)
$SkipGitForWindowsInstallBecauseNonGitForWindowsDetected = $false
$GitExists = $false

# NOTE: See runtime\windows\makeit.cmd for why we check for git-gui.exe first
$GitGuiExe = Get-Command git-gui.exe -ErrorAction Ignore
if ($null -eq $GitGuiExe) {
    $GitExe = Get-Command git.exe -ErrorAction Ignore
    if ($null -ne $GitExe) { $GitExe = $GitExe.Path }
} else {
    # Use git.exe in the same PATH as git-gui.exe.
    # Ex. C:\Program Files\Git\cmd\git.exe not C:\Program Files\Git\bin\git.exe or C:\Program Files\Git\mingw\bin\git.exe
    $GitExe = Join-Path -Path (Get-Item $GitGuiExe.Path).Directory.FullName -ChildPath "git.exe"
}
if ($null -ne $GitExe) {
    $GitExists = $true
    $GitResponse = & "$GitExe" --version
    if ($LastExitCode -eq 0) {
        # git version 2.32.0.windows.2 -> 2.32.0.windows.2
        $GitResponseLast = $GitResponse.Split(" ")[-1]
        # 2.32.0.windows.2 -> 2 32 0
        $GitOriginalVersion = $GitResponseLast.Split(".")[0, 1, 2]
        # check for '.windows.'
        $SkipGitForWindowsInstallBecauseNonGitForWindowsDetected = $GitResponse -notlike "*.windows.*"
    }
}
if (-not $SkipGitForWindowsInstallBecauseNonGitForWindowsDetected) {
    # Less than 1.7.2?
    $GitTooOld = ($GitOriginalVersion[0] -lt 1 -or
        ($GitOriginalVersion[0] -eq 1 -and $GitOriginalVersion[1] -lt 7) -or
        ($GitOriginalVersion[0] -eq 1 -and $GitOriginalVersion[1] -eq 7 -and $GitOriginalVersion[2] -lt 2))
    if ((-not $GitExists) -or ($GitTooOld -and -not $SkipAutoUpgradeGitWhenOld)) {
        # Install Git for Windows 2.36.1

        $GitNewVer = "2.36.1"
        if ([Environment]::Is64BitOperatingSystem) {
            $GitWindowsBits = "64"
            $GitSha256 = "08a0c20374d13d1b448d2c5713222ff55dd1f4bffa15093b85772cc0fc5f30e7"
        } else {
            $GitWindowsBits = "32"
            $GitSha256 = "0a50735bd088698e6015265d9373cb0cc859f46a0689d3073f91da0dc0fe66aa"
        }
        if (!(Test-Path -Path "$GitWindowsSetupAbsPath")) { New-Item -Path "$GitWindowsSetupAbsPath" -ItemType Directory | Out-Null }
        if (!(Test-Path -Path "$GitWindowsSetupAbsPath\Git-$GitNewVer-$GitWindowsBits-bit.exe")) {
            Invoke-WebRequest `
                -Uri https://github.com/git-for-windows/git/releases/download/v$GitNewVer.windows.1/Git-$GitNewVer-$GitWindowsBits-bit.exe `
                -OutFile "$GitWindowsSetupAbsPath\Git-$GitNewVer-$GitWindowsBits-bit.exe"
        }
        $GitActualHash = (Get-FileHash -Algorithm SHA256 "$GitWindowsSetupAbsPath\Git-$GitNewVer-$GitWindowsBits-bit.exe").Hash
        if ("$GitSha256" -ne "$GitActualHash") {
            throw "The Git for Windows installer was corrupted. You will need to retry the installation. If this repeatedly occurs, please send an email to support@diskuv.com"
        }

        # You can see the arguments if you run: Git-$GitNewVer-$GitWindowsArch-bit.exe /?
        # https://jrsoftware.org/ishelp/index.php?topic=setupcmdline has command line options.
        # https://github.com/git-for-windows/build-extra/tree/main/installer has installer source code.
        # https://github.com/chocolatey-community/chocolatey-coreteampackages/blob/master/automatic/git.install/tools/chocolateyInstall.ps1
        # and https://github.com/chocolatey-community/chocolatey-coreteampackages/blob/master/automatic/git.install/tools/helpers.ps1 have
        # options for silent install.
        $res = "icons", "assoc", "assoc_sh"
        $isSystem = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsSystem
        if ( !$isSystem ) { $res += "icons\quicklaunch" }
        $proc = Start-Process -FilePath "$GitWindowsSetupAbsPath\Git-$GitNewVer-$GitWindowsBits-bit.exe" -NoNewWindow -Wait -PassThru `
            -ArgumentList @("/CURRENTUSER",
                "/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/NOCANCEL", "/SP-", "/LOG",
                ('/COMPONENTS="{0}"' -f ($res -join ",")) )
        $exitCode = $proc.ExitCode
        if ($exitCode -ne 0) {
            if (-not $SkipProgress) { Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $global:ProgressActivity -Completed }
            $ErrorActionPreference = "Continue"
            Write-Error "Git installer failed"
            Remove-DirectoryFully -Path "$GitWindowsSetupAbsPath"
            Start-Sleep 5
            Write-Host ''
            Write-Host 'One reason why the Git installer will fail is because you did not'
            Write-Host 'click "Yes" when it asks you to allow the installation.'
            Write-Host 'You can try to rerun the script.'
            Write-Host ''
            Write-Host 'Press any key to exit this script...';
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
            throw
        }

        # Get new PATH so we can locate the new Git
        $OldPath = $env:PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        $GitExe = Get-Command git.exe -ErrorAction Ignore
        if ($null -eq $GitExe) {
            throw "DiskuvOCaml requires that Git is installed in the PATH. The Git installer failed to do so. Please install it manually from https://gitforwindows.org/"
        }
        $GitExe = $GitExe.Path
        $env:PATH = $OldPath
    }
}
Remove-DirectoryFully -Path "$GitWindowsSetupAbsPath"

$GitPath = (get-item "$GitExe").Directory.FullName

# END Git for Windows
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# BEGIN Start deployment

$global:ProgressStatus = "Starting Deployment"
if ($ForceDeploymentSlot0) { $FixedSlotIdx = 0 } else { $FixedSlotIdx = $null }
$ProgramPath = Start-BlueGreenDeploy -ParentPath $InstallationPrefix `
    -DeploymentId $DeploymentId `
    -FixedSlotIdx:$FixedSlotIdx `
    -KeepOldDeploymentWhenSameDeploymentId:$IncrementalDeployment `
    -LogFunction ${function:\Write-ProgressCurrentOperation}

# We also use "deployments" for any temporary directory we need since the
# deployment process handles an aborted setup and the necessary cleaning up of disk
# space (eventually).
if (!$TempParentPath) {
    $TempParentPath = "$Env:temp\diskuvocaml\setupuserprofile"
}
$TempPath = Start-BlueGreenDeploy -ParentPath $TempParentPath `
    -DeploymentId $DeploymentId `
    -KeepOldDeploymentWhenSameDeploymentId:$IncrementalDeployment `
    -LogFunction ${function:\Write-ProgressCurrentOperation}

$ProgramRelGeneralBinDir = "usr\bin"
$ProgramGeneralBinDir = "$ProgramPath\$ProgramRelGeneralBinDir"
$ProgramRelEssentialBinDir = "bin"
$ProgramEssentialBinDir = "$ProgramPath\$ProgramRelEssentialBinDir"

# END Start deployment
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# Enhanced Progress Reporting

$AuditLog = Join-Path -Path $ProgramPath -ChildPath "setup-userprofile.full.log"
if (Test-Path -Path $AuditLog) {
    # backup the original
    Rename-Item -Path $AuditLog -NewName "setup-userprofile.backup.$(Get-CurrentEpochMillis).log"
}

function Invoke-Win32CommandWithProgress {
    param (
        [Parameter(Mandatory=$true)]
        $FilePath,
        $ArgumentList
    )
    if ($null -eq $ArgumentList) {  $ArgumentList = @() }
    # Append what we will do into $AuditLog
    $Command = "$FilePath $($ArgumentList -join ' ')"
    $what = "[Win32] $Command"
    Add-Content -Path $AuditLog -Value "$(Get-CurrentTimestamp) $what" -Encoding UTF8

    if ($SkipProgress) {
        Write-ProgressCurrentOperation -CurrentOperation $what
        $oldeap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        # `ForEach-Object ToString` so that System.Management.Automation.ErrorRecord are sent to Tee-Object as well
        & $FilePath @ArgumentList 2>&1 | ForEach-Object ToString | Tee-Object -FilePath $AuditLog -Append
        $ErrorActionPreference = $oldeap
        if ($LastExitCode -ne 0) {
            throw "Win32 command failed! Exited with $LastExitCode. Command was: $Command."
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
                throw "Win32 command failed! Exited with $exitCode. Command was: $Command.`nError was: $err"
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
function Invoke-MSYS2CommandWithProgress {
    param (
        [Parameter(Mandatory=$true)]
        $Command,
        [Parameter(Mandatory=$true)]
        $MSYS2Dir,
        [switch]
        $ForceConsole,
        [switch]
        $IgnoreErrors
    )
    # Add Git to path
    $GitMSYS2AbsPath = & $MSYS2Dir\usr\bin\cygpath.exe -au "$GitPath"
    $Command = "export PATH='$($GitMSYS2AbsPath)':`"`$PATH`" && $Command"

    # Use our temporary directory, which will get cleaned up automatically,
    # as the parent temp directory for DKML (so it gets cleaned up automatically).
    $TempMSYS2AbsPath = & $MSYS2Dir\usr\bin\cygpath.exe -au "$TempPath"
    $Command = "export DKML_TMP_PARENTDIR='$($TempMSYS2AbsPath)' && $Command"

    # Append what we will do into $AuditLog
    $what = "[MSYS2] $Command"
    Add-Content -Path $AuditLog -Value "$(Get-CurrentTimestamp) $what" -Encoding UTF8

    if ($ForceConsole) {
        if (-not $SkipProgress) {
            Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $global:ProgressActivity -Completed
        }
        Invoke-MSYS2Command -Command $Command -MSYS2Dir $MSYS2Dir -IgnoreErrors:$IgnoreErrors
    } elseif ($SkipProgress) {
        Write-ProgressCurrentOperation -CurrentOperation "$what"
        Invoke-MSYS2Command -Command $Command -MSYS2Dir $MSYS2Dir -IgnoreErrors:$IgnoreErrors `
            -AuditLog $AuditLog
    } else {
        $global:ProgressStatus = $what
        Write-Progress -Id $ProgressId `
            -ParentId $ParentProgressId `
            -Activity $global:ProgressActivity `
            -Status $global:ProgressStatus `
            -CurrentOperation $Command `
            -PercentComplete (100 * ($global:ProgressStep / $ProgressTotalSteps))
        Invoke-MSYS2Command -Command $Command -MSYS2Dir $MSYS2Dir `
            -AuditLog $AuditLog `
            -IgnoreErrors:$IgnoreErrors `
            -TailFunction ${function:\Write-ProgressCurrentOperation}
    }
}

# From here on we need to stuff $ProgramPath with all the binaries for the distribution
# VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV

# Notes:
# * Include lots of `TestPath` existence tests to speed up incremental deployments.

$global:AdditionalDiagnostics = "`n`n"
try {

    # ----------------------------------------------------------------
    # BEGIN inotify-win

    $global:ProgressActivity = "Install inotify-win"
    Write-ProgressStep

    $Vcvars = "$($VisualStudioProps.InstallPath)\Common7\Tools\vsdevcmd.bat"
    $InotifyCacheParentPath = "$TempPath"
    $InotifyCachePath = "$InotifyCacheParentPath\inotify-win"
    $InotifyExeBasename = "inotifywait.exe"
    $InotifyToolDir = "$ProgramPath\tools\inotify-win"
    $InotifyExe = "$InotifyToolDir\$InotifyExeBasename"
    if (!(Test-Path -Path $InotifyExe)) {
        if (!(Test-Path -Path $InotifyToolDir)) { New-Item -Path $InotifyToolDir -ItemType Directory | Out-Null }
        Remove-DirectoryFully -Path $InotifyCachePath
        Invoke-Win32CommandWithProgress -FilePath "$GitExe" -ArgumentList @("-C", "$InotifyCacheParentPath", "clone", "https://github.com/thekid/inotify-win.git")
        Invoke-Win32CommandWithProgress -FilePath "$GitExe" -ArgumentList @("-C", "$InotifyCachePath", "-c", "advice.detachedHead=false", "checkout", "$InotifyTag")
        Set-Content -Path "$InotifyCachePath\compile.bat" -Value "`"$Vcvars`" -no_logo -vcvars_ver=$($VisualStudioProps.VcVarsVer) -winsdk=$($VisualStudioProps.WinSdkVer) && csc.exe /nologo /target:exe `"/out:$InotifyCachePath\inotifywait.exe`" `"$InotifyCachePath\src\*.cs`""
        Invoke-Win32CommandWithProgress -FilePath "$env:ComSpec" -ArgumentList @("/c", "call `"$InotifyCachePath\compile.bat`"")
        Copy-Item -Path "$InotifyCachePath\$InotifyExeBasename" -Destination "$InotifyExe"
        # if (-not $SkipProgress) { Clear-Host }
    }

    # END inotify-win
    # ----------------------------------------------------------------

    if ($VcpkgCompatibility) {
        # ----------------------------------------------------------------
        # BEGIN Ninja

        $global:ProgressActivity = "Install Ninja"
        Write-ProgressStep

        $NinjaCachePath = "$TempPath\ninja"
        $NinjaZip = "$NinjaCachePath\ninja-win.zip"
        $NinjaExeBasename = "ninja.exe"
        $NinjaToolDir = "$ProgramPath\tools\ninja"
        $NinjaExe = "$NinjaToolDir\$NinjaExeBasename"
        if (!(Test-Path -Path $NinjaExe)) {
            if (!(Test-Path -Path $NinjaToolDir)) { New-Item -Path $NinjaToolDir -ItemType Directory | Out-Null }
            if (!(Test-Path -Path $NinjaCachePath)) { New-Item -Path $NinjaCachePath -ItemType Directory | Out-Null }
            Invoke-WebRequest -Uri "https://github.com/ninja-build/ninja/releases/download/v$NinjaVersion/ninja-win.zip" -OutFile "$NinjaZip"
            Expand-Archive -Path $NinjaZip -DestinationPath $NinjaCachePath -Force
            Remove-Item -Path $NinjaZip -Force
            Copy-Item -Path "$NinjaCachePath\$NinjaExeBasename" -Destination "$NinjaExe"
        }

        # END Ninja
        # ----------------------------------------------------------------

        # ----------------------------------------------------------------
        # BEGIN CMake

        $global:ProgressActivity = "Install CMake"
        Write-ProgressStep

        $CMakeCachePath = "$TempPath\cmake"
        $CMakeZip = "$CMakeCachePath\cmake.zip"
        $CMakeToolDir = "$ProgramPath\tools\cmake"
        if (!(Test-Path -Path "$CMakeToolDir\bin\cmake.exe")) {
            if (!(Test-Path -Path $CMakeToolDir)) { New-Item -Path $CMakeToolDir -ItemType Directory | Out-Null }
            if (!(Test-Path -Path $CMakeCachePath)) { New-Item -Path $CMakeCachePath -ItemType Directory | Out-Null }
            if ([Environment]::Is64BitOperatingSystem) {
                $CMakeDistType = "x86_64"
            } else {
                $CMakeDistType = "i386"
            }
            Invoke-WebRequest -Uri "https://github.com/Kitware/CMake/releases/download/v$CMakeVersion/cmake-$CMakeVersion-windows-$CMakeDistType.zip" -OutFile "$CMakeZip"
            Expand-Archive -Path $CMakeZip -DestinationPath $CMakeCachePath -Force
            Remove-Item -Path $CMakeZip -Force
            Copy-Item -Path "$CMakeCachePath\cmake-$CMakeVersion-windows-$CMakeDistType\*" `
                -Recurse `
                -Destination $CMakeToolDir
        }


        # END CMake
        # ----------------------------------------------------------------
    }

    # ----------------------------------------------------------------
    # BEGIN MSYS2

    $global:ProgressActivity = "Install MSYS2"
    Write-ProgressStep

    $MSYS2ParentDir = "$ProgramPath\tools"
    if ($null -eq $MSYS2Dir -or "" -eq $MSYS2Dir) {
        $MSYS2Dir = "$MSYS2ParentDir\MSYS2"
    }
    $MSYS2CachePath = "$TempPath\MSYS2"
    if ([Environment]::Is64BitOperatingSystem) {
        # The "base" installer is friendly for CI (ex. GitLab CI).
        # The non-base installer will not work in CI. Will get exit code -1073741515 (0xFFFFFFFFC0000135)
        # which is STATUS_DLL_NOT_FOUND; likely a graphical DLL is linked that is not present in headless
        # Windows Server based CI systems.
        $MSYS2SetupExeBasename = "msys2-base-x86_64-20210725.sfx.exe"
        $MSYS2UrlPath = "2021-07-25/msys2-base-x86_64-20210725.sfx.exe"
        $MSYS2Sha256 = "43c09824def2b626ff187c5b8a0c3e68c1063e7f7053cf20854137dc58f08592"
        $MSYS2BaseSubdir = "msys64"
        $MSYS2IsBase = $true
    } else {
        # There is no 32-bit base installer, so have to use the automated but graphical installer.
        $MSYS2SetupExeBasename = "msys2-i686-20200517.exe"
        $MSYS2UrlPath = "2020-05-17/msys2-i686-20200517.exe"
        $MSYS2Sha256 = "e478c521d4849c0e96cf6b4a0e59fe512b6a96aa2eb00388e77f8f4bc8886794"
        $MSYS2IsBase = $false
    }
    $MSYS2SetupExe = "$MSYS2CachePath\$MSYS2SetupExeBasename"

    # Skip with ... $global:SkipMSYS2Setup = $true ... remove it with ... Remove-Variable SkipMSYS2Setup
    if (!$global:SkipMSYS2Setup) {
        # https://github.com/msys2/msys2-installer#cli-usage-examples
        if (!(Test-Path "$MSYS2Dir\msys2.exe")) {
            # download and verify installer
            if (!(Test-Path -Path $MSYS2CachePath)) { New-Item -Path $MSYS2CachePath -ItemType Directory | Out-Null }
            if (!(Test-Path -Path $MSYS2SetupExe)) {
                Invoke-WebRequest -Uri "https://github.com/msys2/msys2-installer/releases/download/$MSYS2UrlPath" -OutFile "$MSYS2SetupExe.tmp"
                $MSYS2ActualHash = (Get-FileHash -Algorithm SHA256 "$MSYS2SetupExe.tmp").Hash
                if ("$MSYS2Sha256" -ne "$MSYS2ActualHash") {
                    throw "The MSYS2 installer was corrupted. You will need to retry the installation. If this repeatedly occurs, please send an email to support@diskuv.com"
                }
                Rename-Item -Path "$MSYS2SetupExe.tmp" "$MSYS2SetupExeBasename"
            }

            # remove directory, especially important so possible subsequent Rename-Item to work
            Remove-DirectoryFully -Path $MSYS2Dir

            if ($MSYS2IsBase) {
                # extract
                if ($null -eq $MSYS2BaseSubdir) { throw "check_state MSYS2BaseSubdir is not null"}
                Remove-DirectoryFully -Path "$MSYS2ParentDir\$MSYS2BaseSubdir"
                Invoke-Win32CommandWithProgress -FilePath $MSYS2SetupExe -ArgumentList "-y", "-o$MSYS2ParentDir"

                # rename to MSYS2
                Rename-Item -Path "$MSYS2ParentDir\$MSYS2BaseSubdir" -NewName "MSYS2"
            } else {
                if (!(Test-Path -Path $MSYS2Dir)) { New-Item -Path $MSYS2Dir -ItemType Directory | Out-Null }
                Invoke-Win32CommandWithProgress -FilePath $MSYS2SetupExe -ArgumentList "--silentUpdate", "--verbose", $MSYS2Dir
            }
        }
    }

    $global:AdditionalDiagnostics += "[Advanced] MSYS2 commands can be run with: $MSYS2Dir\msys2_shell.cmd`n"

    # Create home directories and other files and settings
    # A: Use patches from https://patchew.org/QEMU/20210709075218.1796207-1-thuth@redhat.com/
    ((Get-Content -path $MSYS2Dir\etc\post-install\07-pacman-key.post -Raw) -replace '--refresh-keys', '--version') |
        Set-Content -Path $MSYS2Dir\etc\post-install\07-pacman-key.post # A
    Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir -IgnoreErrors `
        -Command ("true") # the first time will exit with `mkdir: cannot change permissions of /dev/shm` but will otherwise set all the directories correctly
    Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
        -Command ("sed -i 's/^CheckSpace/#CheckSpace/g' /etc/pacman.conf") # A

    # Synchronize packages
    #
    # Skip with ... $global:SkipMSYS2Update = $true ... remove it with ... Remove-Variable SkipMSYS2Update
    if (!$global:SkipMSYS2Update) {
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
            Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir -IgnoreErrors `
                -Command ("pacman -Syu --noconfirm")
            Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
                -Command ("pacman -Syu --noconfirm")
        }

        # Install new packages and/or full system if any were not installed ("--needed")
        Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
            -Command ("pacman -S --needed --noconfirm " + ($AllMSYS2Packages -join " "))
    }

    # Create /opt/diskuv-ocaml/installtime/ which is specific to MSYS2 with common pieces from UNIX.
    # Run through dos2unix.
    $DkmlMSYS2AbsPath = & $MSYS2Dir\usr\bin\cygpath.exe -au "$DkmlPath"
    Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
        -Command ("/usr/bin/install -d /opt/diskuv-ocaml/installtime && " +
        "/usr/bin/rsync -a --delete '$DkmlMSYS2AbsPath'/vendor/drd/src/unix/ /opt/diskuv-ocaml/installtime/ && " +
        "/usr/bin/find /opt/diskuv-ocaml/installtime/ -type f | /usr/bin/xargs /usr/bin/dos2unix --quiet && " +
        "/usr/bin/find /opt/diskuv-ocaml/installtime/ -type f | /usr/bin/xargs /usr/bin/chmod +x")

    # END MSYS2
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Define dkmlvars

    # dkmlvars.* (DiskuvOCaml variables) are scripts that set variables about the deployment.
    $InstallationPrefixMSYS2AbsPath = & $MSYS2Dir\usr\bin\cygpath.exe -au "$InstallationPrefix"
    $ProgramMSYS2AbsPath = & $MSYS2Dir\usr\bin\cygpath.exe -au "$ProgramPath"
    $UnixVarsArray = @(
        "DiskuvOCamlVarsVersion=2",
        "DiskuvOCamlHome='$ProgramMSYS2AbsPath'",
        "DiskuvOCamlBinaryPaths='$ProgramMSYS2AbsPath/usr/bin:$ProgramMSYS2AbsPath/bin'",
        "DiskuvOCamlMSYS2Dir='/'",
        "DiskuvOCamlDeploymentId='$DeploymentId'",
        "DiskuvOCamlVersion='$dkml_root_version'"
    )
    $UnixVarsContents = $UnixVarsArray -join [environment]::NewLine
    $PowershellVarsContents = @"
`$env:DiskuvOCamlVarsVersion = 2
`$env:DiskuvOCamlHome = '$ProgramPath'
`$env:DiskuvOCamlBinaryPaths = '$ProgramPath\usr\bin;$ProgramPath\bin'
`$env:DiskuvOCamlMSYS2Dir = '$MSYS2Dir'
`$env:DiskuvOCamlDeploymentId = '$DeploymentId'
`$env:DiskuvOCamlVersion = '$dkml_root_version'
"@
    $CmdVarsContents = @"
`@SET DiskuvOCamlVarsVersion=2
`@SET DiskuvOCamlHome=$ProgramPath
`@SET DiskuvOCamlBinaryPaths=$ProgramPath\usr\bin;$ProgramPath\bin
`@SET DiskuvOCamlMSYS2Dir=$MSYS2Dir
`@SET DiskuvOCamlDeploymentId=$DeploymentId
`@SET DiskuvOCamlVersion=$dkml_root_version
"@
    $CmakeVarsContents = @"
`set(DiskuvOCamlVarsVersion 2)
`cmake_path(SET DiskuvOCamlHome NORMALIZE [=====[$ProgramPath]=====])
`cmake_path(CONVERT [=====[$ProgramPath\usr\bin;$ProgramPath\bin]=====] TO_CMAKE_PATH_LIST DiskuvOCamlBinaryPaths)
`cmake_path(SET DiskuvOCamlMSYS2Dir NORMALIZE [=====[$MSYS2Dir]=====])
`set(DiskuvOCamlDeploymentId [=====[$DeploymentId]=====])
`set(DiskuvOCamlVersion [=====[$dkml_root_version]=====])
"@

    $ProgramPathDoubleSlashed = $ProgramPath.Replace('\', '\\')
    $SexpVarsContents = @"
`(
`("DiskuvOCamlVarsVersion" ("2"))
`("DiskuvOCamlHome" ("$ProgramPathDoubleSlashed"))
`("DiskuvOCamlBinaryPaths" ("$ProgramPathDoubleSlashed\\usr\\bin" "$ProgramPathDoubleSlashed\\bin"))
`("DiskuvOCamlMSYS2Dir" ("$($MSYS2Dir.Replace('\', '\\'))"))
`("DiskuvOCamlDeploymentId" ("$DeploymentId"))
`("DiskuvOCamlVersion" ("$dkml_root_version"))
`)
"@

    # Inside this script we environment variables that recognize that we have an uncompleted installation:
    # 1. dkmlvars-v2.sexp is non existent or old, so can't use with-dkml.exe. WITHDKML_ENABLE=OFF
    # 2. This .ps1 module is typically called from an staging-ocamlrun environment which sets OCAMLLIB.
    #    Unset it so it does not interfere with the OCaml compiler we are building.
    $UnixPlusPrecompleteVarsOnOneLine = ($UnixVarsArray -join " ") + " WITHDKML_ENABLE=OFF OCAMLLIB="

    # END Define dkmlvars
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Compile/install system ocaml.exe

    $global:ProgressActivity = "Install native Windows ocaml.exe and related binaries"
    Write-ProgressStep

    $ProgramGeneralBinMSYS2AbsPath = & $MSYS2Dir\usr\bin\cygpath.exe -au "$ProgramGeneralBinDir"

    # Skip with ... $global:SkipOcamlSetup = $true ... remove it with ... Remove-Variable SkipOcamlSetup
    if (!$global:SkipOcamlSetup) {
        $OcamlInstalled = $true
        foreach ($OcamlBinary in $OCamlBinaries) {
            if (!(Test-Path -Path "$ProgramGeneralBinDir\$OcamlBinary")) {
                $OcamlInstalled = $false
                break
            }
        }
        if ($OcamlInstalled) {
            # okay. already installed
        } else {
            # build into bin/
            Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
                -Command "env $UnixPlusPrecompleteVarsOnOneLine TOPDIR='$DkmlMSYS2AbsPath/vendor/drc/all/emptytop' /opt/diskuv-ocaml/installtime/private/install-ocaml.sh '$DkmlMSYS2AbsPath' $OCamlLangGitCommit $DkmlHostAbi '$ProgramMSYS2AbsPath'"
            # and move into usr/bin/
            if ("$ProgramRelGeneralBinDir" -ne "bin") {
                Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
                    -Command (
                        "install -d '$ProgramGeneralBinMSYS2AbsPath' && " +
                        "for b in $OCamlBinaries; do mv -v '$ProgramMSYS2AbsPath'/bin/`$b '$ProgramGeneralBinMSYS2AbsPath'/; done"
                    )
            }
        }
    }

    # END Compile/install system ocaml.exe
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Fetch/install fdopen-based ocaml/opam repository

    $global:ProgressActivity = "Install fdopen-based ocaml/opam repository"
    Write-ProgressStep

    if ((Test-Path -Path "$ProgramPath\share\dkml\repro\$OCamlLangVersion\repo") -and (Test-Path -Path "$ProgramPath\share\dkml\repro\$OCamlLangVersion\pins.txt")) {
        # Already installed
    } elseif (Import-DiskuvOCamlAsset `
            -PackageName "ocaml_opam_repo-reproducible" `
            -ZipFile "ocaml-opam-repo-$OCamlLangVersion.zip" `
            -TmpPath "$TempPath" `
            -DestinationPath "$ProgramPath\share\dkml\repro\$OCamlLangVersion") {
        # Successfully downloaded from asset
    } else {
        throw "The Diskuv OCaml $dkml_root_version asset ocaml_opam_repo-reproducible/ocaml-opam-repo-$OCamlLangVersion.zip has not been created"
    }

    # END Fetch/install fdopen-based ocaml/opam repository
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Compile/install opam.exe into opam-real.exe
    #
    # When compiling from scratch, opam.exe requires ocamlc.exe, so
    # ocamlc.exe must have been built previously into $ProgramPath.
    #
    # We'll install a opam.exe shim later that will delegate to opam-real.exe

    $global:ProgressActivity = "Install native Windows opam.exe"
    Write-ProgressStep

    $ProgramEssentialBinMSYS2AbsPath = & $MSYS2Dir\usr\bin\cygpath.exe -au "$ProgramEssentialBinDir"

    # Skip with ... $global:SkipOpamSetup = $true ... remove it with ... Remove-Variable SkipOpamSetup
    if (!$global:SkipOpamSetup) {
        # The following go into bin/ because they are required by _all_ with-dkml.exe and compiler invocations:
        #   opam-real.exe
        #   opam-putenv.exe
        #   opam-installer.exe
        $MoveIntoEssentialBin = $false
        if ((Test-Path -Path "$ProgramEssentialBinDir\opam-real.exe") -and `
            (Test-Path -Path "$ProgramEssentialBinDir\opam-putenv.exe") -and `
            (Test-Path -Path "$ProgramEssentialBinDir\opam-installer.exe")) {
            # okay. already installed
        } elseif ($null -ne $OpamBinDir -and "" -ne $OpamBinDir -and `
            (Test-Path -Path "$OpamBinDir\opam.exe") -and `
            (Test-Path -Path "$OpamBinDir\opam-putenv.exe") -and `
            (Test-Path -Path "$OpamBinDir\opam-installer.exe")) {
            # install them
            $OpamBinMSYS2AbsPath = & $MSYS2Dir\usr\bin\cygpath.exe -au "$OpamBinDir"
            Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
                -Command (
                    "install -d '$ProgramEssentialBinMSYS2AbsPath' && " +
                    "install '$OpamBinMSYS2AbsPath'/opam.exe '$ProgramEssentialBinMSYS2AbsPath'/opam-real.exe && " +
                    "install '$OpamBinMSYS2AbsPath'/opam-putenv.exe '$OpamBinMSYS2AbsPath'/opam-installer.exe '$ProgramEssentialBinMSYS2AbsPath'/"
                )
        } elseif (!$global:SkipOpamImport -and (Import-DiskuvOCamlAsset `
                -PackageName "opam-reproducible" `
                -ZipFile "opam-$DkmlHostAbi.zip" `
                -TmpPath "$TempPath" `
                -DestinationPath "$ProgramPath")) {
            # okay. just imported into bin/
            $MoveIntoEssentialBin = $true
        } else {
            # build into bin/
            Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
                -Command "env $UnixPlusPrecompleteVarsOnOneLine TOPDIR='$DkmlMSYS2AbsPath/vendor/drc/all/emptytop' /opt/diskuv-ocaml/installtime/private/install-opam.sh '$DkmlMSYS2AbsPath' $DV_AvailableOpamVersion '$ProgramMSYS2AbsPath'"
            $MoveIntoEssentialBin = $true
        }
        if ($MoveIntoEssentialBin -and "$ProgramRelEssentialBinDir" -ne "bin") {
            Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
                -Command (
                    "install -d '$ProgramEssentialBinMSYS2AbsPath' && " +
                    "mv '$ProgramMSYS2AbsPath'/bin/opam.exe '$ProgramEssentialBinMSYS2AbsPath'/opam-real.exe && " +
                    "mv '$ProgramMSYS2AbsPath'/bin/opam-putenv.exe '$ProgramMSYS2AbsPath'/bin/opam-installer.exe '$ProgramEssentialBinMSYS2AbsPath'/"
                )
        }
    }

    # END Compile/install opam.exe
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN opam init

    if ($StopBeforeInitOpam) {
        Write-Host "Stopping before being completed finished due to -StopBeforeInitOpam switch"
        exit 0
    }

    $global:ProgressActivity = "Initialize opam package manager"
    Write-ProgressStep

    # Upgrades. Possibly ask questions to delete things, so no progress indicator
    Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
        -ForceConsole `
        -Command "env $UnixPlusPrecompleteVarsOnOneLine TOPDIR='$DkmlMSYS2AbsPath/vendor/drc/all/emptytop' '$DkmlPath\vendor\drd\src\unix\private\deinit-opam-root.sh' -o '$ProgramMSYS2AbsPath'"

    # Skip with ... $global:SkipOpamSetup = $true ... remove it with ... Remove-Variable SkipOpamSetup
    if (!$global:SkipOpamSetup) {
        Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
            -Command ("env $UnixPlusPrecompleteVarsOnOneLine TOPDIR='$DkmlMSYS2AbsPath/vendor/drc/all/emptytop' " +
                "'$DkmlPath\vendor\drd\src\unix\private\init-opam-root.sh' -p '$DkmlHostAbi' -o '$ProgramMSYS2AbsPath' -v '$ProgramMSYS2AbsPath'")
    }

    # END opam init
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN opam switch create <dkml>
    #   The dune.X.Y.Z+shim.M.N.O package requires crossplatform-functions.sh to exist.

    if ($StopBeforeInstallSystemSwitch) {
        Write-Host "Stopping before being completed finished due to -StopBeforeInstallSystemSwitch switch"
        exit 0
    }

    $global:ProgressActivity = "Create 'dkml' opam local switch"
    Write-ProgressStep

    # Skip with ... $global:SkipOpamSetup = $true ... remove it with ... Remove-Variable SkipOpamSetup
    if (!$global:SkipOpamSetup) {
        Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
            -Command ("env $UnixPlusPrecompleteVarsOnOneLine TOPDIR='$DkmlMSYS2AbsPath/vendor/drc/all/emptytop' " +
                "'$DkmlPath\vendor\drd\src\unix\private\create-tools-switch.sh' -v '$ProgramMSYS2AbsPath' -p '$DkmlHostAbi' -f '$Flavor' -o '$ProgramMSYS2AbsPath'")
        }

    # END opam switch create <dkml>
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN opam switch create playground and opam dkml plugin

    if ($StopBeforeInstallSystemSwitch) {
        Write-Host "Stopping before being completed finished due to -StopBeforeInstallSystemSwitch switch"
        exit 0
    }

    $global:ProgressActivity = "Create 'playground' opam global switch and opam dkml plugin"
    Write-ProgressStep

    # Skip with ... $global:SkipOpamSetup = $true ... remove it with ... Remove-Variable SkipOpamSetup
    if (!$global:SkipOpamSetup) {
        # Install the playground switch
        Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
            -Command ("env $UnixPlusPrecompleteVarsOnOneLine TOPDIR='$DkmlMSYS2AbsPath/vendor/drc/all/emptytop' " +
                "'$DkmlPath\vendor\drd\src\unix\create-opam-switch.sh' -p '$DkmlHostAbi' -y -n playground -v '$ProgramMSYS2AbsPath' -o '$ProgramMSYS2AbsPath'")

        # Diagnostics: Display all the switches
        Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
            -Command ("env $UnixPlusPrecompleteVarsOnOneLine TOPDIR='$DkmlMSYS2AbsPath/vendor/drc/all/emptytop' " +
                "'$DkmlPath\vendor\drd\src\unix\private\platform-opam-exec.sh' -p '$DkmlHostAbi' -v '$ProgramMSYS2AbsPath' -o '$ProgramMSYS2AbsPath' switch")

        # Make sure `opam dkml` plugin installed by running any opam dkml subcommand.
        #   Technically not necessary since opam automatically will download and build it. But
        #   this makes sure the installation fails if this most basic command does not work.
        #   Additionally, someone will inevitably measure how long it takes to create a
        #   local switch with `opam dkml init`; it should be quick!
        #
        #   Weirdly if this is the first time the plugin is ever installed in the opam root, `-y` will work
        #   because it is interpreted as a normal opam command. But when the plugin is installed
        #   `-y` will choke in some or all versions of opam dkml since `-y` is not a DKML option.
        #   Mitigation: OPAMYES=1.
        #
        #   Similarly, can't use --root with `opam dkml`.
        #   Mitigation: Use -b option which removes --root.
        Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
            -Command ("env $UnixPlusPrecompleteVarsOnOneLine TOPDIR='$DkmlMSYS2AbsPath/vendor/drc/all/emptytop' OPAMYES=1 " +
                "'$DkmlPath\vendor\drd\src\unix\private\platform-opam-exec.sh' -p '$DkmlHostAbi' -v '$ProgramMSYS2AbsPath' -o '$ProgramMSYS2AbsPath' -b dkml version")

    }

    # END opam switch create playground and opam dkml plugin
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN install `dkml` switch binaries to Programs

    $global:ProgressActivity = "Install dkml binaries"
    Write-ProgressStep

    $DiskuvHostToolsDir = "$ProgramPath\dkml\_opam"
    $ProgramLibOcamlDir = "$ProgramPath\lib\ocaml"
    $ProgramStubsDir = "$ProgramPath\lib\ocaml\stublibs"
    $FswatchToolDir = "$ProgramPath\tools\fswatch"

    function Copy-DkmlFile {
        param (
            $OpamFile,
            $Destination
        )
        # Don't copy unless the target file doesn't exist -or- the target file is different from the source file.
        # This helps IncrementalDeployment installations, especially when a file is in use
        # but hasn't changed (especially `dune.exe`, `ocamllsp.exe` which may be open in an IDE)
        if (!(Test-Path "$DiskuvHostToolsDir\$OpamFile")) {
            # no-op since the binary is not part of opam switch (we may have been installed manually like OCaml system compiler)
            $what = "[Copy-DkmlFile] {missing} $DiskuvHostToolsDir\$OpamFile -> $Destination"
            Add-Content -Path $AuditLog -Value "$(Get-CurrentTimestamp) $what" -Encoding UTF8
            Write-Host "$what"
        } elseif (!(Test-Path -Path "$Destination")) {
            $what = "[Copy-DkmlFile] {create}  $DiskuvHostToolsDir\$OpamFile -> $Destination"
            Add-Content -Path $AuditLog -Value "$(Get-CurrentTimestamp) $what" -Encoding UTF8
            Write-Host "$what"

            Copy-Item -Path "$DiskuvHostToolsDir\$OpamFile" -Destination $Destination
        } elseif ((Get-FileHash "$Destination").hash -eq (Get-FileHash $DiskuvHostToolsDir\$OpamFile).hash) {
            $what = "[Copy-DkmlFile] {present} $DiskuvHostToolsDir\$OpamFile -> $Destination"
            Add-Content -Path $AuditLog -Value "$(Get-CurrentTimestamp) $what" -Encoding UTF8
            Write-Host "$what"
        } else {
            # hashes are not equal
            $what = "[Copy-DkmlFile] {modify}  $DiskuvHostToolsDir\$OpamFile -> $Destination"
            Add-Content -Path $AuditLog -Value "$(Get-CurrentTimestamp) $what" -Encoding UTF8
            Write-Host "$what"

            Copy-Item -Path "$DiskuvHostToolsDir\$OpamFile" -Destination $Destination
        }
    }

    # Flavor binaries
    if (!(Test-Path -Path $ProgramGeneralBinDir)) { New-Item -Path $ProgramGeneralBinDir -ItemType Directory | Out-Null }
    foreach ($binary in $FlavorBinaries) {
        Copy-DkmlFile -OpamFile "bin\$binary" -Destination "$ProgramGeneralBinDir\$binary"
    }

    # opam shim
    Copy-DkmlFile -OpamFile "bin\with-dkml.exe" -Destination "$ProgramEssentialBinDir\opam.exe"

    # fswatch
    if (!(Test-Path -Path $FswatchToolDir)) { New-Item -Path $FswatchToolDir -ItemType Directory | Out-Null }
    Copy-DkmlFile -OpamFile "bin\dkml-fswatch.exe" -Destination "$FswatchToolDir\fswatch.exe"

    # Stubs for ocamlrun bytecode
    if (!(Test-Path -Path $ProgramStubsDir)) { New-Item -Path $ProgramStubsDir -ItemType Directory | Out-Null }
    foreach ($stub in $FlavorStubs) {
        Copy-DkmlFile -OpamFile "lib\stublibs\$stub" -Destination "$ProgramStubsDir\$stub"
    }

    # Toplevel files. opam sets OCAML_TOPLEVEL_PATH=lib/toplevel, but we should place them in lib/ocaml so we don't
    # have to define our own system OCAML_TOPLEVEL_PATH which would interfere with opam. Besides, installing a toplevel
    # containing package like "ocamlfind" in a local switch can autopopulate lib/ocaml anyway if we are using the
    # OCaml system compiler (dkml switch, ocaml.exe binary). So place in lib/ocaml anyway.
    if (!(Test-Path -Path $ProgramLibOcamlDir)) { New-Item -Path $ProgramLibOcamlDir -ItemType Directory | Out-Null }
    foreach ($toplevel in $FlavorToplevels) {
        # no-op since the speciallib is not part of opam switch (we may have been installed manually like OCaml system compiler)
        Copy-DkmlFile -OpamFile "lib\toplevel\$toplevel" -Destination "$ProgramLibOcamlDir\$toplevel"
    }

    # END install `dkml` switch binaries to Programs
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Stop deployment. Write deployment vars.

    $global:ProgressActivity = "Finalize deployment"
    Write-ProgressStep

    Stop-BlueGreenDeploy -ParentPath $InstallationPrefix -DeploymentId $DeploymentId -Success
    if ($IncrementalDeployment) {
        Stop-BlueGreenDeploy -ParentPath $TempParentPath -DeploymentId $DeploymentId -Success # don't delete the temp directory
    } else {
        Stop-BlueGreenDeploy -ParentPath $TempParentPath -DeploymentId $DeploymentId # no -Success so always delete the temp directory
    }

    # dkmlvars.* (DiskuvOCaml variables)
    #
    # Since for Unix we should be writing BOM-less UTF-8 shell scripts, and PowerShell 5.1 (the default on Windows 10) writes
    # UTF-8 with BOM (cf. https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-content?view=powershell-5.1)
    # we write to standard Windows encoding `Unicode` (UTF-16 LE with BOM) and then use dos2unix to convert it to UTF-8 with no BOM.
    Set-Content -Path "$InstallationPrefix\dkmlvars.utf16le-bom.sh" -Value $UnixVarsContents -Encoding Unicode
    Set-Content -Path "$InstallationPrefix\dkmlvars.utf16le-bom.cmd" -Value $CmdVarsContents -Encoding Unicode
    Set-Content -Path "$InstallationPrefix\dkmlvars.utf16le-bom.cmake" -Value $CmakeVarsContents -Encoding Unicode
    Set-Content -Path "$InstallationPrefix\dkmlvars.utf16le-bom.sexp" -Value $SexpVarsContents -Encoding Unicode
    Set-Content -Path "$InstallationPrefix\dkmlvars.ps1" -Value $PowershellVarsContents -Encoding Unicode

    Invoke-MSYS2CommandWithProgress -MSYS2Dir $MSYS2Dir `
        -Command (
            "set -x && " +
            "dos2unix --newfile '$InstallationPrefixMSYS2AbsPath/dkmlvars.utf16le-bom.sh'   '$InstallationPrefixMSYS2AbsPath/dkmlvars.tmp.sh' && " +
            "dos2unix --newfile '$InstallationPrefixMSYS2AbsPath/dkmlvars.utf16le-bom.cmd'  '$InstallationPrefixMSYS2AbsPath/dkmlvars.tmp.cmd' && " +
            "dos2unix --newfile '$InstallationPrefixMSYS2AbsPath/dkmlvars.utf16le-bom.cmake'  '$InstallationPrefixMSYS2AbsPath/dkmlvars.tmp.cmake' && " +
            "dos2unix --newfile '$InstallationPrefixMSYS2AbsPath/dkmlvars.utf16le-bom.sexp' '$InstallationPrefixMSYS2AbsPath/dkmlvars.tmp.sexp' && " +
            "rm -f '$InstallationPrefixMSYS2AbsPath/dkmlvars.utf16le-bom.sh' '$InstallationPrefixMSYS2AbsPath/dkmlvars.utf16le-bom.cmd' '$InstallationPrefixMSYS2AbsPath/dkmlvars.utf16le-bom.cmake' '$InstallationPrefixMSYS2AbsPath/dkmlvars.utf16le-bom.sexp' && " +
            "mv '$InstallationPrefixMSYS2AbsPath/dkmlvars.tmp.sh'   '$InstallationPrefixMSYS2AbsPath/dkmlvars.sh' && " +
            "mv '$InstallationPrefixMSYS2AbsPath/dkmlvars.tmp.cmd'  '$InstallationPrefixMSYS2AbsPath/dkmlvars.cmd' && " +
            "mv '$InstallationPrefixMSYS2AbsPath/dkmlvars.tmp.cmake'  '$InstallationPrefixMSYS2AbsPath/dkmlvars.cmake' && " +
            "mv '$InstallationPrefixMSYS2AbsPath/dkmlvars.tmp.sexp' '$InstallationPrefixMSYS2AbsPath/dkmlvars-v2.sexp'"
        )


    # END Stop deployment. Write deployment vars.
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Modify User's environment variables

    $global:ProgressActivity = "Modify environment variables"
    Write-ProgressStep

    $PathModified = $false
    if ($Flavor -eq "Full") {
        # DiskuvOCamlHome
        [Environment]::SetEnvironmentVariable("DiskuvOCamlHome", "$ProgramPath", "User")

        # DiskuvOCamlVersion
        # - used for VSCode's CMake Tools to set VCPKG_ROOT in cmake-variants.yaml
        [Environment]::SetEnvironmentVariable("DiskuvOCamlVersion", "$dkml_root_version", "User")

        # ---------------------------------------------
        # Remove any non-DKML OCaml environment entries
        # ---------------------------------------------

        $OcamlNonDKMLEnvKeys | ForEach-Object { [Environment]::SetEnvironmentVariable($_, "", "User") }

        # -----------
        # Modify PATH
        # -----------

        $splitter = [System.IO.Path]::PathSeparator # should be ';' if we are running on Windows (yes, you can run Powershell on other operating systems)

        $userpath = [Environment]::GetEnvironmentVariable("PATH", "User")
        $userpathentries = $userpath -split $splitter # all of the User's PATH in a collection

        # Prepend usr\bin\ to the User's PATH if it isn't already
        if (!($userpathentries -contains $ProgramGeneralBinDir)) {
            # remove any old deployments
            $PossibleDirs = Get-PossibleSlotPaths -ParentPath $InstallationPrefix -SubPath $ProgramRelGeneralBinDir
            foreach ($possibleDir in $PossibleDirs) {
                $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
                $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $possibleDir)}
            }
            # add new PATH entry
            $userpathentries = @( $ProgramGeneralBinDir ) + $userpathentries
            $PathModified = $true
        }

        # Prepend bin\ to the User's PATH if it isn't already
        if (!($userpathentries -contains $ProgramEssentialBinDir)) {
            # remove any old deployments
            $PossibleDirs = Get-PossibleSlotPaths -ParentPath $InstallationPrefix -SubPath $ProgramRelEssentialBinDir
            foreach ($possibleDir in $PossibleDirs) {
                $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
                $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $possibleDir)}
            }
            # add new PATH entry
            $userpathentries = @( $ProgramEssentialBinDir ) + $userpathentries
            $PathModified = $true
        }

        # Remove non-DKML OCaml installs "...\OCaml\bin" like C:\OCaml\bin from the User's PATH
        # Confer: https://gitlab.com/diskuv/diskuv-ocaml/-/issues/4
        $NonDKMLWildcards = @( "*\OCaml\bin" )
        $c_old = $userpathentries.Count
        foreach ($nonDkmlWildcard in $NonDKMLWildcards) {
            $userpathentries = $userpathentries | Where-Object {$_ -notlike $nonDkmlWildcard}
        }
        $c_new = $userpathentries.Count
        if ($c_old -ne $c_new) {
            $PathModified = $true
        }

        if ($PathModified) {
            # modify PATH
            [Environment]::SetEnvironmentVariable("PATH", ($userpathentries -join $splitter), "User")
        }
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

Write-Host ""
Write-Host ""
Write-Host ""
Write-Host "Setup is complete. Congratulations!"
Write-Host "Enjoy Diskuv OCaml! Documentation can be found at https://diskuv.gitlab.io/diskuv-ocaml/#introduction. Announcements will be available at https://twitter.com/diskuv"
Write-Host ""
Write-Host ""
Write-Host ""
if ($PathModified) {
    Write-Warning "Your User PATH was modified."
    Write-Warning "You will need to log out and log back in"
    Write-Warning "-OR- (for advanced users) exit all of your Command Prompts, Windows Terminals,"
    Write-Warning "PowerShells and IDEs like Visual Studio Code"
}
