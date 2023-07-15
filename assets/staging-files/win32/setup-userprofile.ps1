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
    Either `4.12.1` or `4.14.0`.

    Defaults to 4.14.0
.Parameter OpamExe
    The location of a pre-existing opam.exe.
.Parameter MSYS2Dir
    The MSYS2 installation directory. MSYS2Dir is required when not offline
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
.Parameter ImpreciseC99FloatOps
    Compile OCaml with --enable-imprecise-c99-float-ops for floating-point
    operation emulation. Often needed when running inside VirtualBox on
    macOS hardware.
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
.Parameter Offline
    Setup the OCaml system in offline mode. No Git installation,
    no playground switch and no opam repository.
.Parameter VcpkgCompatibility
    Install Ninja and CMake to accompany Microsoft's
    vcpkg (the C package manager).
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
    [ValidateSet("4.12.1", "4.14.0")]
    [string]
    $OCamlLangVersion = "4.14.0",
    [ValidateSet("windows_x86", "windows_x86_64")]
    [string]
    $DkmlHostAbi,
    [Parameter(Mandatory)]
    [string]
    $OpamExe,
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
    $ImpreciseC99FloatOps,
    [switch]
    $SkipAutoUpgradeGitWhenOld,
    [switch]
    $AllowRunAsAdmin,
    [switch]
    $Offline,
    [switch]
    $VcpkgCompatibility,
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
    $StopBeforeInitOpam,
    [switch]
    $StopBeforeInstallSystemSwitch,
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
Import-Module ListingParser

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

# C. Make sure we know a git commit for the OCaml version
$OCamlLangGitCommit = switch ($OCamlLangVersion)
{
    "4.12.1" {"46c947827ec2f6d6da7fe5e195ae5dda1d2ad0c5"; Break}
    "4.13.1" {"ab626576eee205615a9d7c5a66c2cb2478f1169c"; Break}
    "4.14.0" {"15553b77175270d987058b386d737ccb939e8d5a"; Break}
    "5.00.0+dev0-2021-11-05" {"284834d31767d323aae1cee4ed719cc36aa1fb2c"; Break}
    default {
        Write-Error ("`n`nThe OCaml version $OCamlLangVersion is not supported")
        # exit 1
    }
}

# D. MSYS2Dir is required when not offline but on Win32
if($Offline) {
    $UseMSYS2 = $False
    $MSYS2Dir = $null
} elseif ([System.Environment]::OSVersion.Platform -eq "Win32NT") {
    $UseMSYS2 = $True
    if(-not $MSYS2Dir) {
        Write-Error ("`n`n-MSYS2Dir is required when not offline but on Win32")
        exit 1
    }
} else {
    $UseMSYS2 = $False
    $MSYS2Dir = $null
}

# ----------------------------------------------------------------
# Calculate deployment id, and exit if -OnlyOutputCacheKey switch

# Magic constants that will identify new and existing deployments:
# * Immutable git
$NinjaVersion = "1.10.2"
$CMakeVersion = "3.21.1"
$ListingPath = Join-Path $HereDir -ChildPath "files"
$OCamlBinaries = Get-InstallationBinaries `
    -Part ocaml `
    -ListingPath $ListingPath `
    -Abi $DkmlHostAbi `
    -OCamlVer $OCamlLangVersion
Write-Information "Setting up OCaml binaries: $OCamlBinaries"
$AllMSYS2Packages = $DV_MSYS2Packages + (DV_MSYS2PackagesAbi -DkmlHostAbi $DkmlHostAbi)

