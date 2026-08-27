param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [object[]]$Arguments
)

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

function Set-PlaytimeLimit
{
    param(
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Hours,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Minutes,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Seconds
    )

    $Limit = New-TimeSpan `
        -Hours $Hours `
        -Minutes $Minutes `
        -Seconds $Seconds

    return $Limit
}


$PlaytimeLimit = [TimeSpan]::Zero

switch ($Command)
{
    "Get-PlaytimeLimit"
    {"$PlaytimeLimit"}

    "Set-PlaytimeLimit"
    {
        $Parameters = ConvertTo-ParameterHashtable $Arguments
        $PlaytimeLimit = Set-PlaytimeLimit @Parameters
        "Setting playtime limit to $PlaytimeLimit"
    }

    default
    {throw "Unknown command '$Command'"}
}
