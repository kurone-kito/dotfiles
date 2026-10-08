---
type: guide
title: WSL workload budget
description: Manual baseline, admit, observe, reduce, and resume workflow for bounding concurrent heavy jobs in a WSL guest using the incident collector's evidence.
tags: [wsl, diagnostics, capacity]
---

<!-- cspell:words wslconfig hyperv pgscan pgsteal kswapd pswpin pgmajfault -->

# WSL workload budget

This guide is for an operator who runs several heavy jobs, such as builds,
test suites, or agent sessions, inside one WSL 2 guest and wants a repeatable,
manual way to decide how many to admit at once. It uses the evidence that the
[WSL incident telemetry](wsl-incident-telemetry.md) collector already records.

Everything here is a provisional operating policy. It is not a measured safe
threshold, it does not identify which process causes pressure, and it does not
explain or fix any particular incident.

## What this guide does and does not do

- It defines a manual loop: establish a baseline, admit one bounded workload,
  observe for a finite window, compare aligned windows, then admit more, hold,
  or ask the owner to reduce, and resume with hysteresis.
- It reads timestamped host and guest evidence over the same interval and keeps
  gauges, cumulative counters, and deltas or rates apart.
- It treats missing, partial, or timed-out evidence as unknown. Unknown is never
  read as zero pressure.
- It says correlation can narrow the next observation. It never proves which
  process was responsible.
