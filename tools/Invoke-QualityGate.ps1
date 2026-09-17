[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Fast', 'Full', 'Package', 'Security')]
    [string] $Mode,

    [Parameter()]
    [string[]] $ChangedPath = @(),

    [Parameter()]
    [string] $BaseRef,

    [ValidateSet('luajit', 'luajit-lupa')]
    [string] $LuaRuntime = 'luajit',

    [ValidateRange(1, 10500)]
    [int] $BudgetSeconds = 10500,

    [ValidateRange(1, 10500)]
    [int] $CheckTimeoutSeconds = 5400,

    [Parameter(DontShow)]
    [ValidateSet('None', 'MultipleFailures', 'UnavailableTool', 'Streaming', 'Timeout')]
    [string] $SelfTestScenario = 'None'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$safeRepositoryRoot = $repositoryRoot -replace '\\', '/'
$outputRoot = Join-Path $repositoryRoot 'build/verify'
$logsRoot = Join-Path $outputRoot 'logs'
$expectedOutputRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot 'build/verify'))
$resolvedOutputRoot = [System.IO.Path]::GetFullPath($outputRoot)
if ($resolvedOutputRoot -ne $expectedOutputRoot) {
    throw "Unsafe validation output path: $resolvedOutputRoot"
}
if (Test-Path -LiteralPath $resolvedOutputRoot) {
    Remove-Item -LiteralPath $resolvedOutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null

$node = Get-Command node -ErrorAction SilentlyContinue
$pwsh = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $pwsh)) { $pwsh = Join-Path $PSHOME 'pwsh' }
$git = Get-Command git -ErrorAction SilentlyContinue
$checks = New-Object 'System.Collections.Generic.List[object]'
$gateWatch = [System.Diagnostics.Stopwatch]::StartNew()
$script:activeCheck = $null
$script:defaultCheckTimeout = $CheckTimeoutSeconds
$head = 'unknown'
if ($git) {
    $headRows = & $git.Source -c "safe.directory=$safeRepositoryRoot" -C $repositoryRoot rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $headRows) { $head = ([string] $headRows).Trim() }
}

function Protect-LogText([string] $Text) {
    $Text = $Text.Replace($repositoryRoot, '<repo>').Replace($safeRepositoryRoot, '<repo>')
    return $Text -replace '(?i)[A-Z]:[\\/]Users[\\/][^\\/\s]+', '<user-home>'
}

function Save-Progress {
    param([string] $Result = 'incomplete')
    [ordered]@{
        mode = $Mode
        head = $head
        platform = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        powershell = $PSVersionTable.PSVersion.ToString()
        result = $Result
        updated_at = [DateTime]::UtcNow.ToString('o')
        elapsed_seconds = [Math]::Round($gateWatch.Elapsed.TotalSeconds, 3)
        active = $script:activeCheck
        checks = $checks.ToArray()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputRoot 'progress.json') -Encoding utf8
}
Save-Progress

function Convert-ArgumentText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]] $Arguments)

    return ($Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"', '\\"') + '"' } else { $_ }
    }) -join ' '
}

function Add-CheckResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][ValidateSet('pass', 'fail', 'skipped', 'unavailable')][string] $Result,
        [Parameter(Mandatory)][string] $Command,
        [Parameter()][string] $Reason = '',
        [Parameter()][bool] $Blocking = $true,
        [Parameter()][double] $DurationSeconds = 0,
        [Parameter()][string] $Count = '0/0',
        [Parameter()][string[]] $LogLines = @()
    )

    $safeId = $Id -replace '[^A-Za-z0-9._-]', '-'
    $relativeLog = "logs/$safeId.log"
    $logPath = Join-Path $outputRoot $relativeLog
    $safeLogLines = @($LogLines | ForEach-Object {
        $logText = [string] $_
        $logText = $logText.Replace($repositoryRoot, '<repo>')
        $logText = $logText.Replace($safeRepositoryRoot, '<repo>')
        $logText -replace '(?i)[A-Z]:[\\/]Users[\\/][^\\/\s]+', '<user-home>'
    })
    $safeLogLines | Add-Content -LiteralPath $logPath -Encoding utf8
    $checks.Add([ordered]@{
        id = $Id
        result = $Result
        count = $Count
        duration_seconds = [Math]::Round($DurationSeconds, 3)
        log = $relativeLog
        command = Protect-LogText $Command
        blocking = $Blocking
        reason = Protect-LogText $Reason
        started_at = $(if ($script:activeCheck) { $script:activeCheck.started_at } else { $null })
        completed_at = [DateTime]::UtcNow.ToString('o')
        runtime = $(if ($script:activeCheck) { $script:activeCheck.runtime } else { 'in-process' })
        exit_code = $(if ($script:activeCheck) { $script:activeCheck.exit_code } else { $null })
    })
    $script:activeCheck = $null
    Save-Progress
    Write-Host "CHECK END $Id result=$Result seconds=$([Math]::Round($DurationSeconds, 3)) log=$relativeLog $(Protect-LogText $Reason)"
}

