# ================================
# Deployers.psm1
#
# PowerShell Module to deploy a folder. Meant for deploying an instance which
# must be completed uninstalled before re-installation, while being compatible
# with Blue Green deployers. Can be used for
# installation of executables or for self-cleaning temporary
# directories.
#
# === Deployment Identifiers ===
#
# A requirement is that deployment identifiers are idempotent
# representations of the **contents** of the deployment. That means
# using the same deployment id means deploying the same content.
#
# The following are good deployment identifiers:
# - a separator-delimited concatenation of one or more good deployment identifiers
#     like comma-separated deployment identifiers (as long as there is the separator is not in
#     the deployment identifiers)
# - a hash of one or more good deployment identifiers
# - a monotonically increasing build number
# - a semver label
# - an immutable git tag
# - a hash of the source code and build configuration of the deployment
# - a hash of the contents of the deployment (as long as there are no random or time-varying
#     values inside the deployment)
#
# === Blue Green State ===
#
# An external Deployers may initiate a blue green deployment. That deployer
# must conform to the following:
#
# The state is a triple (SLOT1, SLOT2, SLOT3) where each `SLOT<i>`
# is a record containing:
# - the UNIX epoch milliseconds of the last successful deployment,
#   or $null if no successful deployment to that slot
# - the deployment identifier of the last successful deployment
#   or $null if no successful deployment to that slot
# - a boolean where, if $true, means that this module
#   will never consider the slot for deployment
#
# State Record:
#  - id : string nullable.
#  - lastepochms : signed int64 nonnull default 0.
#  - reserved : boolean default false
#  - success : boolean default false
# We make lastepochms nonnull since it is used in sorting operations (to get
# the oldest slot)

$ErrorActionPreference = "Stop"

$DeployStateJson = "deploy-state-v1.json"
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False

$DeploySlotInitValue = [PSCustomObject]@{ "id" = $null; "lastepochms" = 0; "reserved" = $false; "success" = $false }
$DeployStateInitValue = @( $DeploySlotInitValue )

# Initialize-BlueGreenDeploy
# --------------------------
#
# Given a $ParentPath, on exit a state object
# will be initialized if it hadn't been already
function Initialize-BlueGreenDeploy {
    param (
        [Parameter(Mandatory = $true)]
        $ParentPath
    )
    if (!(Test-Path -Path "$ParentPath\$DeployStateJson")) {
        Set-BlueGreenDeployState -ParentPath $ParentPath -DeployState $DeployStateInitValue
    }
}
Export-ModuleMember -Function Initialize-BlueGreenDeploy

# Start-BlueGreenDeploy
# ---------------------
#
# Given a $ParentPath and a deployment identifier, will give you a
# subfolder of $ParentPath which you can deploy into.
# When you are finished the deployment call `Stop-BlueGreenDeploy`.
#
# Starting a deployment may mean evicting another deployment, which
# in this simple implementation means clearing its directory of all
# of its content.
#
# -KeepOldDeploymentWhenSameDeploymentId: Use if you can do
#    an incremental deployment. This switch will stop the previous
#    deployment content from being cleaned as long as a deployment
#    is found with the same deployment id.
#
# It is **fine** if your deployment does not complete successfully
# and you can't call `Stop-BlueGreenDeploy`.
function Start-BlueGreenDeploy {
    param (
        [Parameter(Mandatory = $true)]
        $ParentPath,
        [Parameter(Mandatory = $true)]
        $DeploymentId,
        [switch]$KeepOldDeploymentWhenSameDeploymentId,
        $FixedSlotIdx,
        $LogFunction
    )

    # init state if not done already
    Initialize-BlueGreenDeploy -ParentPath $ParentPath

    # move to the next deploy slot
    $state = ConvertFrom-Json (Get-BlueGreenDeployState -ParentPath $ParentPath)
    if (-not ($state -is [array])) { $state = @( $state ) } # fix ConvertFrom-Json flattening single element in PWSH 7
    if ($null -eq $FixedSlotIdx) {
        $slotIdx = Step-BlueGreenDeploySlot -ParentPath $ParentPath -DeploymentId $DeploymentId -DeployState $state
    } else {
        $slotIdx = $FixedSlotIdx
    }

    # recreate the directory with no content but only if
    # a) the deployment id has changed or
    # b) the same deployment id was not in SUCCESS and not $KeepOldDeploymentWhenSameDeploymentId
    $DeployPath = Join-Path -Path $ParentPath -ChildPath $slotIdx
    $clean = $false
    if ($DeploymentId -ne $state[$slotIdx].id) {
        $clean = $true
    }
    elseif ((-not $state[$slotIdx].success) -and (-not $KeepOldDeploymentWhenSameDeploymentId)) {
        $clean = $true
    }

    # set the slot state, before we start modifying the slot
    $currentepochms = Get-CurrentEpochMillis
    $state[$slotIdx].id = $DeploymentId
    $state[$slotIdx].lastepochms = $currentepochms
    $state[$slotIdx].success = $false
    Set-BlueGreenDeployState -ParentPath $ParentPath -DeployState $state

    # clean if necessary
    if ($clean) {
        if ($PSBoundParameters.ContainsKey('LogFunction')) {
            Invoke-Command $LogFunction -ArgumentList @("Cleaning directory $DeployPath ...")
        } else {
            Write-Information "Cleaning directory $DeployPath ..." -InformationAction Continue
        }
        New-CleanDirectory -Path $DeployPath
        if ($LogFunction) {
            Invoke-Command $LogFunction -ArgumentList @("Cleaned directory $DeployPath.")
        } else {
            Write-Information "Cleaned directory $DeployPath." -InformationAction Continue
        }
    }

    # give back to caller
    Write-Output $DeployPath
}
Export-ModuleMember -Function Start-BlueGreenDeploy

