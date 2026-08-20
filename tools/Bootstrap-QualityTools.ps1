[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$node = Get-Command node -ErrorAction SilentlyContinue
$npm = Get-Command npm -ErrorAction SilentlyContinue

if (-not $node) {
    throw 'Node.js 20 or newer is required to bootstrap quality tools.'
}
if (-not $npm) {
    throw 'npm is required to bootstrap quality tools. Install a Node.js distribution that includes npm.'
}

$nodeVersion = & $node.Source --version
if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v(?<major>\d+)\.') {
    throw 'Unable to determine the installed Node.js version.'
}
if ([int] $Matches.major -lt 20) {
    throw "Node.js 20 or newer is required; found $nodeVersion."
}

Push-Location $repositoryRoot
try {
    & $npm.Source ci --ignore-scripts --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
        throw "npm ci failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

& (Join-Path $PSScriptRoot 'Bootstrap-SecurityTools.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Security tool bootstrap failed.' }

Write-Output "Quality tools bootstrapped with Node $nodeVersion using package-lock.json."
