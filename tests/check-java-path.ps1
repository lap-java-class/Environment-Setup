# Reproduce multiple executable matches using the real PowerShell command resolver.
# No Java execution, installation, or persistent environment changes.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'setup-windows.ps1')
$previousPath = $env:Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('java-path-test-' + [guid]::NewGuid())
$selected = Join-Path $fixture 'selected JDK\bin'
$other = Join-Path $fixture 'other Java\bin'
try {
    New-Item -ItemType Directory -Path $selected, $other -Force | Out-Null
    # Valid executables are used only for discovery, never run as Java.
    foreach ($folder in @($selected, $other)) {
        foreach ($name in @('java.exe', 'javac.exe')) {
            Copy-Item -LiteralPath $env:ComSpec -Destination (Join-Path $folder $name)
        }
    }
    $env:Path = "$selected;$other"
    $matches = @(Get-Command java.exe -CommandType Application)
    if ($matches.Count -lt 2) { throw 'Fixture did not reproduce multiple Java matches.' }
    Assert-JavaCommandResolution $selected

    $env:Path = "$other;$selected"
    $rejected = $false
    try { Assert-JavaCommandResolution $selected } catch {
        $rejected = $_.Exception.Message -like '*Another java.exe takes precedence*'
    }
    if (-not $rejected) { throw 'A competing Java at the front of PATH was accepted.' }

    $env:Path = $selected
    Assert-JavaCommandResolution $selected
    Remove-Item -LiteralPath (Join-Path $selected 'javac.exe')
    $rejected = $false
    try { Assert-JavaCommandResolution $selected } catch {
        $rejected = $_.Exception.Message -like '*javac.exe was not found*'
    }
    if (-not $rejected) { throw 'Missing Java compiler was accepted.' }
    Write-Host 'PASS: multiple Java matches, actual PATH precedence, single installation, missing compiler.'
} finally {
    $env:Path = $previousPath
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if ($resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedFixture) -like 'java-path-test-*') {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