# Stop-BlueGreenDeploy
#
# Will cleanup or finalize the deployment started by Start-BlueGreenDeploy.
#
# You use `-Success` to indicate that you want to finalize the deployment,
# meaning the deployment directory will live for at least one more successful
# deployment before being recycled. An exception will be thrown if the
# deployment id does not exist (ie. evicted by another deployment).
#
# You omit `-Success` to indicate that you have aborted the deployment, and
# want the deployment directory to be cleaned. No exception will be thrown
# if the deployment id does not exist  (ie. evicted by another deployment).
function Stop-BlueGreenDeploy {
    param (
        [Parameter(Mandatory = $true)]
        $ParentPath,
        [Parameter(Mandatory = $true)]
        $DeploymentId,
        [switch]$Success
    )
    $state = ConvertFrom-Json (Get-BlueGreenDeployState -ParentPath $ParentPath)
    if (-not ($state -is [array])) { $state = @( $state ) } # fix ConvertFrom-Json flattening single element in PWSH 7
    if (-not ($state -is [array])) {
        throw "The deployment $DeploymentId was stopped because the state was in an incorrect format; it was supposed to be an array but was instead $($state.GetType())"
    }
    $matchSlotIdx = -1
    if ($DeploymentId -eq $state[0].id) {
        $matchSlotIdx = 0
    }

    # If and only if the caller says the deployment is success
    if ($Success) {
        if ($matchSlotIdx -lt 0) {
            throw "The deployment $DeploymentId says it finished but was not present. Other than the chance that the deployer has a bug assigning deployment ids, it is very likely that the deployment was evicted by another deployment"
        }
        # Save success and leave
        $state[$matchSlotIdx].success = $true
        Set-BlueGreenDeployState -ParentPath $ParentPath -DeployState $state
        return
    }

    # Deployment was aborted by caller.

    # is it still taking a slot?
    if ($matchSlotIdx -ge 0) {
        # recreate the directory with no content
        $DeployPath = Join-Path -Path $ParentPath -ChildPath $matchSlotIdx
        New-CleanDirectory -Path $DeployPath

        # free the slot, but protect against race condition where an external
        # package manager takes over the slot
        $state2 = ConvertFrom-Json (Get-BlueGreenDeployState -ParentPath $ParentPath)
        if (-not ($state2 -is [array])) { $state2 = @( $state2 ) } # fix ConvertFrom-Json flattening single element in PWSH 7
        $reserved = $state2[$matchSlotIdx].reserved
        $state[$matchSlotIdx] = Copy-BlueGreenDeploySlot $DeploySlotInitValue
        $state[$matchSlotIdx].reserved = $reserved # restore 'reserved'
        Set-BlueGreenDeployState -ParentPath $ParentPath -DeployState $state
    }
}
Export-ModuleMember -Function Stop-BlueGreenDeploy

