using namespace System.IO
using namespace System.IO.Pipes
using namespace System.Collections.Generic
using namespace System.Text

param($State, $PipeName)
        
try
{
    $Pipe = [NamedPipeServerStream]::new(
        $PipeName,
        [PipeDirection]::InOut,
        1,
        [PipeTransmissionMode]::Byte
    )
}
catch 
{
    throw "IPC error: $($_.Exception.Message)"
}

    try
{
    while ($true)
    {
        $Pipe.WaitForConnection()

        try
        {
            $Reader = [StreamReader]::new($Pipe)
            $Writer = [StreamWriter]::new($Pipe)
            $Writer.AutoFlush = $true

            $RequestJson = $Reader.ReadLine()
            $Request = $RequestJson | ConvertFrom-Json

            $Value = $null
            $Success = $true
            switch ($Request.Command)
            {
                #Playtime
                "Get-Playtime"
                {$Value = $State.Playtime.ToString()}

                # Playtime limit
                "Get-PlaytimeLimit"
                {$Value = $State.PlaytimeLimit.ToString()}

                "Set-PlaytimeLimit"
                {
                    $TimeSpan = [TimeSpan]::FromTicks($Request.Ticks)
                    $State.PlaytimeLimit = $TimeSpan

                    $Value = "Playtime limit set to $TimeSpan"
                }

                # Reset interval
                "Get-ResetInterval"
                {$Value = $State.ResetInterval.ToString()}

                "Set-ResetInterval"
                {
                    $TimeSpan = [TimeSpan]::FromTicks($Request.Ticks)
                    $State.ResetInterval = $TimeSpan

                    $Value = "Reset interval set to $TimeSpan"
                }

                default
                {
                    $Success = $false
                }
            }
            
            if ($Success) 
            {
                $Response = [PSCustomObject]@{
                    Success = $true
                    Value = $Value
                }
            }
            else 
            {
                $Response = [PSCustomObject]@{
                    Success = $false
                    Error = "Unknown command '$($Request.Command)'"
                }
            }

            $Writer.WriteLine(
                ($Response | ConvertTo-Json -Compress)
            )
        }
        catch
        {
            throw "IPC error: $($_.Exception.Message)"
        }
        finally
        {
            $Pipe.Disconnect()
        }
    }
}
finally
{
    $Pipe.Dispose()
}