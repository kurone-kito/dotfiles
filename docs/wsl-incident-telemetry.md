---
type: guide
title: WSL incident telemetry
description: Run the bounded, foreground WSL host evidence collector and review its local JSONL records.
tags: [wsl, diagnostics, telemetry]
---

# WSL incident telemetry

The collector is an opt-in diagnostic for a Windows host. It samples
host counters even when a WSL guest probe is unavailable or stalls. File
deployment does not start the collector, register a background task, or
change WSL settings. The guest helper only reads procfs.

## Start and stop

Run the collector in a foreground PowerShell 5.1 or PowerShell 7
session:

```powershell
$collector = Join-Path $HOME '.local\bin\wsl-incident-capture.ps1'
& $collector -IntervalSeconds 5 -DurationSeconds 600
```

The default is host-only. To include an operator-selected distribution,
pass its name explicitly:

```powershell
& $collector -IntervalSeconds 5 -DurationSeconds 600 -GuestDistro 'Ubuntu'
```

The guest name is used for the running-state check and command launch;
the collector does not put it in a log or persistent state file. The
collector checks the running list once and skips stopped or unknown
states without requesting a launch. The WSL command-line interface does
not make that check and command atomic: if the distribution stops after
the final check but before command launch, WSL may start it. Use
host-only mode when that small race is unacceptable.

The process exits after its finite duration. Press **Ctrl+C** in the
foreground session to stop sooner; cleanup is bounded to processes
started by this collector. A second invocation while one is active
returns an `already-running` result and does not touch the first run.
The per-user lock is shared even when runs select different output
directories. Only a confirmed operating-system sharing or lock violation
is reported as `already-running`; other lock I/O failures return an error
so they cannot look like a successful no-op.

If an owned process exits before its descendants can be verified, or a
post-cleanup snapshot finds a new or reused PID under an owned PID, the
collector records a durable cleanup inhibition for that source in
`$env:LOCALAPPDATA\Dotfiles\wsl-incident-telemetry\inhibitions.json`.
Sources remain inhibited while the file contains an entry for that source
or `*` (which inhibits every source). On a later run, the collector
retains every `cleanupUnverified` entry for manual review, even when its
recorded root has exited. A fresh PID/parent-PID snapshot cannot prove
that no descendants remain when an intermediate process exited before the
snapshot. A wildcard without a usable process identity also remains
unresolved for manual review. Entries for processes whose cleanup was
verified can be reconciled automatically when their exact PID and start
time identity has exited.

To clear an inhibition safely, close every collector session first and
inspect `inhibitions.json`. For each entry, compare both `processId` and
`startTimeTicks` with the live process identity; a matching PID with a
different start time is a different process and must not be stopped. Stop
only a process whose PID and recorded start time both match, then verify
that exact process has exited. Every `cleanupUnverified` entry also
requires an independent process-tree check for surviving collector
descendants, even when its recorded root process has exited; the root
identity alone does not prove descendant cleanup. An entry with
`source: "*"` and no usable process identity represents unresolved
ownership and needs the same independent check. Keep the affected sources
inhibited whenever you cannot establish that no collector-owned process
remains. Once every entry has been reconciled, no collector is active,
and all required process-tree checks establish cleanup, delete
`inhibitions.json` to clear the inhibitions. Do not delete it while a
collector is running, because that run may rewrite the marker.

Supported limits are:

| Option | Default | Accepted range |
| --- | ---: | ---: |
| `-IntervalSeconds` | 5 | 1–60 seconds |
| `-DurationSeconds` | 86400 | 1–86400 seconds |
| `-MaximumLogBytes` | 33554432 | 65536–33554432 bytes |
| `-OutputDirectory` | Per-user local state | Any existing or creatable path without a reparse-point segment |

When supplied, `-OutputDirectory` is a base directory. The collector
creates a `dotfiles-wsl-incident-telemetry` subdirectory beneath it and
protects that directory with a per-user Windows ACL. Choose a local
directory that is not synchronized or shared if the evidence must stay
on the machine. Relative paths resolve with PowerShell's FileSystem path
rules, including per-drive locations. Provider-qualified non-FileSystem
paths and relative paths from other providers are rejected.

