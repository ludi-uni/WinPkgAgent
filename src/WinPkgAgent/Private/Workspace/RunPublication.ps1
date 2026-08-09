if (-not ('WinPkgAgent.Native.OwnedDirectoryHandle' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace WinPkgAgent.Native
{
    public sealed class OwnedDirectoryHandle : IDisposable
    {
        private const uint DeleteAccess = 0x00010000;
        private const uint ReadAttributesAccess = 0x00000080;
        private const uint FileShareRead = 0x00000001;
        private const uint FileShareWrite = 0x00000002;
        private const uint FileShareDelete = 0x00000004;
        private const uint FileCreate = 0x00000002;
        private const uint FileDirectoryFile = 0x00000001;
        private const uint FileAttributeDirectory = 0x00000010;
        private const uint ObjectCaseInsensitive = 0x00000040;
        private const ulong FileCreated = 2;
        private const int FileRenameInfo = 3;
        private const int StatusObjectNameCollision = unchecked((int)0xC0000035);
        private SafeFileHandle handle;

        [StructLayout(LayoutKind.Sequential)]
        private struct UnicodeString
        {
            internal ushort Length;
            internal ushort MaximumLength;
            internal IntPtr Buffer;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ObjectAttributes
        {
            internal int Length;
            internal IntPtr RootDirectory;
            internal IntPtr ObjectName;
            internal uint Attributes;
            internal IntPtr SecurityDescriptor;
            internal IntPtr SecurityQualityOfService;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IoStatusBlock
        {
            internal IntPtr Status;
            internal UIntPtr Information;
        }

        private OwnedDirectoryHandle(SafeFileHandle handle)
        {
            this.handle = handle;
        }

        public bool IsOpen
        {
            get { return handle != null && !handle.IsInvalid && !handle.IsClosed; }
        }

        public static OwnedDirectoryHandle CreateAtomically(string path)
        {
            string ntPath = ToNtPath(path);
            int pathByteLength = System.Text.Encoding.Unicode.GetByteCount(ntPath);
            if (pathByteLength > ushort.MaxValue - sizeof(char))
            {
                throw new IOException("Atomic directory path is too long.");
            }

            IntPtr pathBuffer = IntPtr.Zero;
            IntPtr unicodeStringBuffer = IntPtr.Zero;
            IntPtr rawHandle = IntPtr.Zero;
            try
            {
                pathBuffer = Marshal.StringToHGlobalUni(ntPath);
                UnicodeString unicodeString = new UnicodeString
                {
                    Length = (ushort)pathByteLength,
                    MaximumLength = (ushort)(pathByteLength + sizeof(char)),
                    Buffer = pathBuffer
                };
                unicodeStringBuffer = Marshal.AllocHGlobal(Marshal.SizeOf<UnicodeString>());
                Marshal.StructureToPtr(unicodeString, unicodeStringBuffer, false);

                ObjectAttributes objectAttributes = new ObjectAttributes
                {
                    Length = Marshal.SizeOf<ObjectAttributes>(),
                    RootDirectory = IntPtr.Zero,
                    ObjectName = unicodeStringBuffer,
                    Attributes = ObjectCaseInsensitive,
                    SecurityDescriptor = IntPtr.Zero,
                    SecurityQualityOfService = IntPtr.Zero
                };
                IoStatusBlock ioStatusBlock;
                int status = NtCreateFile(
                    out rawHandle,
                    DeleteAccess | ReadAttributesAccess,
                    ref objectAttributes,
                    out ioStatusBlock,
                    IntPtr.Zero,
                    FileAttributeDirectory,
                    FileShareRead | FileShareWrite | FileShareDelete,
                    FileCreate,
                    FileDirectoryFile,
                    IntPtr.Zero,
                    0);
                if (status < 0)
                {
                    if (status == StatusObjectNameCollision)
                    {
                        throw new IOException("Atomic directory already exists.");
                    }
                    throw new IOException("Atomic directory creation failed.");
                }
                if (rawHandle == IntPtr.Zero || rawHandle == new IntPtr(-1) || ioStatusBlock.Information.ToUInt64() != FileCreated)
                {
                    if (rawHandle != IntPtr.Zero && rawHandle != new IntPtr(-1))
                    {
                        new SafeFileHandle(rawHandle, true).Dispose();
                        rawHandle = IntPtr.Zero;
                    }
                    throw new IOException("Atomic directory creation returned an invalid result.");
                }

                SafeFileHandle directoryHandle = new SafeFileHandle(rawHandle, true);
                rawHandle = IntPtr.Zero;
                return new OwnedDirectoryHandle(directoryHandle);
            }
            finally
            {
                if (rawHandle != IntPtr.Zero && rawHandle != new IntPtr(-1))
                {
                    new SafeFileHandle(rawHandle, true).Dispose();
                }
                if (unicodeStringBuffer != IntPtr.Zero) { Marshal.FreeHGlobal(unicodeStringBuffer); }
                if (pathBuffer != IntPtr.Zero) { Marshal.FreeHGlobal(pathBuffer); }
            }
        }

        private static string ToNtPath(string path)
        {
            string fullPath = Path.GetFullPath(path);
            if (fullPath.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase))
            {
                return @"\??\UNC\" + fullPath.Substring(8);
            }
            if (fullPath.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase))
            {
                return @"\??\" + fullPath.Substring(4);
            }
            if (fullPath.StartsWith(@"\\", StringComparison.OrdinalIgnoreCase))
            {
                return @"\??\UNC\" + fullPath.Substring(2);
            }
            return @"\??\" + fullPath;
        }

        public void Rename(string destinationPath)
        {
            if (!IsOpen)
            {
                throw new InvalidOperationException("Directory ownership handle is closed.");
            }

            byte[] destinationBytes = System.Text.Encoding.Unicode.GetBytes(destinationPath);
            int rootOffset = IntPtr.Size == 8 ? 8 : 4;
            int lengthOffset = rootOffset + IntPtr.Size;
            int nameOffset = lengthOffset + sizeof(uint);
            int bufferLength = nameOffset + destinationBytes.Length + sizeof(char);
            IntPtr buffer = Marshal.AllocHGlobal(bufferLength);
            try
            {
                for (int offset = 0; offset < nameOffset; offset += sizeof(int))
                {
                    Marshal.WriteInt32(buffer, offset, 0);
                }
                Marshal.WriteIntPtr(buffer, rootOffset, IntPtr.Zero);
                Marshal.WriteInt32(buffer, lengthOffset, destinationBytes.Length);
                Marshal.Copy(destinationBytes, 0, IntPtr.Add(buffer, nameOffset), destinationBytes.Length);
                Marshal.WriteInt16(buffer, nameOffset + destinationBytes.Length, 0);
                if (!SetFileInformationByHandle(handle, FileRenameInfo, buffer, (uint)bufferLength))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        public void Dispose()
        {
            if (handle != null)
            {
                handle.Dispose();
                handle = null;
            }
        }

        [DllImport("ntdll.dll")]
        private static extern int NtCreateFile(
            out IntPtr fileHandle,
            uint desiredAccess,
            ref ObjectAttributes objectAttributes,
            out IoStatusBlock ioStatusBlock,
            IntPtr allocationSize,
            uint fileAttributes,
            uint shareAccess,
            uint createDisposition,
            uint createOptions,
            IntPtr eaBuffer,
            uint eaLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetFileInformationByHandle(
            SafeFileHandle fileHandle,
            int fileInformationClass,
            IntPtr fileInformation,
            uint bufferSize);
    }
}
'@
}

function New-WpaOwnedDirectoryHandleAtomically {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    try {
        return [WinPkgAgent.Native.OwnedDirectoryHandle]::CreateAtomically([IO.Path]::GetFullPath($Path))
    } catch {
        throw 'PREVIEW_STAGING_OWNERSHIP_NOT_ACQUIRED'
    }
}

function Resolve-WpaTrustedWorkspacePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspacePath)

    $workspace = [IO.Path]::GetFullPath($WorkspacePath)
    $cursor = $workspace
    while ($cursor) {
        try {
            $exists = Test-Path -LiteralPath $cursor -ErrorAction Stop
            $item = if ($exists) { Get-Item -LiteralPath $cursor -Force -ErrorAction Stop } else { $null }
        } catch {
            throw 'Workspace path state could not be verified.'
        }
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Workspace paths may not contain reparse points.'
        }
        if ($cursor -eq $workspace -and $null -ne $item -and -not $item.PSIsContainer) {
            throw 'Workspace path must be a directory.'
        }
        $next = Split-Path $cursor -Parent
        if ($next -eq $cursor) { break }
        $cursor = $next
    }
    return $workspace
}

function Assert-WpaTrustedPublicationAncestry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspacePath,
        [Parameter(Mandatory)][string]$RunsPath,
        [Parameter(Mandatory)][string]$StagingPath,
        [switch]$StagingMustExist
    )

    try {
        $workspaceFull = [IO.Path]::GetFullPath($WorkspacePath)
        $runsFull = [IO.Path]::GetFullPath($RunsPath)
        $stagingFull = [IO.Path]::GetFullPath($StagingPath)
        if (-not [string]::Equals([IO.Path]::GetDirectoryName($runsFull), $workspaceFull, [StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals([IO.Path]::GetDirectoryName($stagingFull), $runsFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'lexical ancestry mismatch'
        }
        $resolvedWorkspace = Resolve-WpaTrustedWorkspacePath -WorkspacePath $workspaceFull
        if (-not [string]::Equals($resolvedWorkspace, $workspaceFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'workspace resolution mismatch'
        }
        $runsExists = Test-Path -LiteralPath $runsFull -ErrorAction Stop
        if (-not $runsExists) {
            if ($StagingMustExist) { throw 'runs path missing' }
            return $true
        }
        $runsItem = Get-Item -LiteralPath $runsFull -Force -ErrorAction Stop
        if (-not $runsItem.PSIsContainer -or ($runsItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not [string]::Equals($runsItem.Parent.FullName, $workspaceFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'runs ancestry untrusted'
        }
        $stagingExists = Test-Path -LiteralPath $stagingFull -ErrorAction Stop
        if (-not $stagingExists) {
            if ($StagingMustExist) { throw 'staging path missing' }
            return $true
        }
        $stagingItem = Get-Item -LiteralPath $stagingFull -Force -ErrorAction Stop
        if (-not $stagingItem.PSIsContainer -or ($stagingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not [string]::Equals($stagingItem.Parent.FullName, $runsItem.FullName, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'staging ancestry untrusted'
        }
    } catch {
        throw 'Run publication ancestry is not trusted.'
    }
    return $true
}

function Test-WpaStagingOwnershipIdentity {
    [CmdletBinding()]
    param([AllowNull()][object]$Ownership)

    try {
        if ($null -eq $Ownership -or $null -eq $Ownership.Stream -or -not $Ownership.Stream.CanRead -or
            $Ownership.PSObject.Properties.Name -notcontains 'DirectoryHandle' -or $null -eq $Ownership.DirectoryHandle -or
            -not $Ownership.DirectoryHandle.IsOpen) { return $false }
        $stagingFull = [IO.Path]::GetFullPath([string]$Ownership.StagingPath)
        $runsFull = [IO.Path]::GetFullPath([string]$Ownership.RunsPath)
        $markerFull = [IO.Path]::GetFullPath([string]$Ownership.MarkerPath)
        if (-not [string]::Equals([IO.Path]::GetDirectoryName($stagingFull), $runsFull, [StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals([IO.Path]::GetFileName($stagingFull), [string]$Ownership.ExpectedLeaf, [StringComparison]::Ordinal) -or
            -not [string]::Equals($markerFull, ([IO.Path]::Combine($stagingFull, '.wpa-staging-owner')), [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        $position = $Ownership.Stream.Position
        $Ownership.Stream.Position = 0
        $buffer = [byte[]]::new(128)
        $read = $Ownership.Stream.Read($buffer, 0, $buffer.Length)
        $Ownership.Stream.Position = $position
        $token = [Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        if (-not [string]::Equals($token, [string]$Ownership.Token, [StringComparison]::Ordinal)) { return $false }
        $markerItem = Get-Item -LiteralPath $markerFull -Force -ErrorAction Stop
        if ($markerItem.PSIsContainer -or ($markerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    } catch {
        return $false
    }
    return $true
}

function Assert-WpaOwnedRunStagingTrust {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership)

    if (-not (Test-WpaStagingOwnershipIdentity -Ownership $Ownership)) {
        throw 'Run staging ownership proof is not valid.'
    }
    Assert-WpaTrustedPublicationAncestry -WorkspacePath $Ownership.WorkspacePath -RunsPath $Ownership.RunsPath -StagingPath $Ownership.StagingPath -StagingMustExist | Out-Null
    return $true
}

function New-WpaRunStagingOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspacePath,
        [Parameter(Mandatory)][string]$RunsPath,
        [Parameter(Mandatory)][string]$StagingPath,
        [Parameter(Mandatory)][string]$ExpectedLeaf
    )

    $workspaceFull = [IO.Path]::GetFullPath($WorkspacePath)
    $runsFull = [IO.Path]::GetFullPath($RunsPath)
    $stagingFull = [IO.Path]::GetFullPath($StagingPath)
    Assert-WpaTrustedPublicationAncestry -WorkspacePath $workspaceFull -RunsPath $runsFull -StagingPath $stagingFull | Out-Null
    if (Test-Path -LiteralPath $stagingFull -ErrorAction Stop) { throw 'Run staging workspace already exists.' }

    $stream = $null
    $directoryHandle = $null
    $directoryAcquired = $false
    try {
        [IO.Directory]::CreateDirectory($runsFull) | Out-Null
        Assert-WpaTrustedPublicationAncestry -WorkspacePath $workspaceFull -RunsPath $runsFull -StagingPath $stagingFull | Out-Null
        $directoryHandle = New-WpaOwnedDirectoryHandleAtomically -Path $stagingFull
        $directoryAcquired = $true
        Assert-WpaTrustedPublicationAncestry -WorkspacePath $workspaceFull -RunsPath $runsFull -StagingPath $stagingFull -StagingMustExist | Out-Null
        $markerPath = [IO.Path]::Combine($stagingFull, '.wpa-staging-owner')
        $token = [guid]::NewGuid().ToString('N')
        $stream = [IO.FileStream]::new(
            $markerPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None,
            4096,
            [IO.FileOptions]::DeleteOnClose
        )
        $bytes = [Text.Encoding]::UTF8.GetBytes($token)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $entries = @(Get-ChildItem -LiteralPath $stagingFull -Force -ErrorAction Stop)
        if ($entries.Count -ne 1 -or -not [string]::Equals($entries[0].FullName, $markerPath, [StringComparison]::OrdinalIgnoreCase) -or
            $entries[0].PSIsContainer -or ($entries[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'staging was not empty at ownership acquisition'
        }
        $ownership = [pscustomobject]@{
            WorkspacePath = $workspaceFull
            RunsPath = $runsFull
            StagingPath = $stagingFull
            ExpectedLeaf = $ExpectedLeaf
            MarkerPath = $markerPath
            Token = $token
            Stream = $stream
            DirectoryHandle = $directoryHandle
            OwnedFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            OwnedDirectories = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        }
        return $ownership
    } catch {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $directoryHandle) { $directoryHandle.Dispose() }
        if ($directoryAcquired) { throw 'PREVIEW_STAGING_PRESERVED' }
        throw 'PREVIEW_STAGING_OWNERSHIP_NOT_ACQUIRED'
    }
}

function Write-WpaOwnedStagingText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    Assert-WpaOwnedRunStagingTrust -Ownership $Ownership | Out-Null
    $fullPath = [IO.Path]::GetFullPath($Path)
    $parentPath = [IO.Path]::GetDirectoryName($fullPath)
    if (-not [string]::Equals($parentPath, $Ownership.StagingPath, [StringComparison]::OrdinalIgnoreCase) -and
        -not $Ownership.OwnedDirectories.Contains($parentPath)) {
        throw 'Owned staging target escapes the staging directory.'
    }
    if (Test-Path -LiteralPath $fullPath -ErrorAction Stop) { throw 'Owned staging target already exists.' }
    $stream = $null
    try {
        $stream = [IO.FileStream]::new(
            $fullPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::Read,
            4096,
            [IO.FileOptions]::WriteThrough
        )
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Owned staging target is not trusted.' }
    $Ownership.OwnedFiles.Add($fullPath) | Out-Null
}

function Write-WpaOwnedStagingJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Data)

    Write-WpaOwnedStagingText -Ownership $Ownership -Path $Path -Text (($Data | ConvertTo-Json -Depth 100) + [Environment]::NewLine)
}

function Assert-WpaOwnedStagingContents {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership,[switch]$OwnershipReleased)

    if ($OwnershipReleased) {
        Assert-WpaTrustedPublicationAncestry -WorkspacePath $Ownership.WorkspacePath -RunsPath $Ownership.RunsPath -StagingPath $Ownership.StagingPath -StagingMustExist | Out-Null
    } else {
        Assert-WpaOwnedRunStagingTrust -Ownership $Ownership | Out-Null
    }
    $seenFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $seenDirectories = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @(Get-ChildItem -LiteralPath $Ownership.StagingPath -Force -ErrorAction Stop)) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Unowned staging content detected.' }
        if ([string]::Equals($entry.FullName, $Ownership.MarkerPath, [StringComparison]::OrdinalIgnoreCase)) {
            if ($OwnershipReleased) { throw 'Released ownership marker remains.' }
            continue
        }
        if ($entry.PSIsContainer) {
            if (-not $Ownership.OwnedDirectories.Contains($entry.FullName)) { throw 'Unowned staging content detected.' }
            $seenDirectories.Add($entry.FullName) | Out-Null
            foreach ($child in @(Get-ChildItem -LiteralPath $entry.FullName -Force -ErrorAction Stop)) {
                if ($child.PSIsContainer -or ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                    -not $Ownership.OwnedFiles.Contains($child.FullName)) { throw 'Unowned staging content detected.' }
                $seenFiles.Add($child.FullName) | Out-Null
            }
        } else {
            if (-not $Ownership.OwnedFiles.Contains($entry.FullName)) { throw 'Unowned staging content detected.' }
            $seenFiles.Add($entry.FullName) | Out-Null
        }
    }
    if ($seenFiles.Count -ne $Ownership.OwnedFiles.Count -or $seenDirectories.Count -ne $Ownership.OwnedDirectories.Count) {
        throw 'Owned staging content changed unexpectedly.'
    }
    return $true
}

function Close-WpaRunStagingOwnershipHandles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership)

    if ($null -ne $Ownership.Stream) {
        try { $Ownership.Stream.Dispose() } catch { }
        $Ownership.Stream = $null
    }
    if ($Ownership.PSObject.Properties.Name -contains 'DirectoryHandle' -and $null -ne $Ownership.DirectoryHandle) {
        try { $Ownership.DirectoryHandle.Dispose() } catch { }
        $Ownership.DirectoryHandle = $null
    }
}

function Remove-WpaOwnedRunStagingDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership)

    Close-WpaRunStagingOwnershipHandles -Ownership $Ownership
    throw 'PREVIEW_STAGING_PRESERVED'
}

function Move-WpaOwnedRunStagingDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership,[Parameter(Mandatory)][string]$FinalPath)

    if ($Ownership.PSObject.Properties.Name -notcontains 'DirectoryHandle' -or
        $null -eq $Ownership.DirectoryHandle -or -not $Ownership.DirectoryHandle.IsOpen) {
        throw 'Owned staging directory identity is unavailable.'
    }
    $Ownership.DirectoryHandle.Rename([IO.Path]::GetFullPath($FinalPath))
}

function Assert-WpaStagingOwnershipMarkerReleased {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership)

    if ([IO.File]::Exists($Ownership.MarkerPath)) { throw 'Staging ownership marker remains open.' }
    return $true
}

function Invoke-WpaStagedPlanActionSetValidation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Actions)

    try {
        Assert-WpaPlanActionSet -Actions $Actions | Out-Null
    } catch {
        if ($Actions.Count -ne 0 -or $_.FullyQualifiedErrorId -notlike 'ParameterArgumentValidationErrorEmptyArrayNotAllowed*') { throw }
    }
}

