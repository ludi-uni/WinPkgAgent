function Export-WpaManifestCandidate {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$InventoryPath,[Parameter(Mandatory)][string]$OutputPath)
    $inventory=Read-WpaJsonFile $InventoryPath;Test-WpaDataSchema $inventory inventory|Out-Null;$duplicates=@($inventory.packages|Group-Object id|Where-Object Count -gt 1);$lines=@('# Candidate manifest generated from inventory. It is not an active manifest.','reviewStatus: pending','warnings:');if($duplicates.Count -gt 0){foreach($duplicate in $duplicates){$lines+="  - cross-manager or duplicate id requires review: $($duplicate.Name)"}}else{$lines+='  - source and category require human confirmation before promotion'};$lines+='packages:'
    foreach($package in @($inventory.packages|Sort-Object manager,id)){
        $name=([string]$package.name).Replace("'","''");$id=([string]$package.id).Replace("'","''");$manager=[string]$package.manager
        $lines+="  - name: '$name'";$lines+="    manager: '$manager'";$lines+="    id: '$id'";$lines+='    reviewStatus: pending';$lines+='    state: present'
        if($package.source){$lines+="    source: '$(([string]$package.source).Replace("'","''"))'"}
        if($package.installedVersion){$lines+="    version: '$(([string]$package.installedVersion).Replace("'","''"))'"}
    }
    $text=($lines -join [Environment]::NewLine)+[Environment]::NewLine;if($PSCmdlet.ShouldProcess($OutputPath,'Write pending manifest candidate')){Write-WpaAtomicText $OutputPath $text};[pscustomobject]@{reviewStatus='pending';path=$OutputPath;count=@($inventory.packages).Count}
}
