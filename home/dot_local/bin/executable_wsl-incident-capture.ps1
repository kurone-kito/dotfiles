# cspell:ignore hyperv cimv pgscan kswapd pgsteal pswpin pgmajfault vhdx
[CmdletBinding()]
param(
  [ValidateRange(1, 60)]
  [int]$IntervalSeconds = 5,

  [ValidateRange(1, 86400)]
  [int]$DurationSeconds = 86400,

  [ValidateRange(65536, 33554432)]
  [long]$MaximumLogBytes = 33554432,

  [string]$OutputDirectory,
  [string]$GuestDistro,
  [switch]$Help,

  # Internal worker arguments. These are not included in logs or error text.
  [ValidateSet('', 'cpu', 'memory', 'disk', 'hyperv')]
  [string]$WorkerSource = '',
  [string]$AliasSalt = '',
  [switch]$Worker
)

$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:WorkerTimeoutMilliseconds = 1500
$script:GuestTimeoutMilliseconds = 2000
$script:CleanupGraceMilliseconds = 300
$script:OutputDrainTimeoutMilliseconds = 1000
$script:RecordLimitBytes = 32768
$script:LogPrefix = 'wsl-capture-'
$script:CollectorScriptPath = $PSCommandPath
$script:AliasSalt = $AliasSalt

function Test-DotfilesWindowsHost {
  return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Get-DotfilesUtcNow {
  if ($null -ne $script:UtcClockProvider) { return & $script:UtcClockProvider }
  return [DateTime]::UtcNow
}

function Get-DotfilesMonotonicMilliseconds {
  if ($null -ne $script:ClockProvider) { return [double](& $script:ClockProvider) }
  return [Diagnostics.Stopwatch]::GetTimestamp() * 1000.0 / [Diagnostics.Stopwatch]::Frequency
}

function Wait-DotfilesMilliseconds {
  param([Parameter(Mandatory = $true)][int]$Milliseconds)
  if ($Milliseconds -le 0) { return }
  if ($null -ne $script:SleepProvider) {
    & $script:SleepProvider $Milliseconds
    return
  }
  Start-Sleep -Milliseconds $Milliseconds
}

function Test-DotfilesGuestProbeAllowed {
  param(
    [string]$Distribution,
    [bool]$Suppressed,
    [object[]]$Inhibitions,
    [double]$NowMilliseconds,
    [double]$LastAttemptMilliseconds
  )
  if ([string]::IsNullOrWhiteSpace($Distribution) -or $Suppressed) { return $false }
  if (@($Inhibitions | Where-Object { $_.source -eq '*' -or $_.source -eq 'guest' }).Count -gt 0) { return $false }
  return (($NowMilliseconds - $LastAttemptMilliseconds) -ge 60000)
}

function Get-DotfilesDefaultStateDirectory {
  $base = $env:LOCALAPPDATA
  if ([string]::IsNullOrWhiteSpace($base)) {
    $base = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
  }
  if ([string]::IsNullOrWhiteSpace($base)) {
    throw 'state-directory-unavailable'
  }
  return [IO.Path]::GetFullPath((Join-Path $base 'Dotfiles\wsl-incident-telemetry'))
}

function Get-DotfilesSafePath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$MustExist
  )

  $full = [IO.Path]::GetFullPath($Path)
  $root = [IO.Path]::GetPathRoot($full)
  if ([string]::IsNullOrWhiteSpace($root)) {
    throw 'path-invalid'
  }
  $current = $root
  $relative = $full.Substring($root.Length)
  foreach ($segment in ($relative -split '[\\/]')) {
    if ([string]::IsNullOrEmpty($segment)) { continue }
    if ($segment.Contains(':') -or $segment.EndsWith(' ') -or $segment.EndsWith('.')) {
      throw 'path-invalid'
    }
    $current = Join-Path $current $segment
    if (Test-Path -LiteralPath $current) {
      $item = Get-Item -LiteralPath $current -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'path-reparse-point'
      }
    }
  }
  if ($MustExist -and -not (Test-Path -LiteralPath $full)) {
    throw 'path-not-found'
  }
  return $full
}

function Resolve-DotfilesOutputDirectoryPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $root = [IO.Path]::GetPathRoot($Path)
  $rootHasSeparator = -not [string]::IsNullOrEmpty($root) -and (
    $root.EndsWith([string][IO.Path]::DirectorySeparatorChar) -or
    $root.EndsWith([string][IO.Path]::AltDirectorySeparatorChar)
  )
  $rootedAndAbsolute = $false
  if (-not [string]::IsNullOrEmpty($root)) {
    if ([IO.Path]::DirectorySeparatorChar -eq [char]'\') {
      $uncShareRoot = $Path.Length -eq $root.Length -and $Path -match '^[\\/]{2}'
      $rootedAndAbsolute = $root.Length -gt 1 -and ($rootHasSeparator -or $uncShareRoot)
    }
    else {
      $rootedAndAbsolute = $Path.Length -eq $root.Length -or $rootHasSeparator
    }
  }
  if ($rootedAndAbsolute) { return [IO.Path]::GetFullPath($Path) }

  $location = Get-Location
  if ($location.Provider.Name -ne 'FileSystem') { throw 'path-invalid' }
  if ($Path.Contains('::')) { throw 'path-invalid' }
  $providerInfo = $null
  $driveInfo = $null
  $providerPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref]$providerInfo, [ref]$driveInfo)
  if ($null -eq $providerInfo -or $providerInfo.Name -ne 'FileSystem') { throw 'path-invalid' }
  return [IO.Path]::GetFullPath($providerPath)
}

function Initialize-DotfilesPrivateDirectory {
  param([Parameter(Mandatory = $true)][string]$Path)

  $wasPresent = Test-Path -LiteralPath $Path
  $safe = Get-DotfilesSafePath -Path $Path
  [void][IO.Directory]::CreateDirectory($safe)
  $safe = Get-DotfilesSafePath -Path $safe -MustExist
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  try {
    $sid = $identity.User
    if ($wasPresent) {
      $existingAcl = Get-Acl -LiteralPath $safe
      $rules = @($existingAcl.Access)
      if ($existingAcl.AreAccessRulesProtected -and $rules.Count -eq 1 -and [string]$rules[0].IdentityReference -eq [string]$sid -and (($rules[0].FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl) -and $rules[0].AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow) {
        return $safe
      }
    }
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($sid)
    $rights = [Security.AccessControl.FileSystemRights]::FullControl
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, $rights, $inheritance, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
    [void]$acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $safe -AclObject $acl
  }
  finally {
    $identity.Dispose()
  }
  return $safe
}

function Get-DotfilesProcessStartTicks {
  param([Parameter(Mandatory = $true)][int]$ProcessId)

  foreach ($attempt in 1, 2, 3) {
    $process = $null
    try {
      $process = [Diagnostics.Process]::GetProcessById($ProcessId)
      if ($process.HasExited) { return $null }
      return $process.StartTime.ToUniversalTime().Ticks
    }
    catch [ArgumentException] {
      return $null
    }
    catch {
      if ($attempt -eq 3) { return 'ambiguous' }
    }
    finally {
      if ($null -ne $process) { $process.Dispose() }
    }
  }
}

function Test-DotfilesRetainedProcessIdentity {
  param(
    [Parameter(Mandatory = $true)]$Process,
    [Parameter(Mandatory = $true)][long]$StartTimeTicks
  )

  # The retained handle names the original process object. A PID-only
  # reopen can fail while that handle is still authoritative. StartTime
  # can also throw for a process that is still the one that was started.
  foreach ($attempt in 1, 2, 3) {
    try {
      if ($Process.HasExited) { return $false }
      return ($Process.StartTime.ToUniversalTime().Ticks -eq $StartTimeTicks)
    }
    catch {
      if ($attempt -eq 3) {
        try {
          if ($Process.HasExited) { return $false }
        }
        catch {
          return $false
        }
        return $true
      }
    }
  }
}

function Test-DotfilesExactProcessIdentity {
  param(
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][long]$StartTimeTicks
  )
  $current = Get-DotfilesProcessStartTicks -ProcessId $ProcessId
  if ($current -is [string] -and $current -eq 'ambiguous') { return $null }
  if ($null -eq $current) { return $false }
  return ([long]$current -eq $StartTimeTicks)
}

function Get-DotfilesLockFailureReason {
  param([Parameter(Mandatory = $true)][Exception]$Exception)

  $nativeErrorCode = [int]$Exception.HResult -band 0xFFFF
  if ([IO.Path]::DirectorySeparatorChar -eq '\') {
    if ($nativeErrorCode -eq 32 -or $nativeErrorCode -eq 33) { return 'already-running' }
  }
  elseif ($nativeErrorCode -eq 11 -or $nativeErrorCode -eq 35) {
    return 'already-running'
  }
  return 'lock-state-unavailable'
}

