$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$state = $PSScriptRoot
$options = Get-Content -Raw (Join-Path $state 'deployment-settings.json') | ConvertFrom-Json
$log = Join-Path $state 'provision.log'
$status = [ordered]@{ generation = $options.generation; complete = $false; stage = 'waiting-windows'; officeInstalled = $false; windowsActivated = $false; officeActivated = $false }
$mutex = [Threading.Mutex]::new($false, 'Global\WinPodX-NixOS-Deployment')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); exit 0 }

function Write-Log([string]$Message) {
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format o) $Message"
}

function Publish-Status {
    $status.checkedAt = Get-Date -Format o
    $json = $status | ConvertTo-Json -Compress
    $temporary = Join-Path $state 'deployment.tmp'
    [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination (Join-Path $state 'deployment.json') -Force
    # Native dockur Samba uses /storage/shared when no /shared mount exists.
    $servers = @('host.lan', '10.0.2.2') + @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty NextHop)
    foreach ($server in ($servers | Select-Object -Unique)) {
        try {
            $share = "\\$server\Data"
            if (-not (Test-Path $share)) { continue }
            $temporary = Join-Path $share 'winpodx-deployment.tmp'
            [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
            Move-Item -LiteralPath $temporary -Destination (Join-Path $share 'winpodx-deployment.json') -Force
            return $true
        } catch { Write-Log "Status share unavailable: $server" }
    }
    return $false
}

function Invoke-License([string]$Script, [string[]]$Arguments, [string]$Label) {
    # License arguments/output can contain keys; do not log them.
    $null = & cscript.exe //NoLogo $Script @Arguments 2>&1
    Write-Log "$Label exit code: $LASTEXITCODE"
}

function Test-WindowsLicense {
    return [bool](Get-CimInstance SoftwareLicensingProduct | Where-Object {
        $_.ApplicationID -eq '55c92734-d682-4d71-983e-d6ec3f16059f' -and $_.PartialProductKey -and $_.LicenseStatus -eq 1
    })
}

function Test-OfficeLicense([string]$Ospp) {
    if (-not $Ospp) { return $false }
    $result = & cscript.exe //NoLogo $Ospp /dstatusall 2>&1 | Out-String
    return $result -match '---LICENSED---'
}

try {
    if (-not (Test-Path 'C:\winpodx\setup_done.txt') -or (Test-Path 'C:\winpodx\oem_reboot_pending.txt')) {
        $null = Publish-Status
        exit 1
    }
    $officeRoot = Join-Path $env:ProgramFiles 'Microsoft Office\root\Office16'
    $installed = Join-Path $state 'office.installed'
    $required = @('WINWORD.EXE', 'EXCEL.EXE', 'POWERPNT.EXE')
    $missing = @($required | Where-Object { -not (Test-Path (Join-Path $officeRoot $_)) })
    if ($options.officeEnabled -and ($missing.Count -gt 0 -or -not (Test-Path $installed))) {
        $status.stage = 'office'
        $null = Publish-Status
        $odt = Join-Path $state 'OfficeSetup.exe'
        if (-not (Test-Path $odt) -or (Get-AuthenticodeSignature $odt).Status -ne 'Valid') {
            Write-Log 'Downloading Microsoft Office Deployment Tool'
            Invoke-WebRequest -UseBasicParsing -Uri 'https://officecdn.microsoft.com/pr/wsus/setup.exe' -OutFile "$odt.tmp"
            Move-Item -LiteralPath "$odt.tmp" -Destination $odt -Force
        }
        $signature = Get-AuthenticodeSignature $odt
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
            throw 'Office Deployment Tool signature verification failed'
        }
        Write-Log 'Installing Office (unattended; an interrupted install is retried)'
        $xml = Join-Path $state 'office-configuration.xml'
        $process = Start-Process -FilePath $odt -ArgumentList @('/configure', "`"$xml`"") -Wait -PassThru
        $process.Refresh()
        if ($process.ExitCode -notin @(0, 3010)) { throw "Office installer exit code: $($process.ExitCode)" }
        $missing = @($required | Where-Object { -not (Test-Path (Join-Path $officeRoot $_)) })
        if ($missing.Count -gt 0) { throw 'Office executables are missing after installation' }
        # Files may exist before ODT finishes. Commit only after exit 0 + checks.
        [IO.File]::WriteAllText("$installed.tmp", $options.generation)
        Move-Item -LiteralPath "$installed.tmp" -Destination $installed -Force
        if ($process.ExitCode -eq 3010) {
            $status.stage = 'office-reboot'
            $null = Publish-Status
            shutdown.exe /r /t 30 /c 'WinPodX: completing Office installation'
            exit 1
        }
    }
    $status.officeInstalled = [bool]($options.officeEnabled -and $missing.Count -eq 0)
    $ospp = @((Join-Path $env:ProgramFiles 'Microsoft Office\Office16\OSPP.VBS'), (Join-Path $officeRoot 'OSPP.VBS')) |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    $status.windowsActivated = Test-WindowsLicense
    $status.officeActivated = Test-OfficeLicense $ospp
    $status.stage = 'activation'
    $null = Publish-Status
    if (-not $status.windowsActivated -or ($options.officeEnabled -and -not $status.officeActivated)) {
        if ($options.activationMethod -eq 'mas') {
            $mas = Join-Path $state 'MAS_AIO.cmd'
            if ((Get-FileHash $mas -Algorithm SHA256).Hash -ne $options.masSha256) { throw 'MAS checksum mismatch' }
            $switches = '/Z-Windows /S'
            if ($options.officeEnabled) { $switches = '/Z-Windows /Z-Office /S' }
            Write-Log 'Running fixed MAS 3.12 inside the guest'
            $process = Start-Process "$env:SystemRoot\System32\cmd.exe" -ArgumentList @('/c', "`"`"$mas`" $switches`"") -Wait -PassThru -WindowStyle Hidden
            Write-Log "MAS exit code: $($process.ExitCode)"
        } else {
            $slmgr = Join-Path $env:SystemRoot 'System32\slmgr.vbs'
            if (Test-Path (Join-Path $state 'windows.key')) {
                Invoke-License $slmgr @('/ipk', (Get-Content -Raw (Join-Path $state 'windows.key')).Trim()) 'Windows key'
            }
            Invoke-License $slmgr @('/ato') 'Windows activation'
            if ($options.officeEnabled -and $ospp) {
                if (Test-Path (Join-Path $state 'office.key')) {
                    Invoke-License $ospp @("/inpkey:$((Get-Content -Raw (Join-Path $state 'office.key')).Trim())") 'Office key'
                }
                Invoke-License $ospp @('/act') 'Office activation'
            }
        }
    }
    $status.windowsActivated = Test-WindowsLicense
    $status.officeActivated = Test-OfficeLicense $ospp
    $licensed = $status.windowsActivated -and (-not $options.officeEnabled -or $status.officeActivated)
    if ($options.requireActivation -and -not $licensed) { throw 'Activation verification failed; retry scheduled' }
    $status.complete = $true
    $status.stage = 'complete'
    if (Publish-Status) {
        Disable-ScheduledTask -TaskName 'WinPodX-NixOS-Deployment' | Out-Null
        Write-Log 'Deployment complete; first-boot task disabled'
    }
} catch {
    $status.stage = 'failed'
    $status.error = $_.Exception.Message
    Write-Log $status.error
    $null = Publish-Status
    exit 1
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
