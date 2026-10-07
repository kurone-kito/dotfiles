# cspell:ignore hyperv pgscan kswapd pgsteal pswpin pgmajfault vhdx
# Fixture-only tests for the opt-in WSL incident evidence collector.

$script:WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT

BeforeAll {
  $script:CollectorPath = Join-Path $PSScriptRoot '../../home/dot_local/bin/executable_wsl-incident-capture.ps1'
  $script:CollectorPath = [IO.Path]::GetFullPath($script:CollectorPath)
  $script:WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
  . $script:CollectorPath
  Initialize-DotfilesBoundedStreamReader
  Initialize-DotfilesProcessTree
}

Describe 'wsl incident capture metric handling' {
  It 'marks the first CPU sample unavailable and computes busy and privileged time from raw counters' {
    $current = @{ status = 'ok'; metrics = @{ percentProcessorTime = 130; percentPrivilegedTime = 10; timestampSys100Ns = 200 } }
    $first = Get-DotfilesCpuMetrics -Snapshot $current -Previous $null
    $first.status | Should -Be 'unavailable'
    $first.error | Should -Be 'first-sample'

    $previous = @{ status = 'ok'; metrics = @{ percentProcessorTime = 100; percentPrivilegedTime = 5; timestampSys100Ns = 100 } }
    $result = Get-DotfilesCpuMetrics -Snapshot $current -Previous $previous
    $result.status | Should -Be 'ok'
    $result.totalPercent | Should -Be 70
    $result.privilegedPercent | Should -Be 5
  }

  It 'marks CPU counter resets unavailable' {
    $previous = @{ status = 'ok'; metrics = @{ percentProcessorTime = 100; percentPrivilegedTime = 5; timestampSys100Ns = 100 } }
    $current = @{ status = 'ok'; metrics = @{ percentProcessorTime = 90; percentPrivilegedTime = 8; timestampSys100Ns = 200 } }

    $result = Get-DotfilesCpuMetrics -Snapshot $current -Previous $previous

    $result.status | Should -Be 'unavailable'
    $result.error | Should -Be 'counter-reset'
  }

  It 'does not turn missing stable counter properties into zero rates' {
    Mock Get-DotfilesCimInstances {
      return @{ Status = 'ok'; Items = @([pscustomobject]@{ Name = '_Total'; PercentProcessorTime = 120; Timestamp_Sys100NS = 200 }) }
    }
    $snapshot = Get-DotfilesHostSourceSnapshot -Source cpu
    $previous = @{ status = 'ok'; metrics = @{ percentProcessorTime = 100; percentPrivilegedTime = 5; timestampSys100Ns = 100 } }

    $snapshot.metrics.percentPrivilegedTime | Should -BeNullOrEmpty
    (Get-DotfilesCpuMetrics -Snapshot $snapshot -Previous $previous).error | Should -Be 'counter-unavailable'
  }

  It 'reports access denial as a fixed category and ignores localized display labels' {
    Mock Get-DotfilesCimInstances {
      param($ClassName)
      if ($ClassName -eq 'Win32_PerfRawData_PerfOS_Processor') {
        return @{ Status = 'ok'; Items = @([pscustomobject]@{ Name = '_Total'; PercentProcessorTime = 120; PercentPrivilegedTime = 10; Timestamp_Sys100NS = 200; LocalizedDisplayName = 'Processor total' }) }
      }
      return @{ Status = 'unavailable'; Error = 'access-denied'; Items = @() }
    }
    $stable = Get-DotfilesHostSourceSnapshot -Source cpu
    $denied = Get-DotfilesHostSourceSnapshot -Source memory

    $stable.status | Should -Be 'ok'
    $stable.metrics.percentProcessorTime | Should -Be 120
    $denied.error | Should -Be 'access-denied'
    (Get-DotfilesSanitizedSource -Result $denied).error | Should -Be 'access-denied'
  }

  It 'selects the system volume by stable identity and redacts its drive label' {
    Mock Get-DotfilesCimInstances {
      param($ClassName)
      switch ($ClassName) {
        'Win32_PerfRawData_PerfDisk_PhysicalDisk' {
          return @{ Status = 'ok'; Items = @(
              [pscustomobject]@{ Name = '0 C:'; DiskReadBytesPerSec = 10; DiskWriteBytesPerSec = 20; Timestamp_PerfTime = 10; Frequency_PerfTime = 10; CurrentDiskQueueLength = 1 },
              [pscustomobject]@{ Name = '_Total'; DiskReadBytesPerSec = 100; DiskWriteBytesPerSec = 200; Timestamp_PerfTime = 10; Frequency_PerfTime = 10; CurrentDiskQueueLength = 2 }
            ) }
        }
        'Win32_OperatingSystem' { return @{ Status = 'ok'; Items = @([pscustomobject]@{ SystemDrive = 'C:' }) } }
        'Win32_PerfRawData_PerfDisk_LogicalDisk' {
          return @{ Status = 'ok'; Items = @(
              [pscustomobject]@{ Name = 'D:'; DiskReadBytesPerSec = 7; DiskWriteBytesPerSec = 9; Timestamp_PerfTime = 10; Frequency_PerfTime = 10; CurrentDiskQueueLength = 0 },
              [pscustomobject]@{ Name = 'C:'; DiskReadBytesPerSec = 50; DiskWriteBytesPerSec = 70; Timestamp_PerfTime = 10; Frequency_PerfTime = 10; CurrentDiskQueueLength = 1 }
            ) }
        }
      }
    }
    $salt = [Convert]::ToBase64String((New-Object byte[] 32))

    $result = Get-DotfilesHostSourceSnapshot -Source disk -AliasSalt $salt
    $json = ConvertTo-Json -InputObject $result -Compress -Depth 8

    $result.status | Should -Be 'ok'
    $result.metrics.physicalTotal.readBytesCounter | Should -Be 100
    $result.metrics.systemVolume.readBytesCounter | Should -Be 50
    $result.metrics.systemVolume.instanceAlias | Should -Match '^volume-[a-f0-9]{16}$'
    $json | Should -Not -Match 'C:|D:'
  }

  It 'calculates raw counter rates and rejects missing or reset baselines' {
    $first = Get-DotfilesRawCounterRate -CurrentValue 20 -PreviousValue $null -CurrentTimestamp 200 -PreviousTimestamp $null -CurrentFrequency 10 -PreviousFrequency $null
    $first.status | Should -Be 'unavailable'
    $first.error | Should -Be 'first-sample'

    $rate = Get-DotfilesRawCounterRate -CurrentValue 20 -PreviousValue 10 -CurrentTimestamp 200 -PreviousTimestamp 100 -CurrentFrequency 10 -PreviousFrequency 10
    $rate.status | Should -Be 'ok'
    $rate.value | Should -Be 1

    $reset = Get-DotfilesRawCounterRate -CurrentValue 5 -PreviousValue 10 -CurrentTimestamp 200 -PreviousTimestamp 100 -CurrentFrequency 10 -PreviousFrequency 10
    $reset.status | Should -Be 'unavailable'
    $reset.error | Should -Be 'counter-reset'
  }

  It 'reports byte and paging rates while preserving point-in-time memory values' {
    $previous = @{ status = 'ok'; metrics = @{ pageReadsCounter = 2; pagesInputCounter = 1; pageWritesCounter = 3; pagesOutputCounter = 4; timestampPerfTime = 10; frequencyPerfTime = 10 } }
    $current = @{ status = 'ok'; metrics = @{ availableBytes = 400; committedBytes = 700; commitLimitBytes = 1200; pageFilePercentUsage = 20; pageReadsCounter = 12; pagesInputCounter = 11; pageWritesCounter = 8; pagesOutputCounter = 9; timestampPerfTime = 20; frequencyPerfTime = 10 } }

    $result = Get-DotfilesMemoryMetrics -Snapshot $current -Previous $previous

    $result.status | Should -Be 'ok'
    $result.metrics.availableBytes | Should -Be 400
    $result.metrics.committedBytes | Should -Be 700
    $result.metrics.commitLimitBytes | Should -Be 1200
    $result.metrics.pageFilePercentUsage | Should -Be 20
    $result.metrics.pagingRates.counters.pageReadsPerSecond.value | Should -Be 10
    $result.metrics.pagingRates.counters.pagesOutputPerSecond.value | Should -Be 5
  }

  It 'preserves counter-reset errors in memory summaries' {
    $previous = @{ status = 'ok'; metrics = @{ pageReadsCounter = 10; pagesInputCounter = 10; pageWritesCounter = 3; pagesOutputCounter = 4; timestampPerfTime = 10; frequencyPerfTime = 10 } }
    $current = @{ status = 'ok'; metrics = @{ availableBytes = 400; committedBytes = 700; commitLimitBytes = 1200; pageFilePercentUsage = 20; pageReadsCounter = 5; pagesInputCounter = 11; pageWritesCounter = 8; pagesOutputCounter = 9; timestampPerfTime = 20; frequencyPerfTime = 10 } }

    $result = Get-DotfilesMemoryMetrics -Snapshot $current -Previous $previous

    $result.status | Should -Be 'partial'
    $result.error | Should -Be 'counter-reset'
    $result.metrics.pagingRates.counters.pageReadsPerSecond.error | Should -Be 'counter-reset'
  }

  It 'marks rates unavailable when a disk instance changes' {
    $previous = @{ status = 'ok'; metrics = @{ physicalTotal = @{ readBytesCounter = 20; writeBytesCounter = 30; timestampPerfTime = 10; frequencyPerfTime = 10; queueLength = 1 }; systemVolume = @{ readBytesCounter = 10; writeBytesCounter = 20; timestampPerfTime = 10; frequencyPerfTime = 10; queueLength = 1; instanceAlias = 'volume-old' } } }
    $current = @{ status = 'ok'; metrics = @{ physicalTotal = @{ readBytesCounter = 120; writeBytesCounter = 230; timestampPerfTime = 20; frequencyPerfTime = 10; queueLength = 2 }; systemVolume = @{ readBytesCounter = 50; writeBytesCounter = 70; timestampPerfTime = 20; frequencyPerfTime = 10; queueLength = 1; instanceAlias = 'volume-new' } } }

    $result = Get-DotfilesDiskMetrics -Snapshot $current -Previous $previous

    $result.metrics.physicalTotal.readBytesPerSecond | Should -Be 100
    $result.metrics.systemVolume.status | Should -Be 'unavailable'
    $result.metrics.systemVolume.error | Should -Be 'counter-reset'
    $result.metrics.systemVolume.readBytesPerSecond | Should -BeNullOrEmpty
  }

  It 'keeps the disk summary partial when either expected view is unavailable' {
    $previous = @{ status = 'ok'; metrics = @{ physicalTotal = @{ readBytesCounter = 10; writeBytesCounter = 20; timestampPerfTime = 10; frequencyPerfTime = 10; queueLength = 1 }; systemVolume = @{ readBytesCounter = 5; writeBytesCounter = 7; timestampPerfTime = 10; frequencyPerfTime = 10; queueLength = 0; instanceAlias = 'volume-fixture' } } }
    $current = @{ status = 'partial'; metrics = @{ physicalTotal = @{ readBytesCounter = 20; writeBytesCounter = 40; timestampPerfTime = 20; frequencyPerfTime = 10; queueLength = 2 }; systemVolume = @{ readBytesCounter = 10; writeBytesCounter = 14; timestampPerfTime = 20; frequencyPerfTime = 10; queueLength = 0; instanceAlias = 'volume-fixture' } } }

    foreach ($missingView in @('physicalTotal', 'systemVolume')) {
      $metrics = @{
        physicalTotal = $current.metrics.physicalTotal
        systemVolume = $current.metrics.systemVolume
      }
      $metrics[$missingView] = $null
      $snapshot = @{ status = 'partial'; metrics = $metrics }

      $result = Get-DotfilesDiskMetrics -Snapshot $snapshot -Previous $previous

      $result.status | Should -Be 'partial'
      $result.error | Should -Be 'counter-unavailable'
      $result.metrics[$missingView].status | Should -Be 'unavailable'
      $healthyView = if ($missingView -eq 'physicalTotal') { 'systemVolume' } else { 'physicalTotal' }
      $result.metrics[$healthyView].status | Should -Be 'ok'
    }

    (Get-DotfilesDiskMetrics -Snapshot $current -Previous $previous).status | Should -Be 'ok'
  }

  It 'uses raw Hyper-V counters to report rates and redact virtual storage paths' {
    $salt = [Convert]::ToBase64String((New-Object byte[] 32))
    $script:HypervSnapshotCount = 0
    Mock Get-DotfilesCimInstances {
      param($ClassName)
      if ($ClassName -ne 'Win32_PerfRawData_Counters_HyperVVirtualStorageDevice') {
        return @{ Status = 'unavailable'; Error = 'counter-unavailable'; Items = @() }
      }
      $script:HypervSnapshotCount++
      $multiplier = $script:HypervSnapshotCount
      return @{ Status = 'ok'; Items = @([pscustomobject]@{
            Name = 'C:\Users\SeedUser\Guests\PrivateDistro.vhdx'
            ReadBytesPersec = 100 * $multiplier
            WriteBytesPersec = 200 * $multiplier
            ReadOperationsPerSec = 10 * $multiplier
            WriteOperationsPerSec = 20 * $multiplier
            Timestamp_PerfTime = 1000 * $multiplier
            Frequency_PerfTime = 1000
          }) }
    }

    $previous = Get-DotfilesHostSourceSnapshot -Source hyperv -AliasSalt $salt
    $current = Get-DotfilesHostSourceSnapshot -Source hyperv -AliasSalt $salt
    $first = Get-DotfilesHypervMetrics -Snapshot $previous -Previous $null
    $result = Get-DotfilesHypervMetrics -Snapshot $current -Previous $previous
    $json = ConvertTo-Json -InputObject $previous -Compress -Depth 8

    $first.metrics.virtualStorage[0].error | Should -Be 'first-sample'
    $result.metrics.virtualStorage[0].readBytesPerSecond | Should -Be 100
    $result.metrics.virtualStorage[0].writeBytesPerSecond | Should -Be 200
    $result.metrics.virtualStorage[0].readOperationsPerSecond | Should -Be 10
    $result.metrics.virtualStorage[0].writeOperationsPerSecond | Should -Be 20
    $json | Should -Not -Match 'SeedUser|PrivateDistro|\.vhdx|C:\\Users'
    $json | Should -Match 'virtual-device-[a-f0-9]{16}'
    Should -Invoke Get-DotfilesCimInstances -Times 2 -Exactly -ParameterFilter { $ClassName -eq 'Win32_PerfRawData_Counters_HyperVVirtualStorageDevice' }
  }

  It 'starts recovered CPU, memory, and disk rates with unavailable baselines' {
    $cpu = Get-DotfilesCpuMetrics -Snapshot @{ status = 'ok'; metrics = @{ percentProcessorTime = 100; percentPrivilegedTime = 10; timestampSys100Ns = 200 } } -Previous $null
    $memory = Get-DotfilesMemoryMetrics -Snapshot @{ status = 'ok'; metrics = @{ pageReadsCounter = 20; pagesInputCounter = 10; pageWritesCounter = 5; pagesOutputCounter = 1; timestampPerfTime = 200; frequencyPerfTime = 100 } } -Previous $null
    $disk = Get-DotfilesDiskMetrics -Snapshot @{ status = 'ok'; metrics = @{ physicalTotal = @{ readBytesCounter = 20; writeBytesCounter = 30; timestampPerfTime = 200; frequencyPerfTime = 100; queueLength = 1 }; systemVolume = @{ readBytesCounter = 5; writeBytesCounter = 7; timestampPerfTime = 200; frequencyPerfTime = 100; queueLength = 0; instanceAlias = 'volume-fixture' } } } -Previous $null

    $cpu.error | Should -Be 'first-sample'
    $memory.metrics.pagingRates.status | Should -Be 'partial'
    $disk.metrics.physicalTotal.error | Should -Be 'first-sample'
    $disk.metrics.systemVolume.error | Should -Be 'first-sample'
  }

  It 'preserves sanitized worker timeout and inhibition reasons for host sources' {
    $timedOut = @{ status = 'timeout'; error = 'timeout'; metrics = @{} }
    $inhibited = @{ status = 'unavailable'; error = 'inhibited'; metrics = @{} }
    $startFailed = Get-DotfilesSanitizedSource -Result @{ status = 'unavailable'; error = 'worker-start-failed'; metrics = @{} }

    (Get-DotfilesCpuMetrics -Snapshot $timedOut -Previous $null).status | Should -Be 'timeout'
    (Get-DotfilesCpuMetrics -Snapshot $inhibited -Previous $null).error | Should -Be 'inhibited'
    (Get-DotfilesMemoryMetrics -Snapshot $inhibited -Previous $null).error | Should -Be 'inhibited'
    (Get-DotfilesDiskMetrics -Snapshot $timedOut -Previous $null).error | Should -Be 'timeout'
    (Get-DotfilesHypervMetrics -Snapshot $inhibited -Previous $null).error | Should -Be 'inhibited'
    $startFailed.error | Should -Be 'worker-start-failed'
  }

  It 'reduces provider and process errors to safe categories' {
    $seed = 'secret-user-host-distro-path-commandline-environment'
    $result = Get-DotfilesSanitizedSource -Result @{ status = 'unavailable'; error = $seed; metrics = @{} }
    $json = ConvertTo-Json -InputObject $result -Compress -Depth 4

    $result.error | Should -Be 'provider-unavailable'
    $json | Should -Not -Match $seed
  }

  It 'whitelists guest JSON fields and strips seeded identity and path values' {
    $seed = 'seed-user-host-distro-home-vhd-commandline-environment'
    $payload = @{
      schemaVersion = 1; status = 'ok'; error = $seed; username = $seed
      memory = @{ status = 'ok'; unit = 'kB'; total = 1000; available = 500; home = $seed }
      swap = @{ status = 'ok'; unit = 'kB'; total = 100; used = 10; distro = $seed }
      psi = @{ status = 'ok'; some = @{ avg10 = 0.1; avg60 = 0.2; avg300 = 0.3; totalUsec = 40; path = $seed }; full = $null }
      counters = @{ pgscan_kswapd = 10; pgscan_direct = 0; pgsteal_kswapd = 2; pgsteal_direct = 0; workingset_refault = 4; pswpin = 0; pswpout = 1; pgfault = 10; pgmajfault = 0; commandLine = $seed }
      deltas = @{ pgscan_kswapd = @{ status = 'ok'; value = 2; perSecond = 1.0; secret = $seed } }
    }
    $safe = ConvertTo-DotfilesSafeGuestSnapshot -Data ($payload | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    $json = ConvertTo-Json -InputObject $safe.Data -Compress -Depth 8

    $safe.Valid | Should -BeTrue
    $safe.Error | Should -BeNullOrEmpty
    $json | Should -Not -Match $seed
    $json | Should -Not -Match 'username|home|commandLine|secret'
    $safe.Data.memory.available | Should -Be 500
    $safe.Data.deltas.pgscan_kswapd.perSecond | Should -Be 1
    $safe.Data.deltas.pgscan_direct.status | Should -Be 'unavailable'
  }

  It 'rejects guest output with an unsupported schema or status' {
    $unsupportedSchema = ConvertTo-DotfilesSafeGuestSnapshot -Data @{ schemaVersion = 2; status = 'ok' }
    $unsupportedStatus = ConvertTo-DotfilesSafeGuestSnapshot -Data @{ schemaVersion = 1; status = 'timed-out' }

    $unsupportedSchema.Valid | Should -BeFalse
    $unsupportedStatus.Valid | Should -BeFalse
  }

  It 'caps child stdout capture and drains stderr without retaining it' {
    $exe = Get-DotfilesPowerShellExecutable
    $owned = Start-DotfilesOwnedProcess -FileName $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', '[Console]::Out.Write((''x'' * 1000000)); [Console]::Error.Write((''secret'' * 100000))') -Source 'fixture'
    try {
      $owned.Process.WaitForExit(10000) | Should -BeTrue
      $capture = $owned.StdoutTask.GetAwaiter().GetResult()
      $stderr = $owned.StderrTask.GetAwaiter().GetResult()

      $capture.Text.Length | Should -Be 65536
      $capture.Truncated | Should -BeTrue
      $stderr | Should -BeNullOrEmpty
    }
    finally { $owned.Process.Dispose() }
  }

  It 'returns worker-output-invalid when an exited worker retains an output pipe' {
    $oldDrainTimeout = $script:OutputDrainTimeoutMilliseconds
    $script:OutputDrainTimeoutMilliseconds = 25
    $pendingOutput = [System.Threading.Tasks.TaskCompletionSource[object]]::new()
    $owned = @{
      Process = [pscustomobject]@{ HasExited = $true }
      StdoutTask = $pendingOutput.Task
      StderrTask = [System.Threading.Tasks.Task]::CompletedTask
      Source = 'cpu'
      ProcessId = 123
      StartTimeTicks = 456
    }
    $watch = [Diagnostics.Stopwatch]::StartNew()

    try {
      $result = Get-DotfilesWorkerResult -Owned $owned

      $result.status | Should -Be 'unavailable'
      $result.error | Should -Be 'worker-output-invalid'
      $result.Cleanup.CleanupUnverified | Should -BeTrue
      $result.Cleanup.Entries[0].source | Should -Be 'cpu'
      $result.Cleanup.Entries[0].processId | Should -Be 123
      $watch.ElapsedMilliseconds | Should -BeLessThan 500
    }
    finally {
      $watch.Stop()
      $null = $pendingOutput.TrySetResult($null)
      $script:OutputDrainTimeoutMilliseconds = $oldDrainTimeout
    }
  }

  It 'inhibits a worker when reading its output task fails' {
    $faultedOutput = [System.Threading.Tasks.TaskCompletionSource[object]]::new()
    $null = $faultedOutput.TrySetException([InvalidOperationException]::new('fixture-output-failure'))
    $owned = @{
      Process = [pscustomobject]@{ HasExited = $true }
      StdoutTask = $faultedOutput.Task
      StderrTask = [System.Threading.Tasks.Task]::CompletedTask
      Source = 'cpu'
      ProcessId = 124
      StartTimeTicks = 457
    }

    $result = Get-DotfilesWorkerResult -Owned $owned

    $result.error | Should -Be 'worker-output-invalid'
    $result.Cleanup.CleanupUnverified | Should -BeTrue
    $result.Cleanup.Entries[0].processId | Should -Be 124
  }

  It 'treats a cancelled output task as incomplete' {
    $cancelledOutput = [System.Threading.Tasks.TaskCompletionSource[object]]::new()
    $null = $cancelledOutput.TrySetCanceled()
    $owned = @{
      StdoutTask = $cancelledOutput.Task
      StderrTask = [System.Threading.Tasks.Task]::CompletedTask
    }

    Test-DotfilesProcessOutputCompleted -Owned $owned | Should -BeFalse
  }
}

Describe 'wsl incident capture guest and writer behavior' {
  It 'derives guest counter intervals from the previous successful sample time' {
    (Get-DotfilesGuestIntervalSeconds -PreviousSampleMilliseconds $null -NowMilliseconds 120000) | Should -BeNullOrEmpty
    (Get-DotfilesGuestIntervalSeconds -PreviousSampleMilliseconds 1000 -NowMilliseconds 62000) | Should -Be 61
    (Get-DotfilesGuestIntervalSeconds -PreviousSampleMilliseconds 1000 -NowMilliseconds 601000) | Should -Be 600
    (Get-DotfilesGuestIntervalSeconds -PreviousSampleMilliseconds 1000 -NowMilliseconds 601500) | Should -BeNullOrEmpty -Because 'elapsed intervals above ten minutes must start a fresh baseline'
    (Get-DotfilesGuestIntervalSeconds -PreviousSampleMilliseconds 1000 -NowMilliseconds 601500.5) | Should -BeNullOrEmpty -Because 'elapsed intervals above ten minutes must start a fresh baseline'
    (Get-DotfilesGuestIntervalSeconds -PreviousSampleMilliseconds 1000 -NowMilliseconds 900000) | Should -BeNullOrEmpty
    (Get-DotfilesGuestIntervalSeconds -PreviousSampleMilliseconds 62000 -NowMilliseconds 61000) | Should -Be 1
  }

  It 'keeps usable counters from partial guest samples as a rate baseline' {
    $partial = [pscustomobject]@{ status = 'partial'; counters = [pscustomobject]@{ pgfault = 10; pswpin = $null } }
    $withoutCounters = [pscustomobject]@{ status = 'partial'; counters = [pscustomobject]@{ pgfault = $null } }
    $unavailable = [pscustomobject]@{ status = 'unavailable'; counters = [pscustomobject]@{ pgfault = 10 } }

    (Test-DotfilesGuestBaselineAvailable -Snapshot $partial) | Should -BeTrue
    (Test-DotfilesGuestBaselineAvailable -Snapshot $withoutCounters) | Should -BeFalse
    (Test-DotfilesGuestBaselineAvailable -Snapshot $unavailable) | Should -BeFalse
  }

  It 'starts the host wait budget after guest preflight returns' {
    $deadline = Get-DotfilesHostSamplingDeadline -DurationDeadlineMilliseconds 5000 -WaitStartedMilliseconds 600 -IntervalSeconds 1

    $deadline | Should -Be 1100
  }

  It 'returns preflight-output-invalid when an exited client retains an output pipe' {
    $oldDrainTimeout = $script:OutputDrainTimeoutMilliseconds
    $script:OutputDrainTimeoutMilliseconds = 25
    $pendingOutput = [System.Threading.Tasks.TaskCompletionSource[object]]::new()
    $fakeProcess = [pscustomobject]@{}
    Add-Member -InputObject $fakeProcess -MemberType ScriptMethod -Name WaitForExit -Value { param($Milliseconds) return $true }
    Add-Member -InputObject $fakeProcess -MemberType ScriptMethod -Name Dispose -Value {}
    $script:PreflightOwnedFixture = @{
      Process = $fakeProcess
      StdoutTask = $pendingOutput.Task
      StderrTask = [System.Threading.Tasks.Task]::CompletedTask
      Source = 'guest'
      ProcessId = 234
      StartTimeTicks = 567
    }
    Mock Get-DotfilesWslExecutable { return 'wsl.exe' }
    Mock Start-DotfilesCommand { return $script:PreflightOwnedFixture }

    try {
      $result = Invoke-DotfilesWslPreflight -Distribution 'Ubuntu'

      $result.Status | Should -Be 'unavailable'
      $result.Error | Should -Be 'preflight-output-invalid'
      $result.Cleanup.CleanupUnverified | Should -BeTrue
      $result.Cleanup.Entries[0].source | Should -Be 'guest'
      $result.Cleanup.Entries[0].processId | Should -Be 234
    }
    finally {
      $null = $pendingOutput.TrySetResult($null)
      Remove-Variable PreflightOwnedFixture -Scope Script -ErrorAction SilentlyContinue
      $script:OutputDrainTimeoutMilliseconds = $oldDrainTimeout
    }
  }

  It 'inhibits the guest source when preflight output reading fails' {
    $faultedOutput = [System.Threading.Tasks.TaskCompletionSource[object]]::new()
    $null = $faultedOutput.TrySetException([InvalidOperationException]::new('fixture-output-failure'))
    $fakeProcess = [pscustomobject]@{}
    Add-Member -InputObject $fakeProcess -MemberType ScriptMethod -Name WaitForExit -Value { param($Milliseconds) return $true }
    Add-Member -InputObject $fakeProcess -MemberType ScriptMethod -Name Dispose -Value {}
    $script:PreflightOwnedFixture = @{
      Process = $fakeProcess
      StdoutTask = $faultedOutput.Task
      StderrTask = [System.Threading.Tasks.Task]::CompletedTask
      Source = 'guest'
      ProcessId = 235
      StartTimeTicks = 568
    }
    Mock Get-DotfilesWslExecutable { return 'wsl.exe' }
    Mock Start-DotfilesCommand { return $script:PreflightOwnedFixture }

    try {
      $result = Invoke-DotfilesWslPreflight -Distribution 'Ubuntu'

      $result.Error | Should -Be 'preflight-output-invalid'
      $result.Cleanup.CleanupUnverified | Should -BeTrue
      $result.Cleanup.Entries[0].processId | Should -Be 235
    }
    finally { Remove-Variable PreflightOwnedFixture -Scope Script -ErrorAction SilentlyContinue }
  }

  It 'does not accept a partial running-distribution listing when WSL exits nonzero' {
    $capture = [pscustomobject]@{ Text = "Ubuntu`n"; Truncated = $false }
    $fakeProcess = [pscustomobject]@{ ExitCode = 1 }
    Add-Member -InputObject $fakeProcess -MemberType ScriptMethod -Name WaitForExit -Value { param($Milliseconds) return $true }
    Add-Member -InputObject $fakeProcess -MemberType ScriptMethod -Name Dispose -Value {}
    $script:PreflightOwnedFixture = @{
      Process = $fakeProcess
      StdoutTask = [System.Threading.Tasks.Task[object]]::FromResult([object]$capture)
      StderrTask = [System.Threading.Tasks.Task]::CompletedTask
      Source = 'guest'
      ProcessId = 456
      StartTimeTicks = 789
    }
    Mock Get-DotfilesWslExecutable { return 'wsl.exe' }
    Mock Start-DotfilesCommand { return $script:PreflightOwnedFixture }

    try {
      $result = Invoke-DotfilesWslPreflight -Distribution 'Ubuntu'

      $result.Status | Should -Be 'unavailable'
      $result.Error | Should -Be 'preflight-failed'
    }
    finally {
      Remove-Variable PreflightOwnedFixture -Scope Script -ErrorAction SilentlyContinue
    }
  }

  It 'returns guest-output-invalid when an exited client retains an output pipe' {
    $oldDrainTimeout = $script:OutputDrainTimeoutMilliseconds
    $script:OutputDrainTimeoutMilliseconds = 25
    $pendingOutput = [System.Threading.Tasks.TaskCompletionSource[object]]::new()
    $owned = @{
      Process = [pscustomobject]@{ HasExited = $true }
      StdoutTask = $pendingOutput.Task
      StderrTask = [System.Threading.Tasks.Task]::CompletedTask
      Source = 'guest'
      ProcessId = 345
      StartTimeTicks = 678
      StartedAtMilliseconds = 0
    }

    try {
      $result = Update-DotfilesGuestProcess -Owned $owned

      $result.Done | Should -BeTrue
      $result.Record.status | Should -Be 'unavailable'
      $result.Record.error | Should -Be 'guest-output-invalid'
      $result.Suppressed | Should -BeTrue
      $result.Inhibitions.Count | Should -Be 1
      $result.Inhibitions[0].source | Should -Be 'guest'
      $result.Inhibitions[0].processId | Should -Be 345
      $result.Inhibitions[0].cleanupUnverified | Should -BeTrue
    }
    finally {
      $null = $pendingOutput.TrySetResult($null)
      $script:OutputDrainTimeoutMilliseconds = $oldDrainTimeout
    }
  }

  It 'inhibits the guest source when guest output reading fails' {
    $faultedOutput = [System.Threading.Tasks.TaskCompletionSource[object]]::new()
    $null = $faultedOutput.TrySetException([InvalidOperationException]::new('fixture-output-failure'))
    $owned = @{
      Process = [pscustomobject]@{ HasExited = $true }
      StdoutTask = $faultedOutput.Task
      StderrTask = [System.Threading.Tasks.Task]::CompletedTask
      Source = 'guest'
      ProcessId = 346
      StartTimeTicks = 679
      StartedAtMilliseconds = 0
    }

    $result = Update-DotfilesGuestProcess -Owned $owned

    $result.Record.error | Should -Be 'guest-output-invalid'
    $result.Suppressed | Should -BeTrue
    $result.Inhibitions.Count | Should -Be 1
    $result.Inhibitions[0].processId | Should -Be 346
    $result.Inhibitions[0].cleanupUnverified | Should -BeTrue
  }

  It 'uses the native PowerShell executable on non-Windows hosts' -Skip:$script:WindowsHost {
    $executable = Get-DotfilesPowerShellExecutable

    [IO.Path]::GetFileName($executable) | Should -Be 'pwsh'
    Test-Path -LiteralPath $executable | Should -BeTrue
  }

  It 'omits the guest counter interval before a baseline and passes the measured interval afterward' {
    $script:GuestArguments = @()
    Mock Invoke-DotfilesWslPreflight { return @{ Status = 'running'; Error = $null } }
    Mock Get-DotfilesWslExecutable { return 'wsl.exe' }
    Mock Start-DotfilesCommand {
      param($Executable, $Arguments, $Source, $StandardInputText)
      $script:GuestArguments = @($Arguments)
      return @{ ProcessId = 1; StartTimeTicks = 1; Source = $Source }
    }

    $null = Start-DotfilesGuestProbe -Distribution 'FixtureDistro' -PreviousCounters ''
    ($script:GuestArguments -notcontains '--interval-seconds') | Should -BeTrue
    $null = Start-DotfilesGuestProbe -Distribution 'FixtureDistro' -IntervalSeconds 61 -PreviousCounters 'fixture'
    $intervalIndex = [Array]::IndexOf($script:GuestArguments, '--interval-seconds')
    $intervalIndex | Should -BeGreaterOrEqual 0
    $script:GuestArguments[$intervalIndex + 1] | Should -Be '61'
    Should -Invoke Start-DotfilesCommand -Times 2 -Exactly
    Should -Invoke Invoke-DotfilesWslPreflight -Times 2 -Exactly
  }

  It 'does not launch a guest command when the selected distribution is not running' {
    Mock Invoke-DotfilesWslPreflight { return @{ Status = 'not-running'; Error = 'distro-not-running' } }
    Mock Start-DotfilesCommand { throw 'guest command must not start' }

    $result = Start-DotfilesGuestProbe -Distribution 'FixtureDistro' -IntervalSeconds 5 -PreviousCounters ''

    $result.Status | Should -Be 'not-running'
    Should -Invoke Start-DotfilesCommand -Times 0 -Exactly
  }

  It 'does not launch a guest command when preflight state is unknown' {
    $cleanup = @{ Exited = $false; CleanupUnverified = $true; Entries = @(@{ source = 'guest'; processId = 456; startTimeTicks = 789; cleanupUnverified = $true }) }
    Mock Invoke-DotfilesWslPreflight { return @{ Status = 'unavailable'; Error = 'preflight-output-invalid'; Cleanup = $cleanup } }
    Mock Start-DotfilesCommand { throw 'guest command must not start' }

    $result = Start-DotfilesGuestProbe -Distribution 'FixtureDistro' -IntervalSeconds 5 -PreviousCounters ''

    $result.Status | Should -Be 'unavailable'
    $result.Error | Should -Be 'preflight-output-invalid'
    $result.Cleanup.CleanupUnverified | Should -BeTrue
    $result.Cleanup.Entries[0].processId | Should -Be 456
    Should -Invoke Start-DotfilesCommand -Times 0 -Exactly
  }

  It 'suppresses a timed-out or inhibited probe even after the one-minute interval' {
    $inhibitions = @()
    (Test-DotfilesGuestProbeAllowed -Distribution FixtureDistro -Suppressed $true -Inhibitions $inhibitions -NowMilliseconds 120000 -LastAttemptMilliseconds 0) | Should -BeFalse
    $inhibitions = @(@{ source = 'guest'; processId = 1; startTimeTicks = 1; cleanupUnverified = $true })
    (Test-DotfilesGuestProbeAllowed -Distribution FixtureDistro -Suppressed $false -Inhibitions $inhibitions -NowMilliseconds 120000 -LastAttemptMilliseconds 0) | Should -BeFalse
    (Test-DotfilesGuestProbeAllowed -Distribution FixtureDistro -Suppressed $false -Inhibitions @() -NowMilliseconds 60000 -LastAttemptMilliseconds 0) | Should -BeTrue
  }

  It 'writes BOM-less UTF-8 and recovers a partial final record' {
    $directory = Join-Path $TestDrive 'logs'
    [void][IO.Directory]::CreateDirectory($directory)
    $runId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $path = Join-Path $directory "wsl-capture-20260101T000000Z-$runId.jsonl"
    [IO.File]::WriteAllText($path, "{`"complete`":true}`n{`"partial`":", [Text.UTF8Encoding]::new($false))

    Repair-DotfilesPartialLogs -Directory $directory -MaximumBytes 65536
    $bytes = [IO.File]::ReadAllBytes($path)
    $text = [Text.UTF8Encoding]::new($false).GetString($bytes)

    $bytes.Length | Should -BeGreaterThan 0
    $bytes[0] | Should -Not -Be 239
    $text | Should -Be "{`"complete`":true}`n"
  }

  It 'enforces the exact log-byte cap and includes temporary records in rotation' {
    $directory = Join-Path $TestDrive 'budget'
    [void][IO.Directory]::CreateDirectory($directory)
    $runId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    $path = Join-Path $directory "wsl-capture-20260101T000000Z-$runId.jsonl"
    $record = @{ schemaVersion = 1; recordType = 'host-sample'; runId = $runId; value = 'fixture' }
    $json = ConvertTo-Json -InputObject $record -Compress -Depth 4
    $exactBytes = $script:Utf8NoBom.GetByteCount($json + "`n")

    $written = Write-DotfilesLogRecord -Directory $directory -Path $path -Record $record -MaximumBytes $exactBytes -RunId $runId
    $written.Written | Should -BeTrue
    $written.Path | Should -Be $path
    (Get-Item -LiteralPath $path).Length | Should -Be $exactBytes
    $overBudget = Write-DotfilesLogRecord -Directory $directory -Path $path -Record $record -MaximumBytes $exactBytes -RunId $runId
    $overBudget.Written | Should -BeTrue
    $overBudget.Path | Should -Match '-0001\.jsonl$'
    Test-Path -LiteralPath $path | Should -BeFalse
    (Get-Item -LiteralPath $overBudget.Path).Length | Should -Be $exactBytes

    $segmentRecord = @{ schemaVersion = 1; recordType = 'host-sample'; runId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'; value = ('x' * 30000) }
    $segmentPath = Join-Path $directory "wsl-capture-20260102T000000Z-$runId-0000.jsonl"
    $firstSegment = Write-DotfilesLogRecord -Directory $directory -Path $segmentPath -Record $segmentRecord -MaximumBytes 65536 -RunId $runId
    $secondSegment = Write-DotfilesLogRecord -Directory $directory -Path $firstSegment.Path -Record $segmentRecord -MaximumBytes 65536 -RunId $runId
    $thirdSegment = Write-DotfilesLogRecord -Directory $directory -Path $secondSegment.Path -Record $segmentRecord -MaximumBytes 65536 -RunId $runId
    $thirdSegment.Written | Should -BeTrue
    $thirdSegment.Path | Should -Match '-0002\.jsonl$'
    Test-Path -LiteralPath $segmentPath | Should -BeFalse
    ((Get-DotfilesCollectorLogFiles -Directory $directory | Measure-Object -Property Length -Sum).Sum) | Should -BeLessOrEqual 65536

    $temporary = Join-Path $directory "wsl-capture-20250101T000000Z-cccccccccccccccccccccccccccccccc.jsonl.tmp"
    [IO.File]::WriteAllBytes($temporary, (New-Object byte[] 65536))
    $replacement = Join-Path $directory 'wsl-capture-20260102T000000Z-dddddddddddddddddddddddddddddddd.jsonl'
    $second = Write-DotfilesLogRecord -Directory $directory -Path $replacement -Record $record -MaximumBytes 65536 -RunId 'dddddddddddddddddddddddddddddddd'
    $second.Written | Should -BeTrue
    Test-Path -LiteralPath $temporary | Should -BeFalse
    ((Get-DotfilesCollectorLogFiles -Directory $directory | Measure-Object -Property Length -Sum).Sum) | Should -BeLessOrEqual 65536
  }

  It 'returns a sanitized result when the last log segment is full' {
    $directory = Join-Path $TestDrive 'segment-limit'
    [void][IO.Directory]::CreateDirectory($directory)
    $runId = 'abababababababababababababababab'
    $path = Join-Path $directory "wsl-capture-20260101T000000Z-$runId-9999.jsonl"
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.SetLength(32768) } finally { $stream.Dispose() }

    $result = Write-DotfilesLogRecord -Directory $directory -Path $path -Record @{ value = 1 } -MaximumBytes 65536 -RunId $runId

    $result.Written | Should -BeFalse
    $result.Error | Should -Be 'log-segment-limit'
    $result.Bytes | Should -Be 32768
    $result.Path | Should -Be $path
  }

  It 'deletes oversized matching logs before bounded partial-record repair' {
    $directory = Join-Path $TestDrive 'oversized-log'
    [void][IO.Directory]::CreateDirectory($directory)
    $path = Join-Path $directory 'wsl-capture-20260101T000000Z-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jsonl'
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.SetLength(65537) } finally { $stream.Dispose() }

    Repair-DotfilesPartialLogs -Directory $directory -MaximumBytes 65536

    Test-Path -LiteralPath $path | Should -BeFalse
  }

  It 'clears inhibition state when the accepted entry collection is empty' {
    $directory = Join-Path $TestDrive 'empty-inhibitions'
    [void][IO.Directory]::CreateDirectory($directory)
    $path = Join-Path $directory 'inhibitions.json'
    [IO.File]::WriteAllText($path, '[]', $script:Utf8NoBom)

    Write-DotfilesInhibitions -StateDirectory $directory -Entries @() -RunId 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

    Test-Path -LiteralPath $path | Should -BeFalse
  }

  It 'preserves a one-entry inhibition as a JSON array' {
    $state = Join-Path $TestDrive 'single-inhibition-state'
    [void][IO.Directory]::CreateDirectory($state)
    $current = [Diagnostics.Process]::GetCurrentProcess()
    try { $entry = @{ source = 'guest'; processId = $current.Id; startTimeTicks = $current.StartTime.ToUniversalTime().Ticks; cleanupUnverified = $true } }
    finally { $current.Dispose() }

    Write-DotfilesInhibitions -StateDirectory $state -Entries @($entry) -RunId 'dddddddddddddddddddddddddddddddd'
    $json = Get-Content -LiteralPath (Join-Path $state 'inhibitions.json') -Raw
    $entries = @(Read-DotfilesInhibitions -StateDirectory $state)

    $json.TrimStart().StartsWith('[') | Should -BeTrue
    $entries.Count | Should -Be 1
    $entries[0].source | Should -Be 'guest'
  }

  It 'journals a prelaunch placeholder and ignores only its own run marker' {
    $state = Join-Path $TestDrive 'worker-journal-state'
    [void][IO.Directory]::CreateDirectory($state)
    $entry = @{ source = 'guest'; processId = -1; startTimeTicks = 0; cleanupUnverified = $true; runId = 'active-run'; launchState = 'preflight' }

    Write-DotfilesInhibitions -StateDirectory $state -Entries @() -RunId 'active-run' -WorkerJournal @($entry)
    $sameRun = @(Read-DotfilesInhibitions -StateDirectory $state -CurrentRunId 'active-run')
    $newRun = @(Read-DotfilesInhibitions -StateDirectory $state -CurrentRunId 'next-run')

    $sameRun.Count | Should -Be 0
    $newRun.Count | Should -Be 1
    $newRun[0].source | Should -Be 'guest'
    $newRun[0].cleanupUnverified | Should -BeTrue
  }

  It 'converts an unknown inhibition source to a persistent wildcard' {
    $state = Join-Path $TestDrive 'unknown-inhibition-source'
    [void][IO.Directory]::CreateDirectory($state)
    $entry = @{ source = 'guest-worker'; processId = 456; startTimeTicks = 789; cleanupUnverified = $false }
    [IO.File]::WriteAllText((Join-Path $state 'inhibitions.json'), (ConvertTo-Json -InputObject ([object[]]@($entry)) -Compress), $script:Utf8NoBom)

    $entries = @(Read-DotfilesInhibitions -StateDirectory $state)

    $entries.Count | Should -Be 1
    $entries[0].source | Should -Be '*'
    $entries[0].cleanupUnverified | Should -BeTrue
    $entries[0].processId | Should -Be -1
  }

  It 'converts malformed inhibition identities to persistent wildcards' {
    $state = Join-Path $TestDrive 'malformed-inhibition-identities'
    [void][IO.Directory]::CreateDirectory($state)
    $fixtures = @(
      @{ source = 'cpu'; processId = -1; startTimeTicks = 10; cleanupUnverified = $false },
      @{ source = 'memory'; processId = 12; startTimeTicks = 0; cleanupUnverified = $false },
      @{ source = 'disk'; processId = 'not-a-pid'; startTimeTicks = 99; cleanupUnverified = $false }
    )
    [IO.File]::WriteAllText((Join-Path $state 'inhibitions.json'), (ConvertTo-Json -InputObject ([object[]]$fixtures) -Compress), $script:Utf8NoBom)

    $entries = @(Read-DotfilesInhibitions -StateDirectory $state)

    $entries.Count | Should -Be 3
    @($entries | Where-Object { $_.source -eq '*' -and $_.cleanupUnverified -and $_.processId -eq -1 }).Count | Should -Be 3
  }

  It 'replaces an existing inhibition file without dropping the new entry' {
    $state = Join-Path $TestDrive 'replace-inhibition-state'
    [void][IO.Directory]::CreateDirectory($state)
    $path = Join-Path $state 'inhibitions.json'
    $oldEntry = @{ source = 'cpu'; processId = 123; startTimeTicks = 456; cleanupUnverified = $true }
    $current = [Diagnostics.Process]::GetCurrentProcess()
    try { $newEntry = @{ source = 'guest'; processId = $current.Id; startTimeTicks = $current.StartTime.ToUniversalTime().Ticks; cleanupUnverified = $true } }
    finally { $current.Dispose() }

    Write-DotfilesInhibitions -StateDirectory $state -Entries @($oldEntry) -RunId 'ffffffffffffffffffffffffffffffff'
    Write-DotfilesInhibitions -StateDirectory $state -Entries @($newEntry) -RunId '11111111111111111111111111111111'

    $json = Get-Content -LiteralPath $path -Raw
    $entries = @(Read-DotfilesInhibitions -StateDirectory $state)
    $json.TrimStart().StartsWith('[') | Should -BeTrue
    $entries.Count | Should -Be 1
    $entries[0].source | Should -Be 'guest'
  }

  It 'preserves an existing inhibition if writing its replacement fails' {
    $state = Join-Path $TestDrive 'failed-replace-inhibition-state'
    [void][IO.Directory]::CreateDirectory($state)
    $path = Join-Path $state 'inhibitions.json'
    $runId = '22222222222222222222222222222222'
    $current = [Diagnostics.Process]::GetCurrentProcess()
    try { $oldEntry = @{ source = 'cpu'; processId = $current.Id; startTimeTicks = $current.StartTime.ToUniversalTime().Ticks; cleanupUnverified = $true } }
    finally { $current.Dispose() }
    $newEntry = @{ source = 'guest'; processId = 789; startTimeTicks = 101112; cleanupUnverified = $true }

    Write-DotfilesInhibitions -StateDirectory $state -Entries @($oldEntry) -RunId '33333333333333333333333333333333'
    [void][IO.Directory]::CreateDirectory((Join-Path $state ".inhibitions.$runId.tmp"))
    { Write-DotfilesInhibitions -StateDirectory $state -Entries @($newEntry) -RunId $runId } | Should -Throw

    $entries = @(Read-DotfilesInhibitions -StateDirectory $state)
    $entries.Count | Should -Be 1
    $entries[0].source | Should -Be 'cpu'
  }

  It 'retains an exited cleanup root when a live grandchild is linked through an exited intermediate' {
    $state = Join-Path $TestDrive 'reconciled-inhibition-state'
    [void][IO.Directory]::CreateDirectory($state)
    $entry = @{ source = 'guest'; processId = 100; startTimeTicks = 1000; exitTimeTicks = 2000; cleanupUnverified = $true }
    [IO.File]::WriteAllText((Join-Path $state 'inhibitions.json'), (ConvertTo-Json -InputObject ([object[]]@($entry)) -Compress), $script:Utf8NoBom)
    Mock Test-DotfilesExactProcessIdentity { return $false }
    Mock Get-DotfilesProcessStartTicks {
      param($ProcessId)
      if ($ProcessId -eq 300) { return 1500 }
      return $null
    }
    Mock Get-DotfilesProcessTreeSnapshot { return @([pscustomobject]@{ ProcessId = 300; ParentId = 200 }) }

    $entries = @(Read-DotfilesInhibitions -StateDirectory $state)

    $entries.Count | Should -Be 1
    $entries[0].cleanupUnverified | Should -BeTrue
  }

  It 'retains a wildcard cleanup root while a matching live child remains' {
    $state = Join-Path $TestDrive 'wildcard-inhibition-state'
    [void][IO.Directory]::CreateDirectory($state)
    $entry = @{ source = '*'; processId = 100; startTimeTicks = 1000; exitTimeTicks = 2000; cleanupUnverified = $true }
    [IO.File]::WriteAllText((Join-Path $state 'inhibitions.json'), (ConvertTo-Json -InputObject ([object[]]@($entry)) -Compress), $script:Utf8NoBom)
    Mock Get-DotfilesProcessStartTicks {
      param($ProcessId)
      if ($ProcessId -eq 200) { return 1500 }
      return $null
    }
    Mock Get-DotfilesProcessTreeSnapshot { return @([pscustomobject]@{ ProcessId = 200; ParentId = 100 }) }

    $entries = @(Read-DotfilesInhibitions -StateDirectory $state)

    $entries.Count | Should -Be 1
    $entries[0].source | Should -Be '*'
  }

  It 'retains an unresolved wildcard without a usable process identity' {
    $state = Join-Path $TestDrive 'unresolved-wildcard-state'
    [void][IO.Directory]::CreateDirectory($state)
    $entry = @{ source = '*'; processId = -1; startTimeTicks = 0; cleanupUnverified = $true }
    [IO.File]::WriteAllText((Join-Path $state 'inhibitions.json'), (ConvertTo-Json -InputObject ([object[]]@($entry)) -Compress), $script:Utf8NoBom)

    $entries = @(Read-DotfilesInhibitions -StateDirectory $state)

    $entries.Count | Should -Be 1
    $entries[0].source | Should -Be '*'
  }

  It 'replaces an oversized record with a safe overflow marker' {
    $directory = Join-Path $TestDrive 'overflow'
    [void][IO.Directory]::CreateDirectory($directory)
    $runId = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
    $path = Join-Path $directory "wsl-capture-20260101T000000Z-$runId.jsonl"
    $record = @{ schemaVersion = 1; recordType = 'host-sample'; runId = $runId; secret = ('fixture-secret-' * 4000) }

    $result = Write-DotfilesLogRecord -Directory $directory -Path $path -Record $record -MaximumBytes 65536 -RunId $runId
    $saved = Get-Content -LiteralPath $path -Raw

    $result.Written | Should -BeTrue
    $saved | Should -Match '"status":"overflow"'
    $saved | Should -Not -Match 'fixture-secret'
    ([IO.File]::ReadAllBytes($path)).Length | Should -BeLessThan 32768
  }

  It 'returns a sanitized write failure when the target cannot be opened as a file' {
    $directory = Join-Path $TestDrive 'write-failure'
    [void][IO.Directory]::CreateDirectory($directory)
    $result = Write-DotfilesLogRecord -Directory $directory -Path $directory -Record @{ value = 1 } -MaximumBytes 65536 -RunId 'ffffffffffffffffffffffffffffffff'

    $result.Written | Should -BeFalse
    $result.Error | Should -Be 'log-write-failed'
  }

  It 'ends cleanly when the log segment limit is reached' {
    $script:FixtureState = Join-Path $TestDrive 'segment-limit-state'
    $script:FixtureOutput = Join-Path $TestDrive 'segment-limit-output'
    $script:FakeClock = 0.0
    $script:InitializationOrder = New-Object System.Collections.ArrayList
    $script:ClockProvider = { [double]$script:FakeClock }
    $script:SleepProvider = { param($Milliseconds) $script:FakeClock += $Milliseconds }
    Mock Test-DotfilesWindowsHost { return $true }
    Mock Initialize-DotfilesPrivateDirectory {
      param($Path)
      [void][IO.Directory]::CreateDirectory($Path)
      return $Path
    }
    Mock Get-DotfilesDefaultStateDirectory { return $script:FixtureState }
    Mock Enter-DotfilesCollectorLock {
      [void]$script:InitializationOrder.Add('lock')
      return @{ Acquired = $true; Reason = $null; Handle = $null; MetadataPath = $null; RunId = 'fixture' }
    }
    Mock Exit-DotfilesCollectorLock { }
    Mock Initialize-DotfilesBoundedStreamReader { [void]$script:InitializationOrder.Add('bounded-stream') }
    Mock Initialize-DotfilesProcessTree { [void]$script:InitializationOrder.Add('process-tree') }
    Mock Start-DotfilesHostWorker {
      param($Source)
      [void]$script:InitializationOrder.Add('worker')
      $fake = [pscustomobject]@{ Id = 6000; HasExited = $true }
      Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value {}
      return @{ Source = $Source; Process = $fake; ProcessId = 6000; StartTimeTicks = 6000 }
    }
    Mock Get-DotfilesWorkerResult {
      param($Owned)
      return @{ source = $Owned.Source; status = 'unavailable'; error = 'counter-unavailable'; metrics = @{} }
    }
    Mock Write-DotfilesLogRecord {
      return @{ Written = $false; Error = 'log-segment-limit'; Bytes = 32768; Path = 'segment-9999.jsonl' }
    }

    try {
      $exitCode = Invoke-DotfilesIncidentCollector -IntervalSeconds 1 -DurationSeconds 2 -MaximumLogBytes 65536 -OutputDirectory $script:FixtureOutput -GuestDistro ''
    }
    finally {
      $script:ClockProvider = $null
      $script:SleepProvider = $null
    }

    $exitCode | Should -Be 0
    @($script:InitializationOrder | Select-Object -First 4) | Should -Be @('lock', 'bounded-stream', 'process-tree', 'worker')
    Should -Invoke Write-DotfilesLogRecord -Times 1 -Exactly
    Test-Path -LiteralPath (Join-Path $script:FixtureState 'collector.lock.json') | Should -BeFalse
    Remove-Variable InitializationOrder -Scope Script -ErrorAction SilentlyContinue
  }

  It 'fails closed when a child PID is reused under another parent after the first snapshot' {
    $exe = Get-DotfilesPowerShellExecutable
    $owned = Start-DotfilesOwnedProcess -FileName $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'fixture'
    $sentinel = Start-DotfilesOwnedProcess -FileName $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'sentinel'
    $current = [Diagnostics.Process]::GetCurrentProcess()
    try { $script:ReplacementParentId = $current.Id } finally { $current.Dispose() }
    $script:TreeSnapshotCall = 0
    $script:TreeSnapshotOwnedId = $owned.ProcessId
    $script:TreeSnapshotChildId = $sentinel.ProcessId
    Mock Get-DotfilesProcessTreeSnapshot {
      $script:TreeSnapshotCall++
      $parentId = if ($script:TreeSnapshotCall -eq 1) { $script:TreeSnapshotOwnedId } else { $script:ReplacementParentId }
      return @([pscustomobject]@{ ProcessId = $script:TreeSnapshotChildId; ParentId = $parentId })
    }

    try {
      $tree = Get-DotfilesVerifiedProcessTree -Owned $owned

      $tree.Complete | Should -BeFalse
      $tree.Processes.Count | Should -Be 0
      $sentinel.Process.HasExited | Should -BeFalse
    }
    finally {
      if (-not $sentinel.Process.HasExited) { $sentinel.Process.Kill(); $null = $sentinel.Process.WaitForExit(3000) }
      if (-not $owned.Process.HasExited) { $owned.Process.Kill(); $null = $owned.Process.WaitForExit(3000) }
      $sentinel.Process.Dispose()
      $owned.Process.Dispose()
      Remove-Variable TreeSnapshotCall, TreeSnapshotOwnedId, TreeSnapshotChildId, ReplacementParentId -Scope Script -ErrorAction SilentlyContinue
    }
  }

  It 'fails closed when a captured child exits before a later descendant snapshot' {
    $exe = Get-DotfilesPowerShellExecutable
    $owned = Start-DotfilesOwnedProcess -FileName $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'fixture'
    $vanished = Start-DotfilesOwnedProcess -FileName $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'exit 0') -Source 'vanished-child'
    $sentinel = Start-DotfilesOwnedProcess -FileName $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'late-descendant'
    $vanished.Process.WaitForExit(10000) | Should -BeTrue
    $script:VanishedSnapshotCall = 0
    $script:VanishedChildId = $vanished.ProcessId
    $script:VanishedRootId = $owned.ProcessId
    $script:LateDescendantId = $sentinel.ProcessId
    Mock Get-DotfilesProcessTreeSnapshot {
      $script:VanishedSnapshotCall++
      if ($script:VanishedSnapshotCall -eq 1) {
        return @([pscustomobject]@{ ProcessId = $script:VanishedChildId; ParentId = $script:VanishedRootId })
      }
      return @([pscustomobject]@{ ProcessId = $script:LateDescendantId; ParentId = $script:VanishedChildId })
    }

    try {
      $tree = Get-DotfilesVerifiedProcessTree -Owned $owned

      $tree.Complete | Should -BeFalse
      $tree.Processes.Count | Should -Be 0
      $sentinel.Process.HasExited | Should -BeFalse
    }
    finally {
      if (-not $sentinel.Process.HasExited) { $sentinel.Process.Kill(); $null = $sentinel.Process.WaitForExit(3000) }
      if (-not $owned.Process.HasExited) { $owned.Process.Kill(); $null = $owned.Process.WaitForExit(3000) }
      $sentinel.Process.Dispose()
      $vanished.Process.Dispose()
      $owned.Process.Dispose()
      Remove-Variable VanishedSnapshotCall, VanishedChildId, VanishedRootId, LateDescendantId -Scope Script -ErrorAction SilentlyContinue
    }
  }

  It 'accepts a verified child that exits before recheck when no descendant remains' {
    $exe = Get-DotfilesPowerShellExecutable
    $owned = Start-DotfilesOwnedProcess -FileName $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'fixture'
    $child = Start-DotfilesOwnedProcess -FileName $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'child'
    $script:RecheckSnapshotCall = 0
    $script:RecheckOwnedId = $owned.ProcessId
    $script:RecheckChildId = $child.ProcessId
    $script:RecheckChildProcess = $child.Process
    Mock Get-DotfilesProcessTreeSnapshot {
      $script:RecheckSnapshotCall++
      if ($script:RecheckSnapshotCall -eq 1) {
        return @([pscustomobject]@{ ProcessId = $script:RecheckChildId; ParentId = $script:RecheckOwnedId })
      }
      if (-not $script:RecheckChildProcess.HasExited) {
        $script:RecheckChildProcess.Kill()
        $null = $script:RecheckChildProcess.WaitForExit(3000)
      }
      return @()
    }

    try {
      $tree = Get-DotfilesVerifiedProcessTree -Owned $owned

      $tree.Complete | Should -BeTrue
      $tree.Processes.Count | Should -Be 2
      $child.Process.HasExited | Should -BeTrue
    }
    finally {
      if (-not $child.Process.HasExited) { $child.Process.Kill(); $null = $child.Process.WaitForExit(3000) }
      if (-not $owned.Process.HasExited) { $owned.Process.Kill(); $null = $owned.Process.WaitForExit(3000) }
      $child.Process.Dispose()
      $owned.Process.Dispose()
      Remove-Variable RecheckSnapshotCall, RecheckOwnedId, RecheckChildId, RecheckChildProcess -Scope Script -ErrorAction SilentlyContinue
    }
  }

  It 'ignores a stale child link whose process started before the owned parent' {
    $exe = Get-DotfilesPowerShellExecutable
    $owned = Start-DotfilesOwnedProcess -FileName $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'fixture'
    $current = [Diagnostics.Process]::GetCurrentProcess()
    $script:StaleLinkPid = $current.Id
    $script:StaleLinkParentId = $owned.ProcessId
    Mock Get-DotfilesProcessTreeSnapshot {
      return @([pscustomobject]@{ ProcessId = $script:StaleLinkPid; ParentId = $script:StaleLinkParentId })
    }

    try {
      $tree = Get-DotfilesVerifiedProcessTree -Owned $owned

      $tree.Complete | Should -BeTrue
      $tree.Processes.Count | Should -Be 1
      $current.HasExited | Should -BeFalse
    }
    finally {
      if (-not $owned.Process.HasExited) { $owned.Process.Kill(); $null = $owned.Process.WaitForExit(3000) }
      $owned.Process.Dispose()
      $current.Dispose()
      Remove-Variable StaleLinkPid, StaleLinkParentId -Scope Script -ErrorAction SilentlyContinue
    }
  }

  It 'does not inhibit cleanup for an unchanged verified stale child link' {
    $exe = Get-DotfilesPowerShellExecutable
    $owned = Start-DotfilesOwnedProcess -FileName $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'fixture'
    $current = [Diagnostics.Process]::GetCurrentProcess()
    $script:StaleCleanupSnapshotCall = 0
    $script:StaleCleanupParentId = $owned.ProcessId
    $script:StaleCleanupChildId = $current.Id
    Mock Get-DotfilesProcessTreeSnapshot {
      $script:StaleCleanupSnapshotCall++
      return @([pscustomobject]@{ ProcessId = $script:StaleCleanupChildId; ParentId = $script:StaleCleanupParentId })
    }

    try {
      $cleanup = Stop-DotfilesOwnedProcess -Owned $owned -GraceMilliseconds 3000

      $cleanup.Exited | Should -BeTrue
      $cleanup.CleanupUnverified | Should -BeFalse
      $script:StaleCleanupSnapshotCall | Should -Be 3
      $current.HasExited | Should -BeFalse
    }
    finally {
      if ($true -eq (Test-DotfilesExactProcessIdentity -ProcessId $owned.ProcessId -StartTimeTicks $owned.StartTimeTicks)) {
        $remaining = [Diagnostics.Process]::GetProcessById($owned.ProcessId)
        try {
          if (-not $remaining.HasExited) { $remaining.Kill(); $null = $remaining.WaitForExit(3000) }
        }
        finally { $remaining.Dispose() }
      }
      $current.Dispose()
      Remove-Variable StaleCleanupSnapshotCall, StaleCleanupParentId, StaleCleanupChildId -Scope Script -ErrorAction SilentlyContinue
    }
  }

  It 'trusts a live retained handle when its start time cannot be read' {
    $unreadable = [pscustomobject]@{ HasExited = $false }
    $exited = [pscustomobject]@{ HasExited = $true }
    $current = [Diagnostics.Process]::GetCurrentProcess()
    try {
      Test-DotfilesRetainedProcessIdentity -Process $unreadable -StartTimeTicks 1 | Should -BeTrue
      Test-DotfilesRetainedProcessIdentity -Process $exited -StartTimeTicks 1 | Should -BeFalse
      Test-DotfilesRetainedProcessIdentity -Process $current -StartTimeTicks 1 | Should -BeFalse
      Test-DotfilesRetainedProcessIdentity -Process $current -StartTimeTicks $current.StartTime.ToUniversalTime().Ticks | Should -BeTrue
    }
    finally { $current.Dispose() }
  }

  It 'stops a live root when reopening its start time is ambiguous' {
    $exe = Get-DotfilesPowerShellExecutable
    $sleepArguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30')
    $sentinel = Start-DotfilesOwnedProcess -FileName $exe -Arguments $sleepArguments -Source 'sentinel'
    $owned = Start-DotfilesOwnedProcess -FileName $exe -Arguments $sleepArguments -Source 'fixture'
    Mock Get-DotfilesProcessTreeSnapshot { return @() }
    Mock Get-DotfilesProcessStartTicks { return 'ambiguous' }
    try {
      $owned.Process.WaitForExit(100) | Should -BeFalse
      $cleanup = Stop-DotfilesOwnedProcess -Owned $owned -GraceMilliseconds 3000
      $cleanup.Exited | Should -BeTrue
      $cleanup.CleanupUnverified | Should -BeFalse
      $sentinel.Process.HasExited | Should -BeFalse
    }
    finally {
      if (-not $sentinel.Process.HasExited) { $sentinel.Process.Kill(); $null = $sentinel.Process.WaitForExit(3000) }
      $sentinel.Process.Dispose()
      try {
        $leftover = [Diagnostics.Process]::GetProcessById($owned.ProcessId)
        try {
          if ($leftover.StartTime.ToUniversalTime().Ticks -eq [long]$owned.StartTimeTicks -and -not $leftover.HasExited) {
            $leftover.Kill()
            $null = $leftover.WaitForExit(3000)
          }
        }
        finally { $leftover.Dispose() }
      }
      catch {
        # The fixture root already exited, or its identity cannot be confirmed.
      }
      try { $owned.Process.Dispose() } catch { }
    }
  }

  It 'persists cleanup inhibition when a new process appears under an owned PID after enumeration' {
    $exe = Get-DotfilesPowerShellExecutable
    $owned = Start-DotfilesOwnedProcess -FileName $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'fixture'
    $lateChild = Start-DotfilesOwnedProcess -FileName $exe -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'late-child'
    $script:CleanupSnapshotCall = 0
    $script:CleanupOwnedId = $owned.ProcessId
    $script:CleanupLateChildId = $lateChild.ProcessId
    Mock Get-DotfilesProcessTreeSnapshot {
      $script:CleanupSnapshotCall++
      if ($script:CleanupSnapshotCall -le 2) { return @() }
      return @([pscustomobject]@{ ProcessId = $script:CleanupLateChildId; ParentId = $script:CleanupOwnedId })
    }

    try {
      $cleanup = Stop-DotfilesOwnedProcess -Owned $owned -GraceMilliseconds 3000

      $cleanup.Exited | Should -BeFalse
      $cleanup.CleanupUnverified | Should -BeTrue
      @($cleanup.Entries | Where-Object { $_.processId -eq $script:CleanupOwnedId -and $_.cleanupUnverified }).Count | Should -Be 1
      $lateChild.Process.HasExited | Should -BeFalse
    }
    finally {
      if (-not $lateChild.Process.HasExited) { $lateChild.Process.Kill(); $null = $lateChild.Process.WaitForExit(3000) }
      $ownedCleanup = $null
      try {
        $ownedCleanup = [Diagnostics.Process]::GetProcessById($owned.ProcessId)
        if ($ownedCleanup.StartTime.ToUniversalTime().Ticks -eq [long]$owned.StartTimeTicks -and -not $ownedCleanup.HasExited) {
          $ownedCleanup.Kill()
          $null = $ownedCleanup.WaitForExit(3000)
        }
      }
      catch { }
      finally { if ($null -ne $ownedCleanup) { $ownedCleanup.Dispose() } }
      $lateChild.Process.Dispose()
      $owned.Process.Dispose()
      Remove-Variable CleanupSnapshotCall, CleanupOwnedId, CleanupLateChildId -Scope Script -ErrorAction SilentlyContinue
    }
  }

  It 'rejects non-Windows execution before creating state' -Skip:$script:WindowsHost {
    $exe = (Get-Command pwsh -ErrorAction Stop).Source
    $stateBase = Join-Path $TestDrive 'state'
    $priorLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'Process')
    try {
      $env:LOCALAPPDATA = $stateBase
      $process = Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-File', $script:CollectorPath) -PassThru -Wait
    }
    finally {
      if ($null -eq $priorLocalAppData) { Remove-Item Env:\LOCALAPPDATA -ErrorAction SilentlyContinue }
      else { $env:LOCALAPPDATA = $priorLocalAppData }
    }
    $process.ExitCode | Should -Be 2
    Test-Path -LiteralPath $stateBase | Should -BeFalse
  }
}