- It keeps the effective WSL memory cap, the reclaim setting, and the
  sparse-VHD setting exactly as they are. See
  [Settings this runbook leaves alone](wsl-incident-recovery.md#settings-this-runbook-leaves-alone).
  The operator this guide was written for has a 20 GB cap; read your own from
  the effective `%UserProfile%\.wslconfig` while everything is healthy and
  record it in each evidence record.
- It does not recommend clearing caches, removing swap, or raising the memory
  cap, and nothing in its evidence can show that any of them fixes a stall.
  Those are separately authorized branches of the
  [recovery runbook](wsl-incident-recovery.md#memory-swap-or-cache-changes).
- It adds no automatic enforcement. Every decision is the operator's.

If the guest stops answering while you follow this guide, stop the workflow and
use the [recovery runbook](wsl-incident-recovery.md). This guide never
escalates.

## Ground rules

Terms: a **heavy job** is one that moves any signal below outside its baseline
range when it runs. A **workload class** is one word from a closed list:
`build`, `test`, `agent-session`, `index`, or `other`. Never record a command
line, an argument, a path, or a user name.

1. **Admission is not intervention.** This guide decides whether new work
   starts. It never reaches into a job another owner already runs.
2. **Reduction is a request.** When pressure persists, ask the owner of the
   running work to consider reducing it. The owner decides, and the owner's
   answer is recorded.
3. Never kill a job by process name, never pause one silently, and never
   restart one automatically.
4. Do not change an agent session's settings, CPU affinity, cgroups, services,
   scheduled tasks, or `.wslconfig` as part of this workflow.
5. Record only coarse facts: counts, classes, UTC times, and collector values.
   Review any record before sharing it, as the telemetry guide says.

## Read the collector evidence

Run the collector as the telemetry guide describes, with an explicit finite
`-DurationSeconds` that covers the baseline, the observation window, and a
margin in **one run**, and add `-GuestDistro '<distribution>'` only when guest
evidence is needed. The default interval is 5 seconds. Read records with the
telemetry guide's own commands.

### Field map

Paths are relative to one JSONL record. "Usable when" states what makes a value
known; see the reading rules below for what to do otherwise.

| Field | Kind | Unit | Usable when |
| --- | --- | --- | --- |
| `host.cpu.totalPercent`, `privilegedPercent` | Interval percentage derived from raw counters | percent | `host.cpu.status` is `ok` |
| `host.memory.metrics.availableBytes`, `committedBytes`, `commitLimitBytes` | Gauge | bytes | present and non-null |
| `host.memory.metrics.pageFilePercentUsage` | Gauge | percent | present and non-null |
| `host.memory.metrics.pagingRates.counters.<name>.value` for `pageReadsPerSecond`, `pagesInputPerSecond`, `pageWritesPerSecond`, `pagesOutputPerSecond` | Rate | events per second | that counter's `status` is `ok` |
| `host.disk.metrics.physicalTotal` and `systemVolume`: `readBytesPerSecond`, `writeBytesPerSecond` | Rate | bytes per second | that entry's `status` is `ok` |
| `host.disk.metrics.physicalTotal.queueLength` | Gauge | requests | present and non-null; `systemVolume` has no queue length |
| `host.hyperv.metrics.virtualStorage[]`: read and write bytes and operations per second | Rate | bytes or operations per second | that device's `status` is `ok` |
| `guest.metrics.memory.total`, `available`; `swap.total`, `used` | Gauge | kB | present and non-null |
| `guest.metrics.psi.some` and `full`: `avg10`, `avg60`, `avg300` | Gauge, averaged by the kernel over the trailing 10, 60, and 300 seconds | percent | present and non-null |
| `guest.metrics.psi.some` and `full`: `totalUsec` | Cumulative counter since guest boot | microseconds | present and non-null |
| `guest.metrics.counters.<name>` | Cumulative counter since guest boot | events | present and non-null |
| `guest.metrics.deltas.<name>`: `value`, `perSecond` | Delta and rate over the interval between two successive successful guest samples | events, events per second | that delta's `status` is `ok` |

The guest counter names are `pgscan_kswapd`, `pgscan_direct`,
`pgsteal_kswapd`, `pgsteal_direct`, `workingset_refault`, `pswpin`, `pswpout`,
`pgfault`, and `pgmajfault`. The paging rates are the collector's names for
Windows performance counters; this guide uses them only as indicators relative
to a baseline. "Commit headroom" is not a field: derive it as
`commitLimitBytes` minus `committedBytes` and label it derived.

### Reading rules

1. **Compare like with like.** Compare gauges with gauges, and rates with
   rates, over aligned windows. A cumulative total is a count since guest boot.
   Compare it only through its delta, never against a rate or a gauge. The
   `avg300` value trails five minutes, so in a window shorter than that it
   still carries the previous phase; prefer `avg10` and `avg60`.
2. **Judge each field, not the whole record.** A gauge is known when it is
   present and non-null. A rate or delta is known only when its own `status` is
   `ok` and it is non-null. A failed source carries an empty `metrics`, so its
   fields are absent, not null. Absent and null are both unknown. A source
   whose status is `partial` or `unavailable` can still hold known gauges, for
   example on the first record of a run. The first record has no sample
   interval, so leave it out of every window. A record with `status` `overflow`
   and `error` `record-size-limit` has no host or guest block at all; treat it
   as a gap.
3. **Unknown is not healthy.** Unknown can neither clear nor confirm a
   hypothesis. The error values `first-sample`, `counter-reset`,
   `probe-interval`, `inhibited`, `distro-not-running`, and `timeout` all mean
   the value is unknown. A missing or timed-out guest reading means unknown,
   never an idle guest.
4. **Guest evidence is sparse.** The collector probes the guest at most once
   every 60 seconds and runs one guest process at a time. A successful guest
   result appears in exactly one record; the records between probes read
   `unavailable` with `probe-interval`, which is normal. After a guest
   `timeout` the collector stops probing for the rest of that run, so every
   later record is unknown. Guest deltas cover the time between two successive
   guest samples, not `sampleIntervalSeconds`; if more than 10 minutes pass
   between them, the next sample starts a new baseline and has no rates. Size
   every window to hold several guest samples (the provisional minimum is three).
5. **Memory pressure only, and a kernel-dependent counter.** The guest helper
   reads `/proc/meminfo`, `/proc/vmstat`, and `/proc/pressure/memory`, so the
   records carry no guest CPU or I/O pressure. It reads `workingset_refault` by
   exact name. Kernels that split it into `workingset_refault_anon` and
   `workingset_refault_file` give a null counter and an unavailable delta, and
   the guest record is then `partial` with the error `provider-unavailable`.
   Such a record is still usable for every field that is known; only the
   refault evidence is unknown. While healthy, `grep -c '^workingset_refault '
   /proc/vmstat` in the guest prints `0` on such a kernel.
6. **Aggregates hide detail.** `physicalTotal` is a total across physical
   disks, and `systemVolume` is only the Windows system volume. Hyper-V
   `virtualStorage[]` entries use random per-run aliases, so a device is
   attributable within one run only, and `overflowCount` above 0 means devices
   were omitted. A second collector run is refused while one is active, so
   baseline and observation windows from separate runs cannot be compared per
   device; use one run for both, or compare only `physicalTotal`. The records do
   not say which of these holds the guest's virtual disk, so a storage
   attribution to the guest is a hypothesis.
7. **Judge windows, not single records.** Host rates are averages over
   `sampleIntervalSeconds`. Judge a window by its many samples.

## Workflow

The loop is: baseline, admit, observe, compare, decide, resume, record. Every
number in it is provisional until you calibrate it against your own healthy
observations (see [Thresholds](#thresholds)).

### 1. Baseline

In the same collector run you will use for the observation, collect an idle or
light-load window. For each signal you will rely on, write down the range it
spans: its median and its highest ordinary value. Record the window's UTC start
and end and the run identifier as the baseline's source. Provisional starting
length: 10 minutes, repeated once. Repeat the baseline when the workload mix
changes.

### 2. Admit one bounded workload

Start conservatively with one heavy job. This is a provisional operating
policy, not a measured safe threshold. Record the admitted job count and the
workload class. Do not admit a second job while the first is being observed.

### 3. Observe for a finite window

Pick the window length before you admit, make it finite, and do not extend it
to wait for a better answer. If it has to be longer, record a new window. Use
the same duration and the same offset from admission as the baseline so the
windows are aligned.

### 4. Compare and decide

A window's verdict is `within-range`, `out-of-range`, or `unknown`. Establish
validity first (reading rule 2), then compare. `within-range` requires every
signal you rely on to be known and inside its baseline range.

| Verdict of the aligned comparison | Decision | Decision class |
| --- | --- | --- |
| `within-range` | You may admit one more job. Return to step 3 for the new count. | Admission |
| `unknown`, or a signal leaves its range only briefly | Hold new admissions. No verdict is possible. Gather a new window. | Admission |
| `out-of-range` for the whole window | Hold new admissions and ask the owner of the running work to consider reducing it. The owner decides. | Admission, then a request to the owner |

### 5. Resume with manual hysteresis

Resume admissions only after consecutive windows have returned inside the
baseline range. Provisional rule: two consecutive windows. Then resume one job
at a time, not at the count that preceded the pressure. Never resume on
unknown evidence.

### 6. Rollback record

Keep one record for each change of the admitted count:

```text
run-id:                <runId>
window-utc:            <start>/<end>, finite, aligned with <baseline label>
effective-memory-cap:  <value read from the effective .wslconfig, or "default (key absent)">
admitted-job-count:    <before> -> <after>
workload-class:        build | test | agent-session | index | other
baseline-source:       <window label, UTC start/end, statistic used>
host-summary:          <signals used and whether each is inside the baseline range>
guest-summary:         <signals used, number of guest samples that were known, or "unknown">
verdict:               within-range | out-of-range | unknown
decision:              admit | hold | ask-owner-to-reduce | resume
owner-response:        <if asked, the owner's decision>
rollback:              <how the previous admitted count is restored by the owner>
```

### Measurement overhead

The collector is a bounded foreground process, and a guest-enabled run adds one
`wsl.exe` launch at most every 60 seconds. Prefer host-only runs for baselines
that do not need guest evidence, keep the 5-second interval, and stop the run
at the end of the window. The telemetry guide's
[overhead check](wsl-incident-telemetry.md#check-collection-overhead) gives a
rough way to compare a quiet window with and without the collector. Observation
can change timing, so treat a small difference as noise.

## Scenarios

Judge validity first, then these hypotheses. A scenario needs its required
fields to be known in the same window; otherwise it is the fourth scenario.

| Scenario | Evidence that supports it | Evidence that weakens it | Required known fields | Next observation |
| --- | --- | --- | --- | --- |
| Guest memory or reclaim pressure | `psi.some.avg10` and `avg60` above baseline; `deltas.pgscan_direct.perSecond`, `deltas.pgsteal_direct.perSecond`, or `deltas.pgmajfault.perSecond` above baseline in the same window; `memory.available` low; `swap.used` rising | Deltas at baseline while only `counters.*` are large; `psi.some` at baseline | `psi`, the reclaim deltas, `memory`, and `swap` in at least three guest samples | A second aligned window with one fewer admitted job |
| Host memory or pagefile pressure | `committedBytes` close to `commitLimitBytes`; `pageFilePercentUsage` high; `pagesInputPerSecond` or `pagesOutputPerSecond` above baseline | `availableBytes` ample and paging at baseline | The host memory gauges and paging rates in every sample used | A window with the same admitted count and host sources only |
| Storage saturation without current memory pressure | `physicalTotal.queueLength` and the read or write rates above baseline; Hyper-V `virtualStorage[]` rates high; guest `psi.some` and reclaim deltas at baseline | Reclaim deltas or `psi.some` rising together with the disk rates | The disk entries, the guest `psi` and reclaim deltas, and the host memory gauges | A window with the storage-heavy class held back |
| Unavailable or conflicting evidence | A required field is unknown, the guest timed out, or host and guest disagree | A complete, consistent window | Not applicable | A new window with guest evidence, or the host-only reading, with no verdict until then |

Guest paths in this table are relative to `guest.metrics`. Each row's
supported, weakened, or unknown status is a hypothesis to test with the next
window, and the only actions are the admission decisions and owner requests in
[step 4](#4-compare-and-decide). Correlation inside a window does not prove a
culprit, and the records do not name processes. Claim "no evidence of pressure"
only when every required field is known and inside its baseline range.

## Worked examples

All values are synthetic, rounded, and from no real host. They show how to read
the fields, not what a threshold should be. Each record is trimmed to the
fields discussed; real records carry every field the telemetry guide lists.

### Example 1: rising reclaim rate in the same window

Two aligned 10-minute windows in one run, one admitted job between them. This
guest record is the last in the baseline window. It is `partial` because the
guest kernel splits the refault counter, so that field is unknown and the rest
is usable:

```json
{
  "sampleTimeUtc": "2000-01-01T00:09:00.0000000Z",
  "guest": {
    "status": "partial",
    "error": "provider-unavailable",
    "metrics": {
      "memory": { "status": "ok", "unit": "kB", "total": 20971520, "available": 15728640 },
      "swap": { "status": "ok", "unit": "kB", "total": 5242880, "used": 0 },
      "psi": { "status": "ok", "some": { "avg10": 0.0, "avg60": 0.0, "avg300": 0.0, "totalUsec": 1200000 } },
      "counters": { "pgscan_direct": 48000000, "workingset_refault": null },
      "deltas": {
        "pgscan_direct": { "status": "ok", "value": 0, "perSecond": 0 },
        "workingset_refault": { "status": "unavailable", "value": null, "perSecond": null }
      }
    }
  }
}
```

This is the guest record nine minutes into the loaded window. Its delta covers
the 60 seconds since the previous guest sample, which is not shown:

```json
{
  "sampleTimeUtc": "2000-01-01T00:29:00.0000000Z",
  "guest": {
    "status": "partial",
    "error": "provider-unavailable",
    "metrics": {
      "memory": { "status": "ok", "unit": "kB", "total": 20971520, "available": 1048576 },
      "swap": { "status": "ok", "unit": "kB", "total": 5242880, "used": 2097152 },
      "psi": { "status": "ok", "some": { "avg10": 38.5, "avg60": 31.2, "avg300": 18.9, "totalUsec": 90000000 } },
      "counters": { "pgscan_direct": 48900000, "workingset_refault": null },
      "deltas": {
        "pgscan_direct": { "status": "ok", "value": 900000, "perSecond": 15000 },
        "workingset_refault": { "status": "unavailable", "value": null, "perSecond": null }
      }
    }
  }
}
```

| Signal | Baseline window | Loaded window |
| --- | --- | --- |
| `psi.some.avg10` | 0.0 | 38.5 |
| `memory.available` (kB) | 15728640 | 1048576 |
| `swap.used` (kB) | 0 | 2097152 |
| `deltas.pgscan_direct.perSecond` | 0 | 15000 |
| `deltas.workingset_refault` | unknown | unknown |

The evidence that supports a reclaim-pressure hypothesis is the *rate* rising
inside the same window as the admission, together with `psi.some` and low
available memory. The cumulative `counters.pgscan_direct` is large in both
records and says only that reclaim happened at some time since boot. The
refault evidence is unknown on this kernel, so the hypothesis rests on the other
fields. Under the decision table this is `out-of-range` for the whole window:
hold admissions and ask the owner to consider reducing the running work. It
does not show which job caused it.

### Example 2: host memory or pagefile pressure

```json
{
  "sampleTimeUtc": "2000-01-01T01:09:00.0000000Z",
  "host": {
    "memory": {
      "status": "ok",
      "error": null,
      "metrics": {
        "availableBytes": 2147483648,
        "committedBytes": 51539607552,
        "commitLimitBytes": 53687091200,
        "pageFilePercentUsage": 78.5,
        "pagingRates": {
          "status": "ok",
          "counters": {
            "pagesInputPerSecond": { "status": "ok", "error": null, "value": 640.0 },
            "pagesOutputPerSecond": { "status": "ok", "error": null, "value": 410.0 }
          }
        }
      }
    }
  },
  "guest": {
    "status": "ok",
    "error": null,
    "metrics": {
      "memory": { "status": "ok", "unit": "kB", "total": 20971520, "available": 12582912 },
      "psi": { "status": "ok", "some": { "avg10": 0.1, "avg60": 0.0, "avg300": 0.0, "totalUsec": 1250000 } }
    }
  }
}
```

Committed memory is about 96 percent of the commit limit (derived), and the page
file is heavily used, while the guest reports ample available memory and no
pressure. That supports host memory or pagefile pressure and weakens a
guest-side reclaim hypothesis. The next observation is a window with the same
admitted count and host sources only, then one with a workload class held back.

### Example 3: storage saturation without current memory pressure

```json
{
  "sampleTimeUtc": "2000-01-01T02:09:00.0000000Z",
  "host": {
    "disk": {
      "status": "ok",
      "error": null,
      "metrics": {
        "physicalTotal": {
          "status": "ok",
          "error": null,
          "alias": "physical-total",
          "readBytesPerSecond": 262144000,
          "writeBytesPerSecond": 104857600,
          "queueLength": 14.0
        }
      }
    }
  },
  "guest": {
    "status": "partial",
    "error": "provider-unavailable",
    "metrics": {
      "psi": { "status": "ok", "some": { "avg10": 0.2, "avg60": 0.1, "avg300": 0.1, "totalUsec": 3400000 } },
      "counters": { "pgscan_direct": 48900000, "pgmajfault": 120000 },
      "deltas": {
        "pgscan_direct": { "status": "ok", "value": 0, "perSecond": 0 },
        "pgmajfault": { "status": "ok", "value": 0, "perSecond": 0 }
      }
    }
  }
}
```

The disk queue and throughput are far above this operator's baseline, but the
guest reports no memory pressure and zero reclaim and fault deltas. The large
`counters` values did not change in the window, so they are history, not
current pressure. That supports storage saturation without current memory
pressure, provided the required fields in the scenario table are known. It does
not say that the guest's disk is the saturated one, because the records cannot
attribute the volume to the guest (reading rule 6). The next observation holds
the storage-heavy class back for one window.

### Example 4: unavailable or conflicting evidence

```json
{
  "sampleTimeUtc": "2000-01-01T03:09:00.0000000Z",
  "host": {
    "cpu": { "status": "ok", "error": null, "totalPercent": 62.0, "privilegedPercent": 48.0 }
  },
  "guest": { "status": "timeout", "error": "timeout", "metrics": {} }
}
```

A timed-out guest record has no metrics. It does not mean the guest is idle or
healthy, and every later record in that run reads `probe-interval`. The host's
high privileged CPU time cannot be attributed to the guest or cleared by it.
The verdict is `unknown`: hold new admissions, then collect a new window in a
new run with guest evidence, or fall back to the host-only reading. When host
and guest evidence disagree, record both and treat the window as having no
verdict.

## Thresholds

- An **observed baseline** is a range you measured, with its source: the window
  label, its UTC start and end, and the statistic (median and highest ordinary
  value). A threshold of this kind carries its source in the record.
- A **provisional value** is a starting point with no measurement behind it.
  Label any provisional value as such wherever you copy it.
- Calibrate against healthy observations before you rely on a value. Run the
  workflow with a light workload you know to be fine and confirm it returns
  `within-range`. If it does not, the baseline is wrong, not the workload.
- Do not turn a value into automatic enforcement. Anything that starts,
  throttles, or stops work on its own needs a separate, evidence-backed
  decision and its own issue.

Every number in this guide is one of the following:

| Number | Where | Status |
| --- | --- | --- |
| 5 seconds | Default sample interval | Collector default |
| 60 seconds | Spacing between guest probes | Collector constant, read from the script |
| 10 minutes | Gap after which a guest sample has no rates | Collector constant, read from the script |
| 10, 60, 300 seconds | `psi` averaging windows | Kernel definition |
| 20 GB | The effective memory cap of the operator this guide was written for | Observed configuration, unchanged |
| One heavy job | First admission | Provisional |
| 10 minutes, repeated once | Baseline length | Provisional |
| Three guest samples | Minimum per window | Provisional |
| Two consecutive windows | Hysteresis before resuming | Provisional |
| All figures in the worked examples | Examples 1 to 4 | Synthetic |

## Limits of the controls

None of these is enabled or prescribed by this guide. They explain what each
can and cannot do, so one is not assumed to solve another. This repository
cannot know your guest's cgroup hierarchy or filesystems; treat every
prerequisite as a condition to check, not a given.

| Control | Resource it can affect | What it does not affect | Prerequisites to check |
| --- | --- | --- | --- |
| Manual admission of fewer concurrent heavy jobs | The demand of new work on CPU, memory, and disk | Jobs already running, and activity outside the admitted jobs | The owners agree which classes count as heavy |
| A tool's own worker setting | That tool's own parallelism, and so its CPU, memory, and I/O demand | Other tools, and the cache growth other tools cause | The tool offers such a setting, and its owner changes their own invocation |
| Linux cgroup v2 `cpu.max` | CPU bandwidth of one cgroup | Memory and I/O | The `cpu` controller is enabled in the parent's `cgroup.subtree_control`, and write access is delegated to the account that would use it |
| Linux cgroup v2 `io.max` | Per block-device bandwidth and operation limits of one cgroup | CPU and memory; buffered writeback is attributed to a cgroup only where the filesystem supports it, otherwise to the root cgroup | The `io` controller is enabled, delegation, and a block device the limit can name |
| Linux cgroup v2 `memory.high` | Throttling and reclaim pressure on one cgroup once its usage exceeds the value | CPU and I/O; it creates reclaim pressure on that cgroup by design | The `memory` controller is enabled, and delegation |
| `.wslconfig` `processors` | The logical processor count of the whole WSL 2 VM, every distribution in it | Any single job or workload class | The operator edits the effective Windows-side file, and the VM restarts for the change to apply, which ends in-memory jobs |

The `.wslconfig` `memory` key is the existing cap that this guide keeps
unchanged. It is not a budget knob here.

Why none substitutes for another:

- A CPU limit does not reduce memory already resident or disk traffic.
- An I/O limit does not bound memory use, and it can miss writeback the
  filesystem does not attribute.
- A VM-wide setting affects every workload equally and cannot protect one job
  from another.
- A per-tool setting only helps if that tool is the source of the demand.

Whether any control should be turned on is a separate, evidence-backed
decision. This guide's records can inform it but cannot make it.

## Sources

- The collector script and its guest helper in this repository: the field map,
  the 60-second guest probe spacing, the 10-minute baseline rule, the exact
  counter names, and the partial-record behavior were read from them. The key
  paths of the example records were checked against records produced by the
  collector's own functions, and the guest helper was run against a fixture with
  split refault counters. Nothing was run on a Windows host.
- [WSL incident telemetry](wsl-incident-telemetry.md) for the collector
  options, the record fields, and the overhead check.
- [Advanced settings configuration in WSL](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)
  for the `.wslconfig` `memory` and `processors` keys and for when a change
  applies.
- [Pressure Stall Information](https://docs.kernel.org/accounting/psi.html)
  for `some`, `full`, the `avg10`, `avg60`, and `avg300` percentages, and the
  cumulative `total` in microseconds.
- [Control Group v2](https://docs.kernel.org/admin-guide/cgroup-v2.html) for
  `cpu.max`, `io.max`, `memory.high`, controller enablement, delegation, and
  writeback attribution.
