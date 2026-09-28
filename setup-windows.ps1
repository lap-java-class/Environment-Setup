#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Preview,
    [switch]$DiagnoseNetwork,
    [Parameter(DontShow = $true)]
    [switch]$Elevated,
    [Parameter(DontShow = $true)]
    [ValidatePattern('^$|^[a-f0-9]{32}$')]
    [string]$RunId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$SublimeBuild = '4215'
$script:SetupExitCode = 0

function Write-SetupMessage([string]$Level, [string]$Message) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message"
}

function Show-SetupLog([string]$LogPath, [ref]$LineCount) {
    # The elevated process writes its own unique transcript. Read only complete
    # lines while allowing that process to continue appending to the file.
    $reader = $null
    try {
        $stream = [IO.File]::Open($LogPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $reader = New-Object IO.StreamReader($stream)
        $contents = $reader.ReadToEnd()
    } catch [IO.IOException] { return
    } catch [UnauthorizedAccessException] { return
    } finally { if ($null -ne $reader) { $reader.Dispose() } }
    $lines = $contents -split '\r?\n'
    # The last element is either incomplete or empty after a trailing newline.
    $completeCount = $lines.Count - 1
    for ($index = $LineCount.Value; $index -lt $completeCount; $index++) {
        if ($lines[$index] -match '^\[\d{2}:\d{2}:\d{2}\] \[(INFO|SUCCESS|WARN|ERROR)\]') {
            Write-Host $lines[$index]
        }
    }
    $LineCount.Value = $completeCount
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ElevationCommand([string]$ScriptPath, [string]$Id = '') {
    # Encode the command so spaces, apostrophes, and shell metacharacters in the
    # downloaded file's path stay data when passed to the elevated PowerShell.
    $literalPath = $ScriptPath.Replace("'", "''")
    if ($Id -and $Id -notmatch '^[a-f0-9]{32}$') { throw 'Invalid setup run ID.' }
    $command = "& '$literalPath' -Elevated -RunId '$Id'; exit `$LASTEXITCODE"
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
}

function Invoke-ElevatedSetup([string]$ScriptPath) {
    $id = [guid]::NewGuid().ToString('N')
    $encoded = Get-ElevationCommand $ScriptPath $id
    $logPath = Join-Path $env:ProgramData "JavaSublimeSetup\logs\windows-$id.log"
    Write-SetupMessage INFO "Live progress will appear here. Log: $logPath"
    $powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try {
        $process = Start-Process -FilePath $powerShell -Verb RunAs -WindowStyle Hidden -PassThru `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)
    } catch {
        throw "Administrator access was cancelled or could not be requested. Run again and approve the Windows prompt, or open Command Prompt as administrator. Details: $($_.Exception.Message)"
    }
    # Retain the process handle so its exit code remains available after exit.
    $null = $process.Handle
    $lineCount = 0
    while (-not $process.HasExited) {
        Show-SetupLog $logPath ([ref]$lineCount)
        Start-Sleep -Milliseconds 500
        $process.Refresh()
    }
    $process.WaitForExit()
    Show-SetupLog $logPath ([ref]$lineCount)
    return $process.ExitCode
}

function Get-DeviceArchitecture {
    $native = $env:PROCESSOR_ARCHITEW6432
    if (-not $native) { $native = $env:PROCESSOR_ARCHITECTURE }
    switch ($native) {
        'AMD64' { return 'x64' }
        'ARM64' { throw 'Windows ARM64 is not supported by this first version. Use the official installers manually.' }
        default { throw "Unsupported Windows architecture: $native. This setup requires 64-bit Intel/AMD Windows." }
    }
}

function Invoke-CurlTransfer([string]$Url, [string]$Destination, [string]$ErrorFile, [int]$TimeoutSeconds) {
    # Keep native stderr out of PowerShell 5.1's terminating-error handling.
    # -q ignores a user's curl config; certificate verification stays enabled.
    $summary = & curl.exe -q --fail --location --silent --show-error --connect-timeout 30 `
        --max-time $TimeoutSeconds --proto '=https' --proto-redir '=https' `
        --output $Destination --stderr $ErrorFile --write-out '%{http_code}|%{url_effective}' $Url
    $code = $LASTEXITCODE
    $parts = ("$summary" -split '\|', 2)
    $status = 0
    [void][int]::TryParse($parts[0], [ref]$status)
    $server = ([uri]$Url).DnsSafeHost
    if ($parts.Count -gt 1 -and $parts[1] -match '^https://') { $server = ([uri]$parts[1]).DnsSafeHost }
    $detail = ''
    if (Test-Path -LiteralPath $ErrorFile) {
        $errorText = Get-Content -LiteralPath $ErrorFile -Raw
        if ($null -ne $errorText) { $detail = $errorText.Trim() }
    }
    return [pscustomobject]@{ ExitCode = $code; Status = $status; Server = $server; Detail = $detail }
}

function Get-DownloadFailureReason([int]$Code) {
    switch ($Code) {
        5 { return 'The proxy hostname could not be resolved.' }
        6 { return 'DNS could not resolve the download server.' }
        7 { return 'A connection to the server could not be established.' }
        18 { return 'The server returned an incomplete download.' }
        22 { return 'The server returned an HTTP error.' }
        28 { return 'The connection or download timed out.' }
        35 { return 'The TLS connection failed.' }
        60 { return 'The server certificate could not be verified.' }
        default { return 'The download connection failed or was interrupted.' }
    }
}

function Save-Download([string]$Url, [string]$Destination, [int]$TimeoutSeconds = 900) {
    if (-not $Url.StartsWith('https://')) { throw 'Refusing a non-HTTPS download.' }
    if (-not (Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'curl.exe is required. Update Windows or install curl, then rerun setup.'
    }
    $partial = "$Destination.partial"
    $errorFile = "$Destination.curl-error"
    try {
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            Write-SetupMessage INFO "Download attempt $attempt/5 from $(([uri]$Url).DnsSafeHost)"
            # Each retry starts a fresh file, never appending a different response.
            Remove-Item -LiteralPath $partial, $errorFile -Force -ErrorAction SilentlyContinue
            $result = Invoke-CurlTransfer $Url $partial $errorFile $TimeoutSeconds
            if ($result.ExitCode -eq 0) {
                if ((Test-Path -LiteralPath $partial) -and (Get-Item -LiteralPath $partial).Length -gt 0) {
                    Move-Item -LiteralPath $partial -Destination $Destination -Force
                    Write-SetupMessage SUCCESS "Downloaded $([IO.Path]::GetFileName($Destination)) ($((Get-Item -LiteralPath $Destination).Length) bytes)."
                    return
                }
                $result.ExitCode = 18
                $result.Detail = 'An empty response was received.'
            }
            $reason = Get-DownloadFailureReason $result.ExitCode
            Write-SetupMessage WARN "Download failed: $reason Server: $($result.Server); curl: $($result.ExitCode); HTTP: $($result.Status)"
            Write-SetupMessage WARN $result.Detail
            $retryable = $result.ExitCode -in @(5, 6, 7, 18, 28, 35, 52, 55, 56, 92) -or
                ($result.ExitCode -eq 22 -and ($result.Status -in @(408, 429) -or $result.Status -ge 500))
            if (-not $retryable -or $attempt -eq 5) {
                throw "$reason Server: $($result.Server). curl exit $($result.ExitCode), HTTP $($result.Status). Run this script with -DiagnoseNetwork on the affected computer."
            }
            $delay = [Math]::Min(30, 2 * [Math]::Pow(2, $attempt - 1))
            Write-SetupMessage INFO "Retrying in $delay seconds..."
            Start-Sleep -Seconds $delay
        }
    } finally {
        Remove-Item -LiteralPath $partial, $errorFile -Force -ErrorAction SilentlyContinue
    }
}

function Test-SetupNetwork {
    if (-not (Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue)) { throw 'curl.exe was not found.' }
    Write-Host 'Network diagnostics only. No installation, elevation, or settings changes.'
    Write-Host 'HTTP 2xx/3xx indicates a response; HTTP 4xx/5xx indicates the server responded with an error.'
    $urls = @(
        'https://raw.githubusercontent.com/lap-java-class/Environment-Setup/main/setup-windows.ps1',
        'https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse',
        'https://github.com/adoptium/temurin21-binaries/releases/latest',
        "https://download.sublimetext.com/sublime_text_build_${SublimeBuild}_x64_setup.exe"
    )
    $failed = $false
    foreach ($url in $urls) {
        Write-Host "Checking $(([uri]$url).DnsSafeHost)..."
        # No --fail: retain HTTP responses (including 403/405) as diagnostic evidence.
        # Do not print signed redirect URLs or credentials.
        & curl.exe -q --head --location --silent --connect-timeout 15 --max-time 30 `
            --proto '=https' --proto-redir '=https' --output NUL `
            --write-out 'HTTP %{http_code}; remote IP %{remote_ip}; time %{time_total}s\n' $url
        $code = $LASTEXITCODE
        if ($code -ne 0) { $failed = $true; Write-Host "curl exit ${code}: $(Get-DownloadFailureReason $code)" }
    }
    Write-Host 'These small HEAD requests do not prove a large download will complete or that a redirected asset CDN is reachable.'
    Write-Host 'Compare results with a stable connection. If using a VPN, keep it connected throughout the run.'
    if ($failed) { $script:SetupExitCode = 1 }
}

function Test-Jdk([string]$JdkPath, [string]$WorkPath) {
    $java = Join-Path $JdkPath 'bin\java.exe'
    $javac = Join-Path $JdkPath 'bin\javac.exe'
    if (-not (Test-Path $javac)) { throw "No compiler found in $JdkPath" }
    $version = & $javac -version 2>&1
    if ($LASTEXITCODE -ne 0 -or "$version" -notmatch '^javac 21(?:\.|\s|$)') {
        throw "Expected JDK 21, received: $version"
    }
    $source = Join-Path $WorkPath 'SetupCheck.java'
    'public class SetupCheck { public static void main(String[] args) { System.out.print("JAVA_SETUP_OK"); } }' |
        Set-Content -LiteralPath $source -Encoding ASCII
    & $javac -d $WorkPath $source
    if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed.' }
    $result = & $java -cp $WorkPath SetupCheck
    if ($LASTEXITCODE -ne 0 -or "$result" -ne 'JAVA_SETUP_OK') { throw 'Java execution failed.' }
    Write-SetupMessage SUCCESS "Verified $version by compiling and running a program."
}

function Main {
    if ($env:OS -ne 'Windows_NT') { throw 'Use setup-unix.sh on macOS/Linux.' }
    if ($DiagnoseNetwork) { Test-SetupNetwork; return }
    if ([Environment]::OSVersion.Version.Major -lt 10) { throw 'Windows 10 or newer is required.' }
    $arch = Get-DeviceArchitecture
    $programFiles = $env:ProgramW6432
    if (-not $programFiles) { $programFiles = $env:ProgramFiles }
    $installRoot = Join-Path $programFiles 'JavaSublimeSetup'
    $sublimeDir = Join-Path $programFiles 'Sublime Text'
    Write-Host "Detected Windows $arch"
    Write-Host "Java: latest Temurin JDK 21 -> $installRoot"
    Write-Host "Sublime Text: build $SublimeBuild -> $sublimeDir (reuse if already installed)"
    Write-Host 'Java will become the machine default through JAVA_HOME and PATH.'
    if ($Preview) { Write-Host 'Preview only. No downloads or changes made.'; return }

    $logDir = Join-Path $env:ProgramData 'JavaSublimeSetup\logs'
    if (-not (Test-Administrator)) {
        if ($Elevated) { throw 'The elevated process did not receive administrator access. Setup stopped.' }
        Write-Host 'Approve the Windows administrator prompt to install Java and Sublime Text.'
        Write-Host "Keep this window open for live installation progress. Logs: $logDir"
        $script:SetupExitCode = Invoke-ElevatedSetup $PSCommandPath
        if ($script:SetupExitCode -eq 0) {
            Write-Host 'Setup complete. Sign out of Windows and sign back in, then check java -version and javac -version.'
        } else {
            Write-Host "Setup stopped (exit code $script:SetupExitCode). Check $logDir for the latest log."
            Write-Host 'If no log was created, rerun from Command Prompt as administrator to see the error.'
        }
        return
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    if (-not $RunId) { $RunId = [guid]::NewGuid().ToString('N') }
    $log = Join-Path $logDir "windows-$RunId.log"
    Start-Transcript -Path $log | Out-Null
    $work = Join-Path ([IO.Path]::GetTempPath()) ("java-sublime-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        Write-SetupMessage SUCCESS "Device checked: Windows $arch; administrator access confirmed."
        Write-SetupMessage INFO '[1/4] Finding and verifying Java 21...'
        $api = "https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=$arch&image_type=jdk&os=windows&vendor=eclipse"
        $metadata = Join-Path $work 'jdk-metadata.json'
        Save-Download $api $metadata 120
        $releases = @(Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json)
        if ($releases.Count -eq 0) { throw 'Adoptium returned no compatible Java 21 download.' }
        $package = $releases[0].binary.package
        if ($package.checksum -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid JDK checksum metadata.' }
        $jdkPath = Join-Path $installRoot ("jdk-21-" + $package.checksum.Substring(0, 16))
        if (-not (Test-Path -LiteralPath $jdkPath)) {
            $archive = Join-Path $work 'jdk.zip'
            Save-Download $package.link $archive
            if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $package.checksum) {
                throw 'JDK checksum mismatch. Nothing from this archive was installed.'
            }
            Write-SetupMessage SUCCESS 'Java download checksum verified.'
            $extracted = Join-Path $work 'extracted'
            Expand-Archive -LiteralPath $archive -DestinationPath $extracted
            Write-SetupMessage SUCCESS 'Java archive extracted.'
            $candidates = @(Get-ChildItem -LiteralPath $extracted -Directory | Where-Object {
                Test-Path (Join-Path $_.FullName 'bin\javac.exe')
            })
            if ($candidates.Count -ne 1) { throw 'Unexpected JDK archive layout.' }
            Test-Jdk $candidates[0].FullName $work
            New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
            # Copy into Program Files so files inherit the destination's protected permissions.
            Copy-Item -LiteralPath $candidates[0].FullName -Destination $jdkPath -Recurse
            Write-SetupMessage SUCCESS "Java files installed: $jdkPath"
        } else {
            Write-SetupMessage INFO "Reusing Java files: $jdkPath"
        }
        Test-Jdk $jdkPath $work
        Write-SetupMessage SUCCESS 'Step 1/4 complete: Java 21 is installed and tested.'

        Write-SetupMessage INFO '[2/4] Installing Sublime Text...'
        $sublime = Join-Path $sublimeDir 'sublime_text.exe'
        if (-not (Test-Path -LiteralPath $sublime)) {
            $installer = Join-Path $work 'sublime-setup.exe'
            Save-Download "https://download.sublimetext.com/sublime_text_build_${SublimeBuild}_x64_setup.exe" $installer
            $signature = Get-AuthenticodeSignature -LiteralPath $installer
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Sublime HQ') {
                throw 'Sublime installer publisher signature could not be verified.'
            }
            Write-SetupMessage SUCCESS 'Sublime Text installer publisher signature verified.'
            $process = Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', ('/DIR="' + $sublimeDir + '"')) -Wait -PassThru
            if ($process.ExitCode -notin @(0, 3010)) { throw "Sublime installer failed: $($process.ExitCode)" }
        } else { Write-SetupMessage INFO 'Reusing the existing Sublime Text installation.' }
        if (-not (Test-Path -LiteralPath $sublime)) { throw 'Sublime Text executable was not found after installation.' }
        Write-SetupMessage SUCCESS 'Step 2/4 complete: Sublime Text executable is present.'

        Write-SetupMessage INFO '[3/4] Saving and configuring system environment...'
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $oldHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
        @{ JAVA_HOME = $oldHome; Path = $machinePath } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $logDir "environment-before-$stamp.json") -Encoding UTF8
        Write-SetupMessage SUCCESS 'Previous system environment settings backed up.'
        $javaBin = Join-Path $jdkPath 'bin'
        $entries = @($machinePath -split ';' | Where-Object {
            $_ -and $_.TrimEnd('\') -ine $javaBin.TrimEnd('\') -and $_.TrimEnd('\') -ine $sublimeDir.TrimEnd('\')
        })
        [Environment]::SetEnvironmentVariable('JAVA_HOME', $jdkPath, 'Machine')
        [Environment]::SetEnvironmentVariable('Path', ((@($javaBin, $sublimeDir) + $entries) -join ';'), 'Machine')
        $env:JAVA_HOME = $jdkPath
        $env:Path = "$javaBin;$sublimeDir;$env:Path"
        Write-SetupMessage SUCCESS 'Step 3/4 complete: system JAVA_HOME and PATH configured.'
        Write-SetupMessage INFO '[4/4] Checking Java command resolution...'
        $resolved = (Get-Command java.exe -CommandType Application).Source
        if ($resolved -ine (Join-Path $javaBin 'java.exe')) { throw "Another Java command takes precedence: $resolved" }
        Write-SetupMessage SUCCESS 'Step 4/4 complete: this setup process resolves java to the selected JDK.'
        Write-SetupMessage SUCCESS "Setup complete. JAVA_HOME=$jdkPath"
        Write-SetupMessage INFO 'Sign out of Windows and sign back in to refresh environment variables in all apps.'
        Write-SetupMessage INFO "Log and previous environment settings: $logDir"
    } catch {
        # Record the final actionable message BEFORE Stop-Transcript, including
        # when the elevated process has no visible console.
        Write-SetupMessage ERROR "SETUP FAILED: $($_.Exception.Message)"
        throw
    } finally {
        # Only remove the unique temporary folder allocated by this invocation.
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        $resolvedWork = [IO.Path]::GetFullPath($work)
        if ($resolvedWork.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($resolvedWork) -like 'java-sublime-*') {
            Remove-Item -LiteralPath $resolvedWork -Recurse -Force -ErrorAction SilentlyContinue
        }
        Stop-Transcript | Out-Null
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Main; exit $script:SetupExitCode } catch { Write-Error "Setup stopped: $($_.Exception.Message)" -ErrorAction Continue; exit 1 }
}
