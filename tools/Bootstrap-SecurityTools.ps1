[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'SecurityBootstrapPolicy.ps1')
$manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'security-tools.json') | ConvertFrom-Json
$toolsRoot = Join-Path $repositoryRoot '.tools/security'
$binRoot = Join-Path $toolsRoot 'bin'
$isWindowsPlatform = $env:OS -eq 'Windows_NT'
$isLinuxPlatform = -not $isWindowsPlatform -and [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)
$platform = if ($isWindowsPlatform) { 'windows-x64' } elseif ($isLinuxPlatform) { 'linux-x64' } else { throw 'Only Windows x64 and Linux x64 are supported.' }
$validatedManifest = Resolve-SecurityBootstrapManifest -Manifest $manifest -RepositoryRoot $repositoryRoot `
    -ToolsRoot $toolsRoot -Platform $platform

New-Item -ItemType Directory -Path $binRoot -Force | Out-Null
$legacyDownloadRoot = Join-Path $toolsRoot 'downloads'
Invoke-SecurityTemporaryDirectory -Path $legacyDownloadRoot -AllowedParent $toolsRoot -Action {} | Out-Null
$bootstrapRoot = Join-Path $toolsRoot "bootstrap-$PID"
Invoke-SecurityTemporaryDirectory -Path $bootstrapRoot -AllowedParent $toolsRoot -Action {
    param($temporaryRoot)

    $downloadRoot = Join-Path $temporaryRoot 'downloads'
    New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    foreach ($name in @('gitleaks', 'actionlint', 'zizmor')) {
        $asset = $manifest.tools.$name.$platform
        if (-not $asset) { throw "No $name asset is pinned for $platform." }
        $archiveName = [System.IO.Path]::GetFileName(([uri] $asset.url).AbsolutePath)
        $archivePath = Join-Path $downloadRoot $archiveName
        Invoke-WebRequest -UseBasicParsing -Uri $asset.url -OutFile $archivePath
        Confirm-SecurityFileHash -Path $archivePath -ExpectedHash $asset.sha256 -Label $name
        $entryRecord = @(Get-SecurityArchiveEntryRecord `
            -ArchivePath $archivePath -ArchiveType $asset.archive_type)
        $expectedRelative = Resolve-SecurityArchiveExecutable `
            -EntryRecord $entryRecord `
            -ExpectedExecutablePath $asset.expected_executable_path `
            -AllowedTopLevel @($asset.allowed_top_level)

        $extractRoot = Join-Path $temporaryRoot "extract-$name"
        Invoke-SecurityTemporaryDirectory -Path $extractRoot -AllowedParent $temporaryRoot -Action {
            param($destinationRoot)
            if ($asset.archive_type -eq 'zip') {
                Expand-Archive -LiteralPath $archivePath -DestinationPath $destinationRoot -Force
            }
            else {
                & tar -xzf $archivePath -C $destinationRoot
                if ($LASTEXITCODE -ne 0) { throw "Unable to extract $archiveName." }
            }
            $sourcePath = Join-Path $destinationRoot ($expectedRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                throw "$name archive did not produce exact executable '$expectedRelative'."
            }
            $installedPath = Join-Path $binRoot $asset.executable
            Copy-Item -LiteralPath $sourcePath -Destination $installedPath -Force
            if (-not $isWindowsPlatform) { & chmod +x $installedPath }
        } | Out-Null
    }

    $pssa = $manifest.psscriptanalyzer
    $moduleRoot = Join-Path $toolsRoot "modules/PSScriptAnalyzer/$($pssa.version)"
    $moduleManifest = Join-Path $moduleRoot 'PSScriptAnalyzer.psd1'
    if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf)) {
        $packagePath = Join-Path $downloadRoot "PSScriptAnalyzer.$($pssa.version).nupkg"
        Invoke-WebRequest -UseBasicParsing -Uri $pssa.url -OutFile $packagePath
        Confirm-SecurityFileHash -Path $packagePath -ExpectedHash $pssa.sha256 -Label 'PSScriptAnalyzer'
        $entryRecord = @(Get-SecurityArchiveEntryRecord `
            -ArchivePath $packagePath -ArchiveType $pssa.archive_type)
        $expectedRelative = Resolve-SecurityArchiveExecutable `
            -EntryRecord $entryRecord `
            -ExpectedExecutablePath $pssa.expected_executable_path `
            -AllowedTopLevel @($pssa.allowed_top_level)
        $moduleExtractRoot = Join-Path $temporaryRoot 'extract-psscriptanalyzer'
        try {
            Invoke-SecurityTemporaryDirectory -Path $moduleExtractRoot -AllowedParent $temporaryRoot -Action {
                param($destinationRoot)
                Expand-Archive -LiteralPath $packagePath -DestinationPath $destinationRoot -Force
                $expectedPath = Join-Path $destinationRoot ($expectedRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
                if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) {
                    throw "PSScriptAnalyzer archive did not produce '$expectedRelative'."
                }
                if (Test-Path -LiteralPath $moduleRoot) { Remove-Item -LiteralPath $moduleRoot -Recurse -Force }
                New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
                Get-ChildItem -LiteralPath $destinationRoot -Force | ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName -Destination $moduleRoot -Recurse -Force
                }
            } | Out-Null
        }
        catch {
            if (Test-Path -LiteralPath $moduleRoot) { Remove-Item -LiteralPath $moduleRoot -Recurse -Force }
            throw
        }
    }

    $requirementsPath = $validatedManifest.RequirementsPath
    $requirements = @(Get-Content -LiteralPath $requirementsPath -ErrorAction Stop)
    Confirm-PythonHashLock -Line $requirements -ExpectedRequirement @($manifest.pre_commit.packages)
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
    if ($python) {
        $venv = Join-Path $toolsRoot 'pre-commit'
        if (Test-Path -LiteralPath $venv) { Remove-Item -LiteralPath $venv -Recurse -Force }
        $installed = $false
        try {
            if ($python.Name -eq 'py.exe') { & $python.Source -3 -m venv $venv } else { & $python.Source -m venv $venv }
            if ($LASTEXITCODE -ne 0) { throw 'Unable to create the pre-commit virtual environment.' }
            $venvPython = if ($isWindowsPlatform) { Join-Path $venv 'Scripts/python.exe' } else { Join-Path $venv 'bin/python' }
            & $venvPython -m pip install --disable-pip-version-check --no-input `
                --require-hashes --only-binary=:all: --no-deps -r $requirementsPath
            if ($LASTEXITCODE -ne 0) { throw 'Unable to install hash-verified pre-commit distributions.' }
            & $venvPython -m pip check
            if ($LASTEXITCODE -ne 0) { throw 'Hash-verified pre-commit environment has broken requirements.' }
            $installed = $true
        }
        finally {
            if (-not $installed -and (Test-Path -LiteralPath $venv)) {
                Remove-Item -LiteralPath $venv -Recurse -Force
            }
        }
    }
    else {
        Write-Warning 'Python is unavailable; pre-commit was not installed.'
    }
} | Out-Null

Write-Output "Security tools bootstrapped for $platform with verified archive layouts and distribution hashes."
