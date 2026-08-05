function Invoke-WpaProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [ValidateRange(1,3600)][int]$TimeoutSeconds = 30,
        [scriptblock]$ProcessRunner
    )
    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        throw [System.ArgumentException]::new('FilePath is required.')
    }
    if (-not [IO.Path]::IsPathFullyQualified($FilePath)) {
        throw [System.ArgumentException]::new('FilePath must be a fully-qualified path.')
    }

    if ($null -ne $ProcessRunner) {
        $injected = & $ProcessRunner -FilePath $FilePath -Arguments @($Arguments) -TimeoutSeconds $TimeoutSeconds
        return [pscustomobject]@{
            Executable = $FilePath
            Arguments = @($Arguments)
            ExitCode = Get-WpaPropertyValue $injected 'ExitCode'
            StdOut = Protect-WpaSensitiveText (Get-WpaPropertyValue $injected 'StdOut' '')
            StdErr = Protect-WpaSensitiveText (Get-WpaPropertyValue $injected 'StdErr' '')
            DurationMs = [Math]::Max(0, [int](Get-WpaPropertyValue $injected 'DurationMs' 0))
            TimedOut = [bool](Get-WpaPropertyValue $injected 'TimedOut' $false)
            Started = [bool](Get-WpaPropertyValue $injected 'Started' $true)
        }
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$psi.ArgumentList.Add([string]$argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $started = [System.Diagnostics.Stopwatch]::StartNew()
    $killError = $null
    try {
        try { [void]$process.Start() } catch {
            return [pscustomobject]@{ Executable=$FilePath; Arguments=@($Arguments); ExitCode=$null; StdOut=''; StdErr=$_.Exception.Message; DurationMs=[int]$started.ElapsedMilliseconds; TimedOut=$false; Started=$false }
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            try { $process.Kill($true) } catch {
                $killError = Protect-WpaSensitiveText $_.Exception.Message
                return [pscustomobject]@{ Executable=$FilePath; Arguments=@($Arguments); ExitCode=$null; StdOut=''; StdErr=$killError; DurationMs=[int]$started.ElapsedMilliseconds; TimedOut=$true; Started=$true }
            }
            if(-not $process.WaitForExit(5000)) {
                return [pscustomobject]@{ Executable=$FilePath; Arguments=@($Arguments); ExitCode=$null; StdOut=''; StdErr='Process did not exit after bounded termination wait.'; DurationMs=[int]$started.ElapsedMilliseconds; TimedOut=$true; Started=$true }
            }
        } else {
            $process.WaitForExit()
        }
        [System.Threading.Tasks.Task]::WaitAll(@($stdoutTask,$stderrTask))
        $standardError=$stderrTask.Result;if($killError){$standardError=(Protect-WpaSensitiveText ($standardError+[Environment]::NewLine+$killError)).Trim()}
        return [pscustomobject]@{ Executable=$FilePath; Arguments=@($Arguments); ExitCode=if($timedOut){$null}else{$process.ExitCode}; StdOut=$stdoutTask.Result; StdErr=$standardError; DurationMs=[int]$started.ElapsedMilliseconds; TimedOut=$timedOut; Started=$true }
    } finally { $started.Stop(); $process.Dispose() }
}