## Find and review records

By default, records are written beneath:

```powershell
$logs = Join-Path $env:LOCALAPPDATA 'Dotfiles\wsl-incident-telemetry\logs\dotfiles-wsl-incident-telemetry'
Get-ChildItem -LiteralPath $logs -Filter '*.jsonl' | Sort-Object LastWriteTimeUtc
```

Each file belongs to one run. Read its JSONL records with:

```powershell
$latest = Get-ChildItem -LiteralPath $logs -Filter '*.jsonl' |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1
Get-Content -LiteralPath $latest.FullName |
  ForEach-Object { $_ | ConvertFrom-Json } |
  Select-Object sampleTimeUtc, elapsedSeconds, sampleIntervalSeconds, host, guest
```

Records use UTF-8 without a byte-order mark. Each host sample includes a
schema version, run identifier, UTC timestamp, monotonic elapsed time,
observed sample interval, units, and a status for each source. A source
can report `ok`, `partial`, `unavailable`, `timeout`, or `pending`.
Errors use fixed categories; raw provider messages and command output
are not recorded. The initial rate sample and the first sample after a
counter reset or device-instance change have null rates and unavailable
status.

Host evidence contains:

- total and privileged CPU percentages;
- available and committed memory, commit limit, pagefile usage, and
  paging rates when the needed counters exist;
- physical-disk and system-volume read/write throughput and queue
  length; and
- optional Hyper-V virtual-storage throughput and operation rates.

With `-GuestDistro`, guest evidence contains available and total memory,
swap use, memory PSI, and interval deltas/rates for supported reclaim,
refault, page-in, page-out, and fault counters. Missing procfs files or
commands produce unavailable fields rather than guessed values. Partial
samples can still establish counter baselines when usable counters exist.
If more than 10 minutes elapse between successful samples, the next sample
starts a new baseline and its counter rates remain unavailable. The stdin
baseline is capped at 4 KiB; a larger baseline is discarded and the sample
continues without rates.

The collector redacts virtual-storage identities into random per-run
aliases before writing. Guest JSON is reduced to a fixed schema of
numeric fields. It does not serialize usernames, hostnames, distribution
names, home or virtual-disk paths, process command lines, credentials,
or environment values. The lock and inhibition files in the per-user
state directory contain process identifiers and start times for safe
ownership checks; they are not telemetry records. Review records before
sharing them, and manually redact any sensitive values before exporting.

The active and rotated log files, temporary files, and partial records
share the configured byte budget. Each record is capped at 32 KiB; an
oversized record is replaced with a small overflow record. A long run
rolls into numbered JSONL segments at a target of one quarter of the
total budget, bounded below by 32 KiB and above by 8 MiB. When another
segment or record would exceed the total budget, the collector removes
its oldest validated logs and keeps the newest evidence. On startup it
drops oversized old logs before inspecting a partial record, then repairs a
partial final line with bounded memory. It rejects symlink/reparse paths
before reading or deleting collector logs.

## Optional operator smoke check

This check is intentionally manual. It starts a short host-only run and
does not induce a stall or start a WSL distribution:

```powershell
& $collector -IntervalSeconds 1 -DurationSeconds 10 -MaximumLogBytes 65536
$latest = Get-ChildItem -LiteralPath $logs -Filter '*.jsonl' |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1
Get-Content -LiteralPath $latest.FullName |
  ForEach-Object { $_ | ConvertFrom-Json } |
  Select-Object schemaVersion, recordType, sampleTimeUtc, elapsedSeconds, host
```

Confirm the run produced versioned records, ended within its requested
duration plus bounded process cleanup, and did not create a service or
scheduled task. Do not apply the whole dotfiles tree solely to run this
check.

## Check collection overhead

Compare a quiet 5-minute baseline with a quiet 5-minute host-only run
under the same workload using Windows Task Manager's CPU and memory
graphs. Record the interval and duration, and repeat once if background
activity changed between runs. This is a rough comparison rather than
a performance guarantee; do not create artificial disk or memory load
to measure it. The collector itself does not change memory limits,
swap state, caches, services, or WSL lifecycle settings.