Describe 'wsl incident capture option validation' {
  It 'rejects zero duration before creating state' {
    Mock Test-DotfilesWindowsHost { return $true }
    Mock Initialize-DotfilesPrivateDirectory { throw 'state must not be created' }

    $exitCode = Invoke-DotfilesIncidentCollector -IntervalSeconds 5 -DurationSeconds 0 -MaximumLogBytes 65536 -OutputDirectory '' -GuestDistro ''

    $exitCode | Should -Be 2
    Should -Invoke Initialize-DotfilesPrivateDirectory -Times 0 -Exactly
  }
}

Describe 'wsl incident output directory paths' {
  It 'resolves relative output paths against the PowerShell FileSystem location' {
    $root = Join-Path $TestDrive 'relative-output-base'
    $currentPath = Join-Path $root 'current'
    [void][IO.Directory]::CreateDirectory($currentPath)
    $driveName = 'Incident' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $originalLocation = Get-Location
    New-PSDrive -Name $driveName -PSProvider FileSystem -Root $root | Out-Null

    try {
      Set-Location -LiteralPath ('{0}:\current' -f $driveName)
      $resolved = Resolve-DotfilesOutputDirectoryPath -Path 'logs'
      $driveRelative = Resolve-DotfilesOutputDirectoryPath -Path ('{0}:logs' -f $driveName)

      $resolved | Should -Be ([IO.Path]::GetFullPath((Join-Path $currentPath 'logs')))
      $driveRelative | Should -Be $resolved
    }
    finally {
      Set-Location -LiteralPath $originalLocation.Path
      Remove-PSDrive -Name $driveName -ErrorAction SilentlyContinue
    }
  }

  It 'resolves a root-relative path against the current PowerShell drive' -Skip:(!$script:WindowsHost) {
    $root = Join-Path $TestDrive 'root-relative-output-base'
    $currentPath = Join-Path $root 'current'
    [void][IO.Directory]::CreateDirectory($currentPath)
    $driveName = 'Incident' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $originalLocation = Get-Location
    New-PSDrive -Name $driveName -PSProvider FileSystem -Root $root | Out-Null

    try {
      Set-Location -LiteralPath ('{0}:\current' -f $driveName)
      $resolved = Resolve-DotfilesOutputDirectoryPath -Path '\logs'

      $resolved | Should -Be ([IO.Path]::GetFullPath((Join-Path $root 'logs')))
    }
    finally {
      Set-Location -LiteralPath $originalLocation.Path
      Remove-PSDrive -Name $driveName -ErrorAction SilentlyContinue
    }
  }

  It 'rejects a path qualified for a non-FileSystem provider' {
    { Resolve-DotfilesOutputDirectoryPath -Path 'Env:PATH' } | Should -Throw
  }

  It 'accepts a UNC share root from a non-FileSystem location' -Skip:(!$script:WindowsHost) {
    $originalLocation = Get-Location
    $uncPath = '\\server\share'

    try {
      Set-Location -LiteralPath 'Env:'
      $resolved = Resolve-DotfilesOutputDirectoryPath -Path $uncPath

      $resolved | Should -Be ([IO.Path]::GetFullPath($uncPath))
    }
    finally { Set-Location -LiteralPath $originalLocation.Path }
  }
}

