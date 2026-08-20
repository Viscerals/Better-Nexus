Set-StrictMode -Version Latest

function Invoke-GitByteOutput {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    $safeRepositoryRoot = ([System.IO.Path]::GetFullPath($RepositoryRoot)) -replace '\\', '/'
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-c', "safe.directory=$safeRepositoryRoot", '-C', $RepositoryRoot) + $Arguments) {
        [void] $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $output = [System.IO.MemoryStream]::new()
    try {
        if (-not $process.Start()) { throw 'Unable to start git.' }
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.StandardOutput.BaseStream.CopyTo($output)
        $process.WaitForExit()
        $errorText = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "git $($Arguments -join ' ') failed with exit code $($process.ExitCode): $errorText"
        }
        return ,$output.ToArray()
    }
    finally {
        $output.Dispose()
        $process.Dispose()
    }
}

function ConvertFrom-NulDelimitedUtf8 {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]] $Bytes)

    if ($Bytes.Length -eq 0) { return @() }
    if ($Bytes[-1] -ne 0) { throw 'NUL-delimited Git output is missing its final terminator.' }
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    $tokens = [System.Collections.Generic.List[string]]::new()
    $start = 0
    for ($index = 0; $index -lt $Bytes.Length; $index++) {
        if ($Bytes[$index] -ne 0) { continue }
        try {
            $tokens.Add($encoding.GetString($Bytes, $start, $index - $start))
        }
        catch {
            throw "Git returned a path that is not valid UTF-8: $($_.Exception.Message)"
        }
        $start = $index + 1
    }
    return @($tokens)
}

function ConvertFrom-GitNameStatusOutput {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]] $Bytes)

    $tokens = @(ConvertFrom-NulDelimitedUtf8 -Bytes $Bytes)
    $records = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $tokens.Count;) {
        $status = $tokens[$index++]
        if ($status -notmatch '^(?<kind>[ACDMR])[0-9]*$') {
            throw "Unsupported or malformed Git name-status token: '$status'"
        }
        $kind = $Matches.kind
        $pathCount = if ($kind -in @('R', 'C')) { 2 } else { 1 }
        if ($index + $pathCount -gt $tokens.Count) {
            throw "Git name-status record '$status' is missing a path."
        }
        $source = $tokens[$index++]
        if (-not $source) { throw "Git name-status record '$status' contains an empty path." }
        if ($pathCount -eq 2) {
            $destination = $tokens[$index++]
            if (-not $destination) { throw "Git name-status record '$status' contains an empty destination." }
            $records.Add([pscustomobject]@{
                Path = $source
                Deleted = $kind -eq 'R'
                Status = $kind
                Role = 'source'
            })
            $records.Add([pscustomobject]@{
                Path = $destination
                Deleted = $false
                Status = $kind
                Role = 'destination'
            })
        }
        else {
            $records.Add([pscustomobject]@{
                Path = $source
                Deleted = $kind -eq 'D'
                Status = $kind
                Role = 'path'
            })
        }
    }
    return @($records)
}

function Get-GitChangedPathRecord {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [string] $BaseRef
    )

    $records = [System.Collections.Generic.List[object]]::new()
    $diffs = @(
        @('diff', '--name-status', '-z', '--find-renames', '--find-copies', '--find-copies-harder', '--diff-filter=ACMRD'),
        @('diff', '--cached', '--name-status', '-z', '--find-renames', '--find-copies', '--find-copies-harder', '--diff-filter=ACMRD')
    )
    if ($BaseRef) {
        $diffs += ,@('diff', '--name-status', '-z', '--find-renames', '--find-copies', '--find-copies-harder', '--diff-filter=ACMRD', "$BaseRef...HEAD")
    }
    foreach ($arguments in $diffs) {
        $bytes = Invoke-GitByteOutput -RepositoryRoot $RepositoryRoot -Arguments $arguments
        foreach ($record in @(ConvertFrom-GitNameStatusOutput -Bytes $bytes)) {
            $records.Add($record)
        }
    }

    $untrackedBytes = Invoke-GitByteOutput -RepositoryRoot $RepositoryRoot `
        -Arguments @('ls-files', '--others', '--exclude-standard', '-z')
    foreach ($path in @(ConvertFrom-NulDelimitedUtf8 -Bytes $untrackedBytes)) {
        if (-not $path) { throw 'Git returned an empty untracked path.' }
        $records.Add([pscustomobject]@{
            Path = $path
            Deleted = $false
            Status = 'A'
            Role = 'path'
        })
    }
    return @($records)
}