function Enter-DotfilesCollectorLock {
  param(
    [Parameter(Mandatory = $true)][string]$StateDirectory,
    [Parameter(Mandatory = $true)][string]$RunId
  )

  $lockHandle = $null
  $activePath = Join-Path $StateDirectory 'collector.active.lock'
  $metadataPath = Join-Path $StateDirectory 'collector.lock.json'
  try {
    if (Test-Path -LiteralPath $activePath) { $null = Get-DotfilesSafePath -Path $activePath -MustExist }
    if (Test-Path -LiteralPath $metadataPath) { $null = Get-DotfilesSafePath -Path $metadataPath -MustExist }
    $lockHandle = [IO.File]::Open($activePath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  }
  catch [IO.IOException] {
    $reason = Get-DotfilesLockFailureReason -Exception $_.Exception
    return @{ Acquired = $false; Reason = $reason; Handle = $null }
  }

  try {
    if (Test-Path -LiteralPath $metadataPath) {
      try {
        $old = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $oldProcessId = 0
        $oldStartTimeTicks = [long]0
        if (-not [int]::TryParse([string]$old.processId, [ref]$oldProcessId) -or $oldProcessId -le 0 -or
          -not [long]::TryParse([string]$old.startTimeTicks, [ref]$oldStartTimeTicks) -or $oldStartTimeTicks -le 0 -or
          [string]::IsNullOrWhiteSpace([string]$old.runId)) {
          throw 'lock-metadata-ambiguous'
        }
        $sameOwner = Test-DotfilesExactProcessIdentity -ProcessId $oldProcessId -StartTimeTicks $oldStartTimeTicks
        if ($null -eq $sameOwner) { throw 'lock-metadata-ambiguous' }
        # The exclusive OS lock is already held here. A still-living
        # metadata owner released that lock, so the record is stale.
      }
      catch {
        $lockHandle.Dispose()
        return @{ Acquired = $false; Reason = 'lock-metadata-ambiguous'; Handle = $null }
      }

    }

    $process = [Diagnostics.Process]::GetCurrentProcess()
    try {
      $metadata = [ordered]@{
        processId = $process.Id
        startTimeTicks = $process.StartTime.ToUniversalTime().Ticks
        runId = $RunId
        acquiredAtUtc = (Get-DotfilesUtcNow).ToString('o')
      }
    }
    finally {
      $process.Dispose()
    }
    $temporary = Join-Path $StateDirectory ('.collector.lock.' + $RunId + '.tmp')
    [IO.File]::WriteAllText($temporary, ($metadata | ConvertTo-Json -Compress), $script:Utf8NoBom)
    if (Test-Path -LiteralPath $metadataPath) {
      [IO.File]::Delete($metadataPath)
    }
    [IO.File]::Move($temporary, $metadataPath)
    return @{ Acquired = $true; Reason = 'acquired'; Handle = $lockHandle; MetadataPath = $metadataPath; RunId = $RunId }
  }
  catch {
    if ($null -ne $lockHandle) { $lockHandle.Dispose() }
    return @{ Acquired = $false; Reason = 'lock-state-unavailable'; Handle = $null }
  }
}

function Exit-DotfilesCollectorLock {
  param([Parameter(Mandatory = $true)]$Lock)

  if ($null -eq $Lock -or -not $Lock.Acquired) { return }
  try {
    if (Test-Path -LiteralPath $Lock.MetadataPath) {
      $metadata = Get-Content -LiteralPath $Lock.MetadataPath -Raw | ConvertFrom-Json
      if ([string]$metadata.runId -eq [string]$Lock.RunId) {
        [IO.File]::Delete($Lock.MetadataPath)
      }
    }
  }
  catch {
    # A leftover marker is reconciled by PID plus process start time next run.
  }
  finally {
    if ($null -ne $Lock.Handle) { $Lock.Handle.Dispose() }
  }
}

function Read-DotfilesInhibitions {
  param(
    [Parameter(Mandatory = $true)][string]$StateDirectory,
    [string]$CurrentRunId
  )

  $path = Join-Path $StateDirectory 'inhibitions.json'
  if (-not (Test-Path -LiteralPath $path)) { return @() }
  try {
    $null = Get-DotfilesSafePath -Path $path -MustExist
    $parsed = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $stored = New-Object System.Collections.ArrayList
    foreach ($entry in @($parsed)) { [void]$stored.Add($entry) }
    $remaining = New-Object System.Collections.ArrayList
    foreach ($entry in $stored) {
      $source = [string]$entry.source
      if ($source -notin @('*', 'cpu', 'memory', 'disk', 'hyperv', 'guest')) {
        [void]$remaining.Add(@{ source = '*'; cleanupUnverified = $true; processId = -1; startTimeTicks = 0 })
        continue
      }
      $processId = 0
      $startTimeTicks = [long]0
      $placeholder = $false
      if ([int]::TryParse([string]$entry.processId, [ref]$processId) -and [long]::TryParse([string]$entry.startTimeTicks, [ref]$startTimeTicks)) {
        $placeholder = $processId -eq -1 -and $startTimeTicks -eq 0 -and $entry.cleanupUnverified -and -not [string]::IsNullOrWhiteSpace([string]$entry.runId)
      }
      if (-not $placeholder -and ($processId -le 0 -or $startTimeTicks -le 0)) {
        [void]$remaining.Add(@{ source = '*'; cleanupUnverified = $true; processId = -1; startTimeTicks = 0 })
        continue
      }
      if (-not [string]::IsNullOrWhiteSpace($CurrentRunId) -and [string]$entry.runId -eq $CurrentRunId) { continue }
      if ($placeholder) {
        [void]$remaining.Add($entry)
        continue
      }
      if ($entry.cleanupUnverified) {
        [void]$remaining.Add($entry)
        continue
      }
      $same = Test-DotfilesExactProcessIdentity -ProcessId $processId -StartTimeTicks $startTimeTicks
      if ($null -eq $same -or $same) { [void]$remaining.Add($entry) }
    }
    return @($remaining.ToArray())
  }
  catch {
    return @(@{ source = '*'; cleanupUnverified = $true; processId = -1; startTimeTicks = 0 })
  }
}

function Write-DotfilesInhibitions {
  param(
    [Parameter(Mandatory = $true)][string]$StateDirectory,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries,
    [Parameter(Mandatory = $true)][string]$RunId,
    [AllowEmptyCollection()][object[]]$WorkerJournal = @()
  )

  $path = Join-Path $StateDirectory 'inhibitions.json'
  $entryArray = [object[]]@($Entries) + [object[]]@($WorkerJournal)
  if ($entryArray.Count -eq 0) {
    if (Test-Path -LiteralPath $path) { [IO.File]::Delete($path) }
    return
  }
  $temporary = Join-Path $StateDirectory ('.inhibitions.' + $RunId + '.tmp')
  $json = ConvertTo-Json -InputObject $entryArray -Compress -Depth 4
  [IO.File]::WriteAllText($temporary, $json, $script:Utf8NoBom)
  if (Test-Path -LiteralPath $path) {
    $backup = Join-Path $StateDirectory ('.inhibitions.' + [Guid]::NewGuid().ToString('N') + '.backup')
    [IO.File]::Replace($temporary, $path, $backup)
    try { [IO.File]::Delete($backup) } catch { }
  }
  else {
    [IO.File]::Move($temporary, $path)
  }
}

function ConvertTo-DotfilesWindowsArgument {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

  $builder = New-Object Text.StringBuilder
  [void]$builder.Append('"')
  $slashes = 0
  foreach ($character in $Value.ToCharArray()) {
    if ($character -eq '\') {
      $slashes++
      continue
    }
    if ($character -eq '"') {
      [void]$builder.Append(('\' * (2 * $slashes + 1)))
      [void]$builder.Append('"')
      $slashes = 0
      continue
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)) }
    [void]$builder.Append($character)
    $slashes = 0
  }
  if ($slashes -gt 0) { [void]$builder.Append(('\' * (2 * $slashes))) }
  [void]$builder.Append('"')
  return $builder.ToString()
}

function Get-DotfilesPowerShellExecutable {
  $base = $PSHOME
  if (-not (Test-DotfilesWindowsHost)) {
    $name = 'pwsh'
  }
  elseif ($PSVersionTable.PSVersion.Major -ge 6) {
    $name = 'pwsh.exe'
  }
  else {
    $name = 'powershell.exe'
  }
  $candidate = Join-Path $base $name
  if (Test-Path -LiteralPath $candidate) { return $candidate }
  $command = Get-Command $name -ErrorAction SilentlyContinue
  if ($null -ne $command) { return $command.Source }
  throw 'powershell-executable-unavailable'
}

function Initialize-DotfilesBoundedStreamReader {
  if ('DotfilesIncident.BoundedStreamReader' -as [type]) { return }
  $typeSource = @'
using System.IO;
using System.Text;
using System.Threading.Tasks;
namespace DotfilesIncident {
  public sealed class CapturedText {
    public readonly string Text;
    public readonly bool Truncated;
    public CapturedText(string text, bool truncated) { Text = text; Truncated = truncated; }
  }
  public static class BoundedStreamReader {
    public static Task<CapturedText> CaptureAsync(TextReader reader, int maxCharacters) {
      return Task.Factory.StartNew(() => {
        var buffer = new char[4096];
        var output = new StringBuilder(maxCharacters < 8192 ? maxCharacters : 8192);
        var truncated = false;
        int count;
        while ((count = reader.Read(buffer, 0, buffer.Length)) > 0) {
          int remaining = maxCharacters - output.Length;
          int keep = remaining > 0 ? (count < remaining ? count : remaining) : 0;
          if (keep > 0) output.Append(buffer, 0, keep);
          if (keep < count) truncated = true;
        }
        return new CapturedText(output.ToString(), truncated);
      });
    }
    public static Task DrainAsync(TextReader reader) {
      return Task.Factory.StartNew(() => {
        var buffer = new char[4096];
        while (reader.Read(buffer, 0, buffer.Length) > 0) { }
      });
    }
  }
}
'@
  Add-Type -TypeDefinition $typeSource -ErrorAction Stop | Out-Null
}

function Initialize-DotfilesProcessTree {
  if ('DotfilesIncident.ProcessTree' -as [type]) { return }
  $typeSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace DotfilesIncident {
  public class ProcessLink { public int ProcessId; public int ParentId; }
  public static class ProcessTree {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PROCESSENTRY32 {
      public uint dwSize; public uint cntUsage; public uint th32ProcessID;
      public IntPtr th32DefaultHeapID; public uint th32ModuleID; public uint cntThreads;
      public uint th32ParentProcessID; public int pcPriClassBase; public uint dwFlags;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile;
    }
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);
    [DllImport("kernel32.dll", EntryPoint="Process32FirstW", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool Process32First(IntPtr snapshot, ref PROCESSENTRY32 entry);
    [DllImport("kernel32.dll", EntryPoint="Process32NextW", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool Process32Next(IntPtr snapshot, ref PROCESSENTRY32 entry);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool CloseHandle(IntPtr handle);
    public static ProcessLink[] Snapshot() {
      IntPtr snapshot = CreateToolhelp32Snapshot(2, 0);
      if (snapshot == new IntPtr(-1)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      try {
        var items = new List<ProcessLink>();
        var entry = new PROCESSENTRY32(); entry.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
        if (!Process32First(snapshot, ref entry)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        do { items.Add(new ProcessLink { ProcessId = (int)entry.th32ProcessID, ParentId = (int)entry.th32ParentProcessID }); }
        while (Process32Next(snapshot, ref entry));
        return items.ToArray();
      } finally { CloseHandle(snapshot); }
    }
  }
}
'@
  Add-Type -TypeDefinition $typeSource -ErrorAction Stop | Out-Null
}

function Start-DotfilesOwnedProcess {
  param(
    [Parameter(Mandatory = $true)][string]$FileName,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$StandardInputText
  )

  $startInfo = New-Object Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FileName
  $startInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-DotfilesWindowsArgument -Value $_ }) -join ' ')
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.RedirectStandardInput = $true
  try { $startInfo.StandardOutputEncoding = [Text.Encoding]::UTF8 } catch { }
  try { $startInfo.StandardErrorEncoding = [Text.Encoding]::UTF8 } catch { }

  $process = New-Object Diagnostics.Process
  $started = $false
  $startTicks = [long]0
  $stdoutTask = $null
  $stderrTask = $null
  try {
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'process-start-failed' }
    $started = $true
    $startTicks = $process.StartTime.ToUniversalTime().Ticks
    $stdoutTask = [DotfilesIncident.BoundedStreamReader]::CaptureAsync($process.StandardOutput, 65536)
    $stderrTask = [DotfilesIncident.BoundedStreamReader]::DrainAsync($process.StandardError)
    if ($null -ne $StandardInputText) {
      $process.StandardInput.Write($StandardInputText)
    }
    $process.StandardInput.Close()
    return @{
      Process = $process
      ProcessId = $process.Id
      StartTimeTicks = $startTicks
      Source = $Source
      StdoutTask = $stdoutTask
      StderrTask = $stderrTask
      StartedAtMilliseconds = Get-DotfilesMonotonicMilliseconds
    }
  }
  catch {
    $mayRemain = $false
    $cleanupEntries = @()
    if ($started) {
      if ($startTicks -gt 0) {
        try {
          $partialOwned = @{ Process = $process; ProcessId = $process.Id; StartTimeTicks = $startTicks; Source = $Source }
          $cleanup = Stop-DotfilesOwnedProcess -Owned $partialOwned -GraceMilliseconds 1000
          $mayRemain = -not [bool]$cleanup.Exited
          if ($mayRemain) { $cleanupEntries = @($cleanup.Entries) }
        }
        catch { $mayRemain = $true }
      }
      else {
        try {
          if (-not $process.HasExited) {
            $process.Kill()
            $null = $process.WaitForExit(1000)
          }
        }
        catch { }
        # Without a stable start time, the root can be stopped by its retained
        # handle but its descendants cannot be reconciled safely.
        $mayRemain = $true
      }
      foreach ($task in @($stdoutTask, $stderrTask)) {
        if ($null -ne $task) { try { $null = $task.Wait(1000) } catch { } }
      }
    }
    try { $_.Exception.Data['DotfilesOwnedProcessMayRemain'] = [bool]$mayRemain } catch { }
    if ($mayRemain -and $cleanupEntries.Count -gt 0) {
      try { $_.Exception.Data['DotfilesOwnedProcessCleanupEntries'] = [object[]]$cleanupEntries } catch { }
    }
    $process.Dispose()
    throw
  }
}

function Get-DotfilesVerifiedProcessTree {
  param([Parameter(Mandatory = $true)]$Owned)

  # The retained handle authenticates the root. After it exits, PID-only
  # parent links cannot prove descendant ownership across reuse.
  if (-not (Test-DotfilesRetainedProcessIdentity -Process $Owned.Process -StartTimeTicks ([long]$Owned.StartTimeTicks))) {
    return @{ Complete = $false; Processes = @() }
  }

  $links = Get-DotfilesProcessTreeSnapshot
  $rootTicks = Test-DotfilesExactProcessIdentity -ProcessId $Owned.ProcessId -StartTimeTicks $Owned.StartTimeTicks
  if ($rootTicks -eq $false) {
    return @{ Complete = $false; Processes = @() }
  }
  if ($null -eq $rootTicks -and -not (Test-DotfilesRetainedProcessIdentity -Process $Owned.Process -StartTimeTicks ([long]$Owned.StartTimeTicks))) {
    return @{ Complete = $false; Processes = @() }
  }
  $verified = New-Object System.Collections.ArrayList
  [void]$verified.Add(@{ ProcessId = $Owned.ProcessId; StartTimeTicks = $Owned.StartTimeTicks; Process = $Owned.Process; ParentId = $null; Root = $true })
  $known = @{}
  $known[[string]$Owned.ProcessId] = [long]$Owned.StartTimeTicks
  $knownProcesses = @{}
  $knownProcesses[[string]$Owned.ProcessId] = $Owned.Process
  $parentIdsWithChildren = @{}
  $staleLinks = @{}
  foreach ($link in $links) { $parentIdsWithChildren[[string]$link.ParentId] = $true }
  $changed = $true
  while ($changed) {
    $changed = $false
    foreach ($link in $links) {
      $parentKey = [string]$link.ParentId
      $childKey = [string]$link.ProcessId
      if (-not $known.ContainsKey($parentKey) -or $known.ContainsKey($childKey)) { continue }
      $childProcess = $null
      try {
        $childProcess = [Diagnostics.Process]::GetProcessById([int]$link.ProcessId)
        if ($childProcess.HasExited) {
          # A child captured in the snapshot may have created descendants
          # before it exited. Its missing handle makes those parent links
          # impossible to verify, even if the first snapshot showed none.
          return @{ Complete = $false; Processes = @() }
        }
        $childTicks = $childProcess.StartTime.ToUniversalTime().Ticks
        if ($childTicks -lt [long]$known[$parentKey]) {
          $staleLinks[$childKey] = @{ ParentId = [int]$link.ParentId; StartTimeTicks = $childTicks }
          continue
        }
        $parentProcess = $knownProcesses[$parentKey]
        if ($null -eq $parentProcess) { return @{ Complete = $false; Processes = @() } }
        if ($parentProcess.HasExited -and $childTicks -gt $parentProcess.ExitTime.ToUniversalTime().Ticks) {
          return @{ Complete = $false; Processes = @() }
        }
        [void]$verified.Add(@{ ProcessId = $childProcess.Id; StartTimeTicks = $childTicks; Process = $childProcess; ParentId = [int]$link.ParentId; Root = $false })
        $known[$childKey] = $childTicks
        $knownProcesses[$childKey] = $childProcess
        $childProcess = $null
        $changed = $true
      }
      catch [ArgumentException] {
        # A missing captured child may have descendants not present in the
        # initial snapshot, so cleanup must remain inhibited.
        return @{ Complete = $false; Processes = @() }
      }
      catch {
        return @{ Complete = $false; Processes = @() }
      }
      finally {
        if ($null -ne $childProcess) { $childProcess.Dispose() }
      }
    }
  }

  # Bind each opened process back to a fresh PID/parent-PID snapshot. If a
  # PID changed owners between enumeration and opening, or the tree changed
  # while it was being checked, keep the source inhibited rather than kill an
  # ambiguous process.
  $recheckedLinks = Get-DotfilesProcessTreeSnapshot
  $recheckedById = @{}
  foreach ($link in $recheckedLinks) {
    $processKey = [string]$link.ProcessId
    if ($recheckedById.ContainsKey($processKey)) { return @{ Complete = $false; Processes = @() } }
    $recheckedById[$processKey] = $link
  }
  foreach ($node in $verified) {
    if ($node.Root) {
      $rootStillSame = Test-DotfilesExactProcessIdentity -ProcessId $node.ProcessId -StartTimeTicks $node.StartTimeTicks
      if ($rootStillSame -eq $false) { return @{ Complete = $false; Processes = @() } }
      if ($null -eq $rootStillSame -and -not (Test-DotfilesRetainedProcessIdentity -Process $node.Process -StartTimeTicks ([long]$node.StartTimeTicks))) {
        return @{ Complete = $false; Processes = @() }
      }
      continue
    }
    $currentLink = $recheckedById[[string]$node.ProcessId]
    if ($null -eq $currentLink) {
      if ($parentIdsWithChildren.ContainsKey([string]$node.ProcessId)) { return @{ Complete = $false; Processes = @() } }
      continue
    }
    if ([int]$currentLink.ParentId -ne [int]$node.ParentId) { return @{ Complete = $false; Processes = @() } }
    $sameProcess = Test-DotfilesExactProcessIdentity -ProcessId $node.ProcessId -StartTimeTicks $node.StartTimeTicks
    if ($null -eq $sameProcess -or -not $sameProcess) { return @{ Complete = $false; Processes = @() } }
    $parentProcess = $knownProcesses[[string]$node.ParentId]
    if ($null -eq $parentProcess) { return @{ Complete = $false; Processes = @() } }
    try {
      if ($parentProcess.HasExited -and $node.StartTimeTicks -gt $parentProcess.ExitTime.ToUniversalTime().Ticks) {
        return @{ Complete = $false; Processes = @() }
      }
    }
    catch { return @{ Complete = $false; Processes = @() } }
  }
  foreach ($link in $recheckedLinks) {
    $parentKey = [string]$link.ParentId
    $childKey = [string]$link.ProcessId
    if ($known.ContainsKey($parentKey) -and -not $known.ContainsKey($childKey)) {
      $stale = $staleLinks[$childKey]
      if ($null -ne $stale -and [int]$stale.ParentId -eq [int]$link.ParentId) {
        $sameStaleProcess = Test-DotfilesExactProcessIdentity -ProcessId ([int]$link.ProcessId) -StartTimeTicks ([long]$stale.StartTimeTicks)
        if ($true -eq $sameStaleProcess) { continue }
      }
      return @{ Complete = $false; Processes = @() }
    }
  }
  return @{ Complete = $true; Processes = @($verified.ToArray()); StaleLinks = $staleLinks }
}

function Get-DotfilesProcessTreeSnapshot {
  return [DotfilesIncident.ProcessTree]::Snapshot()
}

function Stop-DotfilesOwnedProcess {
  param(
    [Parameter(Mandatory = $true)]$Owned,
    [Parameter(Mandatory = $true)][int]$GraceMilliseconds
  )

  try { $rootExited = [bool]$Owned.Process.HasExited }
  catch {
    return @{ Exited = $false; CleanupUnverified = $true; Entries = @(@{ source = $Owned.Source; processId = $Owned.ProcessId; startTimeTicks = $Owned.StartTimeTicks; cleanupUnverified = $true }) }
  }

  if ($rootExited) {
    $exitTimeTicks = 0
    try { $exitTimeTicks = $Owned.Process.ExitTime.ToUniversalTime().Ticks } catch { }
    $entry = @{ source = $Owned.Source; processId = $Owned.ProcessId; startTimeTicks = $Owned.StartTimeTicks; cleanupUnverified = $true }
    if ($exitTimeTicks -gt 0) { $entry.exitTimeTicks = $exitTimeTicks }
    return @{ Exited = $false; CleanupUnverified = $true; Entries = @($entry) }
  }

  $tree = $null
  try { $tree = Get-DotfilesVerifiedProcessTree -Owned $Owned } catch { $tree = @{ Complete = $false; Processes = @() } }
  if (-not $tree.Complete) {
    return @{ Exited = $false; CleanupUnverified = $true; Entries = @(@{ source = $Owned.Source; processId = $Owned.ProcessId; startTimeTicks = $Owned.StartTimeTicks; cleanupUnverified = $true }) }
  }

  $graceWatch = [Diagnostics.Stopwatch]::StartNew()
  for ($index = $tree.Processes.Count - 1; $index -ge 0; $index--) {
    $node = $tree.Processes[$index]
    $stillSame = Test-DotfilesExactProcessIdentity -ProcessId $node.ProcessId -StartTimeTicks $node.StartTimeTicks
    if ($null -eq $stillSame) {
      $retainedRoot = $node.Root -and (Test-DotfilesRetainedProcessIdentity -Process $node.Process -StartTimeTicks ([long]$node.StartTimeTicks))
      if (-not $retainedRoot) {
        return @{ Exited = $false; CleanupUnverified = $true; Entries = @(@{ source = $Owned.Source; processId = $node.ProcessId; startTimeTicks = $node.StartTimeTicks; cleanupUnverified = $true }) }
      }
    }
    elseif (-not $stillSame) { continue }
    try {
      if (-not $node.Process.HasExited) { $node.Process.Kill() }
    }
    catch {
      # Continue to bounded exit checks; the identity is retained below.
    }
  }

  $entries = New-Object System.Collections.ArrayList
  foreach ($node in $tree.Processes) {
    $elapsedMs = [int][Math]::Min([int]::MaxValue, [Math]::Floor($graceWatch.Elapsed.TotalMilliseconds))
    $remaining = [Math]::Max(0, $GraceMilliseconds - $elapsedMs)
    $exited = $false
    # WaitForExit(int) can return before the budget elapses while the
    # process is still alive. Retry only that early return; a wait that
    # consumed the budget stays unverified.
    $guard = 0
    while (-not $exited -and $remaining -gt 0 -and $guard -lt 8) {
      $guard++
      $slice = [Diagnostics.Stopwatch]::StartNew()
      $waitThrew = $false
      try { $exited = [bool]$node.Process.WaitForExit($remaining) }
      catch { $waitThrew = $true }
      if ($waitThrew) {
        Start-Sleep -Milliseconds 15
        $remaining = [Math]::Max(0, $remaining - 15)
      }
      elseif (-not $exited) {
        $hasExited = $false
        $hasExitedThrew = $false
        try { $hasExited = [bool]$node.Process.HasExited }
        catch { $hasExitedThrew = $true }
        if ($hasExited) {
          $exited = $true
        }
        elseif ($hasExitedThrew) {
          break
        }
        else {
          $elapsed = [int][Math]::Ceiling($slice.Elapsed.TotalMilliseconds)
          if ($elapsed + 25 -ge $remaining) { break }
          $remaining = [Math]::Max(0, $remaining - [Math]::Max($elapsed, 15))
          Start-Sleep -Milliseconds 15
        }
      }
    }
    if (-not $exited) {
      [void]$entries.Add(@{ source = $Owned.Source; processId = $node.ProcessId; startTimeTicks = $node.StartTimeTicks; cleanupUnverified = $false })
    }
    if ($null -ne $node.Process) { $node.Process.Dispose() }
  }
  if ($entries.Count -gt 0) {
    [void]$entries.Add(@{ source = $Owned.Source; processId = $Owned.ProcessId; startTimeTicks = $Owned.StartTimeTicks; cleanupUnverified = $true })
    return @{ Exited = $false; CleanupUnverified = $true; Entries = @($entries.ToArray()) }
  }

  # A process can create a descendant after the verified tree snapshot and
  # before its own termination. Recheck after every verified node has exited;
  # any late or reused PID that is not an accepted stale identity under an
  # owned parent keeps cleanup inhibited.
  try {
    $finalLinks = Get-DotfilesProcessTreeSnapshot
    $knownIds = @{}
    foreach ($node in $tree.Processes) { $knownIds[[string]$node.ProcessId] = $true }
    foreach ($link in $finalLinks) {
      if ($knownIds.ContainsKey([string]$link.ParentId)) {
        $stale = $null
        if ($tree.StaleLinks) { $stale = $tree.StaleLinks[[string]$link.ProcessId] }
        if ($null -ne $stale -and [int]$stale.ParentId -eq [int]$link.ParentId) {
          $sameStaleProcess = Test-DotfilesExactProcessIdentity -ProcessId ([int]$link.ProcessId) -StartTimeTicks ([long]$stale.StartTimeTicks)
          if ($true -eq $sameStaleProcess) { continue }
        }
        [void]$entries.Add(@{ source = $Owned.Source; processId = $Owned.ProcessId; startTimeTicks = $Owned.StartTimeTicks; cleanupUnverified = $true })
        return @{ Exited = $false; CleanupUnverified = $true; Entries = @($entries.ToArray()) }
      }
    }
  }
  catch {
    [void]$entries.Add(@{ source = $Owned.Source; processId = $Owned.ProcessId; startTimeTicks = $Owned.StartTimeTicks; cleanupUnverified = $true })
    return @{ Exited = $false; CleanupUnverified = $true; Entries = @($entries.ToArray()) }
  }
  return @{ Exited = ($entries.Count -eq 0); CleanupUnverified = $false; Entries = @($entries.ToArray()) }
}

function Get-DotfilesCimInstances {
  param(
    [Parameter(Mandatory = $true)][string]$ClassName,
    [string]$TargetName
  )
  try {
    if (-not [string]::IsNullOrWhiteSpace($TargetName)) {
      $escapedTarget = $TargetName.Replace("'", "''")
      $targetItems = @(Get-CimInstance -Namespace 'root/cimv2' -ClassName $ClassName -Filter "Name = '$escapedTarget'" -ErrorAction Stop | Select-Object -First 1)
      $targetItem = if ($targetItems.Count -gt 0) { $targetItems[0] } else { $null }
      return @{ Status = 'ok'; Items = @($targetItems); TargetItem = $targetItem; OverflowCount = 0 }
    }
    $boundedItems = @(Get-CimInstance -Namespace 'root/cimv2' -ClassName $ClassName -ErrorAction Stop | Select-Object -First 17)
    $overflowCount = if ($boundedItems.Count -gt 16) { 1 } else { 0 }
    if ($boundedItems.Count -gt 16) { $boundedItems = @($boundedItems | Select-Object -First 16) }
    return @{ Status = 'ok'; Items = $boundedItems; TargetItem = $null; OverflowCount = $overflowCount }
  }
  catch [UnauthorizedAccessException] {
    return @{ Status = 'unavailable'; Error = 'access-denied'; Items = @() }
  }
  catch {
    $errorId = [string]$_.FullyQualifiedErrorId
    if ($errorId -match 'AccessDenied|Unauthorized') {
      return @{ Status = 'unavailable'; Error = 'access-denied'; Items = @() }
    }
    return @{ Status = 'unavailable'; Error = 'provider-unavailable'; Items = @() }
  }
}

function Get-DotfilesPropertyValue {
  param($Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  try {
    $value = [double]$property.Value
    if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0) { return $null }
    return $value
  }
  catch { return $null }
}

function Get-DotfilesPerRunAlias {
  param(
    [Parameter(Mandatory = $true)][string]$Identity,
    [Parameter(Mandatory = $true)][string]$Salt,
    [Parameter(Mandatory = $true)][string]$Prefix
  )
  $key = [Convert]::FromBase64String($Salt)
  $hmac = [Security.Cryptography.HMACSHA256]::new($key)
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Identity)
    $digest = $hmac.ComputeHash($bytes)
    $token = ([BitConverter]::ToString($digest).Replace('-', '').Substring(0, 16)).ToLowerInvariant()
    return "$Prefix-$token"
  }
  finally {
    $hmac.Dispose()
    [Array]::Clear($key, 0, $key.Length)
  }
}

function Get-DotfilesHostSourceSnapshot {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('cpu', 'memory', 'disk', 'hyperv')][string]$Source,
    [string]$AliasSalt = ''
  )

  switch ($Source) {
    'cpu' {
      $query = Get-DotfilesCimInstances -ClassName 'Win32_PerfRawData_PerfOS_Processor' -TargetName '_Total'
      $instance = $query.TargetItem
      if ($null -eq $instance) {
        $matches = @($query.Items | Where-Object { [string]$_.Name -eq '_Total' } | Select-Object -First 1)
        if ($matches.Count -gt 0) { $instance = $matches[0] }
      }
      if ($query.Status -ne 'ok' -or $null -eq $instance) {
        $reason = if ($query.Error) { $query.Error } else { 'counter-unavailable' }
        return @{ source = 'cpu'; status = 'unavailable'; error = $reason; metrics = @{} }
      }
      return @{ source = 'cpu'; status = 'ok'; metrics = @{
        percentProcessorTime = Get-DotfilesPropertyValue $instance 'PercentProcessorTime'
        percentPrivilegedTime = Get-DotfilesPropertyValue $instance 'PercentPrivilegedTime'
        timestampSys100Ns = Get-DotfilesPropertyValue $instance 'Timestamp_Sys100NS'
      } }
    }
    'memory' {
      $query = Get-DotfilesCimInstances -ClassName 'Win32_PerfRawData_PerfOS_Memory'
      $instance = @($query.Items | Select-Object -First 1)
      if ($query.Status -ne 'ok' -or $instance.Count -eq 0) {
        $reason = if ($query.Error) { $query.Error } else { 'counter-unavailable' }
        return @{ source = 'memory'; status = 'unavailable'; error = $reason; metrics = @{} }
      }
      $paging = Get-DotfilesCimInstances -ClassName 'Win32_PerfRawData_PerfOS_PagingFile' -TargetName '_Total'
      $pagingInstance = $paging.TargetItem
      if ($null -eq $pagingInstance) { $pagingInstance = @($paging.Items | Where-Object { [string]$_.Name -eq '_Total' } | Select-Object -First 1) }
      $pagingUsage = $null
      if ($pagingInstance -is [array]) { $pagingInstance = if ($pagingInstance.Count -gt 0) { $pagingInstance[0] } else { $null } }
      if ($null -ne $pagingInstance) {
        $usageRaw = Get-DotfilesPropertyValue $pagingInstance 'PercentUsage'
        $usageBase = Get-DotfilesPropertyValue $pagingInstance 'PercentUsage_Base'
        if ($null -ne $usageRaw -and $null -ne $usageBase -and $usageBase -gt 0) {
          $pagingUsage = [Math]::Min(100.0, 100.0 * $usageRaw / $usageBase)
        }
      }
      $sourceStatus = if ($paging.Status -eq 'ok' -and $null -ne $pagingInstance) { 'ok' } else { 'partial' }
      return @{ source = 'memory'; status = $sourceStatus; metrics = @{
        availableBytes = Get-DotfilesPropertyValue $instance[0] 'AvailableBytes'
        committedBytes = Get-DotfilesPropertyValue $instance[0] 'CommittedBytes'
        commitLimitBytes = Get-DotfilesPropertyValue $instance[0] 'CommitLimit'
        pageFilePercentUsage = $pagingUsage
        pageReadsCounter = Get-DotfilesPropertyValue $instance[0] 'PageReadsPersec'
        pagesInputCounter = Get-DotfilesPropertyValue $instance[0] 'PagesInputPersec'
        pageWritesCounter = Get-DotfilesPropertyValue $instance[0] 'PageWritesPersec'
        pagesOutputCounter = Get-DotfilesPropertyValue $instance[0] 'PagesOutputPersec'
        timestampPerfTime = Get-DotfilesPropertyValue $instance[0] 'Timestamp_PerfTime'
        frequencyPerfTime = Get-DotfilesPropertyValue $instance[0] 'Frequency_PerfTime'
      } }
    }
    'disk' {
      $physical = Get-DotfilesCimInstances -ClassName 'Win32_PerfRawData_PerfDisk_PhysicalDisk' -TargetName '_Total'
      $physicalInstance = $physical.TargetItem
      if ($null -eq $physicalInstance) { $physicalInstance = @($physical.Items | Where-Object { [string]$_.Name -eq '_Total' } | Select-Object -First 1) }
      $os = Get-DotfilesCimInstances -ClassName 'Win32_OperatingSystem'
      $systemDrive = ''
      if ($os.Items.Count -gt 0) { $systemDrive = [string]$os.Items[0].SystemDrive }
      $logical = Get-DotfilesCimInstances -ClassName 'Win32_PerfRawData_PerfDisk_LogicalDisk' -TargetName $systemDrive
      $systemVolume = $logical.TargetItem
      if ($null -eq $systemVolume) { $systemVolume = @($logical.Items | Where-Object { [string]$_.Name -eq $systemDrive } | Select-Object -First 1) }
      if ($physical.Status -ne 'ok' -and ($systemVolume -is [array] -and $systemVolume.Count -eq 0)) {
        return @{ source = 'disk'; status = 'unavailable'; error = 'counter-unavailable'; metrics = @{} }
      }
      if ($physicalInstance -is [array]) { $physicalInstance = if ($physicalInstance.Count -gt 0) { $physicalInstance[0] } else { $null } }
      if ($systemVolume -is [array]) { $systemVolume = if ($systemVolume.Count -gt 0) { $systemVolume[0] } else { $null } }
      $physicalMetrics = $null
      if ($null -ne $physicalInstance) {
        $physicalMetrics = @{
          readBytesCounter = Get-DotfilesPropertyValue $physicalInstance 'DiskReadBytesPerSec'
          writeBytesCounter = Get-DotfilesPropertyValue $physicalInstance 'DiskWriteBytesPerSec'
          timestampPerfTime = Get-DotfilesPropertyValue $physicalInstance 'Timestamp_PerfTime'
          frequencyPerfTime = Get-DotfilesPropertyValue $physicalInstance 'Frequency_PerfTime'
          queueLength = Get-DotfilesPropertyValue $physicalInstance 'CurrentDiskQueueLength'
        }
      }
      $systemMetrics = $null
      if ($null -ne $systemVolume) {
        $systemMetrics = @{
          readBytesCounter = Get-DotfilesPropertyValue $systemVolume 'DiskReadBytesPerSec'
          writeBytesCounter = Get-DotfilesPropertyValue $systemVolume 'DiskWriteBytesPerSec'
          timestampPerfTime = Get-DotfilesPropertyValue $systemVolume 'Timestamp_PerfTime'
          frequencyPerfTime = Get-DotfilesPropertyValue $systemVolume 'Frequency_PerfTime'
          instanceAlias = if ([string]::IsNullOrWhiteSpace($AliasSalt)) { 'system-volume' } else { Get-DotfilesPerRunAlias -Identity $systemDrive -Salt $AliasSalt -Prefix 'volume' }
        }
      }
      if ($physicalMetrics -or $systemMetrics) {
        $sourceStatus = if ($physicalMetrics -and $systemMetrics) { 'ok' } else { 'partial' }
        return @{ source = 'disk'; status = $sourceStatus; metrics = @{ physicalTotal = $physicalMetrics; systemVolume = $systemMetrics } }
      }
      return @{ source = 'disk'; status = 'unavailable'; error = 'counter-unavailable'; metrics = @{} }
    }
    'hyperv' {
      $query = Get-DotfilesCimInstances -ClassName 'Win32_PerfRawData_Counters_HyperVVirtualStorageDevice'
      if ($query.Status -ne 'ok') {
        return @{ source = 'hyperv'; status = 'unavailable'; error = $query.Error; metrics = @{} }
      }
      $devices = New-Object System.Collections.ArrayList
      $index = 0
      foreach ($item in @($query.Items | Select-Object -First 16)) {
        $index++
        [void]$devices.Add(@{
          alias = if ([string]::IsNullOrWhiteSpace($AliasSalt)) { ('virtual-device-{0:D2}' -f $index) } else { Get-DotfilesPerRunAlias -Identity ([string]$item.Name) -Salt $AliasSalt -Prefix 'virtual-device' }
          readBytesCounter = Get-DotfilesPropertyValue $item 'ReadBytesPersec'
          writeBytesCounter = Get-DotfilesPropertyValue $item 'WriteBytesPersec'
          readOperationsCounter = Get-DotfilesPropertyValue $item 'ReadOperationsPerSec'
          writeOperationsCounter = Get-DotfilesPropertyValue $item 'WriteOperationsPerSec'
          timestampPerfTime = Get-DotfilesPropertyValue $item 'Timestamp_PerfTime'
          frequencyPerfTime = Get-DotfilesPropertyValue $item 'Frequency_PerfTime'
        })
      }
      return @{ source = 'hyperv'; status = 'ok'; metrics = @{ virtualStorage = @($devices.ToArray()); overflowCount = [int]$query.OverflowCount } }
    }
  }
}

function Start-DotfilesHostWorker {
  param([Parameter(Mandatory = $true)][string]$Source)

  $exe = Get-DotfilesPowerShellExecutable
  $scriptPath = $script:CollectorScriptPath
      $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $scriptPath, '-Worker', '-WorkerSource', $Source, '-AliasSalt', $script:AliasSalt)
  return Start-DotfilesOwnedProcess -FileName $exe -Arguments $arguments -Source $Source
}