Describe 'wsl incident guest probe startup' {
  It 'propagates unresolved owned-process cleanup from a failed launch' {
    $script:GuestLaunchException = New-Object InvalidOperationException('guest-stdin-write-failed')
    $script:GuestLaunchException.Data['DotfilesOwnedProcessMayRemain'] = $true
    $script:GuestLaunchException.Data['DotfilesOwnedProcessCleanupEntries'] = [object[]]@(@{
        source = 'guest'
        processId = 12345
        startTimeTicks = 67890
        cleanupUnverified = $true
      })
    Mock Get-DotfilesWslExecutable { return 'wsl.exe' }
    Mock Invoke-DotfilesWslPreflight { return @{ Status = 'running'; Error = $null } }
    Mock Start-DotfilesCommand { throw $script:GuestLaunchException }

    try {
      $result = Start-DotfilesGuestProbe -Distribution 'FixtureDistro' -PreviousCounters 'baseline'

      $result.Status | Should -Be 'unavailable'
      $result.Error | Should -Be 'guest-start-failed'
      $result.Cleanup.Exited | Should -BeFalse
      $result.Cleanup.Entries.Count | Should -Be 1
      $result.Cleanup.Entries[0].processId | Should -Be 12345
    }
    finally { Remove-Variable GuestLaunchException -Scope Script -ErrorAction SilentlyContinue }
  }

  It 'preserves the unresolved-start signal when cleanup identity is unavailable' {
    $script:GuestLaunchException = New-Object InvalidOperationException('guest-stdin-write-failed')
    $script:GuestLaunchException.Data['DotfilesOwnedProcessMayRemain'] = $true
    Mock Get-DotfilesWslExecutable { return 'wsl.exe' }
    Mock Invoke-DotfilesWslPreflight { return @{ Status = 'running'; Error = $null } }
    Mock Start-DotfilesCommand { throw $script:GuestLaunchException }

    try {
      $result = Start-DotfilesGuestProbe -Distribution 'FixtureDistro' -PreviousCounters 'baseline'

      $result.Cleanup.Exited | Should -BeFalse
      $result.Cleanup.Entries.Count | Should -Be 0
    }
    finally { Remove-Variable GuestLaunchException -Scope Script -ErrorAction SilentlyContinue }
  }
}

