function Invoke-WpaPlan {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$PlanPath,[Parameter(Mandatory)][string]$ApprovalPath,
        [Parameter(Mandatory)][string]$PolicyPath,[string]$OutputPath='./artifacts/apply-result.json',[string]$VerifyOutputPath='./artifacts/verify-result.json',[string]$SummaryPath='./artifacts/run-summary.md',[switch]$DiagnosticLogging
    )
    $started=[datetimeoffset]::UtcNow
    $plan=Read-WpaJsonFile $PlanPath; Test-WpaDataSchema $plan plan|Out-Null;Assert-WpaPlanActionSet -Actions @($plan.actions)|Out-Null;Assert-WpaPlanIntegrity $plan|Out-Null
    if($started -gt [datetimeoffset]::Parse($plan.expiresAt,[Globalization.CultureInfo]::InvariantCulture)){throw 'Plan has expired.'}
    $approval=Read-WpaJsonFile $ApprovalPath;Test-WpaDataSchema $approval approval|Out-Null;Assert-WpaApproval $approval $plan.planId $plan.planHash $started|Out-Null
    if($plan.environmentId -ne (Get-WpaEnvironmentId)){throw 'Plan targets a different environment.'}
    $policy=Read-WpaPolicyFile $PolicyPath;Test-WpaDataSchema $policy policy|Out-Null
    if((Get-WpaObjectHash $policy) -ne $plan.policyHash){throw 'Policy changed after plan creation.'}
    $currentInventory=Get-WpaInventory
    foreach($snapshot in @($plan.managerFingerprints | Where-Object { $null -ne $_ })){
        $current=@($currentInventory.managers | Where-Object manager -eq $snapshot.manager | Select-Object -First 1).fingerprint
        if($null -eq $snapshot.fingerprint -or $null -eq $current){throw "MANAGER_FINGERPRINT_UNAVAILABLE: $($snapshot.manager)"}
        $snapshotSignatureStatus=[string]$snapshot.fingerprint.signatureStatus
        $currentSignatureStatus=[string]$current.signatureStatus
        if([string]::IsNullOrEmpty($snapshotSignatureStatus) -or [string]::IsNullOrEmpty($currentSignatureStatus) -or $snapshotSignatureStatus -in @('unknown','unavailable','MANAGER_FINGERPRINT_UNAVAILABLE') -or $currentSignatureStatus -in @('unknown','unavailable','MANAGER_FINGERPRINT_UNAVAILABLE')){throw "MANAGER_FINGERPRINT_UNAVAILABLE: $($snapshot.manager)"}
        if($snapshotSignatureStatus -in @('NotSigned','Unknown','HashMismatch','NotTrusted','Invalid') -or $currentSignatureStatus -in @('NotSigned','Unknown','HashMismatch','NotTrusted','Invalid')){throw "MANAGER_SIGNATURE_INVALID: $($snapshot.manager)"}
        if($current.aclAssessment -ne 'trusted' -and $current.aclAssessment -notlike 'trusted;*'){throw "MANAGER_PATH_UNTRUSTED: $($snapshot.manager)"}
        if((Get-WpaObjectHash $snapshot.fingerprint) -ne (Get-WpaObjectHash $current)){throw "MANAGER_EXECUTABLE_CHANGED: $($snapshot.manager)"}
    }
    if((Get-WpaInventoryStateHash $currentInventory) -ne $plan.inventoryHash){throw 'Inventory state changed after plan creation.'}
    $operations=@($plan.actions|Where-Object classification -in @('install','upgrade'))
    if($operations.Count -gt $policy.maxOperations){throw 'Plan exceeds the current maximum operation count.'}
    foreach($operation in $operations){if($operation.operation -notin @('install','upgrade')){throw 'Plan contains an unsupported operation.'}}
    $results=[System.Collections.Generic.List[object]]::new();$failed=$false
    $journalPath=if($OutputPath){[IO.Path]::ChangeExtension($OutputPath,'.journal.json')}else{$null}
    $journal=[pscustomobject][ordered]@{schemaVersion=1;planId=$plan.planId;startedAt=$started.ToString('o');updatedAt=$started.ToString('o');entries=@()}
    foreach($operation in $operations){
        if($failed){$results.Add([pscustomobject]@{manager=$operation.manager;id=$operation.id;operation=$operation.operation;status='not-run';reasonCode='STOPPED_AFTER_FAILURE'});continue}
        if(-not $PSCmdlet.ShouldProcess("$($operation.manager)/$($operation.id)",$operation.operation)){$results.Add([pscustomobject]@{manager=$operation.manager;id=$operation.id;operation=$operation.operation;status='what-if';reasonCode='SHOULD_PROCESS_DECLINED'});continue}
        $phase='journal-before';$external=$null
        try {
            if($journalPath){$journal.entries=@($journal.entries)+@([pscustomobject]@{manager=$operation.manager;id=$operation.id;operation=$operation.operation;status='starting';recordedAt=[datetimeoffset]::UtcNow.ToString('o')});$journal.updatedAt=[datetimeoffset]::UtcNow.ToString('o');Write-WpaAtomicJson $journalPath $journal}
            $phase='adapter'
            $external=Invoke-WpaManagerAction -Action $operation -TimeoutSeconds ([int]$policy.operationTimeoutSeconds)
            $reboot=([int64](Get-WpaPropertyValue $external 'ExitCode' -1) -eq 3010) -or [bool](Get-WpaPropertyValue $external 'RebootRequired' $false)
            $ok=(($external.ExitCode -eq 0 -or $reboot) -and -not $external.TimedOut)
            $stdoutMeta=Get-WpaOutputMetadata $external.StdOut;$stderrMeta=Get-WpaOutputMetadata $external.StdErr
            $operationResult=[ordered]@{manager=$operation.manager;id=$operation.id;operation=$operation.operation;status=$(if($ok){'completed'}else{'failed'});reasonCode=$(if($reboot){'REBOOT_REQUIRED'}elseif($ok){'COMMAND_SUCCEEDED'}elseif($external.TimedOut){'COMMAND_TIMED_OUT'}else{'COMMAND_FAILED'});exitCode=$external.ExitCode;durationMs=$external.DurationMs;timedOut=[bool]$external.TimedOut;rebootRequired=$reboot;stdoutHash=$stdoutMeta.hash;stderrHash=$stderrMeta.hash;stdoutLength=$stdoutMeta.length;stderrLength=$stderrMeta.length;stdoutTruncated=$stdoutMeta.truncated;stderrTruncated=$stderrMeta.truncated;failureSummary=$(if($external.TimedOut){'Command timed out.'}elseif(-not $ok){'Command failed.'}else{$null});diagnosticLoggingEnabled=[bool]$DiagnosticLogging}
            if($DiagnosticLogging){$diagnostic=ConvertTo-WpaDiagnosticText $external.StdOut $external.StdErr;$operationResult.diagnostic=$diagnostic.text;$operationResult.diagnosticTruncated=$diagnostic.truncated;$operationResult.diagnosticWarning='Secret removal is not complete.'}
            $operationResult=[pscustomobject]$operationResult
            $phase='journal-after'
            if($journalPath){$journal.entries=@($journal.entries)+@([pscustomobject]@{manager=$operation.manager;id=$operation.id;operation=$operation.operation;status=$operationResult.status;reasonCode=$operationResult.reasonCode;recordedAt=[datetimeoffset]::UtcNow.ToString('o')});$journal.updatedAt=[datetimeoffset]::UtcNow.ToString('o');Write-WpaAtomicJson $journalPath $journal}
            $results.Add($operationResult)
            if(-not $ok){$failed=$true}
        }catch{
            $reasonCode=if($phase -like 'journal-*'){'JOURNAL_WRITE_FAILED'}else{'ADAPTER_EXCEPTION'}
            $exceptionText=$_.Exception.Message;$stdoutMeta=Get-WpaOutputMetadata $null;$stderrMeta=Get-WpaOutputMetadata $exceptionText
            $errorResult=[ordered]@{manager=$operation.manager;id=$operation.id;operation=$operation.operation;status='failed';reasonCode=$reasonCode;exitCode=(Get-WpaPropertyValue $external 'ExitCode');durationMs=[int](Get-WpaPropertyValue $external 'DurationMs' 0);timedOut=[bool](Get-WpaPropertyValue $external 'TimedOut' $false);rebootRequired=$false;stdoutHash=$stdoutMeta.hash;stderrHash=$stderrMeta.hash;stdoutLength=$stdoutMeta.length;stderrLength=$stderrMeta.length;stdoutTruncated=$false;stderrTruncated=$false;failureSummary='Adapter execution failed.';diagnosticLoggingEnabled=[bool]$DiagnosticLogging}
            if($DiagnosticLogging){$diagnostic=ConvertTo-WpaDiagnosticText $null $exceptionText;$errorResult.diagnostic=$diagnostic.text;$errorResult.diagnosticTruncated=$diagnostic.truncated;$errorResult.diagnosticWarning='Secret removal is not complete.'}
            $results.Add([pscustomobject]$errorResult);$failed=$true
        }
    }
    $executed=@($results|Where-Object status -eq completed)
    $verifyItems=@()
    if($executed.Count -gt 0){
        $afterInventory=Get-WpaInventory
        $executedKeys=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach($item in $executed){$null=$executedKeys.Add("$($item.manager)`0$($item.id)")}
        foreach($operation in $operations|Where-Object {$executedKeys.Contains("$($_.manager)`0$($_.id)")}){$verifyItems+=Test-WpaExpectedState -Action $operation -Inventory $afterInventory}
    }
    $finished=[datetimeoffset]::UtcNow
    $status=if($failed){'partial-failure'}elseif(@($results|Where-Object status -eq 'what-if').Count -gt 0){'what-if'}else{'success'}
    $rebootRequired=@($results|Where-Object {[bool](Get-WpaPropertyValue $_ 'rebootRequired' $false)}).Count -gt 0
    $result=[pscustomobject][ordered]@{schemaVersion=1;planId=$plan.planId;status=$status;startedAt=$started.ToString('o');finishedAt=$finished.ToString('o');operations=@($results);rebootRequired=$rebootRequired;warnings=@('Automatic rollback is not guaranteed.')}
    $verify=[pscustomobject][ordered]@{schemaVersion=1;planId=$plan.planId;status=$(if($rebootRequired){'reboot-required'}elseif(@($verifyItems|Where-Object status -in @('verification-failed','indeterminate')).Count -gt 0){'failed'}elseif($verifyItems.Count -eq 0){'not-run'}else{'success'});verifiedAt=$finished.ToString('o');items=@($verifyItems);rebootRequired=$rebootRequired}
    Test-WpaDataSchema -Data $result -SchemaName apply-result | Out-Null;Test-WpaDataSchema -Data $verify -SchemaName verify-result | Out-Null
    if($OutputPath -and $PSCmdlet.ShouldProcess($OutputPath,'Write apply result')){Write-WpaAtomicJson $OutputPath $result};if($VerifyOutputPath -and $PSCmdlet.ShouldProcess($VerifyOutputPath,'Write verify result')){Write-WpaAtomicJson $VerifyOutputPath $verify};if($SummaryPath -and $PSCmdlet.ShouldProcess($SummaryPath,'Write run summary')){Write-WpaAtomicText $SummaryPath (ConvertTo-WpaRunSummaryMarkdown $result)}
    return [pscustomobject]@{apply=$result;verify=$verify}
}
