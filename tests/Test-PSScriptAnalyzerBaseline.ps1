[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repositoryRoot 'tools/PSScriptAnalyzerBaseline.ps1')

function New-PSScriptAnalyzerFinding {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Rule,
        [Parameter(Mandatory)][string] $Message,
        [int] $Line = 1,
        [int] $Column = 1
    )
    [pscustomobject]@{
        ScriptPath = Join-Path $repositoryRoot $Path
        ScriptName = [System.IO.Path]::GetFileName($Path)
        RuleName = $Rule
        Message = $Message
        Line = $Line
        Column = $Column
    }
}

function Assert-Count {
    param([string] $Label, [int] $Actual, [int] $Expected)
    if ($Actual -ne $Expected) { throw "$Label expected $Expected, got $Actual." }
}

function Assert-Throws {
    param([string] $Label, [scriptblock] $Action)
    try { & $Action }
    catch { return }
    throw "$Label did not fail closed."
}

$inherited = New-PSScriptAnalyzerFinding -Path 'tools/A.ps1' -Rule 'RuleA' -Message 'reviewed finding' -Line 10
$baseline = @(ConvertTo-PSScriptAnalyzerFindingRecord -Finding @($inherited) -RepositoryRoot $repositoryRoot)

$exact = Compare-PSScriptAnalyzerFindingBaseline -FindingRecord $baseline -BaselineRecord $baseline
Assert-Count 'exact inherited' $exact.Inherited.Count 1
Assert-Count 'exact new' $exact.New.Count 0
Assert-Count 'exact resolved' $exact.Resolved.Count 0

$movedLine = @(ConvertTo-PSScriptAnalyzerFindingRecord -Finding @(
    (New-PSScriptAnalyzerFinding -Path 'tools/A.ps1' -Rule 'RuleA' -Message 'reviewed finding' -Line 99)
) -RepositoryRoot $repositoryRoot)
$lineResult = Compare-PSScriptAnalyzerFindingBaseline -FindingRecord $movedLine -BaselineRecord $baseline
Assert-Count 'line movement inherited' $lineResult.Inherited.Count 1

$disappeared = Compare-PSScriptAnalyzerFindingBaseline -FindingRecord @() -BaselineRecord $baseline
Assert-Count 'disappeared improvement' $disappeared.Resolved.Count 1

$otherOwner = @(ConvertTo-PSScriptAnalyzerFindingRecord -Finding @(
    (New-PSScriptAnalyzerFinding -Path 'tools/B.ps1' -Rule 'RuleA' -Message 'reviewed finding')
) -RepositoryRoot $repositoryRoot)
$ownerResult = Compare-PSScriptAnalyzerFindingBaseline -FindingRecord $otherOwner -BaselineRecord $baseline
Assert-Count 'moved owner new' $ownerResult.New.Count 1
Assert-Count 'moved owner resolved' $ownerResult.Resolved.Count 1

$sameRuleReplacement = @(ConvertTo-PSScriptAnalyzerFindingRecord -Finding @(
    (New-PSScriptAnalyzerFinding -Path 'tools/A.ps1' -Rule 'RuleA' -Message 'replacement finding')
) -RepositoryRoot $repositoryRoot)
$replacementResult = Compare-PSScriptAnalyzerFindingBaseline -FindingRecord $sameRuleReplacement -BaselineRecord $baseline
Assert-Count 'same rule replacement new' $replacementResult.New.Count 1

$duplicates = @(ConvertTo-PSScriptAnalyzerFindingRecord -Finding @(
    (New-PSScriptAnalyzerFinding -Path 'tools/A.ps1' -Rule 'RuleA' -Message 'reviewed finding' -Line 10),
    (New-PSScriptAnalyzerFinding -Path 'tools/A.ps1' -Rule 'RuleA' -Message 'reviewed finding' -Line 20)
) -RepositoryRoot $repositoryRoot)
$duplicateResult = Compare-PSScriptAnalyzerFindingBaseline -FindingRecord $duplicates -BaselineRecord $baseline
Assert-Count 'duplicate inherited' $duplicateResult.Inherited.Count 1
Assert-Count 'duplicate remains new' $duplicateResult.New.Count 1

$caseDistinct = @(ConvertTo-PSScriptAnalyzerFindingRecord -Finding @(
    (New-PSScriptAnalyzerFinding -Path 'tools/A.ps1' -Rule 'RuleA' -Message 'case-distinct finding'),
    (New-PSScriptAnalyzerFinding -Path 'tools/a.ps1' -Rule 'RuleA' -Message 'case-distinct finding')
) -RepositoryRoot $repositoryRoot)
Assert-Count 'case-distinct owners retained' $caseDistinct.Count 2
if ($caseDistinct[0].occurrence -ne 1 -or $caseDistinct[1].occurrence -ne 1) {
    throw 'Case-distinct owners shared an occurrence counter.'
}
$caseResult = Compare-PSScriptAnalyzerFindingBaseline -FindingRecord $caseDistinct -BaselineRecord @($caseDistinct[0])
Assert-Count 'case-distinct inherited' $caseResult.Inherited.Count 1
Assert-Count 'case-distinct new' $caseResult.New.Count 1
Assert-Count 'case-distinct resolved' $caseResult.Resolved.Count 0

$staleBaseline = @([pscustomobject]@{
    path = 'tools/Removed.ps1'
    rule = 'RemovedRule'
    message_sha256 = ('0' * 64)
    occurrence = 1
})
$staleResult = Compare-PSScriptAnalyzerFindingBaseline -FindingRecord $otherOwner -BaselineRecord $staleBaseline
Assert-Count 'stale baseline cannot hide new' $staleResult.New.Count 1
Assert-Count 'stale baseline improvement' $staleResult.Resolved.Count 1

Assert-Throws 'outside-repository owner' {
    ConvertTo-PSScriptAnalyzerFindingRecord -Finding @(
        (New-PSScriptAnalyzerFinding -Path '../Outside.ps1' -Rule 'RuleA' -Message 'outside')
    ) -RepositoryRoot $repositoryRoot
}
Assert-Throws 'duplicate baseline fingerprint' {
    Compare-PSScriptAnalyzerFindingBaseline -FindingRecord $baseline -BaselineRecord @($baseline[0], $baseline[0])
}

Write-Output 'PSScriptAnalyzer baseline fixtures: inheritance, improvement, owner/message drift, case-distinct owners, duplicates, stale and malformed entries -- OK'
