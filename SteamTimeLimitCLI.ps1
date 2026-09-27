using namespace System.IO
using namespace System.IO.Pipes
using namespace System.Collections.Generic
using namespace System.Text

param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [object[]]$Arguments
)


# ------ File management ------

function Write-Log($Message)
{
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "CLI | $Timestamp | $Message" | Add-Content -Path $LogPath
}

function New-FileWithParent($Directory, $FileName) 
{
    if (-not (Test-Path $Directory))
    {New-Item -ItemType Directory -Path $Directory | Out-Null}
    return Join-Path $Directory $FileName
}


# ------ Configurable variables ------

$ErrorActionPreference = "Stop"

$LogDirectory = Join-Path "$PSScriptRoot" "Logs"
$LogPath = New-FileWithParent -Directory $LogDirectory -FileName "SteamTimeLimit.log"
$BackgroundScriptDirectory = "$PSScriptRoot"
$BackgroundScriptPath = New-FileWithParent -Directory $BackgroundScriptDirectory -FileName "SteamTimeLimit.ps1"

$PipeName = "SteamTimeLimit"
$TaskName = "SteamTimeLimit"


# ------ CLI request handling ------

function Send-Request($Request)
{
    $Pipe = [NamedPipeClientStream]::new(
        ".",
        $PipeName,
        [PipeDirection]::InOut
    )

    try
    {
        $Pipe.Connect(1000)

        $Reader = [StreamReader]::new($Pipe)
        $Writer = [StreamWriter]::new($Pipe)
        $Writer.AutoFlush = $true

        $RequestJson = $Request | ConvertTo-Json -Compress
        $Writer.WriteLine($RequestJson)

        $ResponseJson = $Reader.ReadLine()
        return $ResponseJson | ConvertFrom-Json
    }
    finally
    {
        $Pipe.Dispose()
    }
}

# ------ Command parameter handling ------

function ConvertTo-ParameterHashtable($Arguments)
{
    $Parameters = @{}

    for ($i = 0; $i -lt $Arguments.Count; $i++)
    {
        $Name = $Arguments[$i]

        if (-not $Name.StartsWith("-"))
        {throw "Expected parameter name, got '$Name'"}

        $Name = $Name.TrimStart("-")

        if ($i + 1 -ge $Arguments.Count)
        {throw "Parameter '-$Name' is missing a value"}

        $Value = $Arguments[$i + 1]
        $i++

        $Parameters[$Name] = $Value
    }

    return $Parameters
}

function New-TimeSpanFromArguments
{
    param(
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Hours,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Minutes,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Seconds
    )

    $PlaytimeLimit = New-TimeSpan `
        -Hours $Hours `
        -Minutes $Minutes `
        -Seconds $Seconds

    return $PlaytimeLimit
}


# ------ Main script ------


switch ($Command)
{
    # Install and manage background script
    "Install"
    {
        try
        {
            $PwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
            $ConhostPath = (Get-Command conhost.exe).Source

            # PowerShell execution
            $Action = New-ScheduledTaskAction `
                -Execute $ConhostPath `
                -Argument "--headless `"$PwshPath`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$BackgroundScriptPath`""

            # Run when the user logs oncd
            $Trigger = New-ScheduledTaskTrigger `
                -AtLogOn

            # Task settings
            $Settings = New-ScheduledTaskSettingsSet `
                -ExecutionTimeLimit (New-TimeSpan -Days 3650) `
                -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries
            
            $UserId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

            # Run as the current user
            $Principal = New-ScheduledTaskPrincipal `
                -UserId $UserId `
                -LogonType Interactive `
                -RunLevel Limited

            # Register the task
            Register-ScheduledTask `
                -TaskName $TaskName `
                -Action $Action `
                -Trigger $Trigger `
                -Settings $Settings `
                -Principal $Principal `
                -Description "SteamTimeLimit background worker" `
                -Force `
                -ErrorAction Stop

            $Response = [PSCustomObject]@{
                Success = $true
                Value = "SteamTimeLimit has been installed"
            }
        }
        catch
        {
            $Response = [PSCustomObject]@{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
    "Uninstall"
    {
        Unregister-ScheduledTask `
        -TaskName $TaskName `
        -Confirm:$false `
        -ErrorAction Stop

        $Response = [PSCustomObject]@{
            Success = $true
            Value = "SteamTimeLimit has been uninstalled"
        }
    }
    "Enable-StartOnLogon"
    {
        Enable-ScheduledTask `
        -TaskName $TaskName `
        -ErrorAction Stop

        $Response = [PSCustomObject]@{
            Success = $true
            Value = "SteamTimeLimit now starts on logon"
        }
    }
    "Disable-StartOnLogon"
    {
        Disable-ScheduledTask `
        -TaskName $TaskName `
        -ErrorAction Stop

        $Response = [PSCustomObject]@{
            Success = $true
            Value = "SteamTimeLimit doesn't start on logon anymore"
        }
    }
    "Start"
    {
        Start-ScheduledTask `
        -TaskName $TaskName `
        -ErrorAction Stop

        $Response = [PSCustomObject]@{
            Success = $true
            Value = "SteamTimeLimit is running! Remember to also run 'Enable-StartOnLogon' for the tool to automatically start after logging on"
        }
    }
    "Stop"
    {
        Stop-ScheduledTask `
        -TaskName $TaskName `
        -ErrorAction Stop

        $Response = [PSCustomObject]@{
            Success = $true
            Value = "SteamTimeLimit is stopped. Also run 'Disable-StartOnLogon' to prevent it from starting again after next log on"
        }
    }
    "Get-Status" 
    {
        $Task = Get-ScheduledTask `
        -TaskName $TaskName `
        -ErrorAction SilentlyContinue

        $Status = "Status could not be resolved"
        if ($null -eq $Task) 
        {$Status = "SteamTimeLimit is not installed"}
        elseif ($Task.State -eq "Disabled") 
        {$Status = "SteamTimeLimit is disabled (won't start on logon)"}
        elseif ($Task.State -eq "Ready")
        {$Status = "SteamTimeLimit is enabled (starts on logon)."}
        elseif ($Task.State -eq "Running")
        {$Status = "SteamTimeLimit is running."}

        $Response = [PSCustomObject]@{
            Success = $true
            Value = $Status
        }
    }

    # Change values
    { $_ -in @("Set-PlaytimeLimit", "Set-ResetInterval") }
    {
        $Parameters = ConvertTo-ParameterHashtable $Arguments
        $TimeSpan = New-TimeSpanFromArguments @Parameters

        $Response = Send-Request @{
            Command = $Command
            Ticks = $TimeSpan.Ticks
        }
    }
    # Read values
    default
    {
        $Response = Send-Request @{
            Command = $Command
        }
    }
}

if (-not $Response.Success)
{throw $Response.Error}
$Response.Value