function Invoke-QualityCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter()][string[]] $Arguments = @(),
        [Parameter()][bool] $Blocking = $true,
        [Parameter()][int[]] $UnavailableExitCodes = @(),
        [Parameter()][int] $TimeoutSeconds = $script:defaultCheckTimeout
    )

    $commandText = "$(Split-Path -Leaf $FilePath) $(Convert-ArgumentText $Arguments)".Trim()
    if (-not $FilePath -or -not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Add-CheckResult -Id $Id -Result unavailable -Command $commandText `
            -Reason 'required executable is unavailable' -Blocking $Blocking `
            -LogLines @('Required executable is unavailable.')
        return
    }

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $relativeLog = "logs/$($Id -replace '[^A-Za-z0-9._-]', '-').log"
    $logPath = Join-Path $outputRoot $relativeLog
    $script:activeCheck = [ordered]@{
        id = $Id; result = 'running'; started_at = [DateTime]::UtcNow.ToString('o')
        command = Protect-LogText $commandText; runtime = Split-Path -Leaf $FilePath
        log = $relativeLog; exit_code = $null; completed_at = $null
    }
    Save-Progress
    Write-Host "CHECK START $Id at=$($script:activeCheck.started_at) command=$($script:activeCheck.command) log=$relativeLog"
    $remaining = $BudgetSeconds - $gateWatch.Elapsed.TotalSeconds
    if ($remaining -le 0) {
        Add-CheckResult -Id $Id -Result fail -Command $commandText -Blocking $Blocking `
            -Reason 'incomplete: profile execution budget exhausted before start'
        return
    }
    $limit = [Math]::Min($TimeoutSeconds, $remaining)
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $repositoryRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Environment['BETTER_NEXUS_QUALITY_GATE_ACTIVE'] = '1'
    foreach ($argument in $Arguments) { [void] $startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stdout = ''
    $stderr = ''
    $interruption = ''
    $exitCode = 1
    $started = $false
    try {
        [void] $process.Start()
        $started = $true
        # Both asynchronous reads stay pending together. Neither pipe waits for
        # the other pipe to reach EOF. Complete lines are redacted before storage.
        $streams = @(
            @{ Reader = $process.StandardOutput; Buffer = [char[]]::new(4096); Pending = $null; Text = ''; Done = $false; Kind = 'stdout' },
            @{ Reader = $process.StandardError; Buffer = [char[]]::new(4096); Pending = $null; Text = ''; Done = $false; Kind = 'stderr' }
        )
        foreach ($stream in $streams) { $stream.Pending = $stream.Reader.ReadAsync($stream.Buffer, 0, $stream.Buffer.Length) }
        while (@($streams | Where-Object { -not $_.Done }).Count -gt 0 -or -not $process.HasExited) {
            if ($interruption -and $watch.Elapsed.TotalSeconds -ge ($limit + 5)) { break }
            if (-not $interruption -and $watch.Elapsed.TotalSeconds -ge $limit) {
                $interruption = "timeout: incomplete after $limit seconds"
                if (-not $process.HasExited) { $process.Kill($true) }
            }
            foreach ($stream in $streams) {
                if ($stream.Done -or -not $stream.Pending.IsCompleted) { continue }
                $length = $stream.Pending.GetAwaiter().GetResult()
                if ($length -eq 0) { $stream.Done = $true }
                else { $stream.Text += [string]::new($stream.Buffer, 0, $length) }
                # Keep an unfinished line redacted as a whole, including paths
                # split across read boundaries. Never stream an unsafe fragment.
                [System.IO.File]::WriteAllText("$logPath.$($stream.Kind).partial.log", (Protect-LogText $stream.Text))
                while ($stream.Text.Contains("`n") -or ($stream.Done -and $stream.Text.Length -gt 0)) {
                    $boundary = $stream.Text.IndexOf("`n")
                    if ($boundary -lt 0) { $boundary = $stream.Text.Length - 1 }
                    $line = Protect-LogText $stream.Text.Substring(0, $boundary + 1)
                    $stream.Text = $stream.Text.Substring($boundary + 1)
                    [System.IO.File]::AppendAllText($logPath, $line)
                    Write-Host -NoNewline $line
                    # Only a bounded tail is needed for count and unavailable markers.
                    if ($stream.Kind -eq 'stdout') { $stdout = ($stdout + $line); if ($stdout.Length -gt 65536) { $stdout = $stdout.Substring($stdout.Length - 65536) } }
                    else { $stderr = ($stderr + $line); if ($stderr.Length -gt 65536) { $stderr = $stderr.Substring($stderr.Length - 65536) } }
                }
                if (-not $stream.Done) { $stream.Pending = $stream.Reader.ReadAsync($stream.Buffer, 0, $stream.Buffer.Length) }
            }
            Start-Sleep -Milliseconds 20
        }
        $exitCode = $process.ExitCode
    }
    catch {
        $stderr = $_.Exception.Message
        [System.IO.File]::AppendAllText($logPath, (Protect-LogText $stderr))
        $exitCode = 1
    }
    finally {
        $watch.Stop()
        if ($started -and -not $process.HasExited) { $process.Kill($true) }
        $process.Dispose()
    }
    $lines = @("CHECK TERMINAL completed_at=$([DateTime]::UtcNow.ToString('o')) exit_code=$exitCode interruption=$interruption")
    if ($interruption) { $exitCode = 124 }
    $script:activeCheck.exit_code = $exitCode
    $unavailable = $exitCode -in $UnavailableExitCodes -and "$stdout`n$stderr" -match '(?m)^UNAVAILABLE:'
    $result = if ($exitCode -eq 0) { 'pass' } elseif ($unavailable) { 'unavailable' } else { 'fail' }
    $count = if ($exitCode -eq 0) { '1/1' } elseif ($unavailable) { '0/0' } else { '0/1' }
    if ($stdout -match 'Lua suite:\s*(?<passed>\d+)/(?<total>\d+) passed') {
        $count = "$($Matches.passed)/$($Matches.total)"
    }
    elseif ($stdout -match 'Lua 5\.1 parse:\s*(?<passed>\d+) passed,\s*(?<failed>\d+) failed') {
        $count = "$($Matches.passed)/$([int] $Matches.passed + [int] $Matches.failed)"
    }
    elseif ($stdout -match 'checks=(?<passed>\d+) failures=(?<failed>\d+)') {
        $count = "$($Matches.passed)/$([int] $Matches.passed + [int] $Matches.failed)"
    }
    Add-CheckResult -Id $Id -Result $result -Command $commandText `
        -Reason $(if ($interruption) { $interruption } elseif ($exitCode -eq 0) { '' } elseif ($unavailable) { 'required tool is unavailable' } else { "command exited $exitCode" }) `
        -Blocking $Blocking -DurationSeconds $watch.Elapsed.TotalSeconds `
        -Count $count -LogLines $lines
}

function Add-ArtifactPathCheck {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Paths)

    . (Join-Path $PSScriptRoot 'ArtifactPathPolicy.ps1')
    $violations = @(Test-ArtifactPathSet -RepositoryRoot $repositoryRoot `
        -Candidates $Paths -ReadContent)
    if ($violations.Count -gt 0) {
        Add-CheckResult -Id 'artifact-paths' -Result fail -Command 'shared artifact path policy' `
            -Reason 'forbidden artifact path detected' -Count "0/$($violations.Count)" -LogLines $violations
    }
    else {
        Add-CheckResult -Id 'artifact-paths' -Result pass -Command 'shared artifact path policy' `
            -Count "$($Paths.Count)/$($Paths.Count)" -LogLines @("Checked $($Paths.Count) changed path(s).")
    }
}

