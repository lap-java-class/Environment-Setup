# Exercises download failure handling without network access or installation.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'setup-windows.ps1')
$realTransfer = ${function:Invoke-CurlTransfer}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('java-download-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture | Out-Null
$destination = Join-Path $fixture 'file with spaces.bin'
function Start-Sleep { param($Seconds); $script:Delays += $Seconds }
function Invoke-CurlTransfer {
    param($Url, $Destination, $ErrorFile, $TimeoutSeconds)
    $item = $script:Responses[$script:Calls]
    $script:Calls++
    [IO.File]::WriteAllText($Destination, $item.Body)
    return [pscustomobject]@{ ExitCode = $item.Code; Status = $item.Http; Server = 'cdn.example.test'; Detail = 'fixture' }
}
function Response($Code, $Http = 0, $Body = 'partial') {
    return @{ Code = $Code; Http = $Http; Body = $Body }
}
function Run-Case($Responses, $ExpectedCalls, $ExpectedError = '') {
    $script:Responses = $Responses
    $script:Calls = 0
    $script:Delays = @()
    $message = ''
    try { Save-Download 'https://example.test/package' $destination } catch { $message = $_.Exception.Message }
    if ($script:Calls -ne $ExpectedCalls) { throw "Expected $ExpectedCalls attempts, got $script:Calls. $message" }
    if ($ExpectedError) {
        if ($message -notlike "*$ExpectedError*") { throw "Missing expected failure: $ExpectedError. Got: $message" }
        if ([IO.File]::ReadAllText($destination) -ne 'complete') { throw 'A failed download replaced the completed destination.' }
    } else {
        if ($message) { throw $message }
        if ([IO.File]::ReadAllText($destination) -ne 'complete') { throw 'Partial bytes were accepted.' }
    }
    if ((Test-Path "$destination.partial") -or (Test-Path "$destination.curl-error")) { throw 'Temporary download files were left behind.' }
}
try {
    # PowerShell 5.1 returns null for an empty stderr file after a successful curl.
    function curl.exe {
        $outputPath = $args[[Array]::IndexOf($args, '--output') + 1]
        $stderrPath = $args[[Array]::IndexOf($args, '--stderr') + 1]
        [IO.File]::WriteAllText($outputPath, 'complete')
        [IO.File]::WriteAllText($stderrPath, '')
        $global:LASTEXITCODE = 0
        Write-Output '200|https://cdn.example.test/package'
    }
    $nativeResult = & $realTransfer 'https://example.test/package' "$destination.partial" "$destination.curl-error" 60
    if ($nativeResult.ExitCode -ne 0 -or $nativeResult.Status -ne 200 -or $nativeResult.Detail -ne '' -or
        $nativeResult.Server -ne 'cdn.example.test') { throw 'Successful curl output was parsed incorrectly.' }
    Remove-Item Function:\curl.exe
    Run-Case @((Response 6), (Response 56), (Response 0 200 'complete')) 3
    if (($script:Delays -join ',') -ne '2,4') { throw 'Unexpected retry backoff.' }
    Run-Case @((Response 6), (Response 6), (Response 6), (Response 6), (Response 6)) 5 'DNS could not resolve'
    Run-Case @((Response 60)) 1 'certificate'
    Run-Case @((Response 22 404)) 1 'HTTP 404'
    Run-Case @((Response 22 503), (Response 0 200 'complete')) 2
    Run-Case @((Response 0 200 ''), (Response 0 200 'complete')) 2
    $rejected = $false
    try { Save-Download 'http://example.test/package' $destination } catch { $rejected = $_.Exception.Message -like '*non-HTTPS*' }
    if (-not $rejected) { throw 'Plain HTTP was accepted.' }
    Write-Host 'PASS: DNS/reset retries, bounded backoff, certificate/HTTP failures, empty responses, partial-file isolation, HTTPS enforcement.'
} finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if ($resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedFixture) -like 'java-download-test-*') {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
