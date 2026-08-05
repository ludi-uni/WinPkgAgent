function Invoke-WpaProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [ValidateRange(1,3600)][int]$TimeoutSeconds = 30
    )
    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        throw [System.ArgumentException]::new('FilePath is required.')
    }
    if (-not [IO.Path]::IsPathFullyQualified($FilePath)) {
        throw [System.ArgumentException]::new('FilePath must be a fully-qualified path.')
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$psi.ArgumentList.Add([string]$argument) }
    # Tests may set this module-scoped factory to provide a Process-shaped fixture.
    # It receives only the already-constructed StartInfo; lifecycle and timeout handling remain here.
    $process = if($null -ne $script:WpaProcessFactory){& $script:WpaProcessFactory -StartInfo $psi}else{[System.Diagnostics.Process]::new()}
    $process.StartInfo = $psi
    $started = [System.Diagnostics.Stopwatch]::StartNew()
    $killError = $null
    try {
        try { [void]$process.Start() } catch {
            return [pscustomobject]@{ Executable=$FilePath; Arguments=@($Arguments); ExitCode=$null; StdOut=''; StdErr=(Protect-WpaSensitiveText $_.Exception.Message); DurationMs=[Math]::Max(0,[int]$started.ElapsedMilliseconds); TimedOut=$false; Started=$false }
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            try { $process.Kill($true) } catch {
                $killError = Protect-WpaSensitiveText $_.Exception.Message
                return [pscustomobject]@{ Executable=$FilePath; Arguments=@($Arguments); ExitCode=$null; StdOut=''; StdErr=$killError; DurationMs=[Math]::Max(0,[int]$started.ElapsedMilliseconds); TimedOut=$true; Started=$true }
            }
            if(-not $process.WaitForExit(5000)) {
                return [pscustomobject]@{ Executable=$FilePath; Arguments=@($Arguments); ExitCode=$null; StdOut=''; StdErr='Process did not exit after bounded termination wait.'; DurationMs=[Math]::Max(0,[int]$started.ElapsedMilliseconds); TimedOut=$true; Started=$true }
            }
        } else {
            $process.WaitForExit()
        }
        [System.Threading.Tasks.Task]::WaitAll(@($stdoutTask,$stderrTask))
        $standardOutput=Protect-WpaSensitiveText $stdoutTask.Result
        $standardError=Protect-WpaSensitiveText $stderrTask.Result;if($killError){$standardError=(Protect-WpaSensitiveText ($standardError+[Environment]::NewLine+$killError)).Trim()}
        return [pscustomobject]@{ Executable=$FilePath; Arguments=@($Arguments); ExitCode=if($timedOut){$null}else{$process.ExitCode}; StdOut=$standardOutput; StdErr=$standardError; DurationMs=[Math]::Max(0,[int]$started.ElapsedMilliseconds); TimedOut=$timedOut; Started=$true }
    } finally { $started.Stop(); $process.Dispose() }
}
