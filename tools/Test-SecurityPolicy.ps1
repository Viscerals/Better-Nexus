[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Gitleaks', 'Actionlint', 'Zizmor', 'PSScriptAnalyzer', 'LuaLS', 'Luacheck', 'StyLua')]
    [string] $Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'PSScriptAnalyzerBaseline.ps1')
$binRoot = Join-Path $repositoryRoot '.tools/security/bin'
$manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'security-tools.json') | ConvertFrom-Json
$isWindowsPlatform = $env:OS -eq 'Windows_NT'

function Unavailable([string] $Message) {
    [Console]::Error.WriteLine("UNAVAILABLE: $Message")
    exit 3
}

function Invoke-External([string] $Executable, [string[]] $Arguments) {
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { Unavailable "$Check executable is missing; run tools/Bootstrap-QualityTools.ps1." }
    & $Executable @Arguments
    exit $LASTEXITCODE
}

Push-Location $repositoryRoot
try {
    switch ($Check) {
        'Gitleaks' {
            $exe = Join-Path $binRoot $(if ($isWindowsPlatform) { 'gitleaks.exe' } else { 'gitleaks' })
            Invoke-External $exe @('dir', '.', '--no-banner', '--redact', '--config', '.gitleaks.toml', '--exit-code', '1')
        }
        'Actionlint' {
            $exe = Join-Path $binRoot $(if ($isWindowsPlatform) { 'actionlint.exe' } else { 'actionlint' })
            $workflows = @(Get-ChildItem -LiteralPath '.github/workflows' -File | Where-Object { $_.Extension -in @('.yml', '.yaml') } | Sort-Object Name | ForEach-Object FullName)
            if ($workflows.Count -eq 0) { throw 'No GitHub workflow files were found.' }
            Invoke-External $exe (@('-no-color') + $workflows)
        }
        'Zizmor' {
            $exe = Join-Path $binRoot $(if ($isWindowsPlatform) { 'zizmor.exe' } else { 'zizmor' })
            $workflows = @(Get-ChildItem -LiteralPath '.github/workflows' -File | Where-Object { $_.Extension -in @('.yml', '.yaml') } | Sort-Object Name | ForEach-Object FullName)
            if ($workflows.Count -eq 0) { throw 'No GitHub workflow files were found.' }
            if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { Unavailable 'Zizmor executable is missing; run tools/Bootstrap-QualityTools.ps1.' }
            # The inherited release-policy workflow has a UTF-8 BOM. Zizmor 1.29
            # misclassifies that byte sequence as multi-document YAML, so audit
            # exact decoded content through temporary no-BOM copies.
            $tempRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot '.tools/security/zizmor-input'))
            $expectedParent = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot '.tools/security'))
            if (-not $tempRoot.StartsWith($expectedParent, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe zizmor temporary path.' }
            if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            try {
                $inputs = foreach ($workflow in $workflows) {
                    $copy = Join-Path $tempRoot ([System.IO.Path]::GetFileName($workflow))
                    [System.IO.File]::WriteAllText($copy, (Get-Content -Raw -LiteralPath $workflow), [System.Text.UTF8Encoding]::new($false))
                    $copy
                }
                & $exe (@('--offline', '--format', 'plain', '--min-severity', 'high') + @($inputs))
                $zizmorExit = $LASTEXITCODE
            }
            finally { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
            exit $zizmorExit
        }
        'PSScriptAnalyzer' {
            $version = $manifest.psscriptanalyzer.version
            $module = Join-Path $repositoryRoot ".tools/security/modules/PSScriptAnalyzer/$version/PSScriptAnalyzer.psd1"
            if (-not (Test-Path -LiteralPath $module)) { Unavailable 'PSScriptAnalyzer module is missing; run tools/Bootstrap-QualityTools.ps1.' }
            Import-Module $module -Force
            $settings = Join-Path $repositoryRoot 'PSScriptAnalyzerSettings.psd1'
            $findings = @(Invoke-ScriptAnalyzer -Path (Join-Path $repositoryRoot 'tools') -Recurse -Settings $settings)
            $blockingRules = @('PSAvoidUsingConvertToSecureStringWithPlainText', 'PSAvoidUsingPlainTextForPassword', 'PSUsePSCredentialType', 'PSAvoidUsingInvokeExpression')
            $blocking = @($findings | Where-Object { $_.Severity -eq 'Error' -or $_.RuleName -in $blockingRules })
            $advisory = @($findings | Where-Object {
                -not ($_.Severity -eq 'Error' -or $_.RuleName -in $blockingRules)
            })
            $baselineDocument = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'tests/security-advisory-baseline.json') | ConvertFrom-Json
            if ([int] $baselineDocument.schema -ne 2) { throw 'Unsupported security advisory baseline schema.' }
            $findingRecord = @(ConvertTo-PSScriptAnalyzerFindingRecord -Finding $advisory -RepositoryRoot $repositoryRoot)
            $comparison = Compare-PSScriptAnalyzerFindingBaseline `
                -FindingRecord $findingRecord -BaselineRecord @($baselineDocument.psscriptanalyzer)
            $findings | Sort-Object ScriptPath,Line,RuleName | ForEach-Object {
                Write-Output "$($_.Severity):$($_.RuleName):$($_.ScriptName):$($_.Line) $($_.Message)"
            }
            $comparison.Resolved | ForEach-Object {
                Write-Output "PSScriptAnalyzer baseline improvement: $($_.path):$($_.rule):occurrence=$($_.occurrence)"
            }
            Write-Output "PSScriptAnalyzer: blocking=$($blocking.Count) advisory=$($advisory.Count) inherited=$($comparison.Inherited.Count) new_advisory=$($comparison.New.Count) baseline_improvements=$($comparison.Resolved.Count)"
            if ($blocking.Count -gt 0 -or $comparison.New.Count -gt 0) { exit 1 }
        }
        'LuaLS' {
            $command = Get-Command lua-language-server -ErrorAction SilentlyContinue
            if (-not $command) { Unavailable 'LuaLS is advisory and is not installed.' }
            Invoke-External $command.Source @('--check', $repositoryRoot, '--checklevel=Warning')
        }
        'Luacheck' {
            $command = Get-Command luacheck -ErrorAction SilentlyContinue
            if (-not $command) { Unavailable 'Luacheck is advisory and is not installed.' }
            Invoke-External $command.Source @('.', '--config', '.luacheckrc')
        }
        'StyLua' {
            $command = Get-Command stylua -ErrorAction SilentlyContinue
            if (-not $command) { Unavailable 'StyLua is check-only advisory and is not installed.' }
            Invoke-External $command.Source @('--check', '.')
        }
    }
}
finally { Pop-Location }