function Get-ChangedPlan {
    [CmdletBinding()]
    param()

    $arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Get-ChangedTestPlan.ps1'))
    if ($ChangedPath.Count -gt 0) { $arguments += '-Paths'; $arguments += $ChangedPath }
    if ($BaseRef) { $arguments += @('-BaseRef', $BaseRef) }
    $result = & $pwsh @arguments
    if ($LASTEXITCODE -ne 0) { throw 'changed-path planning failed' }
    return $result | ConvertFrom-Json
}

function Add-NodeCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter()][bool] $Blocking = $true
    )

    if (-not $node) {
        Add-CheckResult -Id $Id -Result unavailable -Command "node $(Convert-ArgumentText $Arguments)" `
            -Reason 'Node.js is unavailable' -Blocking $Blocking -LogLines @('Node.js is unavailable.')
        return
    }
    Invoke-QualityCheck -Id $Id -FilePath $node.Source -Arguments $Arguments -Blocking $Blocking
}

function Add-PowerShellCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter()][bool] $Blocking = $true,
        [Parameter()][int[]] $UnavailableExitCodes = @()
    )

    Invoke-QualityCheck -Id $Id -FilePath $pwsh -Arguments (@('-NoProfile', '-File') + $Arguments) `
        -Blocking $Blocking -UnavailableExitCodes $UnavailableExitCodes
}

