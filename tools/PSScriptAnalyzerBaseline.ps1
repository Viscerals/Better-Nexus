Set-StrictMode -Version Latest

function Get-PSScriptAnalyzerMessageHash {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $Message)

    $normalized = ($Message -replace '\s+', ' ').Trim()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [System.Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-PSScriptAnalyzerRecordFingerprint {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object] $Record)

    return "$($Record.path)|$($Record.rule)|$($Record.message_sha256)|$($Record.occurrence)"
}

function ConvertTo-PSScriptAnalyzerFindingRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Finding,
        [Parameter(Mandatory)][string] $RepositoryRoot
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $occurrences = [System.Collections.Generic.Dictionary[string, int]]::new(
        [System.StringComparer]::Ordinal)
    $ordered = @($Finding | Sort-Object ScriptPath, RuleName, Message, Line, Column)
    foreach ($item in $ordered) {
        $fullPath = [System.IO.Path]::GetFullPath([string] $item.ScriptPath)
        $relativePath = [System.IO.Path]::GetRelativePath($root, $fullPath)
        if ([System.IO.Path]::IsPathRooted($relativePath) -or $relativePath -eq '..' `
            -or $relativePath.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::Ordinal)) {
            throw "PSScriptAnalyzer finding is outside the repository: $fullPath"
        }
        $path = $relativePath -replace '\\', '/'
        $rule = [string] $item.RuleName
        $messageHash = Get-PSScriptAnalyzerMessageHash -Message ([string] $item.Message)
        if (-not $path -or -not $rule) { throw 'PSScriptAnalyzer finding is missing its path or rule.' }
        $identity = "$path|$rule|$messageHash"
        $occurrence = if ($occurrences.ContainsKey($identity)) { 1 + [int] $occurrences[$identity] } else { 1 }
        $occurrences[$identity] = $occurrence
        $record = [pscustomobject][ordered]@{
            path = $path
            rule = $rule
            message_sha256 = $messageHash
            occurrence = $occurrence
            fingerprint = "$identity|$occurrence"
        }
        Write-Output $record
    }
}

function Assert-PSScriptAnalyzerBaselineRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Record,
        [Parameter(Mandatory)][string] $Source
    )

    foreach ($name in @('path', 'rule', 'message_sha256', 'occurrence')) {
        if (-not $Record.PSObject.Properties[$name]) {
            throw "$Source PSScriptAnalyzer record is missing '$name'."
        }
    }
    if (-not [string] $Record.path -or -not [string] $Record.rule) {
        throw "$Source PSScriptAnalyzer record has an empty path or rule."
    }
    if ([string] $Record.message_sha256 -notmatch '^[0-9a-f]{64}$') {
        throw "$Source PSScriptAnalyzer record has an invalid message_sha256."
    }
    if ([int] $Record.occurrence -lt 1) {
        throw "$Source PSScriptAnalyzer record has an invalid occurrence."
    }
    if ($Record.PSObject.Properties['fingerprint']) {
        $expected = Get-PSScriptAnalyzerRecordFingerprint -Record $Record
        if ([string] $Record.fingerprint -cne $expected) {
            throw "$Source PSScriptAnalyzer record has a mismatched fingerprint."
        }
    }
}

function Compare-PSScriptAnalyzerFindingBaseline {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $FindingRecord,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $BaselineRecord
    )

    $currentByFingerprint = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($record in $FindingRecord) {
        Assert-PSScriptAnalyzerBaselineRecord -Record $record -Source 'Current'
        $fingerprint = Get-PSScriptAnalyzerRecordFingerprint -Record $record
        if ($currentByFingerprint.ContainsKey($fingerprint)) {
            throw "Current PSScriptAnalyzer records contain duplicate fingerprint '$fingerprint'."
        }
        $currentByFingerprint[$fingerprint] = $record
    }

    $baselineByFingerprint = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($record in $BaselineRecord) {
        Assert-PSScriptAnalyzerBaselineRecord -Record $record -Source 'Baseline'
        $fingerprint = Get-PSScriptAnalyzerRecordFingerprint -Record $record
        if ($baselineByFingerprint.ContainsKey($fingerprint)) {
            throw "Baseline PSScriptAnalyzer records contain duplicate fingerprint '$fingerprint'."
        }
        $baselineByFingerprint[$fingerprint] = $record
    }

    $inherited = @($currentByFingerprint.Keys | Where-Object { $baselineByFingerprint.ContainsKey($_) } | Sort-Object | ForEach-Object { $currentByFingerprint[$_] })
    $new = @($currentByFingerprint.Keys | Where-Object { -not $baselineByFingerprint.ContainsKey($_) } | Sort-Object | ForEach-Object { $currentByFingerprint[$_] })
    $resolved = @($baselineByFingerprint.Keys | Where-Object { -not $currentByFingerprint.ContainsKey($_) } | Sort-Object | ForEach-Object { $baselineByFingerprint[$_] })
    return [pscustomobject]@{
        Inherited = $inherited
        New = $new
        Resolved = $resolved
    }
}
