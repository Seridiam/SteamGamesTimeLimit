$Limit = New-TimeSpan -Minutes 1
$ResetInterval = New-TimeSpan -Minutes 2



# ------ Main script ------

$StatePath = "$PSScriptRoot\State.json"

if (Test-Path $StatePath)
{
    try
    {$State = Get-Content $StatePath -Raw | ConvertFrom-Json}
    catch
    {$State = $null}
}
else 
{$State = $null}

$NewState = [PSCustomObject]@{
        PlayTime = [TimeSpan]::Zero
        LastResetTime = Get-LastResetStart $ResetInterval
    }

$LastResetTime = $NewState.LastResetTime

# Use saved LastResetTime to figure out if ResetInterval time passed in order to reset playtime
$Now = Get-Date
if ( ($null -eq $State) -or (($Now - $State.LastResetTime) -ge $ResetInterval) )
{$Playtime = $NewState.PlayTime}
else 
{$Playtime = [TimeSpan]::FromTicks($State.PlayTime)}
if ($null -eq $Playtime) {$Playtime = $NewState.PlayTime}

"Restored playtime: $Playtime"
"Restored last reset time: $LastResetTime"

$PreviousTime = Get-Date
$Cycles = 0

while ($true)
{
    $Cycles++

    $CurrentTime = Get-Date
    $Elapsed = $CurrentTime - $PreviousTime
    $PreviousTime = $CurrentTime

    $PlayTime += $Elapsed
    if ($PlayTime -ge $Limit) 
    {"Limit reached"} 

    # Reset playtime after specified interval
    $TimeSinceLastReset = $CurrentTime - $LastResetTime
    "Time since last reset: $TimeSinceLastReset"
    if ($TimeSinceLastReset -ge $ResetInterval) 
    {
        "Playtime reset"
        $Playtime = $NewState.PlayTime
        $LastResetTime = Get-LastResetStart $ResetInterval
    }

    # Save state as JSON
    if ($Cycles -ge 1) 
    {
        $Cycles = 0

        $State = [PSCustomObject]@{
            PlayTime = $PlayTime.Ticks # PowerShell can't restore TimeSpan from json
            LastResetTime = $LastResetTime
        }
        $StateJson = $State | ConvertTo-Json
        $StateJson | Set-Content -Path $StatePath
    }
    
    Start-Sleep 15
}
