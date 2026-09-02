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


# ------ Configurable variables ------


$PipeName = "SteamTimeLimit"


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
    { $_ -in @("Set-PlaytimeLimit", "Set-ResetInterval") }
    {
        $Parameters = ConvertTo-ParameterHashtable $Arguments
        $TimeSpan = New-TimeSpanFromArguments @Parameters

        $Response = Send-Request @{
            Command = $Command
            Ticks = $TimeSpan.Ticks
        }
    }

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
