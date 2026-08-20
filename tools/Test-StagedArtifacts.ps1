[CmdletBinding()]
param(
    [ValidateSet('Staged', 'All')]
    [string] $Mode = 'Staged',

    [Parameter(ValueFromRemainingArguments)]
    [string[]] $Paths = @(),

    [Parameter(DontShow)]
    [string] $RepositoryRoot,

    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = if ($RepositoryRoot) {
    [System.IO.Path]::GetFullPath($RepositoryRoot)
}
else {
    Split-Path -Parent $PSScriptRoot
}
. (Join-Path $PSScriptRoot 'GitPathRecords.ps1')
. (Join-Path $PSScriptRoot 'ArtifactPathPolicy.ps1')

if ($SelfTest) {
    $bad = @(Test-ArtifactPathSet -RepositoryRoot $repositoryRoot `
        -Candidates @('dist/Nexus.zip', 'Nexus.lua', '.ai/prompt.md', 'logs/runtime.log', 'node_modules/a.js',
            'tests/fixtures/sanitized/.codex/context.txt', 'tests/fixtures/sanitized/build/package.zip'))
    $good = @(Test-ArtifactPathSet -RepositoryRoot $repositoryRoot -Candidates @(
        'tools/Test-StagedArtifacts.ps1',
        'tests/fixtures/sanitized/example.lua',
        'tests/run-savedvariables-analyzer.js',
        'tools/analyze-savedvariables.js'
    ))
    if ($bad.Count -ne 7 -or $good.Count -ne 0) { throw "Artifact self-test failed: bad=$($bad.Count) [$($bad -join ',')] good=$($good.Count)." }
    Write-Output 'staged artifact policy self-test: 7 rejected / 4 allowed -- OK'
    exit 0
}

if ($Paths.Count -eq 0) {
    $arguments = if ($Mode -eq 'All') {
        @('ls-files', '-z')
    }
    else {
        @('diff', '--cached', '--name-only', '-z', '--diff-filter=ACMR')
    }
    $bytes = Invoke-GitByteOutput -RepositoryRoot $repositoryRoot -Arguments $arguments
    $Paths = @(ConvertFrom-NulDelimitedUtf8 -Bytes $bytes)
}

$violations = @(Test-ArtifactPathSet -RepositoryRoot $repositoryRoot -Candidates $Paths -ReadContent)
if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Output "staged artifact policy: checked $($Paths.Count) path(s), violations=0"