function Test-DotfilesProcessOutputCompleted {
  param([Parameter(Mandatory = $true)]$Owned)

  $watch = [Diagnostics.Stopwatch]::StartNew()
  try {
    foreach ($task in @($Owned.StdoutTask, $Owned.StderrTask)) {
      if ($null -eq $task) { return $false }
      if ($task.IsFaulted -or $task.IsCanceled) { return $false }
      if ($task.IsCompleted) { continue }
      $remaining = [Math]::Max(0, $script:OutputDrainTimeoutMilliseconds - [int][Math]::Ceiling($watch.Elapsed.TotalMilliseconds))
      try {
        if (-not $task.Wait($remaining)) { return $false }
      }
      catch [AggregateException] {
        # A faulted or cancelled task has not proved that its output pipe drained.
      }
      if ($task.IsFaulted -or $task.IsCanceled) { return $false }
      if (-not $task.IsCompleted) { return $false }
    }
    return $true
  }
  finally { $watch.Stop() }
}

function New-DotfilesUnverifiedProcessCleanup {
  param([Parameter(Mandatory = $true)]$Owned)

  return @{
    Exited = $false
    CleanupUnverified = $true
    Entries = @(@{
        source = $Owned.Source
        processId = $Owned.ProcessId
        startTimeTicks = $Owned.StartTimeTicks
        cleanupUnverified = $true
      })
  }
}