# Consolidate the magic constants into a single deployment id
$MSYS2Hash = Get-Sha256Hex16OfText -Text ($AllMSYS2Packages -join ',')
$DockerHash = Get-Sha256Hex16OfText -Text "$DV_WindowsMsvcDockerImage"
$OpamHash = (& "$OpamExe" --version)
$DeploymentId = "v-$dkml_root_version;ocaml-$OCamlLangVersion;opam-$OpamHash;msys2-$MSYS2Hash;docker-$DockerHash"
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
    Write-Information "$DeploymentId already deployed."
    Write-Information "Enjoy Diskuv OCaml! Documentation can be found at https://diskuv.gitlab.io/diskuv-ocaml/#introduction"
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
        $uri = "https://gitlab.com/api/v4/projects/diskuv-ocaml%2Fdistributions%2Fdkml/packages/generic/$PackageName/$dkml_root_version/$ZipFile"
        Write-ProgressCurrentOperation -CurrentOperation "Downloading asset $uri"
        Invoke-WebRequest -Uri "$uri" -OutFile "$TmpPath\$ZipFile"
    }
    catch {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        Write-ProgressCurrentOperation -CurrentOperation "HTTP ${StatusCode}: $uri"
        if ($StatusCode -ne 404) {
            throw "HTTP ${StatusCode}: $uri"
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
                throw "HTTP ${StatusCode}: $fixedUri"
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
$ProgressTotalSteps = 7
if ($Offline) {
    $ProgressTotalSteps = 2
}
if (-not $SkipMSYS2Update) {
    $ProgressTotalSteps = $ProgressTotalSteps + 1
}
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
# Initialize directories

if (!(Test-Path -Path $InstallationPrefix)) { New-Item -Path $InstallationPrefix -ItemType Directory | Out-Null }

# ----------------------------------------------------------------
# BEGIN Visual Studio Setup PowerShell Module

if (-not $Offline) {
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
}

# END Visual Studio Setup PowerShell Module
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# BEGIN Git for Windows

# Git is _not_ part of the Diskuv OCaml distribution per se; it is
# is a prerequisite that gets auto-installed. Said another way,
# it does not get a versioned installation like the rest of Diskuv
# OCaml. So we explicitly do version checks during the installation of
# Git.

if (-not $Offline) {
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
                Write-Information ''
                Write-Information 'One reason why the Git installer will fail is because you did not'
                Write-Information 'click "Yes" when it asks you to allow the installation.'
                Write-Information 'You can try to rerun the script.'
                Write-Information ''
                Write-Information 'Press any key to exit this script...';
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
                throw "Git installer failed"
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
}

# END Git for Windows
# ----------------------------------------------------------------

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
    $TempParentPath = "$Env:temp\diskuvocaml\setupuserprofile"
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

    if ($UseMSYS2) {
        $global:AdditionalDiagnostics += "[Advanced] MSYS2 commands can be run with: $MSYS2Dir\msys2_shell.cmd`n"

        # Always use full path to MSYS2 executables, because Scoop and Chocolately can
        # add their own Unix executables to the PATH
        $MSYS2UsrBin = Join-Path (Join-Path $MSYS2Dir -ChildPath "usr") -ChildPath "bin"
        $MSYS2Env = Join-Path $MSYS2UsrBin -ChildPath "env.exe"
        $MSYS2Bash = Join-Path $MSYS2UsrBin -ChildPath "bash.exe"
        $ShExe = Join-Path $MSYS2UsrBin -ChildPath "sh.exe"
        $MSYS2Sed = Join-Path $MSYS2UsrBin -ChildPath "sed.exe"
        $MSYS2Pacman = Join-Path $MSYS2UsrBin -ChildPath "pacman.exe"
        $MSYS2Cygpath = Join-Path $MSYS2UsrBin -ChildPath "cygpath.exe"

        $HereDirNormalPath = & $MSYS2Cygpath -au "$HereDir"

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

        $DkmlNormalPath = & $MSYS2Cygpath -au "$DkmlPath"
        $InstallationPrefixNormalPath = & $MSYS2Cygpath -au "$InstallationPrefix"
        $ProgramNormalPath = & $MSYS2Cygpath -au "$ProgramPath"
    } else {
        $ShExe = "sh"
        $HereDirNormalPath = "$HereDir"
        $DkmlNormalPath = "$DkmlPath"
        $InstallationPrefixNormalPath = "$InstallationPrefix"
        $ProgramNormalPath = "$ProgramPath"
    }

    # END MSYS2
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Define dkmlvars

    # dkmlvars.* (DiskuvOCaml variables) are scripts that set variables about the deployment.
    if ($UseMSYS2) {
        $UnixVarsArray = @(
            "DiskuvOCamlVarsVersion=2",
            "DiskuvOCamlHome='$ProgramNormalPath'",
            "DiskuvOCamlBinaryPaths='$ProgramNormalPath/usr/bin;$ProgramNormalPath/bin'",
            "DiskuvOCamlMSYS2Dir='/'",
            "DiskuvOCamlDeploymentId='$DeploymentId'",
            "DiskuvOCamlVersion='$dkml_root_version'"
        )    
    } else {
        $DkmlUsrPath = Join-Path -Path $DkmlPath -ChildPath "usr"
        $DkmlUsrBinPath = Join-Path -Path $DkmlUsrPath -ChildPath "bin"
        $DkmlBinPath = Join-Path -Path $DkmlPath -ChildPath "bin"
        $UnixVarsArray = @(
            "DiskuvOCamlVarsVersion=2",
            "DiskuvOCamlHome='$DkmlPath'",
            "DiskuvOCamlBinaryPaths='$DkmlUsrBinPath;$DkmlBinPath'",
            "DiskuvOCamlDeploymentId='$DeploymentId'",
            "DiskuvOCamlVersion='$dkml_root_version'"
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
"@
    $CmdVarsContents = @"
`@SET DiskuvOCamlVarsVersion=2
`@SET DiskuvOCamlHome=$ProgramPath
`@SET DiskuvOCamlBinaryPaths=$ProgramUsrBinPath;$ProgramBinPath
`@SET DiskuvOCamlDeploymentId=$DeploymentId
`@SET DiskuvOCamlVersion=$dkml_root_version
"@
    $CmakeVarsContents = @"
`set(DiskuvOCamlVarsVersion 2)
`cmake_path(SET DiskuvOCamlHome NORMALIZE [=====[$ProgramPath]=====])
`cmake_path(CONVERT [=====[$ProgramUsrBinPath;$ProgramBinPath]=====] TO_CMAKE_PATH_LIST DiskuvOCamlBinaryPaths)
`set(DiskuvOCamlDeploymentId [=====[$DeploymentId]=====])
`set(DiskuvOCamlVersion [=====[$dkml_root_version]=====])
"@
    $SexpVarsContents = @"
`(
`("DiskuvOCamlVarsVersion" ("2"))
`("DiskuvOCamlHome" ("$ProgramPathDoubleSlashed"))
`("DiskuvOCamlBinaryPaths" ("$ProgramUsrBinPathDoubleSlashed" "$ProgramBinPathDoubleSlashed"))
`("DiskuvOCamlDeploymentId" ("$DeploymentId"))
`("DiskuvOCamlVersion" ("$dkml_root_version"))
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

    # Inside this script we environment variables that recognize that we have an uncompleted installation:
    # 1. dkmlvars-v2.sexp is non existent or old, so can't use with-dkml.exe. WITHDKML_ENABLE=OFF
    # 2. This .ps1 module is typically called from an staging-ocamlrun environment which sets OCAMLLIB.
    #    Unset it so it does not interfere with the OCaml compiler we are building.
    $UnixPlusPrecompleteVarsArray = $UnixVarsArray + @("WITHDKML_ENABLE=OFF", "OCAMLLIB=")

    # END Define dkmlvars
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN Compile/install system ocaml.exe

    if (-not $Offline) {
        $global:ProgressActivity = "Install native Windows ocaml.exe and related binaries"
        Write-ProgressStep

        if($UseMSYS2) {
            $ProgramGeneralBinUnixAbsPath = & $MSYS2Cygpath -au "$ProgramGeneralBinDir"
        } else {
            $ProgramGeneralBinUnixAbsPath = "$ProgramGeneralBinDir"
        }

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
                if ($ImpreciseC99FloatOps) {
                    $ConfigureArgs = "--enable-imprecise-c99-float-ops"
                } else {
                    # We do not use an empty string since Powershell 5.1.19041.2364
                    # seems to erase empty arguments
                    $ConfigureArgs = "--disable-imprecise-c99-float-ops"
                }
                Invoke-GenericCommandWithProgress `
                    -Command "env" `
                    -ArgumentList ( $UnixPlusPrecompleteVarsArray + @("TOPDIR=$DkmlNormalPath/vendor/drc/all/emptytop"
                        $ShExe
                        "$HereDirNormalPath/install-ocaml.sh"
                        "$DkmlNormalPath"
                        "$OCamlLangGitCommit"
                        "$DkmlHostAbi"
                        "$ProgramNormalPath"
                        "$ConfigureArgs"))
                # and move into usr/bin/
                if ("$ProgramRelGeneralBinDir" -ne "bin") {
                    Invoke-GenericCommandWithProgress `
                        -Command $ShExe -ArgumentList @(
                            "-c",
                            ("install -d '$ProgramGeneralBinUnixAbsPath' && " +
                            "for b in $OCamlBinaries; do mv -v '$ProgramNormalPath'/bin/`$b '$ProgramGeneralBinUnixAbsPath'/; done")
                        )
                }
            }
        }
    }

    # END Compile/install system ocaml.exe
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN opam init

    if ($StopBeforeInitOpam) {
        Write-Information "Stopping before being completed finished due to -StopBeforeInitOpam switch"
        exit 0
    }

    if (-not $Offline) {
        $global:ProgressActivity = "Initialize opam package manager"
        Write-ProgressStep

        # Upgrades. Possibly ask questions to delete things, so no progress indicator
        Invoke-GenericCommandWithProgress `
            -ForceConsole `
            -Command "env" `
            -ArgumentList ( $UnixPlusPrecompleteVarsArray + @("TOPDIR=$DkmlNormalPath/vendor/drc/all/emptytop"
                "$HereDirNormalPath/deinit-opam-root.sh"
                "-d"
                "$DkmlNormalPath"
                "-o"
                "$OpamExe"))

        # Skip with ... $global:SkipOpamSetup = $true ... remove it with ... Remove-Variable SkipOpamSetup
        if (!$global:SkipOpamSetup) {
            Invoke-GenericCommandWithProgress `
                -Command "env" `
                -ArgumentList ( $UnixPlusPrecompleteVarsArray + @("TOPDIR=$DkmlNormalPath/vendor/drc/all/emptytop"
                    "$DkmlPath\vendor\drd\src\unix\private\init-opam-root.sh"
                    "-p"
                    "$DkmlHostAbi"
                    "-o"
                    "$OpamExe"
                    "-v"
                    "$ProgramNormalPath"))
        }
    }

    # END opam init
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # BEGIN opam switch create playground

    if ($StopBeforeInstallSystemSwitch) {
        Write-Information "Stopping before being completed finished due to -StopBeforeInstallSystemSwitch switch"
        exit 0
    }

    if (-not $Offline) {
        $global:ProgressActivity = "Create 'playground' opam global switch"
        Write-ProgressStep

        # Skip with ... $global:SkipOpamSetup = $true ... remove it with ... Remove-Variable SkipOpamSetup
        if (!$global:SkipOpamSetup) {
            # Install the playground switch
            if($UseMSYS2) {
                $ExtraArgsArray = @( "-e"
                "PKG_CONFIG_PATH=$MSYS2Dir\clang64\lib\pkgconfig")
            } else {
                $ExtraArgsArray = @()
            }
            Invoke-GenericCommandWithProgress `
                -Command "env" `
                -ArgumentList ( $UnixPlusPrecompleteVarsArray + @("TOPDIR=$DkmlNormalPath/vendor/drc/all/emptytop"
                    "$DkmlPath\vendor\drd\src\unix\create-opam-switch.sh"
                    "-p"
                    "$DkmlHostAbi"
                    "-y"
                    "-w"
                    "-n"
                    "playground"
                    "-v"
                    "$ProgramNormalPath"
                    "-o"
                    "$OpamExe"
                    # AUTHORITATIVE OPTIONS = dkml-runtime-apps's [cmd_init.ml]. Aka: [dkml init]
                    "-e"
                    "PKG_CONFIG_PATH=$MSYS2Dir\clang64\lib\pkgconfig"
                    "-e"
                    "PKG_CONFIG_SYSTEM_INCLUDE_PATH="
                    "-e"
                    "PKG_CONFIG_SYSTEM_LIBRARY_PATH="
                    "-m"
                    "conf-withdkml") + $ExtraArgsArray)

            # Diagnostics: Display all the switches
            Invoke-GenericCommandWithProgress `
                -Command "env" `
                -ArgumentList ( $UnixPlusPrecompleteVarsArray + @("TOPDIR=$DkmlNormalPath/vendor/drc/all/emptytop"
                    "$DkmlPath\vendor\drd\src\unix\private\platform-opam-exec.sh"
                    "-p"
                    "$DkmlHostAbi"
                    "-v"
                    "$ProgramNormalPath"
                    "-o"
                    "$OpamExe"
                    "switch"))
        }
    }

    # END opam switch create playground
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
    # Since for Unix we should be writing BOM-less UTF-8 shell scripts, and PowerShell 5.1 (the default on Windows 10) writes
    # UTF-8 with BOM (cf. https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-content?view=powershell-5.1)
    # we write to standard Windows encoding `Unicode` (UTF-16 LE with BOM) and then use dos2unix to convert it to UTF-8 with no BOM.
    if($PSVersionTable.PSVersion.Major -le 5) {
        $Encoding = "Unicode"
        $PreCommand = ("dos2unix --newfile '$InstallationPrefixNormalPath/dkmlvars.utf16le-bom.sh'   '$InstallationPrefixNormalPath/dkmlvars.tmp.sh' && " +
            "dos2unix --newfile '$InstallationPrefixNormalPath/dkmlvars.utf16le-bom.cmd'  '$InstallationPrefixNormalPath/dkmlvars.tmp.cmd' && " +
            "dos2unix --newfile '$InstallationPrefixNormalPath/dkmlvars.utf16le-bom.cmake'  '$InstallationPrefixNormalPath/dkmlvars.tmp.cmake' && " +
            "dos2unix --newfile '$InstallationPrefixNormalPath/dkmlvars.utf16le-bom.sexp' '$InstallationPrefixNormalPath/dkmlvars.tmp.sexp' && ")
    } else {
        $Encoding = "UTF8NoBOM"
        $PreCommand = ""
    }
    Set-Content -Path "$InstallationPrefix\dkmlvars.utf16le-bom.sh" -Value $UnixVarsContents -Encoding $Encoding
    Set-Content -Path "$InstallationPrefix\dkmlvars.utf16le-bom.cmd" -Value $CmdVarsContents -Encoding $Encoding
    Set-Content -Path "$InstallationPrefix\dkmlvars.utf16le-bom.cmake" -Value $CmakeVarsContents -Encoding $Encoding
    Set-Content -Path "$InstallationPrefix\dkmlvars.utf16le-bom.sexp" -Value $SexpVarsContents -Encoding $Encoding
    Set-Content -Path "$InstallationPrefix\dkmlvars.ps1" -Value $PowershellVarsContents -Encoding $Encoding

    Invoke-GenericCommandWithProgress `
        -Command $ShExe `
        -ArgumentList @(
            "-eufcx",
            ("$PreCommand" +
             "rm -f '$InstallationPrefixNormalPath/dkmlvars.utf16le-bom.sh' '$InstallationPrefixNormalPath/dkmlvars.utf16le-bom.cmd' '$InstallationPrefixNormalPath/dkmlvars.utf16le-bom.cmake' '$InstallationPrefixNormalPath/dkmlvars.utf16le-bom.sexp' && " +
             "mv '$InstallationPrefixNormalPath/dkmlvars.tmp.sh'   '$InstallationPrefixNormalPath/dkmlvars.sh' && " +
             "mv '$InstallationPrefixNormalPath/dkmlvars.tmp.cmd'  '$InstallationPrefixNormalPath/dkmlvars.cmd' && " +
             "mv '$InstallationPrefixNormalPath/dkmlvars.tmp.cmake'  '$InstallationPrefixNormalPath/dkmlvars.cmake' && " +
             "mv '$InstallationPrefixNormalPath/dkmlvars.tmp.sexp' '$InstallationPrefixNormalPath/dkmlvars-v2.sexp'")
        )

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

        $splitter = [System.IO.Path]::PathSeparator # should be ';' if we are running on Windows (yes, you can run Powershell on other operating systems)

        $userpath = [Environment]::GetEnvironmentVariable("PATH", "User")
        $userpathentries = $userpath -split $splitter # all of the User's PATH in a collection

        # Prepend usr\bin\ to the User's PATH
        #   remove any old deployments
        $userpathentries = $userpathentries | Where-Object {$_ -ne $ProgramGeneralBinDir}
        $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $ProgramGeneralBinDir)}
        $PossibleDirs = Get-PossibleSlotPaths -ParentPath $InstallationPrefix -SubPath $ProgramRelGeneralBinDir
        foreach ($possibleDir in $PossibleDirs) {
            $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
            $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $possibleDir)}
        }
        #   add new PATH entry
        $userpathentries = @( $ProgramGeneralBinDir ) + $userpathentries

        # Prepend bin\ to the User's PATH
        #   remove any old deployments
        $userpathentries = $userpathentries | Where-Object {$_ -ne $ProgramEssentialBinDir}
        $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $ProgramEssentialBinDir)}
        $PossibleDirs = Get-PossibleSlotPaths -ParentPath $InstallationPrefix -SubPath $ProgramRelEssentialBinDir
        foreach ($possibleDir in $PossibleDirs) {
            $userpathentries = $userpathentries | Where-Object {$_ -ne $possibleDir}
            $userpathentries = $userpathentries | Where-Object {$_ -ne (Get-Dos83ShortName $possibleDir)}
        }
        #   add new PATH entry
        $userpathentries = @( $ProgramEssentialBinDir ) + $userpathentries

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
Write-Information "Enjoy DkML! Documentation can be found at https://diskuv.com/dkmlbook/. Announcements will be available at https://twitter.com/diskuv"
Write-Information ""
Write-Information "You will need to log out and log back in"
Write-Information "-OR- (for advanced users) exit all of your Command Prompts, Windows Terminals,"
Write-Information "PowerShells and IDEs like Visual Studio Code"
Write-Information ""
Write-Information ""
