function Invoke-WpaPlan {
    [CmdletBinding(DefaultParameterSetName='Apply',SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$PlanPath,[Parameter(Mandatory,ParameterSetName='Apply')][string]$ApprovalPath,
        [Parameter(Mandatory)][string]$PolicyPath,[Parameter(ParameterSetName='Preflight')][switch]$Preflight,[string]$OutputPath='./artifacts/apply-result.json',[string]$VerifyOutputPath='./artifacts/verify-result.json',[string]$SummaryPath='./artifacts/run-summary.md',[switch]$DiagnosticLogging
    )
    $started=[datetimeoffset]::UtcNow
    $plan=Read-WpaJsonFile $PlanPath
    $managerFingerprintsProperty=$plan.PSObject.Properties['managerFingerprints']
    if($null -eq $managerFingerprintsProperty){throw 'MANAGER_FINGERPRINT_UNAVAILABLE: plan manager fingerprints are missing.'}
    if($null -eq $plan.PSObject.Properties['blockedOperations']){$plan | Add-Member -NotePropertyName blockedOperations -NotePropertyValue @()}
    if($null -eq $plan.PSObject.Properties['warnings']){$plan | Add-Member -NotePropertyName warnings -NotePropertyValue @()}
    if($null -eq $plan.PSObject.Properties['actions']){$plan | Add-Member -NotePropertyName actions -NotePropertyValue @()}
    Test-WpaDataSchema $plan plan|Out-Null;Assert-WpaPlanActionSet -Actions @($plan.actions)|Out-Null;Assert-WpaPlanIntegrity $plan|Out-Null
    if($started -gt [datetimeoffset]::Parse($plan.expiresAt,[Globalization.CultureInfo]::InvariantCulture)){throw 'Plan has expired.'}
    if($PSCmdlet.ParameterSetName -eq 'Apply'){$approval=Read-WpaJsonFile $ApprovalPath;Test-WpaDataSchema $approval approval|Out-Null;Assert-WpaApproval $approval $plan.planId $plan.planHash $started|Out-Null}
    if($plan.environmentId -ne (Get-WpaEnvironmentId)){throw 'Plan targets a different environment.'}
    $policy=Read-WpaPolicyFile $PolicyPath;Test-WpaDataSchema $policy policy|Out-Null
    if((Get-WpaObjectHash $policy) -ne $plan.policyHash){throw 'Policy changed after plan creation.'}
    $currentInventory=ConvertTo-WpaInventoryBoundary (Get-WpaInventory)
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
    if($PSCmdlet.ParameterSetName -eq 'Preflight'){
        return [pscustomobject][ordered]@{preflight=[pscustomobject][ordered]@{status='ready';planId=$plan.planId;operationCount=$operations.Count;approvalRequired=$false;mutationPerformed=$false;artifactsWritten=$false}}
    }
    $results=[System.Collections.Generic.List[object]]::new();$failed=$false
    $journalPath=if($OutputPath){[IO.Path]::ChangeExtension($OutputPath,'.journal.json')}else{$null}
    if($journalPath -and (Test-Path -LiteralPath $journalPath)){throw 'An existing journal was found; inspect it before starting another apply.'}
    $journalSequence=0
    $journal=[pscustomobject][ordered]@{schemaVersion=1;planId=$plan.planId;startedAt=$started.ToString('o');updatedAt=$started.ToString('o');entries=@()}
    foreach($operation in $operations){
        if($failed){$empty=Get-WpaOutputMetadata $null;$results.Add([pscustomobject]@{manager=$operation.manager;id=$operation.id;operation=$operation.operation;status='not-run';reasonCode='STOPPED_AFTER_FAILURE';exitCode=$null;durationMs=0;timedOut=$false;rebootRequired=$false;stdoutHash=$empty.hash;stderrHash=$empty.hash;stdoutLength=0;stderrLength=0;stdoutTruncated=$false;stderrTruncated=$false;failureSummary='Stopped after a previous failure.';diagnosticLoggingEnabled=[bool]$DiagnosticLogging});continue}
        if(-not $PSCmdlet.ShouldProcess("$($operation.manager)/$($operation.id)",$operation.operation)){$empty=Get-WpaOutputMetadata $null;$results.Add([pscustomobject]@{manager=$operation.manager;id=$operation.id;operation=$operation.operation;status='what-if';reasonCode='SHOULD_PROCESS_DECLINED';exitCode=$null;durationMs=0;timedOut=$false;rebootRequired=$false;stdoutHash=$empty.hash;stderrHash=$empty.hash;stdoutLength=0;stderrLength=0;stdoutTruncated=$false;stderrTruncated=$false;failureSummary=$null;diagnosticLoggingEnabled=[bool]$DiagnosticLogging});continue}
        $phase='journal-before';$external=$null
        try {
            if($journalPath){$journalSequence++;$fingerprint=@($plan.managerFingerprints|Where-Object manager -eq $operation.manager|Select-Object -First 1).fingerprint;$journal.entries=@($journal.entries)+@([pscustomobject]@{sequence=$journalSequence;operationId=(Get-WpaSha256 -Text ("$($operation.manager)/$($operation.id)/$($operation.operation)"));operationHash=(Get-WpaObjectHash $operation);planHash=$plan.planHash;manager=$operation.manager;id=$operation.id;operation=$operation.operation;managerFingerprintHash=$(if($fingerprint){Get-WpaObjectHash $fingerprint}else{$null});status='starting';recordedAt=[datetimeoffset]::UtcNow.ToString('o')});$journal.updatedAt=[datetimeoffset]::UtcNow.ToString('o');Write-WpaAtomicJson $journalPath $journal}
            $phase='adapter'
            $external=Invoke-WpaManagerAction -Action $operation -TimeoutSeconds ([int]$policy.operationTimeoutSeconds)
            $exitCode=[int64](Get-WpaPropertyValue $external 'ExitCode' -1);$timedOut=[bool](Get-WpaPropertyValue $external 'TimedOut' $false);$stdout=Get-WpaPropertyValue $external 'StdOut';$stderr=Get-WpaPropertyValue $external 'StdErr';$durationMs=[int](Get-WpaPropertyValue $external 'DurationMs' 0)
            $reboot=($exitCode -eq 3010) -or [bool](Get-WpaPropertyValue $external 'RebootRequired' $false)
            $ok=(($exitCode -eq 0 -or $reboot) -and -not $timedOut)
            $stdoutMeta=Get-WpaOutputMetadata $stdout;$stderrMeta=Get-WpaOutputMetadata $stderr
            $operationResult=[ordered]@{manager=$operation.manager;id=$operation.id;operation=$operation.operation;status=$(if($ok){'completed'}else{'failed'});reasonCode=$(if($reboot){'REBOOT_REQUIRED'}elseif($ok){'COMMAND_SUCCEEDED'}elseif($timedOut){'COMMAND_TIMED_OUT'}else{'COMMAND_FAILED'});exitCode=$exitCode;durationMs=$durationMs;timedOut=$timedOut;rebootRequired=$reboot;stdoutHash=$stdoutMeta.hash;stderrHash=$stderrMeta.hash;stdoutLength=$stdoutMeta.length;stderrLength=$stderrMeta.length;stdoutTruncated=$stdoutMeta.truncated;stderrTruncated=$stderrMeta.truncated;failureSummary=$(if($timedOut){'Command timed out.'}elseif(-not $ok){'Command failed.'}else{$null});diagnosticLoggingEnabled=[bool]$DiagnosticLogging}
            if($DiagnosticLogging){$diagnostic=ConvertTo-WpaDiagnosticText $stdout $stderr;$operationResult.diagnostic=[pscustomobject][ordered]@{text=$diagnostic.text;truncated=$diagnostic.truncated;warning='Secret removal is not complete.'}}
            $operationResult=[pscustomobject]$operationResult
            $phase='journal-after'
            if($journalPath){$journalSequence++;$fingerprint=@($plan.managerFingerprints|Where-Object manager -eq $operation.manager|Select-Object -First 1).fingerprint;$journal.entries=@($journal.entries)+@([pscustomobject]@{sequence=$journalSequence;operationId=(Get-WpaSha256 -Text ("$($operation.manager)/$($operation.id)/$($operation.operation)"));operationHash=(Get-WpaObjectHash $operation);planHash=$plan.planHash;manager=$operation.manager;id=$operation.id;operation=$operation.operation;managerFingerprintHash=$(if($fingerprint){Get-WpaObjectHash $fingerprint}else{$null});status=$operationResult.status;reasonCode=$operationResult.reasonCode;recordedAt=[datetimeoffset]::UtcNow.ToString('o')});$journal.updatedAt=[datetimeoffset]::UtcNow.ToString('o');Write-WpaAtomicJson $journalPath $journal}
            $results.Add($operationResult)
            if(-not $ok){$failed=$true}
        }catch{
            $reasonCode=if($phase -like 'journal-*'){'JOURNAL_WRITE_FAILED'}else{'ADAPTER_EXCEPTION'}
            $exceptionText=$_.Exception.Message;$stdoutMeta=Get-WpaOutputMetadata $null;$stderrMeta=Get-WpaOutputMetadata $exceptionText
            $errorResult=[ordered]@{manager=$operation.manager;id=$operation.id;operation=$operation.operation;status='failed';reasonCode=$reasonCode;exitCode=(Get-WpaPropertyValue $external 'ExitCode');durationMs=[int](Get-WpaPropertyValue $external 'DurationMs' 0);timedOut=[bool](Get-WpaPropertyValue $external 'TimedOut' $false);rebootRequired=$false;stdoutHash=$stdoutMeta.hash;stderrHash=$stderrMeta.hash;stdoutLength=$stdoutMeta.length;stderrLength=$stderrMeta.length;stdoutTruncated=$false;stderrTruncated=$false;failureSummary='Adapter execution failed.';diagnosticLoggingEnabled=[bool]$DiagnosticLogging}
            if($DiagnosticLogging){$diagnostic=ConvertTo-WpaDiagnosticText $null $exceptionText;$errorResult.diagnostic=[pscustomobject][ordered]@{text=$diagnostic.text;truncated=$diagnostic.truncated;warning='Secret removal is not complete.'}}
            $results.Add([pscustomobject]$errorResult);$failed=$true
        }
    }
    $executed=@($results|Where-Object status -eq completed)
    $verifyItems=@()
    if($executed.Count -gt 0){
        $afterInventory=Get-WpaInventory
        $executedKeys=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach($item in $executed){$null=$executedKeys.Add("$($item.manager)`0$($item.id)")}
        foreach($operation in $operations|Where-Object {$executedKeys.Contains("$($_.manager)`0$($_.id)")}){
            $applied=$results|Where-Object {$_.manager -eq $operation.manager -and $_.id -eq $operation.id}|Select-Object -First 1
            if([bool](Get-WpaPropertyValue $applied 'rebootRequired' $false)){$verifyItems+=[pscustomobject]@{name=$operation.name;manager=$operation.manager;id=$operation.id;status='deferred';reasonCode='REBOOT_REQUIRED_BEFORE_VERIFICATION'}}else{$verifyItems+=Test-WpaExpectedState -Action $operation -Inventory $afterInventory}
        }
    }
    $finished=[datetimeoffset]::UtcNow
    $status=if($failed){'partial-failure'}elseif(@($results|Where-Object status -eq 'what-if').Count -gt 0){'what-if'}else{'success'}
    $rebootRequired=@($results|Where-Object {[bool](Get-WpaPropertyValue $_ 'rebootRequired' $false)}).Count -gt 0
    $result=[pscustomobject][ordered]@{schemaVersion=1;planId=$plan.planId;status=$status;startedAt=$started.ToString('o');finishedAt=$finished.ToString('o');operations=@($results);rebootRequired=$rebootRequired;warnings=@('Automatic rollback is not guaranteed.')}
    $verify=[pscustomobject][ordered]@{schemaVersion=1;planId=$plan.planId;status=$(if($rebootRequired){'reboot-required'}elseif(@($verifyItems|Where-Object status -in @('verification-failed','indeterminate')).Count -gt 0){'failed'}elseif(@($verifyItems|Where-Object status -eq 'deferred').Count -gt 0){'deferred'}elseif($verifyItems.Count -eq 0){'not-run'}else{'success'});verifiedAt=$finished.ToString('o');items=@($verifyItems);rebootRequired=$rebootRequired}
    Test-WpaDataSchema -Data $result -SchemaName apply-result | Out-Null;Test-WpaDataSchema -Data $verify -SchemaName verify-result | Out-Null
    if($OutputPath -and $PSCmdlet.ShouldProcess($OutputPath,'Write apply result')){Write-WpaAtomicJson $OutputPath $result};if($VerifyOutputPath -and $PSCmdlet.ShouldProcess($VerifyOutputPath,'Write verify result')){Write-WpaAtomicJson $VerifyOutputPath $verify};if($SummaryPath -and $PSCmdlet.ShouldProcess($SummaryPath,'Write run summary')){Write-WpaAtomicText $SummaryPath (ConvertTo-WpaRunSummaryMarkdown $result)}
    return [pscustomobject]@{apply=$result;verify=$verify}
}