function Get-DotfilesWorkerResult {
  param([Parameter(Mandatory = $true)]$Owned)

  try {
    if (-not $Owned.Process.HasExited) { return $null }
    if (-not (Test-DotfilesProcessOutputCompleted -Owned $Owned)) {
      return @{ source = $Owned.Source; status = 'unavailable'; error = 'worker-output-invalid'; metrics = @{}; Cleanup = (New-DotfilesUnverifiedProcessCleanup -Owned $Owned) }
    }
    $capture = $Owned.StdoutTask.GetAwaiter().GetResult()
    # Drain but never retain or display provider diagnostics from stderr.
    $null = $Owned.StderrTask.GetAwaiter().GetResult()
    $stdout = $capture.Text
    if ($capture.Truncated -or [string]::IsNullOrWhiteSpace($stdout)) {
      return @{ source = $Owned.Source; status = 'unavailable'; error = 'worker-output-invalid'; metrics = @{} }
    }
    return (ConvertFrom-Json -InputObject $stdout -ErrorAction Stop)
  }
  catch {
    return @{ source = $Owned.Source; status = 'unavailable'; error = 'worker-failed'; metrics = @{} }
  }
}

function Start-DotfilesCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$StandardInputText
  )
  return Start-DotfilesOwnedProcess -FileName $Executable -Arguments $Arguments -Source $Source -StandardInputText $StandardInputText
}

function Get-DotfilesWslExecutable {
  $command = Get-Command 'wsl.exe' -ErrorAction SilentlyContinue
  if ($null -eq $command) { return $null }
  return $command.Source
}

function Invoke-DotfilesWslPreflight {
  param([Parameter(Mandatory = $true)][string]$Distribution)

  $wsl = Get-DotfilesWslExecutable
  if ($null -eq $wsl) { return @{ Status = 'unavailable'; Error = 'wsl-client-unavailable' } }
  $owned = $null
  try {
    $owned = Start-DotfilesCommand -Executable $wsl -Arguments @('--list', '--running', '--quiet') -Source 'guest'
    if (-not $owned.Process.WaitForExit(1000)) {
      $stopped = Stop-DotfilesOwnedProcess -Owned $owned -GraceMilliseconds $script:CleanupGraceMilliseconds
      return @{ Status = 'timeout'; Error = 'preflight-timeout'; Cleanup = $stopped }
    }
    if (-not (Test-DotfilesProcessOutputCompleted -Owned $owned)) {
      return @{ Status = 'unavailable'; Error = 'preflight-output-invalid'; Cleanup = (New-DotfilesUnverifiedProcessCleanup -Owned $owned) }
    }
    $capture = $owned.StdoutTask.GetAwaiter().GetResult()
    $null = $owned.StderrTask.GetAwaiter().GetResult()
    $stdout = $capture.Text
    if ($capture.Truncated -or [string]::IsNullOrWhiteSpace($stdout) -or $stdout.Length -gt 32768) {
      return @{ Status = 'unavailable'; Error = 'preflight-output-invalid' }
    }
    if ($owned.Process.ExitCode -ne 0) {
      return @{ Status = 'unavailable'; Error = 'preflight-failed' }
    }
    $stdout = $stdout.Replace([string][char]0, '')
    $names = @($stdout -split "`r?`n" | ForEach-Object { $_.Trim().Trim([char]0) } | Where-Object { $_ })
    foreach ($name in $names) {
      if ([string]::Equals($name, $Distribution, [StringComparison]::OrdinalIgnoreCase)) {
        return @{ Status = 'running'; Error = $null }
      }
    }
    return @{ Status = 'not-running'; Error = 'distro-not-running' }
  }
  catch {
    return @{ Status = 'unavailable'; Error = 'preflight-failed' }
  }
  finally {
    if ($null -ne $owned -and $null -ne $owned.Process) { $owned.Process.Dispose() }
  }
}

