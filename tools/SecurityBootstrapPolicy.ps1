Set-StrictMode -Version Latest

function Resolve-SecurityContainedPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][string] $Label
    )

    $normalized = $RelativePath -replace '\\', '/'
    if (-not $normalized -or $normalized -match '[\x00-\x1f\x7f]' `
        -or $normalized.StartsWith('/', [System.StringComparison]::Ordinal) `
        -or $normalized -match '^[A-Za-z]:' -or $normalized.StartsWith('//')) {
        throw "$Label is not a safe relative path: $RelativePath"
    }
    $parts = @($normalized -split '/')
    if ($parts -contains '' -or $parts -contains '.' -or $parts -contains '..') {
        throw "$Label is not a safe relative path: $RelativePath"
    }
    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $platformPath = $normalized.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $rootFull $platformPath))
    $relative = [System.IO.Path]::GetRelativePath($rootFull, $resolved)
    if ([System.IO.Path]::IsPathRooted($relative) -or $relative -eq '..' `
        -or $relative.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::Ordinal)) {
        throw "$Label escapes its managed root: $RelativePath"
    }
    return $resolved
}

function Assert-SecurityVersionToken {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Version, [Parameter(Mandatory)][string] $Label)
    if ($Version -notmatch '^[0-9]+(?:\.[0-9]+){1,3}$') {
        throw "$Label is not a safe version token: $Version"
    }
}

function Assert-SecurityArchivePathToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Label,
        [switch] $TopLevelOnly
    )
    $normalized = $Path -replace '\\', '/'
    if (-not $normalized -or $normalized -match '[\x00-\x1f\x7f]' `
        -or $normalized.StartsWith('/', [System.StringComparison]::Ordinal) `
        -or $normalized -match '^[A-Za-z]:' -or $normalized.StartsWith('//')) {
        throw "$Label is not a safe archive path: $Path"
    }
    $parts = @($normalized -split '/')
    if ($parts -contains '' -or $parts -contains '.' -or $parts -contains '..' `
        -or ($TopLevelOnly -and $parts.Count -ne 1)) {
        throw "$Label is not a safe archive path: $Path"
    }
}