# Uninstall-BlueGreenDeploy
#
# The last deployment's directory will be cleaned.
#
# If a file cannot be deleted because it is in use, you (the user)
# will be prompted to close the program.
function Uninstall-BlueGreenDeploy {
    param (
        [Parameter(Mandatory = $true)]
        $ParentPath,
        [switch]$Success
    )
    $state = ConvertFrom-Json (Get-BlueGreenDeployState -ParentPath $ParentPath)
    if (-not ($state -is [array])) { $state = @( $state ) } # fix ConvertFrom-Json flattening single element in PWSH 7
    if (-not ($state -is [array])) {
        throw "The uninstallation was stopped because the state was in an incorrect format; it was supposed to be an array but was instead $($state.GetType())"
    }
    # use only valid slot
    $matchSlotIdx = 0

    # is it still taking a slot?
    if ($matchSlotIdx -ge 0) {
        # remove the directory completely
        $DeployPath = Join-Path -Path $ParentPath -ChildPath $matchSlotIdx
        Remove-DirectoryFully `
            -Path $DeployPath `
            -WaitSecondsIfStuck 300 `
            -StuckMessageFormatInfo "Stuck during uninstallation of $DeployPath.`nWaited already {0,5:N1} seconds; will wait at most 300 seconds (5 minutes).`n" `
            -StuckMessageFormatCritical "Please stop using the program, or manually remove the file(s):`t{1}`n"

        # free the slot, but protect against race condition where an external
        # package manager takes over the slot
        $state2 = ConvertFrom-Json (Get-BlueGreenDeployState -ParentPath $ParentPath)
        if (-not ($state2 -is [array])) { $state2 = @( $state2 ) } # fix ConvertFrom-Json flattening single element in PWSH 7
        $reserved = $state2[$matchSlotIdx].reserved
        $state[$matchSlotIdx] = Copy-BlueGreenDeploySlot $DeploySlotInitValue
        $state[$matchSlotIdx].reserved = $reserved # restore 'reserved'
        Set-BlueGreenDeployState -ParentPath $ParentPath -DeployState $state
    }
}
Export-ModuleMember -Function Uninstall-BlueGreenDeploy

# Get-BlueGreenDeployIsFinished
#
# True if and only if the deployment id exists and is in success state.
#
# This is a pure function (no side-effects).
function Get-BlueGreenDeployIsFinished {
    param (
        [Parameter(Mandatory = $true)]
        $ParentPath,
        [Parameter(Mandatory = $true)]
        $DeploymentId
    )
    if (!(Test-Path ("$ParentPath\$DeployStateJson"))) {
        Write-Output $false
        return
    }
    $state = ConvertFrom-Json (Get-BlueGreenDeployState -ParentPath $ParentPath)
    if (-not ($state -is [array])) { $state = @( $state ) } # fix ConvertFrom-Json flattening single element in PWSH 7
    if ($DeploymentId -eq $state[0].id) {
        Write-Output $state[0].success
        return
    }
    Write-Output $false
}
Export-ModuleMember -Function Get-BlueGreenDeployIsFinished

# [Get-PossibleSlotPaths -ParentPath $ParentPath [-SubPath $SubPath]] enumerates all of the paths of
# possible slots within `$ParentPath`: `$ParentPath\0`, `$ParentPath\1` and `$ParentPath\2`.
#
# Instead of the slot directory you can have this function return a slot subdirectory by
# specifying `-SubPath $SubPath`. With a `-SubPath a\b\c` the returned results will be
# `$ParentPath\0\a\b\c`, `$ParentPath\1\a\b\c` and `$ParentPath\2\a\b\c`.
function Get-PossibleSlotPaths {
    param(
        [Parameter(Mandatory = $true)]
        $ParentPath,
        $SubPath
    )
    $DeployPath = Join-Path -Path $ParentPath -ChildPath 0
    if ($SubPath) {
        Write-Output (Join-Path -Path $DeployPath -ChildPath $SubPath)
    } else {
        Write-Output $DeployPath
    }
}
Export-ModuleMember -Function Get-PossibleSlotPaths

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Private Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Copy-BlueGreenDeploySlot
# ------------------------
function Copy-BlueGreenDeploySlot {
    param (
        [Parameter(Mandatory = $true)]
        $slot
    )

    # Type convert each field
    if ($null -eq $slot.id) {
        $id = $null
    }
    else {
        $id = [string]($slot.id)
    }
    $lastepochms = [int64]($slot.lastepochms)
    $reserved = [bool]($slot.reserved)
    $success = [bool]($slot.success)

    [PSCustomObject]@{ "id" = $id; "lastepochms" = $lastepochms; "reserved" = $reserved; "success" = $success }
}