Describe 'wsl incident collector lock' {
  It 'replaces stale metadata once the exclusive lock is held by a live recorded owner' {
    $state = Join-Path $TestDrive 'live-owner-lock-state'
    [void][IO.Directory]::CreateDirectory($state)
    $metadataPath = Join-Path $state 'collector.lock.json'
    $current = [Diagnostics.Process]::GetCurrentProcess()
    try {
      $marker = @{
        processId = $current.Id
        startTimeTicks = $current.StartTime.ToUniversalTime().Ticks
        runId = 'old-live-run'
        acquiredAtUtc = '2026-01-01T00:00:00Z'
      } | ConvertTo-Json -Compress
      [IO.File]::WriteAllText($metadataPath, $marker, $script:Utf8NoBom)
    }
    finally { $current.Dispose() }

    $lock = $null
    $restart = $null
    try {
      $lock = Enter-DotfilesCollectorLock -StateDirectory $state -RunId '11111111111111111111111111111111'

      $lock.Acquired | Should -BeTrue
      $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
      $metadata.runId | Should -Be '11111111111111111111111111111111'
      $second = Enter-DotfilesCollectorLock -StateDirectory $state -RunId '22222222222222222222222222222222'
      $second.Acquired | Should -BeFalse
      $second.Reason | Should -Be 'already-running'
      $lock.Handle.Dispose()
      $lock.Handle = $null
      $current = [Diagnostics.Process]::GetCurrentProcess()
      try {
        $stale = @{
          processId = $current.Id
          startTimeTicks = $current.StartTime.ToUniversalTime().Ticks
          runId = 'old-live-run'
          acquiredAtUtc = '2026-01-01T00:00:00Z'
        } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($metadataPath, $stale, $script:Utf8NoBom)
      }
      finally { $current.Dispose() }
      $restart = Enter-DotfilesCollectorLock -StateDirectory $state -RunId '33333333333333333333333333333333'
      $restart.Acquired | Should -BeTrue
      $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
      $metadata.runId | Should -Be '33333333333333333333333333333333'
    }
    finally {
      if ($null -ne $restart) { Exit-DotfilesCollectorLock -Lock $restart }
      if ($null -ne $lock -and $null -ne $lock.Handle) { Exit-DotfilesCollectorLock -Lock $lock }
    }
  }

  It 'fails closed when the recorded lock owner identity is ambiguous' {
    $state = Join-Path $TestDrive 'ambiguous-owner-lock-state'
    [void][IO.Directory]::CreateDirectory($state)
    $marker = @{ processId = 123; startTimeTicks = 456; runId = 'old-run'; acquiredAtUtc = '2026-01-01T00:00:00Z' } | ConvertTo-Json -Compress
    $path = Join-Path $state 'collector.lock.json'
    [IO.File]::WriteAllText($path, $marker, $script:Utf8NoBom)
    Mock Test-DotfilesExactProcessIdentity { return $null }

    $lock = Enter-DotfilesCollectorLock -StateDirectory $state -RunId '11111111111111111111111111111111'

    $lock.Acquired | Should -BeFalse
    $lock.Reason | Should -Be 'lock-metadata-ambiguous'
    (Get-Content -LiteralPath $path -Raw) | Should -Be $marker
  }
}