function Add-LuaCheck {
    param([string] $Id, [string] $Test)
    Add-NodeCheck -Id $Id -Arguments @('tools/Run-LuaSuite.js', '--runtime', $LuaRuntime,
        '--test', $Test, '--timeout-seconds', '600')
}

function Add-GitDiffCheckSet {
    [CmdletBinding()]
    param()

    if ($BaseRef) {
        Add-PowerShellCheck -Id 'git-diff-check-range' `
            -Arguments @('tools/Test-GitDiffCheck.ps1', '-Mode', 'Range', '-BaseRef', $BaseRef)
    }
    else {
        Add-CheckResult -Id 'git-diff-check-range' -Result skipped `
            -Command 'git diff --check <BaseRef>...HEAD' `
            -Reason 'BaseRef was not supplied; committed range was not evaluated' `
            -Blocking $false -LogLines @('Committed-range whitespace validation requires BaseRef.')
    }
    Add-PowerShellCheck -Id 'git-diff-check-staged' `
        -Arguments @('tools/Test-GitDiffCheck.ps1', '-Mode', 'Staged')
    Add-PowerShellCheck -Id 'git-diff-check-working' `
        -Arguments @('tools/Test-GitDiffCheck.ps1', '-Mode', 'Working')
}

Push-Location $repositoryRoot
try {
    if ($SelfTestScenario -eq 'Streaming') {
        Invoke-QualityCheck -Id 'self-stream' -FilePath $node.Source -Arguments @('-e',
            'for(let i=0;i<2000;i++){console.log("OUT-"+i+" "+"x".repeat(256));console.error("ERR-"+i+" "+"y".repeat(256));} console.log("C:\\Users\\Private\\fixture");')
    }
    elseif ($SelfTestScenario -eq 'Timeout') {
        Invoke-QualityCheck -Id 'self-timeout' -FilePath $node.Source -Arguments @('-e',
            'console.log("PARTIAL-BEFORE-TIMEOUT"); setInterval(()=>{},1000);') -TimeoutSeconds 2
    }
    elseif ($SelfTestScenario -eq 'MultipleFailures') {
        Invoke-QualityCheck -Id 'self-pass' -FilePath $pwsh -Arguments @('-NoProfile', '-Command', 'exit 0')
        Invoke-QualityCheck -Id 'self-fail-a' -FilePath $pwsh -Arguments @('-NoProfile', '-Command', 'Write-Error first; exit 7')
        Invoke-QualityCheck -Id 'self-fail-b' -FilePath $pwsh -Arguments @('-NoProfile', '-Command', 'Write-Error second; exit 8')
    }
    elseif ($SelfTestScenario -eq 'UnavailableTool') {
        Add-CheckResult -Id 'self-unavailable' -Result unavailable -Command 'missing-quality-tool --check' `
            -Reason 'required tool missing for self-test' -LogLines @('Required tool missing for self-test.')
    }
    else {
        $plan = Get-ChangedPlan
        Add-CheckResult -Id 'changed-test-plan' -Result pass -Command 'tools/Get-ChangedTestPlan.ps1' `
            -Count "$($plan.paths.Count)/$($plan.paths.Count)" `
            -LogLines @($plan | ConvertTo-Json -Depth 8)
        Add-ArtifactPathCheck -Paths @($plan.paths)

        if ($Mode -eq 'Fast') {
            foreach ($luaPath in @($plan.paths | Where-Object {
                $_ -match '\.lua$' -and @($plan.deleted_paths) -notcontains $_
            })) {
                Add-NodeCheck -Id "lua-parse-$([System.IO.Path]::GetFileNameWithoutExtension($luaPath))" `
                    -Arguments @('tools/parse-lua51.js', $luaPath)
            }
            foreach ($test in @($plan.tests)) {
                if (-not (Test-Path -LiteralPath $test -PathType Leaf)) {
                    Add-CheckResult -Id "mapped-$([System.IO.Path]::GetFileNameWithoutExtension($test))" `
                        -Result skipped -Command $test -Reason 'mapped check is owned by a later checkpoint' `
                        -Blocking $false -LogLines @("Mapped check not present yet: $test")
                    continue
                }
                if ($test.EndsWith('.lua')) {
                    Add-LuaCheck -Id "mapped-$([System.IO.Path]::GetFileNameWithoutExtension($test))" -Test $test
                }
                else {
                    Add-NodeCheck -Id "mapped-$([System.IO.Path]::GetFileNameWithoutExtension($test))" `
                        -Arguments @($test)
                }
            }
            Add-NodeCheck -Id 'package-metadata' -Arguments @('tests/run-package-metadata.js')
            Add-PowerShellCheck -Id 'release-policy' -Arguments @('tools/Test-ReleasePolicy.ps1')
            Add-GitDiffCheckSet
        }
        elseif ($Mode -eq 'Full') {
            Invoke-QualityCheck -Id 'lua-suite' -FilePath $node.Source `
                -Arguments @('tools/Run-LuaSuite.js', '--runtime', $LuaRuntime, '--timeout-seconds', '600') -TimeoutSeconds $BudgetSeconds
            Write-Host 'Tester runtime policy: complete LuaJIT primary; duplicate Fengari inventory NOT RUN -- SUPPLEMENTARY. Unique JavaScript runners remain required.'
            Add-CheckResult -Id 'lua-suite-manual-legacy-backup' -Result skipped `
                -Command 'manual: tests/run_legacy_backup_smoke.lua <authorized-backup>' `
                -Reason 'requires an explicitly authorized SavedVariables backup path' `
                -Blocking $false -LogLines @('Manual SavedVariables smoke test was not run.')
            Add-NodeCheck -Id 'lua51-parse' -Arguments @('tools/parse-lua51.js', '.', '--tests')
            Add-NodeCheck -Id 'upvalue-boundary' -Arguments @('tests/run-upvalue-compatibility.js')
            Add-LuaCheck -Id 'integration' -Test 'tests/run_integration.lua'
            Add-LuaCheck -Id 'hostile-sync' -Test 'tests/run_sync_hostile_fuzz.lua'
            Add-NodeCheck -Id 'pr58-expected-red' -Arguments @('tests/run-pr58-expected-red.js')
            Add-NodeCheck -Id 'catalog-authority-expected-red' -Arguments @('tests/run-catalog-authority-expected-red.js')
            Add-NodeCheck -Id 'bundled-exporter' -Arguments @('tests/run-bundled-build-export.js')
            Add-NodeCheck -Id 'savedvariables-analyzer' -Arguments @('tests/run-savedvariables-analyzer.js')
            Add-NodeCheck -Id 'package-metadata' -Arguments @('tests/run-package-metadata.js')
            Add-NodeCheck -Id 'package-source' -Arguments @('tools/Test-PackageSource.js', '.')
            Add-LuaCheck -Id 'module-contracts' -Test 'tests/run_module_contract_characterization.lua'
            Add-LuaCheck -Id 'privacy' -Test 'tests/run_security_hardening.lua'
            Add-LuaCheck -Id 'stutteralert' -Test 'tests/run_stutteralert_integration.lua'
            Add-PowerShellCheck -Id 'release-policy' -Arguments @('tools/Test-ReleasePolicy.ps1')
            Add-GitDiffCheckSet
        }
        elseif ($Mode -eq 'Package') {
            Add-NodeCheck -Id 'package-source' -Arguments @('tools/Test-PackageSource.js', '.')
            Add-NodeCheck -Id 'package-metadata' -Arguments @('tests/run-package-metadata.js')
            Add-NodeCheck -Id 'package-lua51' -Arguments @('tools/parse-lua51.js', '.')
            Add-LuaCheck -Id 'package-privacy' -Test 'tests/run_security_hardening.lua'
            Add-PowerShellCheck -Id 'release-policy' -Arguments @('tools/Test-ReleasePolicy.ps1')
            Add-GitDiffCheckSet
        }
        elseif ($Mode -eq 'Security') {
            Add-PowerShellCheck -Id 'staged-artifacts' -Arguments @('tools/Test-StagedArtifacts.ps1', '-Mode', 'All')
            Add-NodeCheck -Id 'security-policy-self-tests' -Arguments @('tests/run-security-policy.js')
            Add-PowerShellCheck -Id 'release-policy' -Arguments @('tools/Test-ReleasePolicy.ps1')
            foreach ($blockingCheck in @('Gitleaks', 'Actionlint', 'Zizmor', 'PSScriptAnalyzer')) {
                Add-PowerShellCheck -Id $blockingCheck.ToLowerInvariant() `
                    -Arguments @('tools/Test-SecurityPolicy.ps1', '-Check', $blockingCheck) `
                    -UnavailableExitCodes @(3)
            }
            foreach ($advisoryCheck in @('LuaLS', 'Luacheck', 'StyLua')) {
                Add-PowerShellCheck -Id $advisoryCheck.ToLowerInvariant() `
                    -Arguments @('tools/Test-SecurityPolicy.ps1', '-Check', $advisoryCheck) `
                    -Blocking $false -UnavailableExitCodes @(3)
            }
            Add-GitDiffCheckSet
        }
    }
}
finally {
    Pop-Location
}

$gateWatch.Stop()
$head = 'unknown'
if ($git) {
    $headRows = & $git.Source -c "safe.directory=$safeRepositoryRoot" -C $repositoryRoot rev-parse HEAD
    if ($LASTEXITCODE -eq 0 -and $headRows) { $head = ([string] $headRows).Trim() }
}
$payloadPath = Join-Path $outputRoot 'summary-input.json'
[ordered]@{
    schema = 1
    mode = $Mode
    head = $head
    duration_seconds = [Math]::Round($gateWatch.Elapsed.TotalSeconds, 3)
    checks = $checks.ToArray()
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $payloadPath -Encoding utf8

if (-not $node) {
    throw 'Node.js is required to write the compact validation summary.'
}
& $node.Source (Join-Path $PSScriptRoot 'Write-ValidationSummary.js') `
    --input $payloadPath --output-dir $outputRoot
if ($LASTEXITCODE -ne 0) { throw 'validation summary generation failed' }
Remove-Item -LiteralPath $payloadPath -Force

$summary = Get-Content -Raw -LiteralPath (Join-Path $outputRoot 'summary.json') | ConvertFrom-Json
Save-Progress -Result $summary.result
Write-Output "Quality gate $Mode`: $($summary.result); passed=$($summary.passed) failed=$($summary.failed) unavailable=$($summary.unavailable) skipped=$($summary.skipped)"
if ($summary.result -ne 'pass') { exit 1 }