# Get-BlueGreenDeployState
# ------------------------
#
# Get the slot for the existing deployment (partial or complete).
#
# If there is no previous deployment then an initial slot will be returned.
function Get-BlueGreenDeployState {
    param (
        [Parameter(Mandatory = $true)]
        $ParentPath
    )
    $absDeployStateJson = Join-Path $ParentPath -ChildPath $DeployStateJson
    if (Test-Path "$absDeployStateJson") {
        # We have the file deploy-state-v1.json; use it ...

        $jsState = [System.IO.File]::ReadAllText($absDeployStateJson, $Utf8NoBomEncoding)
        $jsState = ConvertFrom-Json ($jsState)
        if (-not ($jsState -is [array])) { $jsState = @( $jsState ) } # fix ConvertFrom-Json flattening single element in PWSH 7

        # fill in only valid state
        $slot = Copy-BlueGreenDeploySlot $jsState[0]
    } else {
        # We have no prior deploy-state; use initial value instead

        $slot = $DeploySlotInitValue
    }

    ConvertTo-Json -Depth 5 -Compress (@( $slot ))
}

# Copy-BlueGreenDeployState
# ------------------------
function Copy-BlueGreenDeployState {
    param(
        [Parameter(Mandatory = $true)]
        $DeployState
    )

    # Always force an array, even with wonky PowerShell scalar deconversion
    # when array size = 1.
    if ($DeployState.Count -eq 0) {
        return @()
    } elseif ($DeployState.Count -eq 1) {
        $state = @( $true )
    } else {
        $state = 1..$DeployState.Count | ForEach-Object { $true }
    }

    for ($i = 0; $i -lt $DeployState.Count; $i++) {
        $state[$i] = Copy-BlueGreenDeploySlot $DeployState[$i]
    }

    ConvertTo-Json -Depth 5 -Compress $state
}

# Set-BlueGreenDeployState
# ------------------------
function Set-BlueGreenDeployState {
    param (
        [Parameter(Mandatory = $true)]
        $ParentPath,
        [Parameter(Mandatory = $true)]
        $DeployState
    )
    if (!(Test-Path -Path "$ParentPath")) {
        New-Item -Path $ParentPath -ItemType Directory | Out-Null
    }
    if ($null -eq $DeployState.lastepochms) {
        throw "Null 'lastepochms' deploy state"
    }
    if ($null -eq $DeployState.reserved) {
        throw "Null 'reserved' deploy state"
    }
    $absDeployStateJson = Join-Path $ParentPath -ChildPath $DeployStateJson
    if (Test-Path "$absDeployStateJson") {
        Copy-Item "$absDeployStateJson" -Destination "$absDeployStateJson.bak" -Force
    }

    # Convert array of PSCustomObject into JSON array.
    # Always force an array, even with wonky PowerShell scalar deconversion
    # when array size = 1.
    if ($DeployState.Count -eq 0) {
        $Str = "[]"
    } else {
        if ($DeployState.Count -eq 1) {
            $arr = @( $true )
        } else {
            $arr = 1..$DeployState.Count | ForEach-Object { $true }
        }
        for ($i = 0; $i -lt $DeployState.Count; $i++) {
            $arr[$i] = Copy-BlueGreenDeploySlot $DeployState[$i]
        }
        $Str = ConvertTo-Json -Depth 5 ($arr)
    }

    [System.IO.File]::WriteAllText("$absDeployStateJson.tmp", $Str, $Utf8NoBomEncoding)
    if (Test-Path "$absDeployStateJson") {
        Remove-Item "$absDeployStateJson" -Force
    }
    Rename-Item "$absDeployStateJson.tmp" "$DeployStateJson" -Force
}