function Start-DotfilesGuestProbe {
  param(
    [Parameter(Mandatory = $true)][string]$Distribution,
    [int]$IntervalSeconds = 0,
    [string]$PreviousCounters
  )

  if ($Distribution.Length -gt 128 -or $Distribution -match '[\x00-\x1f\x7f]') {
    return @{ Status = 'unavailable'; Error = 'distro-argument-invalid'; Process = $null }
  }
  $preflight = Invoke-DotfilesWslPreflight -Distribution $Distribution
  if ($preflight.Status -ne 'running') {
    return @{ Status = $preflight.Status; Error = $preflight.Error; Process = $null; Cleanup = $preflight.Cleanup }
  }
  # This executes a noninteractive command only after an exact running-state
  # preflight. The WSL client is the owned process; cleanup never invokes
  # --terminate or --shutdown and never targets the VM.
  $wsl = Get-DotfilesWslExecutable
  if ($IntervalSeconds -lt 0 -or $IntervalSeconds -gt 600) {
    return @{ Status = 'unavailable'; Error = 'guest-interval-invalid'; Process = $null }
  }
  $shellCommand = 'exec "$HOME/.local/bin/wsl-incident-guest-snapshot" --previous-stdin "$@"'
  $arguments = @('--distribution', $Distribution, '--exec', '/bin/sh', '-c', $shellCommand, 'dotfiles-guest')
  if ($IntervalSeconds -gt 0) { $arguments += @('--interval-seconds', [string]$IntervalSeconds) }
  try {
    $owned = Start-DotfilesCommand -Executable $wsl -Arguments $arguments -Source 'guest' -StandardInputText $PreviousCounters
    return @{ Status = 'pending'; Error = $null; Process = $owned }
  }
  catch {
    $mayRemain = $false
    $cleanupEntries = @()
    try { $mayRemain = [bool]$_.Exception.Data['DotfilesOwnedProcessMayRemain'] } catch { }
    try {
      $storedCleanupEntries = $_.Exception.Data['DotfilesOwnedProcessCleanupEntries']
      if ($null -ne $storedCleanupEntries) { $cleanupEntries = @($storedCleanupEntries) }
    }
    catch { }
    $cleanup = if ($mayRemain) { @{ Exited = $false; CleanupUnverified = $true; Entries = $cleanupEntries } } else { $null }
    return @{ Status = 'unavailable'; Error = 'guest-start-failed'; Process = $null; Cleanup = $cleanup }
  }
}

function Get-DotfilesGuestResult {
  param([Parameter(Mandatory = $true)]$Owned)

  try {
    if (-not $Owned.Process.HasExited) { return $null }
    if (-not (Test-DotfilesProcessOutputCompleted -Owned $Owned)) {
      return @{ Status = 'unavailable'; Error = 'guest-output-invalid'; Data = $null; Cleanup = (New-DotfilesUnverifiedProcessCleanup -Owned $Owned) }
    }
    $capture = $Owned.StdoutTask.GetAwaiter().GetResult()
    $null = $Owned.StderrTask.GetAwaiter().GetResult()
    $stdout = $capture.Text
    if ($capture.Truncated -or [string]::IsNullOrWhiteSpace($stdout) -or $stdout.Length -gt 32768) {
      return @{ Status = 'unavailable'; Error = 'guest-output-invalid'; Data = $null }
    }
    $data = ConvertFrom-Json -InputObject $stdout -ErrorAction Stop
    $safe = ConvertTo-DotfilesSafeGuestSnapshot -Data $data
    if (-not $safe.Valid) {
      return @{ Status = 'unavailable'; Error = 'guest-output-invalid'; Data = $null }
    }
    return @{ Status = $safe.Status; Error = $safe.Error; Data = $safe.Data }
  }
  catch {
    return @{ Status = 'unavailable'; Error = 'guest-failed'; Data = $null }
  }
}

function ConvertTo-DotfilesSafeGuestNumber {
  param($Value, [switch]$Integer)
  if ($null -eq $Value) { return $null }
  try {
    if ($Integer) {
      $number = [decimal]$Value
      if ($number -lt 0 -or $number -gt [long]::MaxValue -or [decimal]::Truncate($number) -ne $number) { return $null }
      return [long]$number
    }
    $number = [double]$Value
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0) { return $null }
    return $number
  }
  catch { return $null }
}

function ConvertTo-DotfilesSafeGuestSnapshot {
  param([Parameter(Mandatory = $true)]$Data)

  if ([int]$Data.schemaVersion -ne 1 -or [string]$Data.status -notin @('ok', 'partial', 'unavailable')) {
    return @{ Valid = $false; Status = 'unavailable'; Error = 'guest-output-invalid'; Data = $null }
  }
  $safeErrors = @('procfs-unavailable', 'required-command-missing', 'memory-data-unavailable')
  $safeError = if ([string]$Data.error -in $safeErrors) { [string]$Data.error } else { $null }
  $statuses = @('ok', 'partial', 'unavailable')
  $memoryStatus = if ([string]$Data.memory.status -in $statuses) { [string]$Data.memory.status } else { 'unavailable' }
  $swapStatus = if ([string]$Data.swap.status -in $statuses) { [string]$Data.swap.status } else { 'unavailable' }
  $psiStatus = if ([string]$Data.psi.status -in $statuses) { [string]$Data.psi.status } else { 'unavailable' }

  $memory = [ordered]@{
    status = $memoryStatus
    unit = 'kB'
    total = ConvertTo-DotfilesSafeGuestNumber $Data.memory.total -Integer
    available = ConvertTo-DotfilesSafeGuestNumber $Data.memory.available -Integer
  }
  $swap = [ordered]@{
    status = $swapStatus
    unit = 'kB'
    total = ConvertTo-DotfilesSafeGuestNumber $Data.swap.total -Integer
    used = ConvertTo-DotfilesSafeGuestNumber $Data.swap.used -Integer
  }
  $psi = [ordered]@{ status = $psiStatus; some = $null; full = $null }
  foreach ($side in @('some', 'full')) {
    $inputSide = $Data.psi.$side
    if ($null -eq $inputSide) { continue }
    $psi[$side] = [ordered]@{
      avg10 = ConvertTo-DotfilesSafeGuestNumber $inputSide.avg10
      avg60 = ConvertTo-DotfilesSafeGuestNumber $inputSide.avg60
      avg300 = ConvertTo-DotfilesSafeGuestNumber $inputSide.avg300
      totalUsec = ConvertTo-DotfilesSafeGuestNumber $inputSide.totalUsec -Integer
    }
  }
  $counterNames = @('pgscan_kswapd', 'pgscan_direct', 'pgsteal_kswapd', 'pgsteal_direct', 'workingset_refault', 'workingset_refault_anon', 'workingset_refault_file', 'pswpin', 'pswpout', 'pgfault', 'pgmajfault')
  $counters = [ordered]@{}
  $deltas = [ordered]@{}
  foreach ($name in $counterNames) {
    $counters[$name] = ConvertTo-DotfilesSafeGuestNumber $Data.counters.$name -Integer
    $delta = $Data.deltas.$name
    $deltaStatus = if ([string]$delta.status -in @('ok', 'unavailable')) { [string]$delta.status } else { 'unavailable' }
    $deltaValue = ConvertTo-DotfilesSafeGuestNumber $delta.value -Integer
    $rateValue = ConvertTo-DotfilesSafeGuestNumber $delta.perSecond
    if ($deltaStatus -ne 'ok' -or $null -eq $deltaValue -or $null -eq $rateValue) {
      $deltaStatus = 'unavailable'
      $deltaValue = $null
      $rateValue = $null
    }
    $deltas[$name] = [ordered]@{ status = $deltaStatus; value = $deltaValue; perSecond = $rateValue }
  }
  $safeData = [ordered]@{
    schemaVersion = 1
    status = [string]$Data.status
    error = $safeError
    memory = $memory
    swap = $swap
    psi = $psi
    counters = $counters
    deltas = $deltas
  }
  $normalized = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $safeData -Compress -Depth 8) -ErrorAction Stop
  return @{ Valid = $true; Status = [string]$Data.status; Error = $safeError; Data = $normalized }
}

function Update-DotfilesGuestProcess {
  param([Parameter(Mandatory = $true)]$Owned)

  try {
    if ($Owned.Process.HasExited) {
      $result = Get-DotfilesGuestResult -Owned $Owned
      $inhibitions = @()
      if ($result.Cleanup -and -not $result.Cleanup.Exited) { $inhibitions = @($result.Cleanup.Entries) }
      return @{ Done = $true; Record = @{ status = $result.Status; error = $result.Error; metrics = $result.Data }; Data = $result.Data; Suppressed = ($inhibitions.Count -gt 0); Inhibitions = $inhibitions }
    }
  }
  catch {
    $cleanup = Stop-DotfilesOwnedProcess -Owned $Owned -GraceMilliseconds $script:CleanupGraceMilliseconds
    return @{ Done = $true; Record = @{ status = 'unavailable'; error = 'guest-failed'; metrics = @{} }; Data = $null; Suppressed = $true; Inhibitions = @($cleanup.Entries) }
  }
  if (((Get-DotfilesMonotonicMilliseconds) - $Owned.StartedAtMilliseconds) -lt $script:GuestTimeoutMilliseconds) {
    return @{ Done = $false; Record = @{ status = 'pending'; error = $null; metrics = @{} }; Data = $null; Suppressed = $false; Inhibitions = @() }
  }
  $cleanup = Stop-DotfilesOwnedProcess -Owned $Owned -GraceMilliseconds $script:CleanupGraceMilliseconds
  return @{ Done = $true; Record = @{ status = 'timeout'; error = 'timeout'; metrics = @{} }; Data = $null; Suppressed = $true; Inhibitions = @($cleanup.Entries) }
}

function Get-DotfilesGuestBaseline {
  param($Snapshot)
  $pairs = New-Object System.Collections.ArrayList
  if ($null -eq $Snapshot -or $null -eq $Snapshot.counters) { return '' }
  foreach ($property in $Snapshot.counters.PSObject.Properties) {
    $value = [string]$property.Value
    if ($value -match '^[0-9]+$') { [void]$pairs.Add("$($property.Name)`t$value`n") }
  }
  return ($pairs -join '')
}

function Test-DotfilesGuestBaselineAvailable {
  param($Snapshot)
  if ($null -eq $Snapshot -or $Snapshot.status -notin @('ok', 'partial')) { return $false }
  return -not [string]::IsNullOrWhiteSpace((Get-DotfilesGuestBaseline -Snapshot $Snapshot))
}

function Get-DotfilesGuestIntervalSeconds {
  param([object]$PreviousSampleMilliseconds, [double]$NowMilliseconds)
  if ($null -eq $PreviousSampleMilliseconds) { return $null }
  $elapsedMilliseconds = $NowMilliseconds - [double]$PreviousSampleMilliseconds
  if ($elapsedMilliseconds -gt 600000) { return $null }
  $elapsedSeconds = [Math]::Floor($elapsedMilliseconds / 1000.0)
  return [int][Math]::Max(1, $elapsedSeconds)
}

function Get-DotfilesHostSamplingDeadline {
  param(
    [double]$DurationDeadlineMilliseconds,
    [double]$WaitStartedMilliseconds,
    [int]$IntervalSeconds
  )
  $waitBudget = [Math]::Min($script:WorkerTimeoutMilliseconds, [Math]::Max(250, ($IntervalSeconds * 1000) - 500))
  return [Math]::Min($DurationDeadlineMilliseconds, $WaitStartedMilliseconds + $waitBudget)
}

function Get-DotfilesCpuMetrics {
  param($Snapshot, $Previous)
  if ($null -eq $Snapshot -or $Snapshot.status -ne 'ok' -or $null -eq $Snapshot.metrics) {
    $failure = Get-DotfilesSourceFailure -Snapshot $Snapshot
    return @{ status = $failure.status; error = $failure.error; totalPercent = $null; privilegedPercent = $null }
  }
  $metrics = $Snapshot.metrics
  if ($null -eq $metrics.percentProcessorTime -or $null -eq $metrics.percentPrivilegedTime -or $null -eq $metrics.timestampSys100Ns) {
    return @{ status = 'unavailable'; error = 'counter-unavailable'; totalPercent = $null; privilegedPercent = $null }
  }
  if ($null -eq $Previous -or $null -eq $metrics.timestampSys100Ns -or $null -eq $Previous.metrics.timestampSys100Ns) {
    return @{ status = 'unavailable'; error = 'first-sample'; totalPercent = $null; privilegedPercent = $null }
  }
  $timeDelta = [double]$metrics.timestampSys100Ns - [double]$Previous.metrics.timestampSys100Ns
  $totalDelta = [double]$metrics.percentProcessorTime - [double]$Previous.metrics.percentProcessorTime
  $privilegedDelta = [double]$metrics.percentPrivilegedTime - [double]$Previous.metrics.percentPrivilegedTime
  if ($timeDelta -le 0 -or $totalDelta -lt 0 -or $privilegedDelta -lt 0) {
    return @{ status = 'unavailable'; error = 'counter-reset'; totalPercent = $null; privilegedPercent = $null }
  }
  return @{
    status = 'ok'
    error = $null
    totalPercent = [Math]::Min(100.0, [Math]::Max(0.0, 100.0 * (1.0 - ($totalDelta / $timeDelta))))
    privilegedPercent = [Math]::Min(100.0, [Math]::Max(0.0, 100.0 * $privilegedDelta / $timeDelta))
  }
}