function Publish-WpaPreparedRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Preparation,[Parameter(Mandatory)][string]$WorkspacePath)

    $runId = [string](Get-WpaPropertyValue -InputObject $Preparation.run -Name 'runId' -Default '')
    if ($runId -cnotmatch '^[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') { throw 'RUN_ID_INVALID' }
    $workspace = Resolve-WpaTrustedWorkspacePath -WorkspacePath $WorkspacePath
    $runsPath = [IO.Path]::GetFullPath((Join-Path $workspace 'runs'))
    $finalPath = [IO.Path]::GetFullPath((Join-Path $runsPath $runId))
    $stagingLeaf = ".staging-$runId"
    $stagingPath = [IO.Path]::GetFullPath((Join-Path $runsPath $stagingLeaf))
    Assert-WpaTrustedPublicationAncestry -WorkspacePath $workspace -RunsPath $runsPath -StagingPath $stagingPath | Out-Null
    if (Test-Path -LiteralPath $finalPath -ErrorAction Stop) { throw 'Final run workspace already exists.' }
    if (Test-Path -LiteralPath $stagingPath -ErrorAction Stop) { throw 'Run staging workspace already exists.' }

    $profilesPath = [IO.Path]::GetFullPath((Join-Path $stagingPath 'profiles'))
    $profileWrites = [System.Collections.Generic.List[object]]::new()
    foreach ($profile in @(Get-WpaPropertyValue -InputObject $Preparation -Name 'profiles' -Default @())) {
        $profileName = [string](Get-WpaPropertyValue -InputObject $profile -Name 'name' -Default '')
        if ($profileName -cnotmatch '^[a-z0-9][a-z0-9-]{0,31}$') { throw 'Invalid profile name.' }
        $profilePath = [IO.Path]::GetFullPath((Join-Path $profilesPath "$profileName.yaml"))
        if (-not [string]::Equals([IO.Path]::GetDirectoryName($profilePath), $profilesPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Profile path escapes the staging directory.'
        }
        $profileWrites.Add([pscustomobject]@{Path=$profilePath;Text=[string](Get-WpaPropertyValue -InputObject $profile -Name 'text' -Default '')})
    }

    $ownership = $null
    $stagingCreated = $false
    try {
        $ownership = New-WpaRunStagingOwnership -WorkspacePath $workspace -RunsPath $runsPath -StagingPath $stagingPath -ExpectedLeaf $stagingLeaf
        $stagingCreated = $true
        Write-WpaOwnedStagingText -Ownership $ownership -Path (Get-WpaRunArtifactPath $stagingPath manifest) -Text $Preparation.manifestText
        Write-WpaOwnedStagingText -Ownership $ownership -Path (Get-WpaRunArtifactPath $stagingPath policy) -Text $Preparation.policyText
        Write-WpaOwnedStagingJson -Ownership $ownership -Path (Get-WpaRunArtifactPath $stagingPath inventory) -Data $Preparation.inventory
        Write-WpaOwnedStagingJson -Ownership $ownership -Path (Get-WpaRunArtifactPath $stagingPath plan) -Data $Preparation.plan
        Write-WpaOwnedStagingText -Ownership $ownership -Path (Get-WpaRunArtifactPath $stagingPath planMarkdown) -Text (ConvertTo-WpaPlanMarkdown $Preparation.plan)
        Write-WpaOwnedStagingJson -Ownership $ownership -Path (Get-WpaRunArtifactPath $stagingPath run) -Data $Preparation.run

        if ($profileWrites.Count -gt 0) {
            Assert-WpaOwnedRunStagingTrust -Ownership $ownership | Out-Null
            [IO.Directory]::CreateDirectory($profilesPath) | Out-Null
            $profilesItem = Get-Item -LiteralPath $profilesPath -Force -ErrorAction Stop
            if (($profilesItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or @(Get-ChildItem -LiteralPath $profilesPath -Force).Count -ne 0) {
                throw 'Profile snapshot directory is not trusted.'
            }
            $ownership.OwnedDirectories.Add($profilesPath) | Out-Null
            foreach ($profileWrite in $profileWrites) {
                Write-WpaOwnedStagingText -Ownership $ownership -Path $profileWrite.Path -Text $profileWrite.Text
            }
        }

        Assert-WpaOwnedRunStagingTrust -Ownership $ownership | Out-Null
        Read-WpaRun -RunPath $stagingPath | Out-Null
        $stagedPlan = Read-WpaJsonFile (Get-WpaRunArtifactPath $stagingPath plan)
        Test-WpaDataSchema -Data $stagedPlan -SchemaName plan | Out-Null
        Invoke-WpaStagedPlanActionSetValidation -Actions @($stagedPlan.actions)
        Assert-WpaPlanIntegrity -Plan $stagedPlan | Out-Null
        Assert-WpaOwnedStagingContents -Ownership $ownership | Out-Null
        $ownership.Stream.Dispose()
        $ownership.Stream = $null
        Assert-WpaStagingOwnershipMarkerReleased -Ownership $ownership | Out-Null
        Move-WpaOwnedRunStagingDirectory -Ownership $ownership -FinalPath $finalPath
        return $finalPath
    } catch {
        if ($stagingCreated) {
            if ($null -ne $ownership) { Close-WpaRunStagingOwnershipHandles -Ownership $ownership }
            throw 'PREVIEW_STAGING_PRESERVED'
        }
        throw
    } finally {
        if ($null -ne $ownership) { Close-WpaRunStagingOwnershipHandles -Ownership $ownership }
    }
}