Describe 'wsl incident collector lock failure handling' {
  It 'classifies only sharing and lock violations as active collectors' {
    $otherFailure = New-Object IO.IOException('unrelated I/O failure')

    if ([IO.Path]::DirectorySeparatorChar -eq '\') {
      $sharingViolation = New-Object IO.IOException('sharing violation', 32)
      $lockViolation = New-Object IO.IOException('lock violation', 33)
    }
    else {
      $sharingViolation = New-Object IO.IOException('resource temporarily unavailable', 11)
      $lockViolation = New-Object IO.IOException('resource temporarily unavailable', 35)
    }

    (Get-DotfilesLockFailureReason -Exception $sharingViolation) | Should -Be 'already-running'
    (Get-DotfilesLockFailureReason -Exception $lockViolation) | Should -Be 'already-running'
    (Get-DotfilesLockFailureReason -Exception $otherFailure) | Should -Be 'lock-state-unavailable'
  }

  It 'treats only an active collector as a successful no-op' {
    $script:FixtureState = Join-Path $TestDrive 'lock-failure-state'
    $script:LockFailureReason = 'already-running'
    Mock Test-DotfilesWindowsHost { return $true }
    Mock Initialize-DotfilesPrivateDirectory {
      param($Path)
      [void][IO.Directory]::CreateDirectory($Path)
      return $Path
    }
    Mock Get-DotfilesDefaultStateDirectory { return $script:FixtureState }
    Mock Enter-DotfilesCollectorLock {
      return @{ Acquired = $false; Reason = $script:LockFailureReason; Handle = $null }
    }

    try {
      $alreadyRunning = Invoke-DotfilesIncidentCollector -IntervalSeconds 1 -DurationSeconds 1 -MaximumLogBytes 65536 -OutputDirectory '' -GuestDistro ''
      $script:LockFailureReason = 'lock-metadata-ambiguous'
      $lockFailure = Invoke-DotfilesIncidentCollector -IntervalSeconds 1 -DurationSeconds 1 -MaximumLogBytes 65536 -OutputDirectory '' -GuestDistro ''

      $alreadyRunning | Should -Be 0
      $lockFailure | Should -Be 1
      $script:LockFailureReason = 'lock-state-unavailable'
      $ioFailure = Invoke-DotfilesIncidentCollector -IntervalSeconds 1 -DurationSeconds 1 -MaximumLogBytes 65536 -OutputDirectory '' -GuestDistro ''
      $ioFailure | Should -Be 1
    }
    finally { Remove-Variable FixtureState, LockFailureReason -Scope Script -ErrorAction SilentlyContinue }
  }
}