# Step-BlueGreenDeploySlotDryRun
#
# Do a dry-run of a move to the next deployment slot. Returns
# a PowerShell object of form:
#
#    @{
#       "chosenSlotIdx" = ...[int];
#       "stateAfterUpdate" = ...[PSCustomObject]
#    }
# or will throw an exception if there is no deployment slot.
#
# This is a pure function (no side-effects).
function Step-BlueGreenDeploySlotDryRun {
    param (
        [Parameter(Mandatory = $true)]
        $DeploymentId,
        [Parameter(Mandatory = $true)]
        $ImmutableDeployState,
        [Parameter(Mandatory = $true)]
        $CurrentEpochMs
    )
    $state = ConvertFrom-Json (Copy-BlueGreenDeployState $ImmutableDeployState)
    if (-not ($state -is [array])) { $state = @( $state ) } # fix ConvertFrom-Json flattening single element in PWSH 7

    # use what we picked (which is an indirect reference to $state)
    $state[0].lastepochms = $CurrentEpochMs
    $state[0].id = $DeploymentId
    $state[0].success = $false

    # give slot back to caller
    @{ "chosenSlotIdx" = 0; "stateAfterUpdate" = $state }
}

# Step-BlueGreenDeploySlot
#
# Move to the next available deployment slot.
function Step-BlueGreenDeploySlot {
    param (
        [Parameter(Mandatory = $true)]
        $ParentPath,
        [Parameter(Mandatory = $true)]
        $DeploymentId,
        [Parameter(Mandatory = $true)]
        $DeployState
    )
    $currentepochms = Get-CurrentEpochMillis
    $next = Step-BlueGreenDeploySlotDryRun `
        -DeploymentId $DeploymentId `
        -ImmutableDeployState $DeployState `
        -CurrentEpochMs $currentepochms
    Set-BlueGreenDeployState -ParentPath $ParentPath -DeployState $next.stateAfterUpdate
    Write-Output $next.chosenSlotIdx
}

# Remove-DirectoryFully
#
# Remove a directory and all of its contents. Unlike Remove-Item -Recurse this will work in
# all versions of Windows.
# Will not fail if the path does not already exist.
#
# This behaves like the DKML Install API's [uninstall_directory] function that
# tells you and waits for you to close any open files.
function Remove-DirectoryFully {
    param(
        [Parameter(Mandatory = $true)] $Path,
        [int] $WaitSecondsIfStuck = -1,
        [string] $StuckMessageFormatInfo = "Stuck during removal of directory after {0} seconds.`n`t{1}",
        [string] $StuckMessageFormatCritical = "`t{1}"
    )

    if (Test-Path -Path $Path) {
        # On Windows 11 Build 22478.1012 with Powershell 5.1, even though `Remove-Item -Force`
        # should delete ReadOnly files (which are typical for Opam installed executables), it
        # fails with: "You do not have sufficient access rights to perform this operation".
        # Instead we have to remove the ReadOnly attribute.
        $firstFailure = $null
        Get-ChildItem $Path -Recurse -Force | Where-Object { $_.Attributes -band [io.fileattributes]::ReadOnly } | ForEach-Object {
            # $_ is now the file object
            $currentFile = $_
            try {
                Set-ItemProperty -Path $_.FullName -Name Attributes -Value ($_.Attributes -band (-bnot [io.fileattributes]::ReadOnly))
            } catch {
                # Handle drives that do not support setting attributes, even though we are not adding any!
                # https://github.com/diskuv/dkml-installer-ocaml/issues/38.
                # $_ is now the error object
                if ($null -eq $firstFailure) {
                    $firstFailure = (
                        "The drive containing $Path does not support setting attributes on some or all of its files. " +
                        "Here is one file that could not be set: $($currentFile.FullName). $_")
                }
            }
        }
        if ($firstFailure) {
            Write-Warning "$firstFailure"
        }

        # We want to do `Remove-Item -Path $Path -Recurse -Force`. However the docs for Remove-Item
        # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/remove-item?view=powershell-7.2#parameters
        # say:
        # > The Recurse parameter might not delete all subfolders or all child items. This is a known issue.
        # > ! Note
        # > This behavior was fixed in Windows versions 1909 and newer.
        # So we use the Command Prompt instead (with COMSPEC so that MSYS2 "cmd" does not get run).
        $timer = [Diagnostics.Stopwatch]::StartNew()
        if ("$env:COMSPEC" -eq "") {
            # not Windows

            # TODO: We have no "STUCK" logic to check if process needs to be stopped!
            # On Linux systems we can remove the file while it is being
            # used... the inode lives on.
            # Don't know if the same goes for macOS.

            Remove-Item -Path $Path -Recurse -Force
            $success = $true
        } else {
            # Windows

            # We have "STUCK" logic where ... if a file can't be deleted
            # because it was in use by another porcess ... we say so and
            # wait. This logic only occurs when $WaitSecondsIfStuck >= 0.

            # Sigh ... we won't get any error codes from `rd`. But we will get:
            #   C:\Users\beckf\AppData\Local\Temp\f46f0508-df03-40e8-8661-728f1be41647\UninstallBlueGreenDeploy2\0\cmd.exe - Access is denied.
            # So any output on the error console indicates a problem
            $success = $false
            $stderr = New-TemporaryFile
            do {
                Start-Process `
                    -Wait `
                    -NoNewWindow `
                    -RedirectStandardError $stderr `
                    -FilePath "$env:COMSPEC" `
                    -ArgumentList @("/c", "rd /s /q `"$Path`"")
                $errlen = (Get-Item -Path $stderr).Length
                if ($errlen -eq 0) {
                    # no errors means success
                    $success = $true
                    break
                }

                # If not explicit that we want to wait, immediately exit
                # and say what the problem was.
                if ($WaitSecondsIfStuck -lt 0) {
                    throw (Get-Content $stderr)
                }

                # We are waiting until unstuck!
                $sofar = $timer.elapsed.totalseconds
                #   don't overwhelm display or PowerShell if lots of errors
                $errcontent = Get-Content -TotalCount 5 $stderr | Out-String
		#   Write-Information is missing -NoNewline and -ForegroundColor
		#   so we use Write-Host
                Write-Host ($StuckMessageFormatInfo -f @($sofar, $errcontent)) -NoNewline
                Write-Host ($StuckMessageFormatCritical -f @($sofar, $errcontent)) -ForegroundColor Red -BackgroundColor Black
                Start-Sleep -Seconds 5
            } while ($timer.elapsed.totalseconds -lt $WaitSecondsIfStuck)
            Remove-Item $stderr
        }
        if (!$success -and ($WaitSecondsIfStuck -ge 0)) {
            throw "Could not remove the directory $Path after waiting $WaitSecondsIfStuck seconds"
        }
    }
}
Export-ModuleMember -Function Remove-DirectoryFully

