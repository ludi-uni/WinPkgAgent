function Export-WpaManifestCandidate {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$InventoryPath,[Parameter(Mandatory)][string]$OutputPath)
    $inventory=Read-WpaJsonFile $InventoryPath;Test-WpaDataSchema $inventory inventory|Out-Null;$duplicates=@($inventory.packages|Group-Object id|Where-Object Count -gt 1);$lines=@('# Candidate manifest generated from inventory. It is not an active manifest.','reviewStatus: pending','profiles: []','warnings:','  - manager export detection does not prove original manager ownership; confirm migration and reinstall impact');if($duplicates.Count -gt 0){foreach($duplicate in $duplicates){$lines+="  - cross-manager or duplicate id requires review: $($duplicate.Name)"}}else{$lines+='  - source and category require human confirmation before promotion'};$lines+='packages:';$usedNames=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach($package in @($inventory.packages|Sort-Object manager,id)){
        $id=[string]$package.id;$name=ConvertTo-WpaLogicalPackageName -Id $id;$baseName=$name;$suffix=2;while(-not $usedNames.Add($name)){ $suffixText="-$suffix";$prefixLength=[Math]::Max(1,64-$suffixText.Length);$name=($baseName.Substring(0,[Math]::Min($baseName.Length,$prefixLength)).TrimEnd('-'))+$suffixText;$suffix++ };$id=$id.Replace("'","''");$manager=[string]$package.manager
        $lines+="  - name: '$name'";$lines+="    manager: '$manager'";$lines+="    id: '$id'";$lines+='    reviewStatus: pending';$lines+='    state: present'
        $detectedBy=Get-WpaPropertyValue (Get-WpaPropertyValue $package 'metadata' $null) 'detectedBy' $null;if($detectedBy){$lines+="    # detectedBy: $detectedBy"}
        if($package.source){$lines+="    source: '$(([string]$package.source).Replace("'","''"))'"}
        if($package.installedVersion){$lines+="    version: '$(([string]$package.installedVersion).Replace("'","''"))'"}
    }
    $text=($lines -join [Environment]::NewLine)+[Environment]::NewLine;if($PSCmdlet.ShouldProcess($OutputPath,'Write pending manifest candidate')){Write-WpaAtomicText $OutputPath $text};[pscustomobject]@{reviewStatus='pending';path=$OutputPath;count=@($inventory.packages).Count}
}
