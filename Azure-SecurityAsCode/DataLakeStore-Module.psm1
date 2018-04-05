#Import Helpers
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here/SecurityAsCode-Helpers.ps1"


function _Get-DLS-Folder-AccessEntries {
    param
    (
        [string] $dlsName,
        [string] $dlsPath
    )

    Write-Host "Processing Access Entries for [$($dlsPath)]"

    $accessEntries = "$(az dls fs access show --account $dlsName --path "$($dlsPath)")" 
    $accessEntries = ConvertFrom-Json $accessEntries
    $aeArray = @()
    
    foreach ($a in $accessEntries.entries) {
        $def = $false
        $type = ""
        $username = ""
        $rights = ""

        if ($a.Contains("default")) {
            $def = $true
        }

        if ($a.Contains("user")) {
            $type = "user"
        }
        if ($a.Contains("group")) {
            $type = "group"
        }
        if ($a.Contains("other")) {
            $type = "other"
        }

        $rightsArray = $a.split(':')
        if ($rightsArray.length -eq 4) {
            #includes default
            $username = $rightsArray[2]
            $rights = $rightsArray[3]
        }
        if ($rightsArray.length -eq 3) {
            #includes default
            $username = $rightsArray[1]
            $rights = $rightsArray[2]
        }
        

        if ($username -ne "") {
        $aeDict = [ordered]@{
            userprincipal = $username
            type = $type
            isDefault = $def
            permissions = $rights
        }

        $aeArray += $aeDict
    }
        
    }
    

    return $aeArray
}

function _Get-DLS-Folder-Structure {
    param
    (
        [string] $dlsPath,
        $folderArray
    )

    Write-Host "Processing Folders"
    $folders = "$(az dls fs list --account $dls.Name --path "$($dlspath)")" 
    $folders = ConvertFrom-Json $folders
    
    if ($dlsPath -eq "/") {
        #also the root folder
        $folderDict = [ordered]@{folderPath = "/"}
        $folderArray += $folderDict
        $aeArray = _Get-DLS-Folder-AccessEntries -dlsName $dls.Name -dlsPath "/"
        $folderDict.Add('access', $aeArray)

    }

    foreach ($f in $folders) {
        if ($f.type -eq "DIRECTORY") {
            Write-Host "Processing Folder [$($f.name)]"
            $folderDict = [ordered]@{folderPath = $f.name}
            $folderArray += $folderDict
            $folderArray = _Get-DLS-Folder-Structure -dlsPath "/$($f.name)" -folderArray $folderArray
            $aeArray = _Get-DLS-Folder-AccessEntries -dlsName $dls.Name -dlsPath $dlsPath
            $folderDict.Add('access', $aeArray)
    
        }
    }

    return $folderArray
}



function Get-Asac-DataLakeStore {
    param
    (
        [string] $datalakeStoreAccount,
        [string] $outputPath
    )

    $outputPath = _Get-Asac-OutputPath -outputPath $outputPath


    $dls = Invoke-Asac-AzCommandLine -azCommandLine "az dls account show --account $($datalakeStoreAccount) --output json"

    $dlsDict = [ordered]@{name = $dls.name
        resourcegroupname = $dls.resourceGroup
    }

    $folderArray = @()
    $folderArray = _Get-DLS-Folder-Structure -dlsPath "/" -folderArray $folderArray

    $dlsDict.Add('folders', $folderArray)

    $path = Join-Path $outputPath -ChildPath "dls"
    New-Item $path -Force -ItemType Directory | Out-Null
    $filePath = Join-Path $path -ChildPath "dls.$($dls.name).yml"
    Write-Host $filePath
    ConvertTo-YAML $dlsDict > $filePath
}



Export-ModuleMember -Function Get-Asac-DataLakeStore