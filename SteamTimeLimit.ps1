using namespace System.Collections.Generic


# ------ Configurable variables ------


$PlaytimeLimit = New-TimeSpan -Minutes 60
$ResetInterval = New-TimeSpan -Minutes 360

$StatePath = "$PSScriptRoot\State.json"
$Verbose = $true


# ------ Application management functions ------

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


# ------ Time management functions ------

function Get-LastResetStart($ResetInterval)
{
    $Now = Get-Date

    [long]$RoundedTicks =
        [Math]::Floor($Now.Ticks / $ResetInterval.Ticks) *
        $ResetInterval.Ticks

    return [DateTime]::new($RoundedTicks)
}

function Restore-State($StatePath)
{
    if (Test-Path $StatePath)
    {
        try
        {$State = Get-Content $StatePath -Raw | ConvertFrom-Json}
        catch
        {$State = $null}
    }
    else 
    {$State = $null}

    $Now = Get-Date
    # Saved LastResetTime is only needed once to determine if ResetInterval time passed during offtime
    if ( ($null -eq $State) -or (($Now - $State.LastResetTime) -ge $ResetInterval) )
    {$Playtime = [TimeSpan]::Zero}
    else 
    {$Playtime = [TimeSpan]::FromTicks($State.PlayTime)}
    if ($null -eq $Playtime) {$Playtime = [TimeSpan]::Zero}

    # Recalculate LastResetTime in case of ResetInterval change
    $LastResetTime = Get-LastResetStart $ResetInterval

    return [PSCustomObject]@{
        Playtime = $Playtime
        LastResetTime = $LastResetTime
    }
}

function Save-State($StatePath, $State) 
{
    $StateJson = $State | ConvertTo-Json
    $StateJson | Set-Content -Path $StatePath
}


# ------ Main script ------


$GamesInfo = Get-AllGamesInfo

$RestoredState = Restore-State $StatePath
$Playtime = $RestoredState.Playtime
$LastResetTime = $RestoredState.LastResetTime

if ($Verbose) 
{
    "Restored playtime: $Playtime"
    "Restored last reset time: $LastResetTime"
}

$PreviousTime = Get-Date
$Cycles = 0

while ($true) 
{
    $Cycles++
    $CurrentTime = Get-Date

    if ($Verbose) 
    {
        "------------------------------------------------"
        "Playtime: $Playtime"
    }

    # Test if games are running, increase playtime if yes
    if ($Playtime -lt $PlaytimeLimit)
    {
        $Elapsed = $CurrentTime - $PreviousTime
        $PreviousTime = $CurrentTime

        if (Test-AnyGameRunning -GamesInfo $GamesInfo) 
        {
            $Playtime += $Elapsed
            if ($Verbose) {"Games are running"}
        }
        else 
        {if ($Verbose) {"Games aren't running"}}
    }
    # Block games after playtime limit is passed
    else
    {
        if ($Verbose) {"Playtime limit reached"}
        if (($Cycles % 4) -eq 0)
        {Stop-AnyGameRunning -GamesInfo $GamesInfo}
    }

    # Reset playtime after specified interval
    $TimeSinceLastReset = $CurrentTime - $LastResetTime
    $TimeUntilNextReset = -($TimeSinceLastReset - $ResetInterval)
    if ($Verbose) {"Time since last reset: $TimeSinceLastReset"}
    if ($Verbose) {"Time until next reset: $TimeUntilNextReset"}

    if ($TimeSinceLastReset -ge $ResetInterval) 
    {
        if ($Verbose) {"Playtime reset"}
        $Playtime = [TimeSpan]::Zero
        $LastResetTime = Get-LastResetStart $ResetInterval
    }

    # Save state as JSON
    if (($Cycles % 2) -eq 0) 
    {
        $SaveState = [PSCustomObject]@{
            Playtime = $Playtime.Ticks # Powershell can't directly restore TimeSpan from json
            LastResetTime = $LastResetTime
        }
        Save-State -StatePath $StatePath -State $SaveState
    }

    Start-Sleep 15
}

