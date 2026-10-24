{
  config,
  lib,
  inputs,
  ...
}:

let
  cfg = config.programs.winapps;
  generatedOfficeConfiguration = ''
    <Configuration>
      <Add OfficeClientEdition="64" Channel="${cfg.office.channel}">
        <Product ID="${cfg.office.productId}">
          <Language ID="${cfg.office.language}" />
        </Product>
      </Add>
      <Property Name="SharedComputerLicensing" Value="0" />
      <Property Name="AUTOACTIVATE" Value="1" />
      <Updates Enabled="TRUE" Channel="${cfg.office.channel}" />
      <RemoveMSI />
      <Display Level="None" AcceptEULA="TRUE" />
    </Configuration>
  '';
in
{
  config = lib.mkIf (cfg.podman.enable || cfg.docker.enable) {
    environment.etc = {
      "winapps/oem/RDPApps.reg".source = "${inputs.winapps}/oem/RDPApps.reg";
      "winapps/oem/Container.reg".source = "${inputs.winapps}/oem/Container.reg";
      "winapps/oem/NetProfileCleanup.ps1".source = "${inputs.winapps}/oem/NetProfileCleanup.ps1";
      "winapps/oem/TimeSync.ps1".source = "${inputs.winapps}/oem/TimeSync.ps1";

      "winapps/oem/office-configuration.xml" =
        if cfg.office.configurationFile != null then
          { source = cfg.office.configurationFile; }
        else
          { text = generatedOfficeConfiguration; };

      "winapps/oem/NixOSProvision.ps1".text = ''
        $ErrorActionPreference = 'Stop'
        # Windows PowerShell 5.1 defaults to TLS 1.0, which Microsoft's CDN rejects.
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $stateRoot = Join-Path $env:ProgramData 'WinApps'
        $logPath = Join-Path $stateRoot 'provision.log'
        $markerPath = '\\host.lan\Data\.winapps-provisioned'
        New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null

        function Write-ProvisionLog {
            param([string]$Message)
            $line = "$(Get-Date -Format o) $Message"
            Add-Content -LiteralPath $logPath -Value $line
            Write-Host $line
        }

        function Read-ProductKey {
            param([string]$Path)
            $shared = Join-Path '\\host.lan\Data' (Split-Path -Leaf $Path)
            if (-not (Test-Path -LiteralPath $Path) -and (Test-Path -LiteralPath $shared)) {
                Copy-Item -LiteralPath $shared -Destination $Path -Force
            }
            if (-not (Test-Path -LiteralPath $Path)) { return $null }
            $key = (Get-Content -LiteralPath $Path -Raw).Trim().ToUpperInvariant()
            if ($key -notmatch '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$') {
                throw "Invalid product key format in $Path"
            }
            return $key
        }

        function Invoke-LicenseCommand {
            param([string]$Script, [string[]]$Arguments, [string]$Label)
            Write-ProvisionLog "Running $Label"
            $output = & cscript.exe //NoLogo $Script @Arguments 2>&1 | Out-String
            Add-Content -LiteralPath $logPath -Value $output
            Write-ProvisionLog "$Label exited with code $LASTEXITCODE"
            return $LASTEXITCODE
        }

        try {
            $wordPaths = @(
                "$env:ProgramFiles\Microsoft Office\root\Office16\WINWORD.EXE",
                "$env:ProgramFiles\Microsoft Office\Office16\WINWORD.EXE"
            )
            $word = $wordPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

            if (${if cfg.office.enable then "$true" else "$false"} -and -not $word) {
                $odt = Join-Path $stateRoot 'OfficeSetup.exe'
                $officeConfiguration = Join-Path $stateRoot 'office-configuration.xml'
                if (-not (Test-Path -LiteralPath $officeConfiguration)) {
                    # The installer normally stages the configuration locally; fall
                    # back to dockur's Data share when the script runs from there.
                    $sharedConfiguration = '\\host.lan\Data\office-configuration.xml'
                    if (Test-Path -LiteralPath $sharedConfiguration) {
                        Copy-Item -LiteralPath $sharedConfiguration -Destination $officeConfiguration -Force
                    } else {
                        throw "Office configuration is missing: $officeConfiguration"
                    }
                }
                Write-ProvisionLog 'Downloading Microsoft Office Deployment Tool'
                Invoke-WebRequest -UseBasicParsing -Uri 'https://officecdn.microsoft.com/pr/wsus/setup.exe' -OutFile $odt
                Write-ProvisionLog 'Installing Office'
                $process = Start-Process -FilePath $odt -ArgumentList @('/configure', $officeConfiguration) -Wait -PassThru
                if ($process.ExitCode -ne 0) { throw "Office Deployment Tool exited with code $($process.ExitCode)" }
                $word = $wordPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
                if (-not $word) { throw 'Office installation finished without WINWORD.EXE' }
            }
            Write-ProvisionLog "Office executable: $word"

            $windowsKeyPath = Join-Path $stateRoot 'windows-product-key'
            $windowsKey = Read-ProductKey $windowsKeyPath
            $slmgr = Join-Path $env:SystemRoot 'System32\slmgr.vbs'
            if ($windowsKey) {
                Invoke-LicenseCommand $slmgr @('/ipk', $windowsKey) 'Windows product-key installation' | Out-Null
            }
            Invoke-LicenseCommand $slmgr @('/ato') 'Windows activation' | Out-Null

            $ospp = @(
                "$env:ProgramFiles\Microsoft Office\Office16\OSPP.VBS",
                "$env:ProgramFiles\Microsoft Office\root\Office16\OSPP.VBS",
                "''${env:ProgramFiles(x86)}\Microsoft Office\Office16\OSPP.VBS",
                "''${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\OSPP.VBS"
            ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
            if ($ospp) {
                $officeKey = Read-ProductKey (Join-Path $stateRoot 'office-product-key')
                if ($officeKey) {
                    Invoke-LicenseCommand $ospp @("/inpkey:$officeKey") 'Office product-key installation' | Out-Null
                }
                Invoke-LicenseCommand $ospp @('/act') 'Office activation' | Out-Null
            } else {
                Write-ProvisionLog 'OSPP.VBS is unavailable; subscription Office must be activated by signing in with a licensed account.'
            }

            $status = @(
                "completed=$(Get-Date -Format o)",
                "office=$([bool]$word)",
                "windows-key-configured=$([bool]$windowsKey)",
                "office-license-tool=$([bool]$ospp)"
            )
            # Write both the host-visible share marker and a local copy so the
            # boot-suspend check works even if the Samba share is unavailable.
            Set-Content -LiteralPath $markerPath -Value $status -Encoding ASCII -ErrorAction SilentlyContinue
            Set-Content -LiteralPath (Join-Path $stateRoot 'provisioned') -Value $status -Encoding ASCII
            Remove-Item -Force -ErrorAction SilentlyContinue $windowsKeyPath, (Join-Path $stateRoot 'office-product-key')
            schtasks.exe /Delete /TN 'WinApps_NixOSProvision' /F 2>&1 | Add-Content -LiteralPath $logPath
            Write-ProvisionLog 'Provisioning completed'
            exit 0
        } catch {
            Write-ProvisionLog "Provisioning failed: $($_.Exception.Message)"
            exit 1
        }
      '';

      "winapps/oem/install.bat".text = builtins.readFile "${inputs.winapps}/oem/install.bat" + ''

        :: NixOS extension: install Office, then activate Windows and Office using
        :: their own Microsoft licensing tools. This task retries after failures.
        set "WINAPPS_STATE=%ProgramData%\WinApps"
        if not exist "%WINAPPS_STATE%" mkdir "%WINAPPS_STATE%"
        copy /Y "%~dp0NixOSProvision.ps1" "%WINAPPS_STATE%\NixOSProvision.ps1" >nul
        copy /Y "%~dp0office-configuration.xml" "%WINAPPS_STATE%\office-configuration.xml" >nul
        if exist "%~dp0windows-product-key" copy /Y "%~dp0windows-product-key" "%WINAPPS_STATE%\windows-product-key" >nul
        if exist "%~dp0office-product-key" copy /Y "%~dp0office-product-key" "%WINAPPS_STATE%\office-product-key" >nul
        schtasks /create /tn "WinApps_NixOSProvision" /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%WINAPPS_STATE%\NixOSProvision.ps1\"" /sc onstart /ru SYSTEM /rl HIGHEST /f >nul 2>&1
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WINAPPS_STATE%\NixOSProvision.ps1"
      '';
    };
  };
}