# New-CleanDirectory
#
# Clean the directory of all of its content. Make it if it doesn't already exist.
function New-CleanDirectory {
    param( [Parameter(Mandatory = $true)] $Path )

    Remove-DirectoryFully -Path $Path `
        -WaitSecondsIfStuck 300 `
        -StuckMessageFormatInfo "Stuck during uninstallation of $Path.`nWaited already {0,5:N1} seconds; will wait at most 300 seconds (5 minutes).`n" `
        -StuckMessageFormatCritical "Please stop using the program, or manually remove the file(s):`t{1}`n"
    New-Item -Path $Path -ItemType Directory | Out-Null
}
Export-ModuleMember -Function New-CleanDirectory

function Get-CurrentEpochMillis {
    [long]$timestamp = [math]::Round((([datetime]::UtcNow) - (Get-Date -Date '1/1/1970')).TotalMilliseconds)
    $timestamp
}
Export-ModuleMember -Function Get-CurrentEpochMillis

function Get-CurrentTimestamp {
    (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffK")
}
Export-ModuleMember -Function Get-CurrentTimestamp

if ((Get-Command New-Object).Parameters.Keys.Contains("ComObject")) {
    # Only Windows has DOS 8.3 names
    $fsobject = New-Object -ComObject Scripting.FileSystemObject
} else {
    $fsobject = $null
}
function Get-Dos83ShortName {
    param(
        [Parameter(Mandatory=$true)]
        $Path
    )
    if ($null -ne $fsobject -and (Test-Path -Path $Path -PathType Container)) {
        $output = $fsobject.GetFolder($Path)
        $output.ShortPath
    } elseif ($null -ne $fsobject -and (Test-Path -Path $Path -PathType Leaf)) {
        $output = $fsobject.GetFile($Path)
        $output.ShortPath
    } else {
        $Path
    }
}
Export-ModuleMember -Function Get-Dos83ShortName
