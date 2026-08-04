function Get-WpaEnvironmentId {
    [CmdletBinding()]
    param()
    $machineGuid = ''
    try { $machineGuid = [string](Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop) } catch { $machineGuid = [Environment]::MachineName }
    $material = [ordered]@{
        machine = $machineGuid
        os = [Environment]::OSVersion.VersionString
        architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    }
    return Get-WpaObjectHash -InputObject $material
}
