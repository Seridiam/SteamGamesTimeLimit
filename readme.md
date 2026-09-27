SteamGamesTimeLimit is a tool that allows setting a time limit and reset period for all Steam games.
I created this because I couldn't find a reliable free app with this purpose.

### Installation

*Please note that the tool was mainly made for personal use and therefore doesn't have a clean CLI, graphical interface, installation process, or Powershell 5.1 support. I am willing to add these features if this repo gets enough traction, however.*

**Prerequisites: Powershell 7 with admin (elevated) access (ensure you have pwsh.exe, not powershell.exe since that is specific to 5.1)**

Open a Terminal (Command Prompt) window with admin rights and run the following commands.

Cd inside the directory where the tool is located:
```
cd C:\Users\<YOURUSER>\Documents\GitHub\SteamGamesTimeLimit
```

In order to automatically set up the Task Scheduler job (so that the tool starts automatically on logon), call:
```
./SteamTimeLimitCLI.ps1 Install
```
If you also wish to start it in your current session, call:
```
./SteamTimeLimitCLI.ps1 Start
```

### Usage

**Commands below can be ran in any Terminal (Command Prompt) window:**

Check playtime:
```
.\SteamTimeLimitCLI.ps1 Get-Playtime
```

Set playtime limit:
```
.\SteamTimeLimitCLI.ps1 Set-PlaytimeLimit -Hours 1 -Minutes 45 -Seconds 30
```
You don't have to fill in all 3 parameters, if left out they will be set to 0:
```
.\SteamTimeLimitCLI.ps1 Set-PlaytimeLimit -Minutes 45 # Sets playtime limit to 00:45:00
```

Set time interval after which playtime is reset:
```
.\SteamTimeLimitCLI.ps1 Set-ResetInterval -Hours 1 -Minutes 45 -Seconds 30
```

**Commands below can only be ran in a terminal with admin rights:**

Stop until next logon:
```
./SteamTimeLimitCLI Stop
```

Temporarily disable tool:
```
./SteamTimeLimitCLI Disable-StartOnLogon
```
Reenable tool:
```
./SteamTimeLimitCLI Enable-StartOnLogon
```

Remove Task Scheduler job:
```
./SteamTimeLimitCLI Uninstall
```

### Credits

The tool was and is currently developed only by me (Seridiam on GitHub).
Published under the MIT License (see LICENSE).
