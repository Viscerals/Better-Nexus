Set-StrictMode -Version Latest

function ConvertTo-NormalizedArtifactPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $normalized = $Path -replace '\\', '/'
    while ($normalized.StartsWith('./', [System.StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(2)
    }
    return $normalized
}

function Test-ArtifactPathSet {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Candidates,
        [switch] $ReadContent
    )

    $forbiddenPathPatterns = @(
        '(?i)(^|/)(build|dist|coverage|tmp|temp|node_modules|\.tools|\.ai|\.codex|\.chatgpt)/',
        '(?i)(^|/)(prompts?|transcripts?|chat[-_ ]?exports?)(/|$)',
        '(?i)(^|/)(Nexus\.lua|SavedVariables(?:[-_].*)?\.(lua|txt|json)|.*profiler.*|.*runtime.*\.log)$',
        '(?i)\.(zip|7z|rar|bak|tmp|log|prof|pprof)$',
        '(?i)(^|/)(Nexus\.codex-backup-|Nexus-backup-|package-root)'
    )
    $privateContentPatterns = @(
        '(?i)[A-Z]:[\\/]Users[\\/][^\\/\s]+',
        '(?i)(api[_-]?key|client[_-]?secret|access[_-]?token|password)\s*[:=]\s*["''][^"'']{8,}["'']',
        '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
    )
    $fixturePrefix = 'tests/fixtures/sanitized/'
    $rootFull = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $rootPrefix = $rootFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar) `
        + [System.IO.Path]::DirectorySeparatorChar
    $violations = [System.Collections.Generic.List[string]]::new()

    foreach ($raw in @($Candidates | Sort-Object -Unique)) {
        $path = ConvertTo-NormalizedArtifactPath $raw
        if (-not $path) { continue }
        foreach ($pattern in $forbiddenPathPatterns) {
            if ($path -match $pattern) { $violations.Add("path:$path"); break }
        }
        if (-not $ReadContent) { continue }
        if ($path.StartsWith($fixturePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $relativePlatformPath = $path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $full = [System.IO.Path]::GetFullPath((Join-Path $rootFull $relativePlatformPath))
        if (-not $full.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $violations.Add("outside-repository:$path")
            continue
        }
        if ((Test-Path -LiteralPath $full -PathType Leaf) `
            -and (Get-Item -LiteralPath $full -Force).Length -le 1048576) {
            $text = Get-Content -Raw -LiteralPath $full -ErrorAction Stop
            foreach ($pattern in $privateContentPatterns) {
                if ($text -match $pattern) { $violations.Add("private-content:$path"); break }
            }
        }
    }
    return @($violations | Sort-Object -Unique)
}