function Get-DotfilesRawCounterRate {
  param(
    $CurrentValue,
    $PreviousValue,
    $CurrentTimestamp,
    $PreviousTimestamp,
    $CurrentFrequency,
    $PreviousFrequency
  )
  if ($null -eq $CurrentValue -or $null -eq $PreviousValue -or $null -eq $CurrentTimestamp -or $null -eq $PreviousTimestamp -or $null -eq $CurrentFrequency -or $null -eq $PreviousFrequency) {
    return @{ status = 'unavailable'; error = 'first-sample'; value = $null }
  }
  $counterDelta = [double]$CurrentValue - [double]$PreviousValue
  $timeDelta = [double]$CurrentTimestamp - [double]$PreviousTimestamp
  if ($timeDelta -le 0 -or $counterDelta -lt 0 -or [double]$CurrentFrequency -ne [double]$PreviousFrequency) {
    return @{ status = 'unavailable'; error = 'counter-reset'; value = $null }
  }
  $rate = $counterDelta * [double]$CurrentFrequency / $timeDelta
  if ([double]::IsNaN($rate) -or [double]::IsInfinity($rate) -or $rate -lt 0) {
    return @{ status = 'unavailable'; error = 'counter-reset'; value = $null }
  }
  return @{ status = 'ok'; error = $null; value = $rate }
}

function Get-DotfilesSourceFailure {
  param($Snapshot)
  $status = if ($Snapshot -and $Snapshot.status -eq 'timeout') { 'timeout' } else { 'unavailable' }
  $failureReason = [string]$Snapshot.error
  if ($failureReason -notin @('access-denied', 'provider-unavailable', 'counter-unavailable', 'timeout', 'worker-failed', 'worker-output-invalid', 'worker-start-failed', 'inhibited', 'first-sample', 'counter-reset')) {
    $failureReason = if ($status -eq 'timeout') { 'timeout' } else { 'provider-unavailable' }
  }
  return @{ status = $status; error = $failureReason }
}

function Get-DotfilesMemoryMetrics {
  param($Snapshot, $Previous)
  if ($null -eq $Snapshot -or $Snapshot.status -notin @('ok', 'partial') -or $null -eq $Snapshot.metrics) {
    $failure = Get-DotfilesSourceFailure -Snapshot $Snapshot
    return @{ status = $failure.status; error = $failure.error; metrics = @{} }
  }
  $raw = $Snapshot.metrics
  $previousRaw = if ($Previous) { $Previous.metrics } else { $null }
  $rates = [ordered]@{}
  foreach ($counter in @(
    @{ Name = 'pageReadsPerSecond'; Raw = 'pageReadsCounter' },
    @{ Name = 'pagesInputPerSecond'; Raw = 'pagesInputCounter' },
    @{ Name = 'pageWritesPerSecond'; Raw = 'pageWritesCounter' },
    @{ Name = 'pagesOutputPerSecond'; Raw = 'pagesOutputCounter' }
  )) {
    $prior = $null
    if ($previousRaw) { $prior = $previousRaw.($counter.Raw) }
    $rate = Get-DotfilesRawCounterRate -CurrentValue $raw.($counter.Raw) -PreviousValue $prior -CurrentTimestamp $raw.timestampPerfTime -PreviousTimestamp $(if ($previousRaw) { $previousRaw.timestampPerfTime } else { $null }) -CurrentFrequency $raw.frequencyPerfTime -PreviousFrequency $(if ($previousRaw) { $previousRaw.frequencyPerfTime } else { $null })
    $rates[$counter.Name] = $rate
  }
  $rateStatus = 'ok'
  if (@($rates.Values | Where-Object { $_.status -ne 'ok' }).Count -gt 0) { $rateStatus = 'partial' }
  $rateError = if (@($rates.Values | Where-Object { $_.error -eq 'counter-reset' }).Count -gt 0) { 'counter-reset' } else { 'first-sample' }
  return @{
    status = if ($Snapshot.status -eq 'partial' -or $rateStatus -ne 'ok') { 'partial' } else { 'ok' }
    error = if ($rateStatus -ne 'ok') { $rateError } else { $null }
    metrics = @{
      availableBytes = $raw.availableBytes
      committedBytes = $raw.committedBytes
      commitLimitBytes = $raw.commitLimitBytes
      pageFilePercentUsage = $raw.pageFilePercentUsage
      pagingRates = @{ status = $rateStatus; counters = $rates }
    }
  }
}

function Get-DotfilesDiskMetrics {
  param($Snapshot, $Previous)
  if ($null -eq $Snapshot -or $Snapshot.status -notin @('ok', 'partial') -or $null -eq $Snapshot.metrics) {
    $failure = Get-DotfilesSourceFailure -Snapshot $Snapshot
    return @{ status = $failure.status; error = $failure.error; metrics = @{} }
  }
  $current = $Snapshot.metrics
  $previousMetrics = if ($Previous) { $Previous.metrics } else { $null }
  $disks = [ordered]@{}
  foreach ($name in @('physicalTotal', 'systemVolume')) {
    $device = $current.$name
    if ($null -eq $device) {
      $disks[$name] = @{ status = 'unavailable'; error = 'counter-unavailable'; readBytesPerSecond = $null; writeBytesPerSecond = $null; queueLength = $null }
      continue
    }
    $prior = if ($previousMetrics) { $previousMetrics.$name } else { $null }
    $identityChanged = $false
    if ($name -eq 'systemVolume' -and $null -ne $prior -and [string]$prior.instanceAlias -ne [string]$device.instanceAlias) { $identityChanged = $true }
    if ($identityChanged) { $prior = $null }
    $read = Get-DotfilesRawCounterRate -CurrentValue $device.readBytesCounter -PreviousValue $(if ($prior) { $prior.readBytesCounter } else { $null }) -CurrentTimestamp $device.timestampPerfTime -PreviousTimestamp $(if ($prior) { $prior.timestampPerfTime } else { $null }) -CurrentFrequency $device.frequencyPerfTime -PreviousFrequency $(if ($prior) { $prior.frequencyPerfTime } else { $null })
    $write = Get-DotfilesRawCounterRate -CurrentValue $device.writeBytesCounter -PreviousValue $(if ($prior) { $prior.writeBytesCounter } else { $null }) -CurrentTimestamp $device.timestampPerfTime -PreviousTimestamp $(if ($prior) { $prior.timestampPerfTime } else { $null }) -CurrentFrequency $device.frequencyPerfTime -PreviousFrequency $(if ($prior) { $prior.frequencyPerfTime } else { $null })
    $status = if ($read.status -eq 'ok' -and $write.status -eq 'ok' -and -not $identityChanged) { 'ok' } else { 'unavailable' }
    $reason = if ($identityChanged -or $read.error -eq 'counter-reset' -or $write.error -eq 'counter-reset') { 'counter-reset' } elseif ($status -ne 'ok') { 'first-sample' } else { $null }
    $disks[$name] = @{
      status = $status
      error = $reason
      alias = if ($name -eq 'systemVolume') { $device.instanceAlias } else { 'physical-total' }
      readBytesPerSecond = $read.value
      writeBytesPerSecond = $write.value
      queueLength = $device.queueLength
    }
  }
  $overall = if (@($disks.Values | Where-Object { $_.status -ne 'ok' }).Count -eq 0) { 'ok' } else { 'partial' }
  $error = $null
  if ($overall -eq 'partial') {
    if (@($disks.Values | Where-Object { $_.error -eq 'counter-unavailable' }).Count -gt 0) { $error = 'counter-unavailable' }
    elseif (@($disks.Values | Where-Object { $_.error -eq 'counter-reset' }).Count -gt 0) { $error = 'counter-reset' }
    else { $error = 'first-sample' }
  }
  return @{ status = $overall; error = $error; metrics = $disks }
}

function Get-DotfilesHypervMetrics {
  param($Snapshot, $Previous)
  if ($null -eq $Snapshot -or $Snapshot.status -ne 'ok' -or $null -eq $Snapshot.metrics.virtualStorage) {
    $failure = Get-DotfilesSourceFailure -Snapshot $Snapshot
    return @{ status = $failure.status; error = $failure.error; metrics = @{} }
  }
  $previousDevices = @{}
  if ($Previous -and $Previous.metrics.virtualStorage) {
    foreach ($device in $Previous.metrics.virtualStorage) { $previousDevices[[string]$device.alias] = $device }
  }
  $devices = New-Object System.Collections.ArrayList
  foreach ($device in $Snapshot.metrics.virtualStorage) {
    $prior = $previousDevices[[string]$device.alias]
    if ($null -eq $prior) {
      [void]$devices.Add(@{ alias = $device.alias; status = 'unavailable'; error = 'first-sample'; readBytesPerSecond = $null; writeBytesPerSecond = $null; readOperationsPerSecond = $null; writeOperationsPerSecond = $null })
    }
    else {
      $rates = @{
        readBytesPerSecond = Get-DotfilesRawCounterRate -CurrentValue $device.readBytesCounter -PreviousValue $prior.readBytesCounter -CurrentTimestamp $device.timestampPerfTime -PreviousTimestamp $prior.timestampPerfTime -CurrentFrequency $device.frequencyPerfTime -PreviousFrequency $prior.frequencyPerfTime
        writeBytesPerSecond = Get-DotfilesRawCounterRate -CurrentValue $device.writeBytesCounter -PreviousValue $prior.writeBytesCounter -CurrentTimestamp $device.timestampPerfTime -PreviousTimestamp $prior.timestampPerfTime -CurrentFrequency $device.frequencyPerfTime -PreviousFrequency $prior.frequencyPerfTime
        readOperationsPerSecond = Get-DotfilesRawCounterRate -CurrentValue $device.readOperationsCounter -PreviousValue $prior.readOperationsCounter -CurrentTimestamp $device.timestampPerfTime -PreviousTimestamp $prior.timestampPerfTime -CurrentFrequency $device.frequencyPerfTime -PreviousFrequency $prior.frequencyPerfTime
        writeOperationsPerSecond = Get-DotfilesRawCounterRate -CurrentValue $device.writeOperationsCounter -PreviousValue $prior.writeOperationsCounter -CurrentTimestamp $device.timestampPerfTime -PreviousTimestamp $prior.timestampPerfTime -CurrentFrequency $device.frequencyPerfTime -PreviousFrequency $prior.frequencyPerfTime
      }
      $status = if (@($rates.Values | Where-Object { $_.status -eq 'ok' }).Count -eq $rates.Count) { 'ok' } else { 'unavailable' }
      $deviceError = if ($status -eq 'ok') { $null } elseif (@($rates.Values | Where-Object { $_.error -eq 'counter-reset' }).Count -gt 0) { 'counter-reset' } else { 'first-sample' }
      [void]$devices.Add(@{
        alias = $device.alias
        status = $status
        error = $deviceError
        readBytesPerSecond = $rates.readBytesPerSecond.value
        writeBytesPerSecond = $rates.writeBytesPerSecond.value
        readOperationsPerSecond = $rates.readOperationsPerSecond.value
        writeOperationsPerSecond = $rates.writeOperationsPerSecond.value
      })
    }
  }
  $status = if (@($devices | Where-Object { $_.status -eq 'ok' }).Count -gt 0) { 'ok' } else { 'partial' }
  return @{ status = $status; error = if ($status -eq 'partial') { 'first-sample' } else { $null }; metrics = @{ virtualStorage = @($devices.ToArray()); overflowCount = $Snapshot.metrics.overflowCount } }
}

function Get-DotfilesCollectorLogFiles {
  param([Parameter(Mandatory = $true)][string]$Directory)
  $files = @(Get-ChildItem -LiteralPath $Directory -File -Force -ErrorAction Stop | Where-Object { $_.Name -match '^wsl-capture-[0-9TZ-]+-[a-f0-9]{32}(?:-[0-9]{4})?\.jsonl(?:\.tmp|\.partial)?$' })
  foreach ($file in $files) {
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'log-reparse-point' }
    $safe = Get-DotfilesSafePath -Path $file.FullName -MustExist
    if ([IO.Path]::GetDirectoryName($safe) -ne [IO.Path]::GetFullPath($Directory)) { throw 'log-path-escape' }
  }
  return $files
}

