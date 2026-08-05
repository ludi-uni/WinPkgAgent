function Get-WpaInventoryAggregate {
    [CmdletBinding()]
    param([hashtable]$Adapters,[datetime]$CollectedAt=(Get-Date).ToUniversalTime())
    if($null -eq $Adapters){$Adapters=@{winget={Get-WpaWingetInventory};scoop={Get-WpaScoopInventory}}}
    $managers=@(); $packages=@(); $warnings=@(); $inventoryWarnings=@()
    foreach($name in @('winget','scoop')) {
        $adapter=$Adapters[$name]
        if($null -eq $adapter){$r=[pscustomobject]@{Available=$false;Success=$false;Packages=@();Warning='manager unavailable';TimedOut=$false}}
        else {
        try {$r=& $adapter} catch {$r=[pscustomobject]@{Manager=$name;Available=$false;Success=$false;Packages=@();Warning=(Protect-WpaSensitiveText $_.Exception.Message);TimedOut=$false}}
        }
        $adapterSuccess=[bool](Get-WpaPropertyValue $r 'Success' $false);$adapterStatus=Get-WpaPropertyValue $r 'status' 'failed'
        $managerStatus=if($adapterSuccess){if($adapterStatus -eq 'partial'){'partial'}else{'success'}}else{'failed'}
        $managerWarning=Protect-WpaSensitiveText (Get-WpaPropertyValue $r 'Warning');$managerPackages=@(Get-WpaPropertyValue $r 'Packages' @())
        $adapterWarning=$managerWarning
        $fingerprint=$null
        try {$executable=Get-WpaPropertyValue $r 'Executable' (Resolve-WpaManagerExecutable -Manager $name);if($executable){$fingerprint=Get-WpaManagerFingerprint -Manager $name -Executable $executable}} catch {
            $fingerprintWarning=Protect-WpaSensitiveText ('fingerprint resolution failed: '+$_.Exception.Message)
            $maxWarningPartLength=2047
            if($managerWarning.Length -gt $maxWarningPartLength){$managerWarning=$managerWarning.Substring(0,$maxWarningPartLength)}
            if($fingerprintWarning.Length -gt $maxWarningPartLength){$fingerprintWarning=$fingerprintWarning.Substring(0,$maxWarningPartLength)}
            $managerWarning=if($managerWarning){$managerWarning+'; '+$fingerprintWarning}else{$fingerprintWarning}
        }
        $managers += [pscustomobject]@{manager=$name;version=(Get-WpaPropertyValue $r 'version');status=$managerStatus;timedOut=[bool](Get-WpaPropertyValue $r 'TimedOut' $false);warning=$managerWarning;fingerprint=$fingerprint}
        if($managerPackages.Count -gt 0){$packages += $managerPackages}
        if($managerWarning){$warnings += [string]$managerWarning}
        if($adapterWarning){$inventoryWarnings += [string]$adapterWarning}
    }
    $usable=@($managers | Where-Object status -in @('success','partial')).Count;$successful=@($managers | Where-Object status -eq 'success').Count
    $status=if($usable -eq 0){'failed'}elseif($successful -lt 2 -or $inventoryWarnings.Count -gt 0){'partial'}else{'success'}
    $envId=if(Get-Command Get-WpaEnvironmentId -ErrorAction SilentlyContinue){Get-WpaEnvironmentId}else{$null}
    [pscustomobject]@{schemaVersion=1;environment=[pscustomobject]@{id=$envId};collectedAt=$CollectedAt.ToUniversalTime().ToString('o');status=$status;managers=@($managers);packages=@($packages);warnings=@($warnings)}
}