if ($script:WindowsHost) {
  Describe 'wsl incident capture Windows coordination' {
  It 'streams CIM instances with a fixed retention bound and finds a late target' {
    Mock Get-CimInstance {
      param($Filter)
      if ($Filter) { return [pscustomobject]@{ Name = '_Total' } }
      1..40 | ForEach-Object {
        $script:CimInstancesSeen++
        [pscustomobject]@{ Name = "instance-$_" }
      }
    }

    $script:CimInstancesSeen = 0
    $query = Get-DotfilesCimInstances -ClassName 'FixtureClass'
    $target = Get-DotfilesCimInstances -ClassName 'FixtureClass' -TargetName '_Total'

    $query.Items.Count | Should -Be 16
    $query.OverflowCount | Should -Be 1
    $script:CimInstancesSeen | Should -Be 17
    $target.TargetItem.Name | Should -Be '_Total'
  }

  It 'persists worker ownership before launch and keeps host-only capture available after restart' {
    $script:FixtureState = Join-Path $TestDrive 'restart-journal-state'
    $script:FixtureOutput = Join-Path $TestDrive 'restart-journal-output'
    $script:FakeClock = 0.0
    $script:ClockProvider = { [double]$script:FakeClock }
    $script:SleepProvider = { param($Milliseconds) $script:FakeClock += $Milliseconds }
    $script:GuestStartCount = 0
    [void][IO.Directory]::CreateDirectory($script:FixtureState)
    $oldGuest = @{ source = 'guest'; processId = 123456; startTimeTicks = 987654; cleanupUnverified = $true; runId = 'previous-run'; launchState = 'running' }
    Write-DotfilesInhibitions -StateDirectory $script:FixtureState -Entries @($oldGuest) -RunId 'previous-run'
    Mock Test-DotfilesWindowsHost { return $true }
    Mock Get-DotfilesDefaultStateDirectory { return $script:FixtureState }
    Mock Initialize-DotfilesPrivateDirectory {
      param($Path)
      [void][IO.Directory]::CreateDirectory($Path)
      return $Path
    }
    Mock Start-DotfilesHostWorker {
      param($Source)
      $persisted = @(Get-Content -LiteralPath (Join-Path $script:FixtureState 'inhibitions.json') -Raw | ConvertFrom-Json)
      $placeholder = @($persisted | Where-Object { $_.source -eq $Source -and $_.processId -eq -1 -and $_.startTimeTicks -eq 0 -and $_.launchState -eq 'starting' })
      if ($placeholder.Count -ne 1) { throw 'worker-journal-not-durable-before-launch' }
      $fake = [pscustomobject]@{ Id = 1000; HasExited = $true }
      Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value {}
      return @{ Source = $Source; Process = $fake; ProcessId = 1000; StartTimeTicks = 2000 }
    }
    Mock Get-DotfilesWorkerResult {
      param($Owned)
      return @{ source = $Owned.Source; status = 'unavailable'; error = 'counter-unavailable'; metrics = @{} }
    }
    Mock Start-DotfilesGuestProbe {
      $script:GuestStartCount++
      throw 'guest-probe-started-despite-persisted-inhibition'
    }

    try {
      $exitCode = Invoke-DotfilesIncidentCollector -IntervalSeconds 1 -DurationSeconds 1 -MaximumLogBytes 65536 -OutputDirectory $script:FixtureOutput -GuestDistro 'FixtureDistro'
    }
    finally {
      $script:ClockProvider = $null
      $script:SleepProvider = $null
    }

    $exitCode | Should -Be 0
    $script:GuestStartCount | Should -Be 0
    $path = Get-ChildItem -LiteralPath (Join-Path $script:FixtureOutput 'dotfiles-wsl-incident-telemetry') -Filter '*.jsonl' | Select-Object -First 1
    $records = @(Get-Content -LiteralPath $path.FullName | ForEach-Object { $_ | ConvertFrom-Json })
    $records.Count | Should -BeGreaterThan 0
    $records[0].host.cpu.status | Should -Be 'unavailable'
    $records[0].guest.error | Should -Be 'inhibited'
    $persisted = @(Get-Content -LiteralPath (Join-Path $script:FixtureState 'inhibitions.json') -Raw | ConvertFrom-Json)
    @($persisted | Where-Object { $_.source -eq 'guest' -and $_.runId -eq 'previous-run' }).Count | Should -Be 1
  }

  It 'serializes per-user starts across output paths and reconciles a reused PID' {
    $state = Join-Path $TestDrive 'lock-state'
    [void][IO.Directory]::CreateDirectory($state)
    $current = [Diagnostics.Process]::GetCurrentProcess()
    try {
      $ticks = $current.StartTime.ToUniversalTime().Ticks
      $marker = @{ processId = $current.Id; startTimeTicks = $ticks - 10000000; runId = 'old-run'; acquiredAtUtc = '2026-01-01T00:00:00Z' } | ConvertTo-Json -Compress
      [IO.File]::WriteAllText((Join-Path $state 'collector.lock.json'), $marker, $script:Utf8NoBom)
    }
    finally { $current.Dispose() }

    $first = Enter-DotfilesCollectorLock -StateDirectory $state -RunId '11111111111111111111111111111111'
    $first.Acquired | Should -BeTrue
    $second = Enter-DotfilesCollectorLock -StateDirectory $state -RunId '22222222222222222222222222222222'
    $second.Acquired | Should -BeFalse
    $second.Reason | Should -Be 'already-running'
    Exit-DotfilesCollectorLock -Lock $first
  }

  It 'retains unresolved process identities across a restart and clears only verified exits' {
    $state = Join-Path $TestDrive 'inhibition-state'
    [void][IO.Directory]::CreateDirectory($state)
    $current = [Diagnostics.Process]::GetCurrentProcess()
    try {
      $entry = @{ source = 'guest'; processId = $current.Id; startTimeTicks = $current.StartTime.ToUniversalTime().Ticks; cleanupUnverified = $false }
    }
    finally { $current.Dispose() }
    $inhibitionJson = ConvertTo-Json -InputObject ([object[]]@($entry)) -Compress
    [IO.File]::WriteAllText((Join-Path $state 'inhibitions.json'), $inhibitionJson, $script:Utf8NoBom)

    $readEntries = @(Read-DotfilesInhibitions -StateDirectory $state)
    $readEntries.Count | Should -Be 1
    $entry.cleanupUnverified = $true
    $inhibitionJson = ConvertTo-Json -InputObject ([object[]]@($entry)) -Compress
    [IO.File]::WriteAllText((Join-Path $state 'inhibitions.json'), $inhibitionJson, $script:Utf8NoBom)
    $readEntries = @(Read-DotfilesInhibitions -StateDirectory $state)
    $readEntries.Count | Should -Be 1

    $entry.cleanupUnverified = $false
    $entry.startTimeTicks = 1
    $inhibitionJson = ConvertTo-Json -InputObject ([object[]]@($entry)) -Compress
    [IO.File]::WriteAllText((Join-Path $state 'inhibitions.json'), $inhibitionJson, $script:Utf8NoBom)
    $readEntries = @(Read-DotfilesInhibitions -StateDirectory $state)
    $readEntries.Count | Should -Be 0
  }

  It 'rejects a reparse-point path segment before file writes' {
    $target = Join-Path $TestDrive 'reparse-target'
    $junction = Join-Path $TestDrive 'reparse-link'
    [void][IO.Directory]::CreateDirectory($target)
    New-Item -ItemType Junction -Path $junction -Target $target | Out-Null
    try {
      { Get-DotfilesSafePath -Path (Join-Path $junction 'escaped.jsonl') } | Should -Throw '*path-reparse-point*'
    }
    finally {
      Remove-Item -LiteralPath $junction -Force
    }
  }

  It 'stops the verified owned root and leaves an unrelated sentinel alive' {
    $exe = Get-DotfilesPowerShellExecutable
    $sleepArguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30')
    $sentinel = Start-DotfilesOwnedProcess -FileName $exe -Arguments $sleepArguments -Source 'sentinel'
    $owned = Start-DotfilesOwnedProcess -FileName $exe -Arguments $sleepArguments -Source 'fixture'
    Mock Get-DotfilesProcessTreeSnapshot { return @() }
    try {
      $owned.Process.WaitForExit(100) | Should -BeFalse
      $result = Stop-DotfilesOwnedProcess -Owned $owned -GraceMilliseconds 3000
      $result.Exited | Should -BeTrue
      $sentinel.Process.HasExited | Should -BeFalse
    }
    finally {
      if (-not $sentinel.Process.HasExited) { $sentinel.Process.Kill(); $null = $sentinel.Process.WaitForExit(3000) }
      $sentinel.Process.Dispose()
      if (Test-DotfilesExactProcessIdentity -ProcessId $owned.ProcessId -StartTimeTicks $owned.StartTimeTicks) {
        $leftover = [Diagnostics.Process]::GetProcessById($owned.ProcessId)
        try { $leftover.Kill(); $null = $leftover.WaitForExit(3000) } finally { $leftover.Dispose() }
      }
      $owned.Process.Dispose()
    }
  }

  It 'retains an exited root even when a fresh process-tree snapshot has no direct children' {
    $state = Join-Path $TestDrive 'exited-root-inhibition'
    [void][IO.Directory]::CreateDirectory($state)
    $owned = Start-DotfilesOwnedProcess -FileName (Get-DotfilesPowerShellExecutable) -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'exit 0') -Source 'fixture'
    Mock Get-DotfilesProcessTreeSnapshot { return @() }
    try {
      $owned.Process.WaitForExit(10000) | Should -BeTrue

      $tree = Get-DotfilesVerifiedProcessTree -Owned $owned
      $cleanup = Stop-DotfilesOwnedProcess -Owned $owned -GraceMilliseconds 100

      $tree.Complete | Should -BeFalse
      $tree.Processes.Count | Should -Be 0
      $cleanup.Exited | Should -BeFalse
      $cleanup.CleanupUnverified | Should -BeTrue
      $cleanup.Entries.Count | Should -Be 1
      Write-DotfilesInhibitions -StateDirectory $state -Entries $cleanup.Entries -RunId 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
      $readEntries = @(Read-DotfilesInhibitions -StateDirectory $state)
      $readEntries.Count | Should -Be 1
      $readEntries[0].cleanupUnverified | Should -BeTrue
    }
    finally { $owned.Process.Dispose() }
  }

  It 'retains an exited root when a live child started within its lifetime' {
    $state = Join-Path $TestDrive 'exited-root-with-child'
    [void][IO.Directory]::CreateDirectory($state)
    $owned = Start-DotfilesOwnedProcess -FileName (Get-DotfilesPowerShellExecutable) -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 2') -Source 'fixture'
    $child = Start-DotfilesOwnedProcess -FileName (Get-DotfilesPowerShellExecutable) -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'fixture-child'
    $script:ExitedRootId = $owned.ProcessId
    $script:ExitedChildId = $child.ProcessId
    Mock Get-DotfilesProcessTreeSnapshot { return @([pscustomobject]@{ ProcessId = $script:ExitedChildId; ParentId = $script:ExitedRootId }) }
    try {
      $child.StartTimeTicks | Should -BeGreaterThan $owned.StartTimeTicks
      $owned.Process.WaitForExit(10000) | Should -BeTrue

      $cleanup = Stop-DotfilesOwnedProcess -Owned $owned -GraceMilliseconds 100

      $cleanup.Exited | Should -BeFalse
      $cleanup.CleanupUnverified | Should -BeTrue
      $cleanup.Entries[0].processId | Should -Be $owned.ProcessId
      $cleanup.Entries[0].exitTimeTicks | Should -BeGreaterOrEqual $child.StartTimeTicks
      Write-DotfilesInhibitions -StateDirectory $state -Entries $cleanup.Entries -RunId 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
      $readEntries = @(Read-DotfilesInhibitions -StateDirectory $state)
      $readEntries.Count | Should -Be 1
    }
    finally {
      if (-not $child.Process.HasExited) { $child.Process.Kill(); $null = $child.Process.WaitForExit(3000) }
      $child.Process.Dispose()
      $owned.Process.Dispose()
      Remove-Variable ExitedRootId, ExitedChildId -Scope Script -ErrorAction SilentlyContinue
    }
  }

  It 'keeps host samples flowing while an owned provider hangs and preserves an unrelated process' {
    $script:FixtureState = Join-Path $TestDrive 'provider-timeout-state'
    $script:FixtureOutput = Join-Path $TestDrive 'provider-timeout-output'
    $script:FakeClock = 0.0
    $script:ActiveCpu = $false
    $script:CpuStarts = 0
    $script:ClockProvider = { [double]$script:FakeClock }
    $script:SleepProvider = { param($Milliseconds) $script:FakeClock += $Milliseconds }
    $sentinel = Start-DotfilesOwnedProcess -FileName (Get-DotfilesPowerShellExecutable) -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'sentinel'
    Mock Get-DotfilesDefaultStateDirectory { return $script:FixtureState }
    Mock Start-DotfilesHostWorker {
      param($Source)
      if ($Source -eq 'cpu') {
        if ($script:ActiveCpu) {
          $same = Test-DotfilesExactProcessIdentity -ProcessId $script:LastCpuProcessId -StartTimeTicks $script:LastCpuStartTimeTicks
          if ($null -eq $same -or $same) { throw 'same-source-overlap' }
          $script:ActiveCpu = $false
        }
        $script:ActiveCpu = $true
        $script:CpuStarts++
        $owned = Start-DotfilesOwnedProcess -FileName (Get-DotfilesPowerShellExecutable) -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') -Source 'cpu'
        $script:LastCpuProcessId = $owned.ProcessId
        $script:LastCpuStartTimeTicks = $owned.StartTimeTicks
        return $owned
      }
      $fake = [pscustomobject]@{ Id = 5000; HasExited = $true }
      Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value {}
      return @{ Source = $Source; Process = $fake; ProcessId = 5000; StartTimeTicks = 5000 }
    }
    Mock Get-DotfilesWorkerResult {
      param($Owned)
      switch ($Owned.Source) {
        'memory' { return @{ source = 'memory'; status = 'ok'; metrics = @{ availableBytes = 400; committedBytes = 700; commitLimitBytes = 1200; pageFilePercentUsage = 10; pageReadsCounter = 10; pagesInputCounter = 20; pageWritesCounter = 30; pagesOutputCounter = 40; timestampPerfTime = 1000; frequencyPerfTime = 1000 } } }
        'disk' { return @{ source = 'disk'; status = 'unavailable'; error = 'counter-unavailable'; metrics = @{} } }
        'hyperv' { return @{ source = 'hyperv'; status = 'unavailable'; error = 'counter-unavailable'; metrics = @{} } }
      }
    }
    try {
      $exitCode = Invoke-DotfilesIncidentCollector -IntervalSeconds 1 -DurationSeconds 2 -MaximumLogBytes 1048576 -OutputDirectory $script:FixtureOutput -GuestDistro ''
      $sentinel.Process.HasExited | Should -BeFalse
    }
    finally {
      $script:ClockProvider = $null
      $script:SleepProvider = $null
      if (-not $sentinel.Process.HasExited) { $sentinel.Process.Kill(); $null = $sentinel.Process.WaitForExit(3000) }
      $sentinel.Process.Dispose()
    }

    $exitCode | Should -Be 0
    $script:CpuStarts | Should -BeGreaterOrEqual 1
    (Test-DotfilesExactProcessIdentity -ProcessId $script:LastCpuProcessId -StartTimeTicks $script:LastCpuStartTimeTicks) | Should -BeFalse
    $path = Get-ChildItem -LiteralPath (Join-Path $script:FixtureOutput 'dotfiles-wsl-incident-telemetry') -Filter '*.jsonl' | Select-Object -First 1
    $records = @(Get-Content -LiteralPath $path.FullName | ForEach-Object { $_ | ConvertFrom-Json })
    $records.Count | Should -BeGreaterThan 1
    $records[0].host.memory.metrics.availableBytes | Should -Be 400
    @($records | Where-Object { $_.host.cpu.status -eq 'timeout' }).Count | Should -BeGreaterOrEqual 1
  }

  It 'continues host records while a guest hangs and never retries it after timeout' {
    $script:FixtureState = Join-Path $TestDrive 'coordinator-state'
    $script:FixtureOutput = Join-Path $TestDrive 'coordinator-output'
    $script:FakeClock = 0.0
    $script:ActiveSources = New-Object 'Collections.Generic.HashSet[string]'
    $script:GuestStartCount = 0
    $script:GuestTimeoutAt = 1500.0
    $script:ClockProvider = { [double]$script:FakeClock }
    $script:SleepProvider = { param($Milliseconds) $script:FakeClock += $Milliseconds }
    $oldGuestTimeout = $script:GuestTimeoutMilliseconds
    $script:GuestTimeoutMilliseconds = 1500

    Mock Get-DotfilesDefaultStateDirectory { return $script:FixtureState }
    Mock Start-DotfilesHostWorker {
      param($Source)
      if (-not $script:ActiveSources.Add($Source)) { throw 'same-source-overlap' }
      $fake = [pscustomobject]@{ Id = 1000; HasExited = ($Source -ne 'cpu') }
      Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value {}
      return @{ Source = $Source; Process = $fake; ProcessId = 1000; StartTimeTicks = 1000; StartedAtMilliseconds = $script:FakeClock }
    }
    Mock Get-DotfilesWorkerResult {
      param($Owned)
      [void]$script:ActiveSources.Remove($Owned.Source)
      $tick = [Math]::Floor($script:FakeClock / 1000.0) + 1
      switch ($Owned.Source) {
        'memory' { return @{ source = 'memory'; status = 'ok'; metrics = @{ availableBytes = 400; committedBytes = 700; commitLimitBytes = 1200; pageFilePercentUsage = 10; pageReadsCounter = 10 * $tick; pagesInputCounter = 20 * $tick; pageWritesCounter = 30 * $tick; pagesOutputCounter = 40 * $tick; timestampPerfTime = 1000 * $tick; frequencyPerfTime = 1000 } } }
        'disk' { return @{ source = 'disk'; status = 'ok'; metrics = @{ physicalTotal = @{ readBytesCounter = 100 * $tick; writeBytesCounter = 200 * $tick; timestampPerfTime = 1000 * $tick; frequencyPerfTime = 1000; queueLength = 1 }; systemVolume = @{ readBytesCounter = 50 * $tick; writeBytesCounter = 80 * $tick; timestampPerfTime = 1000 * $tick; frequencyPerfTime = 1000; queueLength = 1; instanceAlias = 'volume-fixture' } } } }
        'hyperv' { return @{ source = 'hyperv'; status = 'unavailable'; error = 'provider-unavailable'; metrics = @{} } }
      }
    }
    Mock Stop-DotfilesOwnedProcess {
      param($Owned, $GraceMilliseconds)
      $Owned.Process.HasExited = $true
      [void]$script:ActiveSources.Remove($Owned.Source)
      return @{ Exited = $true; CleanupUnverified = $false; Entries = @() }
    }
    Mock Start-DotfilesGuestProbe {
      param($Distribution, $IntervalSeconds, $PreviousCounters)
      $script:GuestStartCount++
      $fake = [pscustomobject]@{ Id = 2000; HasExited = $false }
      Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value {}
      return @{ Status = 'pending'; Error = $null; Process = @{ Process = $fake; Source = 'guest'; StartedAtMilliseconds = $script:FakeClock; ProcessId = 2000; StartTimeTicks = 2000 } }
    }
    Mock Update-DotfilesGuestProcess {
      param($Owned)
      if ($script:FakeClock -ge ($Owned.StartedAtMilliseconds + $script:GuestTimeoutAt)) {
        return @{ Done = $true; Record = @{ status = 'timeout'; error = 'timeout'; metrics = @{} }; Data = $null; Suppressed = $true; Inhibitions = @() }
      }
      return @{ Done = $false; Record = @{ status = 'pending'; error = $null; metrics = @{} }; Data = $null; Suppressed = $false; Inhibitions = @() }
    }

    try {
      $exitCode = Invoke-DotfilesIncidentCollector -IntervalSeconds 1 -DurationSeconds 62 -MaximumLogBytes 1048576 -OutputDirectory $script:FixtureOutput -GuestDistro 'FixtureDistro'
      $exitCode | Should -Be 0
    }
    finally {
      $script:GuestTimeoutMilliseconds = $oldGuestTimeout
      $script:ClockProvider = $null
      $script:SleepProvider = $null
    }

    $logs = @(Get-ChildItem -LiteralPath (Join-Path $script:FixtureOutput 'dotfiles-wsl-incident-telemetry') -Filter '*.jsonl')
    $records = @($logs | ForEach-Object { Get-Content -LiteralPath $_.FullName | ForEach-Object { $_ | ConvertFrom-Json } })
    $records.Count | Should -BeGreaterThan 50
    $records[0].guest.status | Should -Be 'pending'
    $records[0].host.memory.metrics.availableBytes | Should -Be 400
    $records[1].guest.status | Should -Be 'timeout'
    $records[-1].elapsedSeconds | Should -BeGreaterThan 60
    $script:GuestStartCount | Should -Be 1
    $script:ActiveSources.Count | Should -Be 0
  }

  It 'caps the final wait at duration when interval is longer and releases the lock' {
    $script:FixtureState = Join-Path $TestDrive 'finite-state'
    $script:FixtureOutput = Join-Path $TestDrive 'finite-output'
    $script:FakeClock = 0.0
    $script:ClockProvider = { [double]$script:FakeClock }
    $script:SleepProvider = { param($Milliseconds) $script:FakeClock += $Milliseconds }
    Mock Get-DotfilesDefaultStateDirectory { return $script:FixtureState }
    Mock Start-DotfilesHostWorker {
      param($Source)
      $fake = [pscustomobject]@{ Id = 3000; HasExited = $true }
      Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value {}
      return @{ Source = $Source; Process = $fake; ProcessId = 3000; StartTimeTicks = 3000 }
    }
    Mock Get-DotfilesWorkerResult {
      param($Owned)
      return @{ source = $Owned.Source; status = 'unavailable'; error = 'counter-unavailable'; metrics = @{} }
    }

    try {
      $exitCode = Invoke-DotfilesIncidentCollector -IntervalSeconds 60 -DurationSeconds 1 -MaximumLogBytes 65536 -OutputDirectory $script:FixtureOutput -GuestDistro ''
    }
    finally {
      $script:ClockProvider = $null
      $script:SleepProvider = $null
    }

    $exitCode | Should -Be 0
    $script:FakeClock | Should -BeLessOrEqual 1000
    $lockPath = Join-Path $script:FixtureState 'collector.lock.json'
    Test-Path -LiteralPath $lockPath | Should -BeFalse
  }

  It 'runs bounded cleanup and releases the lock on the Ctrl+C pipeline stop path' {
    $script:FixtureState = Join-Path $TestDrive 'interrupt-state'
    $script:FixtureOutput = Join-Path $TestDrive 'interrupt-output'
    $script:FakeClock = 0.0
    $script:ClockProvider = { [double]$script:FakeClock }
    $script:SleepProvider = { param($Milliseconds) throw [System.Management.Automation.PipelineStoppedException]::new() }
    Mock Get-DotfilesDefaultStateDirectory { return $script:FixtureState }
    Mock Start-DotfilesHostWorker {
      param($Source)
      $fake = [pscustomobject]@{ Id = 4000; HasExited = $true }
      Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value {}
      return @{ Source = $Source; Process = $fake; ProcessId = 4000; StartTimeTicks = 4000 }
    }
    Mock Get-DotfilesWorkerResult {
      param($Owned)
      return @{ source = $Owned.Source; status = 'unavailable'; error = 'counter-unavailable'; metrics = @{} }
    }

    try {
      $exitCode = Invoke-DotfilesIncidentCollector -IntervalSeconds 5 -DurationSeconds 10 -MaximumLogBytes 65536 -OutputDirectory $script:FixtureOutput -GuestDistro ''
    }
    finally {
      $script:ClockProvider = $null
      $script:SleepProvider = $null
    }

    $exitCode | Should -Be 0
    Test-Path -LiteralPath (Join-Path $script:FixtureState 'collector.lock.json') | Should -BeFalse
  }
  }
}