function Resolve-SecurityDownloadUri {
    [CmdletBinding()]
    [OutputType([uri])]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][object] $Value,
        [Parameter(Mandatory)][string] $Label
    )

    if ($Value -isnot [string]) {
        throw "$Label must be a string."
    }
    $text = [string] $Value
    if (-not $text -or $text -cne $text.Trim() -or $text -match '[\x00-\x1f\x7f]' `
        -or $text.Contains('\') -or $text -match '%(?![0-9A-Fa-f]{2})') {
        throw "$Label is not a safe download URI."
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($text, [System.UriKind]::Absolute, [ref] $uri) `
        -or -not $uri.IsAbsoluteUri -or $uri.Scheme -cne 'https' `
        -or [string]::IsNullOrWhiteSpace($uri.Host) -or $uri.UserInfo -or $uri.Fragment) {
        throw "$Label must be an absolute HTTPS URI without credentials or a fragment."
    }
    return $uri
}

function Resolve-SecurityBootstrapManifest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object] $Manifest,
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string] $ToolsRoot,
        [Parameter(Mandatory)][ValidateSet('windows-x64', 'linux-x64')][string] $Platform
    )

    if ([int] $Manifest.schema -ne 2) { throw 'Unsupported security manifest schema.' }
    $binRoot = Resolve-SecurityContainedPath -Root $ToolsRoot -RelativePath 'bin' -Label 'security bin root'
    foreach ($name in @('gitleaks', 'actionlint', 'zizmor')) {
        $tool = $Manifest.tools.$name
        if (-not $tool) { throw "Security manifest is missing tool '$name'." }
        Assert-SecurityVersionToken -Version ([string] $tool.version) -Label "$name version"
        foreach ($platformName in @('windows-x64', 'linux-x64')) {
            $asset = $tool.$platformName
            if (-not $asset) { throw "Security manifest is missing $name asset '$platformName'." }
            if ([string] $asset.sha256 -notmatch '^[0-9a-f]{64}$') { throw "$name $platformName has an invalid checksum." }
            if ([string] $asset.archive_type -notin @('zip', 'tar.gz')) { throw "$name $platformName has an invalid archive type." }
            $uri = Resolve-SecurityDownloadUri -Value $asset.url -Label "$name $platformName URL"
            $archiveName = [System.IO.Path]::GetFileName($uri.AbsolutePath)
            Assert-SecurityArchivePathToken -Path $archiveName -Label "$name $platformName download name" -TopLevelOnly
            Resolve-SecurityContainedPath -Root (Join-Path $ToolsRoot 'manifest-downloads') `
                -RelativePath $archiveName -Label "$name $platformName download path" | Out-Null
            Resolve-SecurityContainedPath -Root $binRoot -RelativePath ([string] $asset.executable) `
                -Label "$name $platformName executable" | Out-Null
            Assert-SecurityArchivePathToken -Path ([string] $asset.expected_executable_path) `
                -Label "$name $platformName expected executable"
            foreach ($allowed in @($asset.allowed_top_level)) {
                Assert-SecurityArchivePathToken -Path ([string] $allowed) `
                    -Label "$name $platformName allowed top-level entry" -TopLevelOnly
            }
        }
    }

    $pssa = $Manifest.psscriptanalyzer
    Assert-SecurityVersionToken -Version ([string] $pssa.version) -Label 'PSScriptAnalyzer version'
    Resolve-SecurityDownloadUri -Value $pssa.url -Label 'PSScriptAnalyzer URL' | Out-Null
    if ([string] $pssa.sha256 -notmatch '^[0-9a-f]{64}$' -or [string] $pssa.archive_type -cne 'zip') {
        throw 'PSScriptAnalyzer metadata is invalid.'
    }
    Resolve-SecurityContainedPath -Root $ToolsRoot `
        -RelativePath "modules/PSScriptAnalyzer/$($pssa.version)" -Label 'PSScriptAnalyzer module path' | Out-Null
    Assert-SecurityArchivePathToken -Path ([string] $pssa.expected_executable_path) -Label 'PSScriptAnalyzer expected manifest'
    foreach ($allowed in @($pssa.allowed_top_level)) {
        Assert-SecurityArchivePathToken -Path ([string] $allowed) -Label 'PSScriptAnalyzer allowed top-level entry' -TopLevelOnly
    }

    Assert-SecurityVersionToken -Version ([string] $Manifest.pre_commit.version) -Label 'pre-commit version'
    $requirementsRelative = [string] $Manifest.pre_commit.requirements_file
    if ($requirementsRelative -cne 'tools/pre-commit-requirements.txt') {
        throw "pre-commit requirements_file must be tools/pre-commit-requirements.txt."
    }
    $requirementsPath = Resolve-SecurityContainedPath -Root $RepositoryRoot `
        -RelativePath $requirementsRelative -Label 'pre-commit requirements file'
    return [pscustomobject]@{
        Platform = $Platform
        BinRoot = $binRoot
        RequirementsPath = $requirementsPath
    }
}

function Get-SecurityArchiveEntryRecord {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $ArchivePath,
        [Parameter(Mandatory)][ValidateSet('zip', 'tar.gz')][string] $ArchiveType
    )

    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Security archive does not exist: $ArchivePath"
    }
    if ($ArchiveType -eq 'zip') {
        Add-Type -AssemblyName System.IO.Compression
        $stream = [System.IO.File]::OpenRead($ArchivePath)
        $archive = [System.IO.Compression.ZipArchive]::new(
            $stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            foreach ($entry in $archive.Entries) {
                $unixType = (($entry.ExternalAttributes -shr 16) -band 0xF000)
                $kind = if ($unixType -eq 0xA000) {
                    'link'
                }
                elseif (-not $entry.Name) {
                    'directory'
                }
                else {
                    'file'
                }
                Write-Output ([pscustomobject]@{ Path = $entry.FullName; Kind = $kind })
            }
        }
        finally {
            $archive.Dispose()
            $stream.Dispose()
        }
        return
    }

    $file = [System.IO.File]::OpenRead($ArchivePath)
    $gzip = [System.IO.Compression.GZipStream]::new(
        $file, [System.IO.Compression.CompressionMode]::Decompress, $false)
    $reader = [System.Formats.Tar.TarReader]::new($gzip, $false)
    try {
        while ($entry = $reader.GetNextEntry()) {
            $kind = if ($entry.EntryType -in @(
                [System.Formats.Tar.TarEntryType]::RegularFile,
                [System.Formats.Tar.TarEntryType]::V7RegularFile
            )) {
                'file'
            }
            elseif ($entry.EntryType -eq [System.Formats.Tar.TarEntryType]::Directory) {
                'directory'
            }
            else {
                'link'
            }
            Write-Output ([pscustomobject]@{ Path = $entry.Name; Kind = $kind })
        }
    }
    finally {
        $reader.Dispose()
        $gzip.Dispose()
        $file.Dispose()
    }
}

function Resolve-SecurityArchiveExecutable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $EntryRecord,
        [Parameter(Mandatory)][string] $ExpectedExecutablePath,
        [Parameter(Mandatory)][string[]] $AllowedTopLevel
    )

    $normalizedExpected = $ExpectedExecutablePath -replace '\\', '/'
    $seen = @{}
    $executableMatches = [System.Collections.Generic.List[string]]::new()
    $expectedKind = $null
    foreach ($record in $EntryRecord) {
        $raw = [string] $record.Path
        if (-not $raw -or $raw -match '[\x00-\x1f\x7f]') {
            throw 'Security archive contains an empty or control-character path.'
        }
        $normalized = $raw -replace '\\', '/'
        if ($normalized.StartsWith('/', [System.StringComparison]::Ordinal) `
            -or $normalized -match '^[A-Za-z]:' -or $normalized.StartsWith('//')) {
            throw "Security archive contains an absolute or drive-qualified path: $raw"
        }
        $normalized = $normalized.TrimEnd('/')
        $parts = @($normalized -split '/')
        if (-not $normalized -or $parts -contains '' -or $parts -contains '.' -or $parts -contains '..') {
            throw "Security archive contains an unsafe path: $raw"
        }
        if ($AllowedTopLevel -cnotcontains $parts[0]) {
            throw "Security archive contains unexpected top-level entry '$($parts[0])'."
        }
        $folded = $normalized.ToUpperInvariant()
        if ($seen.ContainsKey($folded)) {
            throw "Security archive contains duplicate or case-conflicting path: $normalized"
        }
        $seen[$folded] = $true
        if ([string] $record.Kind -notin @('file', 'directory')) {
            throw "Security archive contains unsupported link entry: $normalized"
        }
        if ([System.IO.Path]::GetFileName($normalized).Equals(
            [System.IO.Path]::GetFileName($normalizedExpected),
            [System.StringComparison]::OrdinalIgnoreCase)) {
            $executableMatches.Add($normalized)
        }
        if ($normalized -ceq $normalizedExpected) { $expectedKind = [string] $record.Kind }
    }
    if ($expectedKind -ne 'file') {
        throw "Security archive is missing expected executable '$normalizedExpected'."
    }
    if ($executableMatches.Count -ne 1 -or $executableMatches[0] -cne $normalizedExpected) {
        throw "Security archive contains an unexpected executable layout for '$normalizedExpected'."
    }
    return $normalizedExpected
}

