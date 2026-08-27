using namespace System.Collections.Generic


# ------ File management functions ------

$Verbose = $false
function Write-Log($Message)
{
    if (-not $Verbose) {return}
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp | $Message" | Add-Content -Path $LogPath
}

function New-FileWithParent($Directory, $FileName) 
{
    if (-not (Test-Path $Directory))
    {New-Item -ItemType Directory -Path $Directory | Out-Null}
    return Join-Path $Directory $FileName
}


# ------ Configurable variables ------

$StateDirectory = "$PSScriptRoot"
$StatePath = New-FileWithParent -Directory $StateDirectory -FileName "State.json"
$LogDirectory = Join-Path "$PSScriptRoot" "Logs"
$LogPath = New-FileWithParent -Directory $LogDirectory -FileName "SteamTimeLimit.log"

$ErrorActionPreference = "Stop"


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

    if ($null -eq $State)
    {$Playtime = [TimeSpan]::Zero}
    else 
    {
        $Now = Get-Date

        $ResetInterval = [TimeSpan]::FromTicks($State.ResetInterval)
        if ($null -eq $ResetInterval || 0 -eq $ResetInterval.Ticks) {$ResetInterval = New-TimeSpan -Hours 24}

        # Saved LastResetTime is only needed once to determine if ResetInterval time passed during offtime
        if (($Now - $State.LastResetTime) -ge $ResetInterval)
        {$Playtime = [TimeSpan]::Zero}
        else 
        {$Playtime = [TimeSpan]::FromTicks($State.PlayTime)}
        if ($null -eq $Playtime) {$Playtime = [TimeSpan]::Zero}
        
        $PlaytimeLimit = $State.PlaytimeLimit
        if ($null -eq $PlaytimeLimit) {$PlaytimeLimit = [TimeSpan]::Zero}
    }

    # Recalculate LastResetTime in case of ResetInterval change
    $LastResetTime = Get-LastResetStart $ResetInterval

    return [PSCustomObject]@{
        Playtime = $Playtime
        PlaytimeLimit = $PlaytimeLimit
        LastResetTime = $LastResetTime
        ResetInterval = $ResetInterval
    }
}

function Save-State($StatePath, $State) 
{
    $StateJson = $State | ConvertTo-Json
    $StateJson | Set-Content -Path $StatePath
}


# ------ Main script ------


try 
{
    $GamesInfo = Get-AllGamesInfo
    $State = Restore-State $StatePath

    Write-Log "Restored playtime: $($State.Playtime)"
    Write-Log "Restored playtime limit: $($State.PlaytimeLimit)"
    Write-Log "Restored last reset time: $($State.LastResetTime)"
    Write-Log "Restored reset interval: $($State.ResetInterval)"

    $PreviousTime = Get-Date
    $Cycles = 0

    while ($true) 
    {
        $Cycles++
        $CurrentTime = Get-Date

        Write-Log "------------------------------------------------"
        Write-Log "Playtime: $($State.Playtime)"

        # Test if games are running, increase playtime if yes
        if ($State.Playtime -lt $State.PlaytimeLimit)
        {
            $Elapsed = $CurrentTime - $PreviousTime
            $PreviousTime = $CurrentTime

            if (Test-AnyGameRunning -GamesInfo $GamesInfo) 
            {
                $State.Playtime += $Elapsed
                Write-Log "Games are running"
            }
            else 
            {Write-Log "Games aren't running"}
        }
        # Block games after playtime limit is passed
        else
        {
            Write-Log "Playtime limit reached"
            if (($Cycles % 4) -eq 0)
            {Stop-AnyGameRunning -GamesInfo $GamesInfo}
        }

        # Reset playtime after specified interval
        $TimeSinceLastReset = $CurrentTime - $State.LastResetTime
        $TimeUntilNextReset = -($TimeSinceLastReset - $State.ResetInterval)
        Write-Log "Time since last reset: $TimeSinceLastReset"
        Write-Log "Time until next reset: $TimeUntilNextReset"

        if ($TimeSinceLastReset -ge $State.ResetInterval) 
        {
            Write-Log "Playtime reset"
            $State.Playtime = [TimeSpan]::Zero
            $State.LastResetTime = Get-LastResetStart $State.ResetInterval
        }

        # Save state as JSON
        if (($Cycles % 2) -eq 0) 
        {
            $SaveState = [PSCustomObject]@{
                Playtime = $State.Playtime.Ticks # Powershell can't directly restore TimeSpan from json
                PlaytimeLimit = $State.PlaytimeLimit.Ticks
                LastResetTime = $State.LastResetTime
                ResetInterval = $State.ResetInterval.Ticks
            }
            Save-State -StatePath $StatePath -State $SaveState
        }

        Start-Sleep 15
    }
}
catch
{
    Write-Log "!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!"
    Write-Log "$($_.Exception.Message)"
    throw
}

