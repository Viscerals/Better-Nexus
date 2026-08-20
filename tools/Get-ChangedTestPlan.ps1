[CmdletBinding()]
param(
    [Parameter()]
    [string[]] $Paths = @(),

    [Parameter()]
    [string] $BaseRef,

    [Parameter(DontShow)]
    [string] $RepositoryRoot,

    [Parameter(DontShow)]
    [string] $MapPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = if ($RepositoryRoot) {
    [System.IO.Path]::GetFullPath($RepositoryRoot)
}
else {
    Split-Path -Parent $PSScriptRoot
}
$mapPath = if ($MapPath) { $MapPath } else { Join-Path $repositoryRoot 'tests/validation-map.json' }
$map = Get-Content -Raw -LiteralPath $mapPath | ConvertFrom-Json
if ($map.schema -ne 1) {
    throw "Unsupported validation-map schema: $($map.schema)"
}

. (Join-Path $PSScriptRoot 'GitPathRecords.ps1')

function ConvertTo-NormalizedChangedPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $normalized = $Path -replace '\\', '/'
    while ($normalized.StartsWith('./', [System.StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(2)
    }
    return $normalized
}

function Add-ChangedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [switch] $DeletedFlag
    )

    $normalized = ConvertTo-NormalizedChangedPath $Path
    if (-not $normalized) { return }
    [void] $changed.Add($normalized)
    if ($DeletedFlag) {
        [void] $deleted.Add($normalized)
    }
}

$changed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$deleted = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
if ($Paths.Count -gt 0) {
    foreach ($candidate in $Paths) {
        if ($candidate) {
            $normalized = ConvertTo-NormalizedChangedPath $candidate
            $relativePlatformPath = $normalized.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $relativePlatformPath))
            Add-ChangedPath $candidate -DeletedFlag:(-not (Test-Path -LiteralPath $fullPath -PathType Leaf))
        }
    }
}
else {
    foreach ($record in @(Get-GitChangedPathRecord -RepositoryRoot $repositoryRoot -BaseRef $BaseRef)) {
        Add-ChangedPath -Path $record.Path -DeletedFlag:$record.Deleted
    }
}

$groups = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$tests = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$fullRequired = $false
$allDocumentation = $changed.Count -gt 0

foreach ($path in @($changed | Sort-Object)) {
    $matched = $false
    $documentationMatch = $false
    foreach ($route in $map.routes) {
        $routeMatch = $false
        foreach ($pattern in $route.patterns) {
            if ($path -match $pattern) {
                $routeMatch = $true
                break
            }
        }
        if (-not $routeMatch) { continue }
        $matched = $true
        if ($route.id -eq 'documentation') { $documentationMatch = $true }
        foreach ($group in $route.groups) { [void] $groups.Add([string] $group) }
        foreach ($test in $route.tests) { [void] $tests.Add([string] $test) }
        if ($route.full_required) { $fullRequired = $true }
    }
    if (-not $matched) {
        foreach ($group in $map.default.groups) { [void] $groups.Add([string] $group) }
        foreach ($test in $map.default.tests) { [void] $tests.Add([string] $test) }
        if ($map.default.full_required) { $fullRequired = $true }
    }
    if (-not $documentationMatch) { $allDocumentation = $false }
}

[ordered]@{
    schema = 1
    paths = @($changed | Sort-Object)
    deleted_paths = @($deleted | Sort-Object)
    groups = @($groups | Sort-Object)
    tests = @($tests | Sort-Object)
    full_required = [bool] $fullRequired
    documentation_only = [bool] $allDocumentation
} | ConvertTo-Json -Depth 5