function Repair-DotfilesPartialLogs {
  param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][long]$MaximumBytes
  )
  $files = @(Get-DotfilesCollectorLogFiles -Directory $Directory | Sort-Object LastWriteTimeUtc)
  $total = 0L
  foreach ($file in $files) { $total += [long]$file.Length }
  foreach ($file in $files) {
    if ($total -le $MaximumBytes) { break }
    $safe = Get-DotfilesSafePath -Path $file.FullName -MustExist
    [IO.File]::Delete($safe)
    $total -= [long]$file.Length
  }
  foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file.FullName)) { continue }
    if ($file.Length -gt $MaximumBytes) {
      $safe = Get-DotfilesSafePath -Path $file.FullName -MustExist
      [IO.File]::Delete($safe)
      continue
    }
    $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
      if ($stream.Length -eq 0) { continue }
      $lastByte = New-Object byte[] 1
      $stream.Position = $stream.Length - 1
      if ($stream.Read($lastByte, 0, 1) -eq 1 -and $lastByte[0] -eq 10) { continue }
      $buffer = New-Object byte[] 4096
      $scanPosition = $stream.Length
      $lastNewline = -1L
      while ($scanPosition -gt 0) {
        $count = [int][Math]::Min($buffer.Length, $scanPosition)
        $scanPosition -= $count
        $stream.Position = $scanPosition
        $read = $stream.Read($buffer, 0, $count)
        for ($index = $read - 1; $index -ge 0; $index--) {
          if ($buffer[$index] -eq 10) {
            $lastNewline = $scanPosition + $index
            break
          }
        }
        if ($lastNewline -ge 0) { break }
      }
      $stream.SetLength([Math]::Max(0, $lastNewline + 1))
    }
    finally { $stream.Dispose() }
  }
}

function Get-DotfilesNextLogSegmentPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  $name = [IO.Path]::GetFileName($Path)
  if ($name -notmatch '^(?<stem>wsl-capture-[0-9TZ-]+-[a-f0-9]{32})(?:-(?<segment>[0-9]{4}))?\.jsonl$') {
    throw 'log-path-invalid'
  }
  $segment = 0
  if ($matches.segment) { $segment = [int]$matches.segment }
  if ($segment -ge 9999) { throw 'log-segment-limit' }
  return (Join-Path ([IO.Path]::GetDirectoryName($Path)) ('{0}-{1:D4}.jsonl' -f $matches.stem, ($segment + 1)))
}

function Write-DotfilesLogRecord {
  param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][long]$MaximumBytes,
    [Parameter(Mandatory = $true)][string]$RunId
  )

  $json = ConvertTo-Json -InputObject $Record -Compress -Depth 12
  $bytes = $script:Utf8NoBom.GetBytes($json + "`n")
  if ($bytes.Length -gt $script:RecordLimitBytes) {
    $overflow = [ordered]@{
      schemaVersion = 1
      recordType = 'host-sample'
      runId = $RunId
      sampleTimeUtc = [string]$Record.sampleTimeUtc
      elapsedSeconds = $Record.elapsedSeconds
      status = 'overflow'
      error = 'record-size-limit'
    }
    $bytes = $script:Utf8NoBom.GetBytes((ConvertTo-Json -InputObject $overflow -Compress) + "`n")
  }

  $segmentLimit = [Math]::Min($MaximumBytes, [Math]::Max([long]$script:RecordLimitBytes, [Math]::Min(8388608L, [long][Math]::Floor($MaximumBytes / 4.0))))
  $currentLength = 0L
  if (Test-Path -LiteralPath $Path) { $currentLength = [long](Get-Item -LiteralPath $Path -Force).Length }
  if ($currentLength -gt 0 -and ($currentLength + $bytes.Length) -gt $segmentLimit) {
    try { $Path = Get-DotfilesNextLogSegmentPath -Path $Path }
    catch {
      $errorCode = if ($_.Exception.Message -eq 'log-segment-limit') { 'log-segment-limit' } else { 'log-write-failed' }
      return @{ Written = $false; Error = $errorCode; Bytes = $currentLength; Path = $Path }
    }
  }

  $files = @(Get-DotfilesCollectorLogFiles -Directory $Directory | Sort-Object LastWriteTimeUtc)
  $total = 0L
  foreach ($file in $files) { $total += [long]$file.Length }
  foreach ($file in $files) {
    if (($total + $bytes.Length) -le $MaximumBytes) { break }
    if ($file.FullName -eq $Path) { continue }
    $safe = Get-DotfilesSafePath -Path $file.FullName -MustExist
    [IO.File]::Delete($safe)
    $total -= [long]$file.Length
  }
  if (($total + $bytes.Length) -gt $MaximumBytes) {
    return @{ Written = $false; Error = 'log-budget-exhausted'; Bytes = $total; Path = $Path }
  }
  try {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try {
      $stream.Write($bytes, 0, $bytes.Length)
      $stream.Flush($true)
    }
    finally { $stream.Dispose() }
    return @{ Written = $true; Error = $null; Bytes = $total + $bytes.Length; Path = $Path }
  }
  catch {
    return @{ Written = $false; Error = 'log-write-failed'; Bytes = $total; Path = $Path }
  }
}

function Get-DotfilesSanitizedSource {
  param($Result)
  if ($null -eq $Result) { return @{ status = 'unavailable'; error = 'timeout'; metrics = @{} } }
  $status = [string]$Result.status
  if ($status -notin @('ok', 'partial', 'unavailable', 'timeout', 'pending')) { $status = 'unavailable' }
  $safeError = $null
  if ($status -ne 'ok') {
    $candidate = [string]$Result.error
    if ($candidate -match '^(access-denied|provider-unavailable|counter-unavailable|first-sample|counter-reset|timeout|worker-failed|worker-output-invalid|worker-start-failed|inhibited|probe-interval|not-requested|distro-not-running|preflight-timeout|preflight-output-invalid|preflight-failed|wsl-client-unavailable|guest-output-invalid|guest-failed|guest-start-failed|memory-data-unavailable|procfs-unavailable|required-command-missing)$') {
      $safeError = $candidate
    }
    elseif ($status -eq 'timeout') { $safeError = 'timeout' }
    else { $safeError = 'provider-unavailable' }
  }
  return @{ status = $status; error = $safeError; metrics = $Result.metrics }
}