function Confirm-SecurityFileHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string] $ExpectedHash,
        [Parameter(Mandatory)][string] $Label
    )

    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($actual -cne $ExpectedHash) {
        throw "$Label checksum mismatch: expected $ExpectedHash, got $actual."
    }
}

function Confirm-PythonHashLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Line,
        [Parameter(Mandatory)][string[]] $ExpectedRequirement
    )

    $locked = @{}
    foreach ($raw in $Line) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $match = [regex]::Match($line, '^(?<requirement>[A-Za-z0-9_.-]+==[^\s]+)(?<hashes>(?:\s+--hash=sha256:[0-9a-f]{64})+)\s*$')
        if (-not $match.Success) {
            throw "Python distribution lock contains an unhashed or malformed requirement: $line"
        }
        $requirement = $match.Groups['requirement'].Value
        $key = $requirement.ToLowerInvariant()
        if ($locked.ContainsKey($key)) { throw "Python distribution lock contains duplicate requirement '$requirement'." }
        $locked[$key] = $true
    }
    $expected = @{}
    foreach ($requirement in $ExpectedRequirement) {
        $key = $requirement.ToLowerInvariant()
        if ($expected.ContainsKey($key)) { throw "Expected Python requirements contain duplicate '$requirement'." }
        $expected[$key] = $true
    }
    $missing = @($expected.Keys | Where-Object { -not $locked.ContainsKey($_) })
    $extra = @($locked.Keys | Where-Object { -not $expected.ContainsKey($_) })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        throw "Python distribution lock mismatch: missing=$($missing -join ',') extra=$($extra -join ',')."
    }
}

function Invoke-SecurityTemporaryDirectory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $AllowedParent,
        [Parameter(Mandatory)][scriptblock] $Action
    )

    $parent = [System.IO.Path]::GetFullPath($AllowedParent)
    $target = [System.IO.Path]::GetFullPath($Path)
    $relative = [System.IO.Path]::GetRelativePath($parent, $target)
    if ([System.IO.Path]::IsPathRooted($relative) -or $relative -eq '..' `
        -or $relative.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)") -or $relative -eq '.') {
        throw "Unsafe security temporary directory: $target"
    }
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    try { Write-Output (& $Action $target) }
    finally {
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    }
}
