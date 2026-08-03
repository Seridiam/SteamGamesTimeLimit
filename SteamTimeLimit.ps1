using namespace System.Collections.Generic

function Get-LineValue($Line, $Header) 
{
    if ($Line -match "`"$Header`"\s+`"([^`"]+)`"")
    {return $Matches[1]}
    return $null;
}

function Get-HeaderValue($FileContent, $Header) 
{
    foreach ($Line in $FileContent)
    {
        $Value = Get-LineValue -Line $Line -Header $Header
        if ($null -ne $Value)
        {return $Value}
    }
}

function Get-GameInfo($ManifestFile) 
{
    $Manifest = Get-Content $ManifestFile.FullName

    $Name = Get-HeaderValue -FileContent $Manifest -Header 'name'
    $InstallDir = Get-HeaderValue -FileContent $Manifest -Header 'installdir'
    
    if (-not $Name -or -not $InstallDir)
    {throw "Manifest could not be parsed. No line including specified headers found"}

    $ManifestParentDir = $ManifestFile.DirectoryName
    $CommonFolder = Join-Path $ManifestParentDir "common"
    $FullPath = Join-Path $CommonFolder $InstallDir
    $Executables = Get-ChildItem $FullPath -Filter *.exe -Recurse

    return [PSCustomObject]@{
        Name = $Name
        InstallDir = $InstallDir
        FullPath = $FullPath
        Executables = $Executables
    }
}

function Get-AllGamesInfo() 
{
    $LibrariesFile = Get-ChildItem "C:\Program Files (x86)\Steam\steamapps" -Filter "libraryfolders.vdf"
    $Libraries = Get-Content $LibrariesFile.FullName
    $GamesInfo = [List[psobject]]::new()

    foreach ($Line in $Libraries) 
    {
        $LibraryPath = Get-LineValue -Line $Line -Header "path"
        if ($null -ne $LibraryPath)
        {
            $SteamAppsDir = Join-Path $LibraryPath "steamapps"
            $ManifestFiles = Get-ChildItem $SteamAppsDir -Filter "appmanifest_*.acf"

            foreach ($ManifestFile in $ManifestFiles)
            {
                $GameInfo = Get-GameInfo -ManifestFile $ManifestFile
                $GamesInfo.Add($GameInfo)
            }
        }
    }

    return $GamesInfo
}

function Test-GameRunning($GameInfo) 
{
    # Check each executable under a game's directory in order to skip guessing names
    # since extra executables typically don't run without the main one
    foreach ($Executable in $GameInfo.Executables) 
    {
        if (Get-Process $Executable.BaseName -ErrorAction SilentlyContinue) 
        {return $true}
    }
    return $false
}

function Test-AnyGameRunning($GamesInfo) 
{
    foreach ($GameInfo in $GamesInfo)
    {
        $IsRunning = Test-GameRunning -GameInfo $GameInfo
        if ($IsRunning) 
        {return $true}
    }
    return $false
}

function Stop-AnyGameRunning($GamesInfo) 
{
    foreach ($GameInfo in $GamesInfo)
    {
        $IsRunning = Test-GameRunning -GameInfo $GameInfo
        if ($IsRunning) 
        {
            foreach ($Executable in $GameInfo.Executables)
            {Stop-Process -Name $Executable.BaseName -ErrorAction SilentlyContinue}
        }
    }
}


# ------ Main script ------

$GamesInfo = Get-AllGamesInfo

$Playtime = [TimeSpan]::Zero
$PreviousTime = Get-Date
$Limit = New-TimeSpan -Minutes 2

while ($true) 
{
    if ($Playtime -lt $Limit)
    {
        $CurrentTime = Get-Date
        $Elapsed = $CurrentTime - $PreviousTime
        $PreviousTime = $CurrentTime

        if (Test-AnyGameRunning -GamesInfo $GamesInfo) 
        {
            $PlayTime += $Elapsed
            "Games are running"
        }
        else 
        {"Games aren't running"}
    }
    else
    {
        "Limit reached"
        Stop-AnyGameRunning -GamesInfo $GamesInfo
        Start-Sleep 20
    }

    Start-Sleep 10
}

