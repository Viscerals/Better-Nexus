[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Range', 'Staged', 'Working')]
    [string] $Mode,

    [Parameter()]
    [string] $BaseRef,

    [Parameter(DontShow)]
    [string] $RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = if ($RepositoryRoot) {
    [System.IO.Path]::GetFullPath($RepositoryRoot)
}
else {
    Split-Path -Parent $PSScriptRoot
}
$safeRepositoryRoot = $repositoryRoot -replace '\\', '/'
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { throw 'git is required for whitespace validation.' }

function Invoke-GitCheck {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]] $Arguments)

    $rows = @(& $git.Source -c "safe.directory=$safeRepositoryRoot" `
        -C $repositoryRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $detail = ($rows | ForEach-Object { [string] $_ }) -join [Environment]::NewLine
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE.$([Environment]::NewLine)$detail"
    }
    return $rows
}

switch ($Mode) {
    'Range' {
        if (-not $BaseRef) { throw 'BaseRef is required for committed-range whitespace validation.' }
        [void] (Invoke-GitCheck @('rev-parse', '--verify', '--quiet', "$BaseRef^{commit}"))
        [void] (Invoke-GitCheck @('diff', '--check', "$BaseRef...HEAD"))
        Write-Output "git diff --check $BaseRef...HEAD -- OK"
    }
    'Staged' {
        [void] (Invoke-GitCheck @('diff', '--cached', '--check'))
        Write-Output 'git diff --cached --check -- OK'
    }
    'Working' {
        [void] (Invoke-GitCheck @('diff', '--check'))
        Write-Output 'git diff --check working tree -- OK'
    }
}
