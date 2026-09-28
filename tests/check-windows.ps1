# No installations, network requests, elevation, or persistent environment changes.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'setup-windows.ps1'
$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
. $scriptPath

$previousNative = $env:PROCESSOR_ARCHITEW6432
$previousProcess = $env:PROCESSOR_ARCHITECTURE
try {
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $env:PROCESSOR_ARCHITEW6432 = $null
    if ((Get-DeviceArchitecture) -ne 'x64') { throw 'x64 detection failed.' }
    $env:PROCESSOR_ARCHITECTURE = 'x86'
    $env:PROCESSOR_ARCHITEW6432 = 'AMD64'
    if ((Get-DeviceArchitecture) -ne 'x64') { throw '32-bit process on x64 OS detection failed.' }
    foreach ($unsupported in @('ARM64', 'x86')) {
        $env:PROCESSOR_ARCHITECTURE = $unsupported
        $env:PROCESSOR_ARCHITEW6432 = $null
        $rejected = $false
        try { Get-DeviceArchitecture | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw "Architecture $unsupported was not rejected." }
    }
    $pathWithSpecialCharacters = "C:\Users\A & B\O'Brien\setup.ps1"
    $encoded = Get-ElevationCommand $pathWithSpecialCharacters
    $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
    $elevationAst = [Management.Automation.Language.Parser]::ParseInput($decoded, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Elevation command does not parse.' }
    $invocation = $elevationAst.EndBlock.Statements[0].PipelineElements[0]
    if ($invocation.CommandElements[0].Value -ne $pathWithSpecialCharacters) { throw 'Elevation changed the literal script path.' }
    if ($invocation.CommandElements[1].ParameterName -ne 'Elevated') { throw 'Elevation recursion guard missing.' }

    # Mock the OS boundary: these checks must never launch a real UAC prompt.
    function Start-Process {
        param($FilePath, $Verb, $WindowStyle, [switch]$Wait, [switch]$PassThru, $ArgumentList)
        $script:Launch = $PSBoundParameters
        if ($script:CancelElevation) { throw 'Simulated UAC cancellation' }
        $fakeProcess = [pscustomobject]@{ ExitCode = 37; HasExited = $true; Handle = 0 }
        $fakeProcess | Add-Member ScriptMethod WaitForExit { }
        return $fakeProcess
    }
    $script:CancelElevation = $false
    if ((Invoke-ElevatedSetup $pathWithSpecialCharacters) -ne 37) { throw 'Child exit code was lost.' }
    if ($script:Launch.Verb -ne 'RunAs' -or $script:Launch.WindowStyle -ne 'Hidden' -or $script:Launch.ContainsKey('Wait')) {
        throw 'Unexpected elevation launch options.'
    }
    $script:CancelElevation = $true
    $cancelled = $false
    try { Invoke-ElevatedSetup $pathWithSpecialCharacters } catch {
        $cancelled = $_.Exception.Message -like '*Administrator access was cancelled*'
    }
    if (-not $cancelled) { throw 'Cancellation message missing.' }

    $logFixture = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($logFixture, "Transcript header`n[12:00:00] [SUCCESS] Java checked.`n[12:00:01] [SUCCESS] Sub")
        $lineCount = 0
        $first = Show-SetupLog $logFixture ([ref]$lineCount) 6>&1 | Out-String
        if ($first -notmatch 'Java checked' -or $first -match 'Transcript header|Sub') { throw 'Live log filtering or partial-line handling failed.' }
        $second = Show-SetupLog $logFixture ([ref]$lineCount) 6>&1 | Out-String
        if ($second.Trim()) { throw 'Live log repeated a completed line.' }
        [IO.File]::AppendAllText($logFixture, "lime checked.`n[12:00:02] [ERROR] Next step failed.`n")
        $third = Show-SetupLog $logFixture ([ref]$lineCount) 6>&1 | Out-String
        if ($third -notmatch 'Sublime checked' -or $third -notmatch 'Next step failed' -or $third -match 'Java checked') {
            throw 'Live log did not relay completed and error messages exactly once.'
        }
    } finally { Remove-Item -LiteralPath $logFixture -Force }

    function Test-Administrator { return $false }
    function Invoke-ElevatedSetup { param($ScriptPath); $script:ElevationCalls++; $script:ElevatedPath = $ScriptPath; return 37 }
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $env:PROCESSOR_ARCHITEW6432 = $null
    $script:ElevationCalls = 0
    $Preview = $true
    Main
    if ($script:ElevationCalls -ne 0) { throw 'Preview requested elevation.' }
    $Preview = $false
    Main
    if ($script:ElevationCalls -ne 1 -or $script:SetupExitCode -ne 37) { throw 'Main did not propagate child failure.' }
    if ($script:ElevatedPath -ne $scriptPath) { throw 'Main did not elevate the downloaded script path.' }
    $Elevated = $true
    $blocked = $false
    try { Main } catch { $blocked = $_.Exception.Message -like '*did not receive administrator access*' }
    if (-not $blocked -or $script:ElevationCalls -ne 1) { throw 'Elevation recursion was not blocked.' }
    function Test-SetupNetwork { $script:NetworkCalls++ }
    $script:NetworkCalls = 0
    $DiagnoseNetwork = $true
    Main
    if ($script:NetworkCalls -ne 1 -or $script:ElevationCalls -ne 1) { throw 'Network diagnostics requested elevation or did not run.' }
    Write-Host 'PASS: syntax, architecture, elevation, cancellation/status, live log relay, preview, recursion guard.'
} finally {
    $env:PROCESSOR_ARCHITEW6432 = $previousNative
    $env:PROCESSOR_ARCHITECTURE = $previousProcess
}
