#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Preview,
    [Parameter(DontShow = $true)]
    [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$SublimeBuild = '4215'
$script:SetupExitCode = 0

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ElevationCommand([string]$ScriptPath) {
    # Encode the command so spaces, apostrophes, and shell metacharacters in the
    # downloaded file's path stay data when passed to the elevated PowerShell.
    $literalPath = $ScriptPath.Replace("'", "''")
    $command = "& '$literalPath' -Elevated; exit `$LASTEXITCODE"
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
}

function Invoke-ElevatedSetup([string]$ScriptPath) {
    $encoded = Get-ElevationCommand $ScriptPath
    $powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try {
        $process = Start-Process -FilePath $powerShell -Verb RunAs -WindowStyle Hidden -Wait -PassThru `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)
    } catch {
        throw "Administrator access was cancelled or could not be requested. Run again and approve the Windows prompt, or open Command Prompt as administrator. Details: $($_.Exception.Message)"
    }
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

function Save-Download([string]$Url, [string]$Destination) {
    if (-not $Url.StartsWith('https://')) { throw 'Refusing a non-HTTPS download.' }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination -TimeoutSec 600
            return
        } catch {
            if ($attempt -eq 3) { throw }
            Start-Sleep -Seconds 2
        }
    }
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
    Write-Host "Verified $version by compiling and running a program."
}

function Main {
    if ($env:OS -ne 'Windows_NT') { throw 'Use setup-unix.sh on macOS/Linux.' }
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
        Write-Host "Installation will run in the background. Keep this window open. Logs: $logDir"
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
    $log = Join-Path $logDir "windows-$stamp.log"
    Start-Transcript -Path $log | Out-Null
    $work = Join-Path ([IO.Path]::GetTempPath()) ("java-sublime-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        Write-Host '[1/4] Finding and verifying Java 21...'
        $api = "https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=$arch&image_type=jdk&os=windows&vendor=eclipse"
        $releases = @(Invoke-RestMethod -Uri $api -TimeoutSec 60)
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
            $extracted = Join-Path $work 'extracted'
            Expand-Archive -LiteralPath $archive -DestinationPath $extracted
            $candidates = @(Get-ChildItem -LiteralPath $extracted -Directory | Where-Object {
                Test-Path (Join-Path $_.FullName 'bin\javac.exe')
            })
            if ($candidates.Count -ne 1) { throw 'Unexpected JDK archive layout.' }
            Test-Jdk $candidates[0].FullName $work
            New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
            # Copy into Program Files so files inherit the destination's protected permissions.
            Copy-Item -LiteralPath $candidates[0].FullName -Destination $jdkPath -Recurse
        }
        Test-Jdk $jdkPath $work

        Write-Host '[2/4] Installing Sublime Text...'
        $sublime = Join-Path $sublimeDir 'sublime_text.exe'
        if (-not (Test-Path -LiteralPath $sublime)) {
            $installer = Join-Path $work 'sublime-setup.exe'
            Save-Download "https://download.sublimetext.com/sublime_text_build_${SublimeBuild}_x64_setup.exe" $installer
            $signature = Get-AuthenticodeSignature -LiteralPath $installer
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Sublime HQ') {
                throw 'Sublime installer publisher signature could not be verified.'
            }
            $process = Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', ('/DIR="' + $sublimeDir + '"')) -Wait -PassThru
            if ($process.ExitCode -notin @(0, 3010)) { throw "Sublime installer failed: $($process.ExitCode)" }
        } else { Write-Host 'Reusing the existing Sublime Text installation.' }
        if (-not (Test-Path -LiteralPath $sublime)) { throw 'Sublime Text executable was not found after installation.' }

        Write-Host '[3/4] Saving and configuring system environment...'
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $oldHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
        @{ JAVA_HOME = $oldHome; Path = $machinePath } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $logDir "environment-before-$stamp.json") -Encoding UTF8
        $javaBin = Join-Path $jdkPath 'bin'
        $entries = @($machinePath -split ';' | Where-Object {
            $_ -and $_.TrimEnd('\') -ine $javaBin.TrimEnd('\') -and $_.TrimEnd('\') -ine $sublimeDir.TrimEnd('\')
        })
        [Environment]::SetEnvironmentVariable('JAVA_HOME', $jdkPath, 'Machine')
        [Environment]::SetEnvironmentVariable('Path', ((@($javaBin, $sublimeDir) + $entries) -join ';'), 'Machine')
        $env:JAVA_HOME = $jdkPath
        $env:Path = "$javaBin;$sublimeDir;$env:Path"
        Write-Host '[4/4] Checking Java command resolution...'
        $resolved = (Get-Command java.exe -CommandType Application).Source
        if ($resolved -ine (Join-Path $javaBin 'java.exe')) { throw "Another Java command takes precedence: $resolved" }
        Write-Host "Setup complete. JAVA_HOME=$jdkPath"
        Write-Host 'Sign out of Windows and sign back in to refresh environment variables in all apps.'
        Write-Host "Log and previous environment settings: $logDir"
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
