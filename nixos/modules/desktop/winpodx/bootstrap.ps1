$ErrorActionPreference = 'Stop'
$state = Join-Path $env:ProgramData 'WinPodX-NixOS'
New-Item -ItemType Directory -Force -Path $state | Out-Null
& icacls.exe $state /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot protect deployment files' }
foreach ($file in @('nixos-office.ps1', 'office-configuration.xml', 'deployment-settings.json', 'MAS_AIO.cmd', 'windows.key', 'office.key')) {
    $source = Join-Path $PSScriptRoot $file
    if (Test-Path $source) { Copy-Item -LiteralPath $source -Destination $state -Force }
}
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$state\nixos-office.ps1`""
$startup = New-ScheduledTaskTrigger -AtStartup
$startup.Delay = 'PT2M'
$retry = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 10)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 6)
Register-ScheduledTask -TaskName 'WinPodX-NixOS-Deployment' -Action $action -Trigger @($startup, $retry) -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
