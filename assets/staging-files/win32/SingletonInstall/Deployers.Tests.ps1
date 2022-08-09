# Upgrade Pester to be >= 4.6.0 using Administrator PowerShell:
#   Install-Module -Name Pester -Force -SkipPublisherCheck

# In VSCode just click "Run tests" below

BeforeAll { 
    $dsc = [System.IO.Path]::DirectorySeparatorChar
    if (Get-Module Deployers) {
        Write-Host "Removing old Deployers module from PowerShell session"
        Remove-Module Deployers
    }
    $env:PSModulePath += "$([System.IO.Path]::PathSeparator)${PSCommandPath}${dsc}.."
    Import-Module Deployers
}

Describe 'StopBlueGreenDeploy' {
    
    # Regression test R001. Because old code (pre May 2022; pre DKML 0.4.0) used to flatten an array of one
    # element to simply the one element (the surrounding array was gone), we should cover reading that
    # bad input. The root cause was that PowerShell 7 will remove the surrounding array if it is piped
    # to ConvertTo-Json rather than given as an argument to ConvertTo-Json.
    It 'Given no existing state, when no success, it does not error' {
        $DeploymentId = "testdeploymentid"
        $TestDir = "$TestDrive${dsc}StopBlueGreenDeploy1"
        New-CleanDirectory -Path $TestDir
        Start-BlueGreenDeploy -ParentPath $TestDir -DeploymentId $DeploymentId -Debug
        Stop-BlueGreenDeploy -ParentPath $TestDir -DeploymentId "testdeploymentid" -Success:$False -Debug
    }

    # Regression test R002. Same as R001 except makes sure reads a buggy state json.
    It 'Given real state with buggy+missing array, when no success, it does not error' {
        $DeploymentId = "testdeploymentid"
        $TestDir = "$TestDrive${dsc}StopBlueGreenDeploy2"
        New-CleanDirectory -Path $TestDir
        Set-Content -Path "$TestDir${dsc}deploy-state-v1.json" '
        {
            "success":  true,
            "lastepochms":  1650060359153,
            "id":  "v-0.4.0-prerel18;ocaml-4.12.1;opam-2.1.0.msys2.12;ninja-1.10.2;cmake-3.21.1;jq-1.6;inotify-36d18f3dfe042b21d7136a1479f08f0d8e30e2f9;cygwin-349E3ED1821A077C;msys2-D549335C67946BEB;docker-B01818D2C9F9286A;pkgs-FDD450FB7CBC43C3;bins-B528D33838E7C749;stubs-4E6958B274EAB043;toplevels-80941AA1C64DA259",
            "reserved":  false
        }
        '        
        Start-BlueGreenDeploy -ParentPath $TestDir -DeploymentId $DeploymentId -Debug
        Stop-BlueGreenDeploy -ParentPath $TestDir -DeploymentId "testdeploymentid" -Success:$False -Debug
    }
}

Describe 'UninstallBlueGreenDeploy' {
    It "Given no existing state, when uninstall, it does not error" {
        $TestDir = "$TestDrive${dsc}UninstallBlueGreenDeploy1"
        New-CleanDirectory -Path $TestDir
        Uninstall-BlueGreenDeploy -ParentPath $TestDir -Debug

        if (!(Test-Path "$TestDir/deploy-state-v1.json")) {
            throw "Expected deploy-state-v1.json to be created"
        }
    }

    It "Given program running, when uninstall, it waits for program to stop running" {
        if ($env:COMSPEC) {
            $TestDir = "$TestDrive${dsc}UninstallBlueGreenDeploy2"
            New-CleanDirectory -Path $TestDir

            # Start and finish a deployment successfully. During the deployment
            # we'll copy cmd.exe (something present on all Windows machines, including
            # CI) to mimic a real deployment that would contain ocamlrun.exe,
            # ocamllsp.exe, dune.exe, etc.
            $DeploymentId = "testdeploymentid"
            $DeployPath = Start-BlueGreenDeploy -ParentPath $TestDir -DeploymentId $DeploymentId -Debug
            $DeployedCmdExe = Join-Path -Path $DeployPath -ChildPath "cmd.exe"
            Copy-Item -Path "$env:COMSPEC" -Destination $DeployedCmdExe
            Stop-BlueGreenDeploy -ParentPath $TestDir -DeploymentId $DeploymentId -Success -Debug

            # Use our deployed cmd.exe to run for 15 seconds. Ideally we would use
            # 'timeout' but that will not work in a CI scenario where there is no
            # standard input. Instead we use ping. Inspired by
            # https://stackoverflow.com/questions/1672338/how-to-sleep-for-five-seconds-in-a-batch-file-cmd
            Start-Process -FilePath $DeployedCmdExe -ArgumentList @("/c", "ping 127.0.0.1 -n 15")

            # Wait 1 second to ensure that the background "ping" job is running
            Start-Sleep -Seconds 1
            
            Uninstall-BlueGreenDeploy -ParentPath $TestDir -Debug
            Write-Host "Finished uninstall with no error thrown"
        } else {
            Write-Host "Can't do anything on a non-Windows host"
        }
    }
}