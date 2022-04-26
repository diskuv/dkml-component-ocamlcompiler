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