function Invoke-DotfilesIncidentCollector {
  param(
    [int]$IntervalSeconds,
    [int]$DurationSeconds,
    [long]$MaximumLogBytes,
    [string]$OutputDirectory,
    [string]$GuestDistro
  )

  if (-not (Test-DotfilesWindowsHost)) {
    [Console]::Error.WriteLine('wsl-incident-capture: Windows only')
    return 2
  }
  if ($IntervalSeconds -lt 1 -or $IntervalSeconds -gt 60 -or $DurationSeconds -lt 1 -or $DurationSeconds -gt 86400 -or $MaximumLogBytes -lt 65536 -or $MaximumLogBytes -gt 33554432) {
    [Console]::Error.WriteLine('wsl-incident-capture: invalid bounded option')
    return 2
  }
  if (-not [string]::IsNullOrWhiteSpace($GuestDistro) -and ($GuestDistro.Length -gt 128 -or $GuestDistro -match '[\x00-\x1f\x7f]')) {
    [Console]::Error.WriteLine('wsl-incident-capture: invalid bounded option')
    return 2
  }
  $resolvedOutputDirectory = $null
  if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
    try {
      $resolvedOutputDirectory = Resolve-DotfilesOutputDirectoryPath -Path $OutputDirectory
      $null = Get-DotfilesSafePath -Path $resolvedOutputDirectory
    }
    catch { [Console]::Error.WriteLine('wsl-incident-capture: output path rejected'); return 2 }
  }

  $stateDirectory = $null
  $logsDirectory = $null
  $lock = $null
  $ownedWorkers = @{}
  $workerJournal = @{}
  $blockedSources = @{}
  $inhibitions = @()
  $runId = [Guid]::NewGuid().ToString('N')
  $runStartedMilliseconds = Get-DotfilesMonotonicMilliseconds
  $lastGuest = $null
  $lastGuestSampleMilliseconds = $null
  $guestProcess = $null
  $guestLastAttemptMilliseconds = -60000.0
  $guestSuppressed = $false
  $guestCompletedSinceRecord = $false
  $previousCpu = $null
  $previousMemory = $null
  $previousDisk = $null
  $previousHyperv = $null
  $previousSampleMilliseconds = $null
  $latestSources = @{}
  $lastWriteError = $null
  $randomSalt = New-Object byte[] 32
  $randomProvider = New-Object Security.Cryptography.RNGCryptoServiceProvider
  try {
    $randomProvider.GetBytes($randomSalt)
    $script:AliasSalt = [Convert]::ToBase64String($randomSalt)
  }
  finally {
    $randomProvider.Dispose()
    [Array]::Clear($randomSalt, 0, $randomSalt.Length)
  }

  try {
    $stateDirectory = Initialize-DotfilesPrivateDirectory -Path (Get-DotfilesDefaultStateDirectory)
    $lock = Enter-DotfilesCollectorLock -StateDirectory $stateDirectory -RunId $runId
    if (-not $lock.Acquired) {
      [Console]::Error.WriteLine(('wsl-incident-capture: {0}' -f $lock.Reason))
      if ($lock.Reason -eq 'already-running') { return 0 }
      return 1
    }
    Initialize-DotfilesBoundedStreamReader
    Initialize-DotfilesProcessTree
    $logsBase = $resolvedOutputDirectory
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $logsBase = Join-Path $stateDirectory 'logs' }
    else { $logsBase = Resolve-DotfilesOutputDirectoryPath -Path $OutputDirectory }
    $logsBase = Get-DotfilesSafePath -Path $logsBase
    [void][IO.Directory]::CreateDirectory($logsBase)
    $logsDirectory = Initialize-DotfilesPrivateDirectory -Path (Join-Path $logsBase 'dotfiles-wsl-incident-telemetry')
    Repair-DotfilesPartialLogs -Directory $logsDirectory -MaximumBytes $MaximumLogBytes
    $inhibitions = @(Read-DotfilesInhibitions -StateDirectory $stateDirectory -CurrentRunId $runId)
    Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
    $stamp = (Get-DotfilesUtcNow).ToString('yyyyMMddTHHmmssZ')
    $logPath = Join-Path $logsDirectory ($script:LogPrefix + $stamp + '-' + $runId + '-0000.jsonl')
    while (((Get-DotfilesMonotonicMilliseconds) - $runStartedMilliseconds) / 1000.0 -lt $DurationSeconds) {
      $tickStart = Get-DotfilesMonotonicMilliseconds
      $inhibitions = @(Read-DotfilesInhibitions -StateDirectory $stateDirectory -CurrentRunId $runId)
      if ([string]::IsNullOrWhiteSpace($GuestDistro)) {
        $latestSources.guest = @{ status = 'unavailable'; error = 'not-requested'; metrics = @{} }
      }
      elseif (-not $guestCompletedSinceRecord) {
        $latestSources.guest = @{ status = 'unavailable'; error = 'probe-interval'; metrics = @{} }
      }
      $guestCompletedSinceRecord = $false
      foreach ($source in @('cpu', 'memory', 'disk', 'hyperv')) {
        $blocked = $blockedSources.ContainsKey($source) -or @($inhibitions | Where-Object { $_.source -eq '*' -or $_.source -eq $source }).Count -gt 0
        if ($blocked) {
          $latestSources[$source] = @{ status = 'unavailable'; error = 'inhibited'; metrics = @{} }
          continue
        }
        if ($ownedWorkers.ContainsKey($source)) { continue }
        $latestSources[$source] = @{ status = 'unavailable'; error = 'provider-unavailable'; metrics = @{} }
        $workerJournal[$source] = @{ source = $source; processId = -1; startTimeTicks = 0; cleanupUnverified = $true; runId = $runId; launchState = 'starting' }
        Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
        try { $owned = Start-DotfilesHostWorker -Source $source }
        catch {
          $mayRemain = $false
          try { $mayRemain = [bool]$_.Exception.Data['DotfilesOwnedProcessMayRemain'] } catch { }
          if ($mayRemain) {
            $blockedSources[$source] = $true
            $latestSources[$source] = @{ status = 'unavailable'; error = 'inhibited'; metrics = @{} }
          }
          else {
            $workerJournal.Remove($source)
            $latestSources[$source] = @{ status = 'unavailable'; error = 'worker-start-failed'; metrics = @{} }
            Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
          }
          continue
        }
        $ownedWorkers[$source] = $owned
        $workerJournal[$source] = @{ source = $source; processId = [int]$owned.ProcessId; startTimeTicks = [long]$owned.StartTimeTicks; cleanupUnverified = $false; runId = $runId; launchState = 'running' }
        Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
      }

      $guestBlocked = $blockedSources.ContainsKey('guest') -or @($inhibitions | Where-Object { $_.source -eq '*' -or $_.source -eq 'guest' }).Count -gt 0
      if ($guestBlocked) {
        $latestSources.guest = @{ status = 'unavailable'; error = 'inhibited'; metrics = @{} }
      }
      elseif ((Test-DotfilesGuestProbeAllowed -Distribution $GuestDistro -Suppressed $guestSuppressed -Inhibitions $inhibitions -NowMilliseconds $tickStart -LastAttemptMilliseconds $guestLastAttemptMilliseconds) -and $null -eq $guestProcess) {
        $guestLastAttemptMilliseconds = $tickStart
        $guestIntervalSeconds = Get-DotfilesGuestIntervalSeconds -PreviousSampleMilliseconds $lastGuestSampleMilliseconds -NowMilliseconds $tickStart
        $guestPreviousCounters = ''
        if ($null -ne $guestIntervalSeconds) { $guestPreviousCounters = Get-DotfilesGuestBaseline -Snapshot $lastGuest }
        else { $guestIntervalSeconds = 0 }
        $workerJournal.guest = @{ source = 'guest'; processId = -1; startTimeTicks = 0; cleanupUnverified = $true; runId = $runId; launchState = 'preflight' }
        Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
        $guestStart = Start-DotfilesGuestProbe -Distribution $GuestDistro -IntervalSeconds $guestIntervalSeconds -PreviousCounters $guestPreviousCounters
        if ($guestStart.Status -eq 'pending') {
          $guestProcess = $guestStart.Process
          $workerJournal.guest = @{ source = 'guest'; processId = [int]$guestProcess.ProcessId; startTimeTicks = [long]$guestProcess.StartTimeTicks; cleanupUnverified = $true; runId = $runId; launchState = 'running' }
          $latestSources.guest = @{ status = 'pending'; error = $null; metrics = @{} }
        }
        else {
          $latestSources.guest = @{ status = $guestStart.Status; error = $guestStart.Error; metrics = @{} }
          if ($guestStart.Status -eq 'timeout') {
            $guestSuppressed = $true
          }
          if ($guestStart.Cleanup -and -not $guestStart.Cleanup.Exited) {
            $guestSuppressed = $true
            $blockedSources['guest'] = $true
            $cleanupEntries = @()
            if ($null -ne $guestStart.Cleanup.Entries) { $cleanupEntries = @($guestStart.Cleanup.Entries) }
            if ($cleanupEntries.Count -gt 0) { $inhibitions += $cleanupEntries }
          }
          else {
            $workerJournal.Remove('guest')
          }
          Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
        }
        if ($guestStart.Status -eq 'pending') {
          Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
        }
      }

      $durationDeadline = $runStartedMilliseconds + ($DurationSeconds * 1000.0)
      $hostWaitStartedMilliseconds = Get-DotfilesMonotonicMilliseconds
      $hostDeadline = Get-DotfilesHostSamplingDeadline -DurationDeadlineMilliseconds $durationDeadline -WaitStartedMilliseconds $hostWaitStartedMilliseconds -IntervalSeconds $IntervalSeconds
      while ((Get-DotfilesMonotonicMilliseconds) -lt $hostDeadline) {
        $pending = $false
        foreach ($source in @($ownedWorkers.Keys)) {
          $owned = $ownedWorkers[$source]
          if ($owned.Process.HasExited) {
            $result = Get-DotfilesWorkerResult -Owned $owned
            $latestSources[$source] = Get-DotfilesSanitizedSource -Result $result
            if ($result.Cleanup -and -not $result.Cleanup.Exited) { $inhibitions += @($result.Cleanup.Entries) }
            $workerJournal.Remove($source)
            $owned.Process.Dispose()
            $ownedWorkers.Remove($source)
            Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
          }
          else { $pending = $true }
        }
        if ($null -ne $guestProcess) {
          $guestUpdate = Update-DotfilesGuestProcess -Owned $guestProcess
          $latestSources.guest = $guestUpdate.Record
          if ($guestUpdate.Done) {
            if (Test-DotfilesGuestBaselineAvailable -Snapshot $guestUpdate.Data) {
              $lastGuest = $guestUpdate.Data
              $lastGuestSampleMilliseconds = Get-DotfilesMonotonicMilliseconds
            }
            $guestSuppressed = $guestUpdate.Suppressed
            $inhibitions += @($guestUpdate.Inhibitions)
            $workerJournal.Remove('guest')
            $guestProcess.Process.Dispose()
            $guestProcess = $null
            Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
          }
        }
        if (-not $pending) { break }
        Wait-DotfilesMilliseconds -Milliseconds 25
      }

      foreach ($source in @($ownedWorkers.Keys)) {
        $owned = $ownedWorkers[$source]
        if ($owned.Process.HasExited) {
          $result = Get-DotfilesWorkerResult -Owned $owned
          $latestSources[$source] = Get-DotfilesSanitizedSource -Result $result
          if ($result.Cleanup -and -not $result.Cleanup.Exited) { $inhibitions += @($result.Cleanup.Entries) }
          $workerJournal.Remove($source)
          $owned.Process.Dispose()
          $ownedWorkers.Remove($source)
          Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
        }
        else {
          $cleanup = Stop-DotfilesOwnedProcess -Owned $owned -GraceMilliseconds $script:CleanupGraceMilliseconds
          $latestSources[$source] = @{ status = 'timeout'; error = 'timeout'; metrics = @{} }
          if (-not $cleanup.Exited) { $inhibitions += @($cleanup.Entries) }
          $workerJournal.Remove($source)
          $ownedWorkers.Remove($source)
          Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
        }
      }

      if ($null -ne $guestProcess) {
        $guestUpdate = Update-DotfilesGuestProcess -Owned $guestProcess
        $latestSources.guest = $guestUpdate.Record
        if ($guestUpdate.Done) {
          if (Test-DotfilesGuestBaselineAvailable -Snapshot $guestUpdate.Data) {
            $lastGuest = $guestUpdate.Data
            $lastGuestSampleMilliseconds = Get-DotfilesMonotonicMilliseconds
          }
          $guestSuppressed = $guestUpdate.Suppressed
          $inhibitions += @($guestUpdate.Inhibitions)
          $workerJournal.Remove('guest')
          $guestProcess.Process.Dispose()
          $guestProcess = $null
          Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
        }
      }

      $now = Get-DotfilesUtcNow
      $cpuSnapshot = $null
      if ($latestSources.ContainsKey('cpu')) { $cpuSnapshot = $latestSources.cpu }
      $cpu = Get-DotfilesCpuMetrics -Snapshot $cpuSnapshot -Previous $previousCpu
      if ($cpuSnapshot -and $cpuSnapshot.status -eq 'ok' -and $null -ne $cpuSnapshot.metrics.percentProcessorTime -and $null -ne $cpuSnapshot.metrics.percentPrivilegedTime -and $null -ne $cpuSnapshot.metrics.timestampSys100Ns) { $previousCpu = $cpuSnapshot }
      else { $previousCpu = $null }

      $memorySnapshot = if ($latestSources.ContainsKey('memory')) { $latestSources.memory } else { $null }
      $memory = Get-DotfilesMemoryMetrics -Snapshot $memorySnapshot -Previous $previousMemory
      if ($memorySnapshot -and $memorySnapshot.status -in @('ok', 'partial') -and $memorySnapshot.metrics.timestampPerfTime) { $previousMemory = $memorySnapshot }
      else { $previousMemory = $null }

      $diskSnapshot = if ($latestSources.ContainsKey('disk')) { $latestSources.disk } else { $null }
      $disk = Get-DotfilesDiskMetrics -Snapshot $diskSnapshot -Previous $previousDisk
      if ($diskSnapshot -and $diskSnapshot.status -in @('ok', 'partial') -and ($diskSnapshot.metrics.physicalTotal -or $diskSnapshot.metrics.systemVolume)) { $previousDisk = $diskSnapshot }
      else { $previousDisk = $null }

      $hypervSnapshot = if ($latestSources.ContainsKey('hyperv')) { $latestSources.hyperv } else { $null }
      $hyperv = Get-DotfilesHypervMetrics -Snapshot $hypervSnapshot -Previous $previousHyperv
      if ($hypervSnapshot -and $hypervSnapshot.status -eq 'ok' -and $hypervSnapshot.metrics.virtualStorage) { $previousHyperv = $hypervSnapshot }
      else { $previousHyperv = $null }

      $hostSources = [ordered]@{
        cpu = $cpu
        memory = $memory
        disk = $disk
        hyperv = $hyperv
      }
      $guestRecord = if ($latestSources.ContainsKey('guest')) { Get-DotfilesSanitizedSource -Result $latestSources.guest } else { @{ status = 'unavailable'; error = 'not-requested'; metrics = @{} } }
      $record = [ordered]@{
        schemaVersion = 1
        recordType = 'host-sample'
        runId = $runId
        sampleTimeUtc = $now.ToString('o')
        elapsedSeconds = [Math]::Round(((Get-DotfilesMonotonicMilliseconds) - $runStartedMilliseconds) / 1000.0, 3)
        sampleIntervalSeconds = if ($null -eq $previousSampleMilliseconds) { $null } else { [Math]::Round(((Get-DotfilesMonotonicMilliseconds) - $previousSampleMilliseconds) / 1000.0, 3) }
        units = @{
          cpu = 'percent'
          memory = 'bytes'
          pageFileUsage = 'percent'
          pagingRates = 'events-per-second'
          diskThroughput = 'bytes-per-second'
          diskQueue = 'requests'
          guestMemory = 'kB'
          guestPsi = 'percent'
          guestVmCounters = 'events'
        }
        host = $hostSources
        guest = $guestRecord
      }
      $previousSampleMilliseconds = Get-DotfilesMonotonicMilliseconds
      $write = Write-DotfilesLogRecord -Directory $logsDirectory -Path $logPath -Record $record -MaximumBytes $MaximumLogBytes -RunId $runId
      if (-not $write.Written) {
        $lastWriteError = $write.Error
        if ($write.Error -in @('log-budget-exhausted', 'log-segment-limit')) { break }
      }
      else { $logPath = $write.Path }
      Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)

      $sampleDeadline = [Math]::Min($durationDeadline, $tickStart + ($IntervalSeconds * 1000.0))
      $remaining = $sampleDeadline - (Get-DotfilesMonotonicMilliseconds)
      while ($remaining -gt 0) {
        Wait-DotfilesMilliseconds -Milliseconds ([int][Math]::Min($remaining, 50))
        if ($null -ne $guestProcess) {
          $guestUpdate = Update-DotfilesGuestProcess -Owned $guestProcess
          if ($guestUpdate.Done) {
            $latestSources.guest = $guestUpdate.Record
            if (Test-DotfilesGuestBaselineAvailable -Snapshot $guestUpdate.Data) {
              $lastGuest = $guestUpdate.Data
              $lastGuestSampleMilliseconds = Get-DotfilesMonotonicMilliseconds
            }
            $guestSuppressed = $guestUpdate.Suppressed
            $inhibitions += @($guestUpdate.Inhibitions)
            $workerJournal.Remove('guest')
            $guestProcess.Process.Dispose()
            $guestProcess = $null
            $guestCompletedSinceRecord = $true
            Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values)
          }
        }
        $remaining = $sampleDeadline - (Get-DotfilesMonotonicMilliseconds)
      }
    }
  }
  catch [System.Management.Automation.PipelineStoppedException] {
    # Ctrl+C is a normal stop path; finally performs bounded owned-process cleanup.
  }
  catch {
    [Console]::Error.WriteLine('wsl-incident-capture: collector-failed')
    return 1
  }
  finally {
    foreach ($source in @($ownedWorkers.Keys)) {
      $owned = $ownedWorkers[$source]
      $cleanup = Stop-DotfilesOwnedProcess -Owned $owned -GraceMilliseconds $script:CleanupGraceMilliseconds
      if (-not $cleanup.Exited) { $inhibitions += @($cleanup.Entries) }
      $workerJournal.Remove($source)
      $owned.Process.Dispose()
    }
    if ($null -ne $guestProcess) {
      $cleanup = Stop-DotfilesOwnedProcess -Owned $guestProcess -GraceMilliseconds $script:CleanupGraceMilliseconds
      if (-not $cleanup.Exited) { $inhibitions += @($cleanup.Entries) }
      $workerJournal.Remove('guest')
      $guestProcess.Process.Dispose()
    }
    if ($null -ne $stateDirectory -and $null -ne $lock -and $lock.Acquired) {
      try { Write-DotfilesInhibitions -StateDirectory $stateDirectory -Entries $inhibitions -RunId $runId -WorkerJournal @($workerJournal.Values) } catch { }
    }
    if ($null -ne $lock) { Exit-DotfilesCollectorLock -Lock $lock }
  }

  if ($lastWriteError) {
    [Console]::Error.WriteLine(('wsl-incident-capture: {0}' -f $lastWriteError))
  }
  return 0
}

if ($MyInvocation.InvocationName -ne '.') {
  if ($Help) {
    @'
Usage: wsl-incident-capture.ps1 [-IntervalSeconds 1..60] [-DurationSeconds 1..86400]
       [-MaximumLogBytes 65536..33554432] [-OutputDirectory DIR] [-GuestDistro NAME]

Runs a foreground, bounded host evidence collector. Default behavior is host-only.
'@ | Write-Output
    exit 0
  }
  if ($Worker) {
    if (-not (Test-DotfilesWindowsHost)) { exit 2 }
    try {
      $result = Get-DotfilesHostSourceSnapshot -Source $WorkerSource -AliasSalt $AliasSalt
      [Console]::Out.WriteLine((ConvertTo-Json -InputObject $result -Compress -Depth 8))
      exit 0
    }
    catch {
      [Console]::Out.WriteLine((ConvertTo-Json -InputObject @{ source = $WorkerSource; status = 'unavailable'; error = 'worker-failed'; metrics = @{} } -Compress))
      exit 0
    }
  }
  $exitCode = Invoke-DotfilesIncidentCollector -IntervalSeconds $IntervalSeconds -DurationSeconds $DurationSeconds -MaximumLogBytes $MaximumLogBytes -OutputDirectory $OutputDirectory -GuestDistro $GuestDistro
  exit $exitCode
}
