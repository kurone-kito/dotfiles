---
type: guide
title: WSL workload budget
description: Manual baseline, admit, observe, reduce, and resume workflow for bounding concurrent heavy jobs in a WSL guest using the incident collector's evidence.
tags: [wsl, diagnostics, capacity]
---

<!-- cspell:words wslconfig hyperv pgscan pgsteal kswapd -->
<!-- cspell:words pswpin pswpout pgmajfault -->

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
  observe for a finite window, compare against the baseline, then admit more,
  hold, or ask the owner to reduce, and resume with hysteresis.
- It reads timestamped host and guest evidence over the same interval and keeps
  gauges, cumulative counters, and deltas or rates apart.
- It treats missing or timed-out evidence as unknown, and judges partial
  evidence field by field. Unknown is never read as zero pressure, and it can
  never license admitting more work.
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
  Clearing caches and changing swap are separately authorized branches of the
  [recovery runbook](wsl-incident-recovery.md#memory-swap-or-cache-changes),
  which stops at any change to the memory cap. This guide keeps the cap
  unchanged.
- It adds no automatic enforcement. Every decision is the operator's.

If the guest stops answering while you follow this guide, stop the workflow and
use the [recovery runbook](wsl-incident-recovery.md). This guide never
escalates. The per-user collector lock is shared, so the runbook's collector
would answer `already-running` while your run is active. Either let your run
reach its finite end and record its output directory in the runbook's
checkpoint, or end it first (press **Ctrl+C** in its session).

## Ground rules

Terms: a **heavy job** is one that its owners agree is heavy; the guide does
not define it by its effect on the signals. A **workload class** is one word
from a closed list: `build`, `test`, `agent-session`, `index`, or `other`. Never
record a command line, an argument, a path, or a user name.

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
`-DurationSeconds` that covers the baseline, every observation window you plan,
and a margin in **one run**, and with `-GuestDistro '<distribution>'`. The
workflow needs guest evidence to admit work, because host evidence cannot show
guest memory pressure. A host-only run can still support a hold, a request to
the owner, or a narrower hypothesis, but it can never return `within-range`.
The default interval is 5 seconds. The telemetry guide describes the small
check-then-launch race that `-GuestDistro` carries, and the runbook's
[bounded guest read](wsl-incident-recovery.md#bounded-guest-read-optional)
lists the prerequisites. The guest helper must exist at
`$HOME/.local/bin/wsl-incident-guest-snapshot` inside the guest, or every probe
fails.

Give every run its own new `-OutputDirectory`, never the default directory,
which may hold records from an incident. The log byte budget is shared by every
run that writes to one directory, and a run deletes the oldest records first;
see [Protect existing evidence](wsl-incident-recovery.md#protect-existing-evidence).
A long run can also prune its own oldest records, so copy the baseline
statistics into the evidence record before that can happen.

The telemetry guide's commands read the default directory. Point them at your
run first:

```powershell
$logs = Join-Path '<OutputDirectory>' 'dotfiles-wsl-incident-telemetry'
```

A run's records can span several numbered files: the same run identifier in the
name, then `-0000.jsonl`, `-0001.jsonl`, and so on. Read every file of your run,
in name order, for each window. The telemetry guide's newest-file command shows
only the last one.

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
| `host.disk.metrics.physicalTotal.queueLength` | Gauge | requests | present and non-null; `systemVolume.queueLength` is always null |
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
`commitLimitBytes` minus `committedBytes` (or as their ratio) and label it
derived.

### Pressure indicators and context

A heavy job is expected to raise the load on the machine, and the level of free
memory falls by construction when work runs. So the verdict rests only on
**pressure indicators**: signs of stalls and saturation. Everything else is
**context**.

| Indicator | Role | Bad direction |
| --- | --- | --- |
| Guest `psi.some` and `psi.full`, `avg60` | Pressure | High |
| Guest `deltas.pgscan_direct`, `pgsteal_direct`, `pswpin`, `pswpout` rates, and `workingset_refault` when it is known | Pressure | High |
| Host `pagesInputPerSecond` and `pagesOutputPerSecond` | Pressure | High |
| `physicalTotal.queueLength` | Pressure | High |
| Level gauges: guest `memory.available`, host `availableBytes`, derived commit headroom, `pageFilePercentUsage`, `swap.used` | Context | Low for availability, high for usage |
| Load: host CPU percentages, disk and Hyper-V throughput and operation rates, `pageReadsPerSecond`, `pageWritesPerSecond`, `pgfault`, `pgmajfault`, `pgscan_kswapd`, `pgsteal_kswapd` | Context | Not used |

Context never sets a verdict. A level gauge outside its range supports a
hypothesis only together with a pressure indicator outside its range in the
same window.

The set of pressure indicators you rely on is **fixed when you take the
baseline** and written into the record: every pressure indicator in the table,
including the guest ones, except `workingset_refault` when the counter is null
on your kernel. Do not drop an indicator later because it is inconvenient.

### Reading rules

1. **Compare like with like.** Compare gauges with gauges, and rates with
   rates, against the baseline. A cumulative total is a count since guest boot.
   Compare it only through its delta, never against a rate or a gauge. Guest
   samples are at least 60 seconds apart, so `avg10` describes only the 10
   seconds before each sample and `avg300` still carries the previous phase;
   prefer `avg60`, and the difference of `totalUsec` between two samples.
2. **Judge each field, not the whole record.** A gauge is known when it is
   present and non-null. A rate or delta is known only when its own `status` is
   `ok` and it is non-null. A failed source carries an empty `metrics`, so its
   fields are absent, not null; `host.cpu` has no `metrics` and its fields are
   null. Absent and null are both unknown. A `partial` source can still hold
   known gauges, for example on the first record of a run. The first record has
   no sample interval, so leave it out of every window. A record with `status`
   `overflow` and `error` `record-size-limit` has no host or guest block at all;
   treat it as a gap.
   **Eligible samples** are the records of the window other than the first
   record and the gaps. For a guest indicator they are the records of one probe
   attempt each: every record whose guest status is not `probe-interval`,
   `pending`, or `not-requested`. A failed attempt is eligible, and unknown. For
   a delta, the first successful guest result of the run and the first after a
   gap of more than 10 minutes are not eligible, because they have no rates. An
   indicator has **coverage** for a window when it is known in at
   least 90 percent (provisional) of its eligible samples and in at least three
   of them. Coverage only decides `within-range` (step 4); an excursion is
   tested on any indicator with at least three known samples.
3. **Unknown is not healthy.** Unknown can neither clear nor confirm a
   hypothesis. A rate, delta, or source block whose own status is `unavailable`,
   `timeout`, or `pending` is unknown for the fields it carries, whatever its
   `error` value is, and a `partial` one is judged field by field under rule
   2. Examples are `first-sample` and `counter-reset` on host rates, and
   `probe-interval`, `inhibited`, `not-requested`, `distro-not-running`,
   `wsl-client-unavailable`, a `guest-*` or `preflight-*` value, and `timeout`
   on the guest. A missing or timed-out guest reading means unknown, never an
   idle guest.
4. **Guest evidence is sparse.** The collector probes the guest at most once
   every 60 seconds and runs one guest process at a time. A successful guest
   result appears in exactly one record; the records between probes read
   `unavailable` with `probe-interval`, which is normal. Guest deltas cover the
   time between two successive guest samples, not `sampleIntervalSeconds`; if
   more than 10 minutes pass between them, the next sample starts a new
   baseline and has no rates. Size every window to hold several guest samples
   (the provisional minimum is three). A guest `timeout` or `preflight-timeout`
   is the recovery runbook's stalled-guest state: the collector stops probing
   for the rest of the run, and this workflow stops with it. Hold admissions
   and follow the runbook; do not start another guest run from here. An
   `inhibited` guest or host source goes to the runbook too, because an
   inhibition persists across runs. A failed or invalid guest result can also
   suppress or inhibit the guest source, after which the records read
   `probe-interval` or `inhibited` for the rest of the run: treat that like a
   timeout. Plain unknowns, such as `distro-not-running` or
   `wsl-client-unavailable`, do not stop the collector: it probes again after 60
   seconds, but coverage is judged per window, so the earlier unknown results
   stay in this window and only a new window can recover. Start a new run with
   `-GuestDistro` only if you have deliberately ended this one, and only when
   the runbook's
   [bounded guest read](wsl-incident-recovery.md#bounded-guest-read-optional)
   prerequisites hold; the new run needs its own baseline.
5. **Memory pressure only, and a kernel-dependent counter.** The guest helper
   reads `/proc/meminfo`, `/proc/vmstat`, and `/proc/pressure/memory`, so the
   records carry no guest CPU or I/O pressure. It reads `workingset_refault` by
   exact name. Kernels that split it into `workingset_refault_anon` and
   `workingset_refault_file` give a null counter and an unavailable delta, and
   the guest record is then `partial` with the error `provider-unavailable`.
   Such a record is still usable for every field that is known; only the
   refault evidence is unknown, and that indicator leaves the relied-on set.
   Check your own guest while healthy. This prints `0` on such a kernel:

   ```sh
   grep -c '^workingset_refault ' /proc/vmstat
   ```

6. **Aggregates hide detail.** `physicalTotal` is a total across physical
   disks, and `systemVolume` is only the Windows system volume. The records do
   not say which of these holds the guest's virtual disk, so a storage
   attribution to the guest is a hypothesis.
7. **Per-run aliases.** Hyper-V `virtualStorage[]` entries use random per-run
   aliases, so a device is attributable within one run only, and
   `overflowCount` above 0 means devices were omitted. Baseline and observation
   windows from separate runs cannot be compared per device, so use one run for
   both, or compare only `physicalTotal`.
8. **Judge windows, not single records.** Host rates are averages over
   `sampleIntervalSeconds`. Judge a window by its many samples.

## Workflow

The loop is: baseline, admit, observe, compare, decide, resume, record. Every
number in it is provisional until you calibrate it against your own healthy
observations (see [Thresholds](#thresholds)).

### 1. Baseline

Take the baseline **before the first admitted job**, in the same collector run
you will use for the observations, while the machine is idle or lightly loaded.
For each pressure indicator in the relied-on set, write down the range it
spans: the minimum and maximum over all known baseline samples, and the median
for reporting. Do not trim samples. Each repeat must meet the coverage rule of
reading rule 2; otherwise lengthen or repeat it. An indicator that is unknown
in every baseline sample, such as `queueLength` on a host that does not report
it, cannot be relied on, so no window can be `within-range` and the count stays
where it is. A range of zero width, such as 0 to 0, is legal. If calibration
fails only because of tiny values, lengthen the baseline and record the change.
Record the window's UTC start and end and the run identifier as the baseline's
source. Provisional starting length: 10 minutes, repeated once, with the range
spanning both repeats. To baseline a new workload class, do it before any job
of that class runs, or start a new run and a new baseline.

### 2. Admit one bounded workload

Start conservatively with one heavy job. This is a provisional operating
policy, not a measured safe threshold. Record the admitted job count, the
workload class, and the start time in UTC of each admitted job. Do not admit
another job while the current count is being observed.

### 3. Observe for a finite window

Pick the window length before you admit, make it finite, and do not extend it
to wait for a better answer. If it has to be longer, record a new window. The
observation window starts at the admission, has the same duration as one
baseline repeat, and counts only while all the admitted jobs run: record each
job's end time in UTC. If a job ended early, still give the part of the window
before the end its step 4 verdict: an excursion stands. Ask the owner why the
job ended before any repeat, and do not re-admit it on a repeat. Compare each
window with the baseline range every time, not only with the window before it.
Size
`-DurationSeconds` for the whole ladder of admissions, or take a new baseline
in a new run.

### 4. Compare and decide

Establish validity first (reading rule 2). Then, for each pressure indicator in
the relied-on set with at least three known samples, count the known samples
outside its baseline range in the bad direction, and take the share of its
known samples. Assign one verdict from the worst indicator:

- `out-of-range-sustained`: some indicator is outside its range in more than
  half of its known samples (provisional).
- `out-of-range-brief`: otherwise, some indicator is outside its range in more
  than one fifth of its known samples (provisional).
- `unknown`: no indicator is outside its range in more than one fifth of its
  known samples, and some indicator in the relied-on set lacks coverage or the
  window holds a guest `timeout`, `preflight-timeout`, or `inhibited` record.
  This verdict is for missing evidence only.
- `within-range`: every indicator in the relied-on set has coverage for the
  window, and none is outside its range in more than one fifth of its known
  samples. A guest `timeout`, `preflight-timeout`, or `inhibited` record in the
  window is never an excursion, but it bars this verdict.

An out-of-range verdict takes precedence over `unknown`: a known excursion is
not cancelled by missing data elsewhere. A window with no guest evidence, with
a guest block of `not-requested`, with fewer than three known guest samples,
or holding a guest `timeout`, `preflight-timeout`, or `inhibited` record can
never be `within-range`.

| Verdict | Decision | Decision class |
| --- | --- | --- |
| `within-range` | If no window since the baseline was other than `within-range`, or the hysteresis in step 5 is met, you may admit one more job, but only up to the count the owners need. Return to step 2 for the new count. | Admission |
| `unknown` | Hold new admissions. No verdict is possible. Gather a new window, except after a guest `timeout`, `preflight-timeout`, or an `inhibited` source (reading rule 4). After two consecutive `unknown` windows, stop gathering windows: stay at the current count, or end the run deliberately and start a new run and baseline under the runbook's prerequisites. | Admission |
| `out-of-range-brief` | Hold new admissions at the current count and observe another window at the same count. Two consecutive `out-of-range-brief` windows count as `out-of-range-sustained`. | Admission |
| `out-of-range-sustained` | Hold new admissions and ask the owner of the running work to consider reducing it. The owner decides. | Admission, then a request to the owner |

### 5. Resume with manual hysteresis

After any window that was not `within-range`, a `within-range` window admits
nothing by itself. Resume admissions only after two consecutive `within-range`
windows at the held count (provisional), and then resume one job at a time, not
at the count that preceded the pressure. Never resume on unknown evidence. If
the owner declines the request or does not answer, admissions stay held and the
guide does not escalate. The last count that finished the hysteresis with
`within-range` is your provisional operating count, and a count that returned
`out-of-range-sustained` is a ceiling until the workload or the machine changes.
Stop at the count the owners need: the loop is not a search for the limit.

### 6. Evidence record

Keep one record for each window and decision, including a hold or a request to
the owner, not only a change of the admitted count:

```text
run-id:                <runId>
window-utc:            <start>/<end>, finite, same duration as <baseline label>
job-utc:               <start>/<end>, one line per admitted job
effective-memory-cap:  <value read from the effective .wslconfig, or "default (key absent)">
admitted-job-count:    <before> -> <after>
workload-class:        build | test | agent-session | index | other (one per job)
baseline-source:       <window label, UTC start/end>
baseline-ranges:       <for each relied-on indicator: median and range>
relied-on-set:         <pressure indicators fixed at baseline>
scenario:              guest-memory | host-memory | storage | unavailable | none (one or more)
host-summary:          <pressure indicators used and the share of samples outside the range>
guest-summary:         <pressure indicators used, number of known guest samples, or "unknown">
unknown-fields:        <fields that were unknown, or "none">
verdict:               within-range | out-of-range-brief | out-of-range-sustained | unknown
decision:              admit | hold | ask-owner-to-reduce (implies hold) | resume
owner-response:        <if asked, the owner's decision>
rollback:              <how the previous admitted count is restored by the owner>
```

### Measurement overhead

The collector is a bounded foreground process. A guest-enabled run adds two
short sequential `wsl.exe` calls at most every 60 seconds: a 1-second
running-state preflight, then a 2-second probe. The telemetry guide's
[overhead check](wsl-incident-telemetry.md#check-collection-overhead) gives a
rough way to compare a quiet window with and without the collector. Keep the
5-second interval and stop the run at the end of the loop. Observation can
change timing, so treat a small difference as noise.

## Scenarios

Judge validity first, then these hypotheses. A scenario needs its required
fields to be known in the same window; otherwise it is the fourth scenario.
More than one scenario can be supported in one window; list each in the record.

| Scenario | Evidence that supports it | Evidence that weakens it | Required known fields | Next observation |
| --- | --- | --- | --- | --- |
| Guest memory or reclaim pressure | `psi.some.avg60` above baseline; `deltas.pgscan_direct`, `pgsteal_direct`, `pswpin`, or `pswpout` `.perSecond` above baseline in the same window; corroborated by low `memory.available` | Deltas at baseline while only `counters.*` are large; `psi.some` at baseline | `psi` and the reclaim and swap deltas, in at least three guest samples | Another window at the same count, or after the owner decides on a reduction |
| Host memory or pagefile pressure | `pagesInputPerSecond` or `pagesOutputPerSecond` above baseline; corroborated by `committedBytes` close to `commitLimitBytes`, `pageFilePercentUsage` high, or low `availableBytes` | Paging at baseline | The host paging rates in every sample used | Another window at the same admitted count |
| Storage saturation without current memory pressure | `physicalTotal.queueLength` above baseline; corroborated by high read or write rates and Hyper-V `virtualStorage[]` rates; host paging rates, guest `psi.some`, and reclaim deltas at baseline | Reclaim deltas or `psi.some` rising together with the disk signals | The disk entries, the host paging rates, and the guest `psi` and reclaim deltas | Another window with the next admission withheld |
| Unavailable or conflicting evidence | A required field is unknown, the guest timed out, or the pressure indicators conflict: for example `psi.some` is out of range while the reclaim and swap deltas sit at baseline, or an indicator is out of range while a required field of its scenario is unknown | A complete, consistent window | Not applicable | The same count in a new window; record `unavailable`, and the verdict still comes from the pressure indicators |

Guest paths in this table are relative to `guest.metrics`. Each row's
supported, weakened, or unknown status is a hypothesis to test with the next
window, and the only actions are the admission decisions and owner requests in
[step 4](#4-compare-and-decide). Correlation inside a window does not prove a
culprit, and the records do not name processes. Claim "no evidence of pressure"
only when the verdict is `within-range`.

## Worked examples

All values are synthetic, rounded, and from no real host. They show how to read
the fields, not what a threshold should be. Each record is trimmed to the
fields discussed; real records carry every field the telemetry guide lists. The
other samples in each window read alike, which is what lets one record stand
for its window here. Each example is its own run, so counters do not carry over
from one to the next.

### Example 1: rising reclaim rate in the same window

One run holds two 10-minute baseline repeats (00:00 to 00:10, then B1 from
00:10 to 00:20) and a loaded window from 00:20 to 00:30, when one job is
admitted. This guest record is the last in B1.
It is `partial` because the guest kernel splits the refault counter, so that
field is unknown and the rest is usable:

```json
{
  "sampleTimeUtc": "2000-01-01T00:19:00.0000000Z",
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
the 60 seconds since the previous guest sample, which is not shown. The counter
rose by about 8 million since the baseline record and `psi` stalled for about
170 seconds, which is consistent with a steady rate over most of the window:

```json
{
  "sampleTimeUtc": "2000-01-01T00:29:00.0000000Z",
  "guest": {
    "status": "partial",
    "error": "provider-unavailable",
    "metrics": {
      "memory": { "status": "ok", "unit": "kB", "total": 20971520, "available": 1048576 },
      "swap": { "status": "ok", "unit": "kB", "total": 5242880, "used": 2097152 },
      "psi": { "status": "ok", "some": { "avg10": 33.5, "avg60": 31.2, "avg300": 29.9, "totalUsec": 168000000 } },
      "counters": { "pgscan_direct": 56100000, "workingset_refault": null },
      "deltas": {
        "pgscan_direct": { "status": "ok", "value": 900000, "perSecond": 15000 },
        "workingset_refault": { "status": "unavailable", "value": null, "perSecond": null }
      }
    }
  }
}
```

| Indicator | Role | Baseline (range over both repeats) | Loaded window (typical sample) |
| --- | --- | --- | --- |
| `psi.some.avg60` | Pressure | 0.0 to 0.0 | 31.2 |
| `deltas.pgscan_direct.perSecond` | Pressure | 0 to 0 | 15000 |
| `deltas.workingset_refault` | Not relied on (unknown on this kernel) | unknown | unknown |
| `memory.available` (kB) | Context | 15728640 to 15728640 | 1048576 |

The evidence that supports a reclaim-pressure hypothesis is the *rate* rising
inside the same window as the admission, together with `psi.some`, corroborated
by low available memory. The cumulative `counters.pgscan_direct` is large in
both records and says only that reclaim happened at some time since boot. Both
relied-on pressure indicators shown are outside their ranges in all of the
loaded window's guest samples, so the verdict is `out-of-range-sustained`: hold
admissions and ask the owner to consider reducing the running work. The record
for this window:

```text
run-id:                synthetic-run-1
window-utc:            2000-01-01T00:20:00Z/2000-01-01T00:30:00Z, same duration as one repeat
job-utc:               2000-01-01T00:20:00Z/2000-01-01T00:32:00Z (one job)
effective-memory-cap:  20 GB
admitted-job-count:    0 -> 1
workload-class:        build
baseline-source:       both repeats, 2000-01-01T00:00:00Z/2000-01-01T00:20:00Z
baseline-ranges:       psi.some.avg60 median 0.0, 0.0 to 0.0; pgscan_direct rate median 0, 0 to 0; the others as in the baseline
relied-on-set:         psi.some.avg60, psi.full.avg60, pgscan_direct, pgsteal_direct, pswpin, pswpout, paging rates, queueLength
scenario:              guest-memory
host-summary:          paging rates and queueLength inside their baseline ranges (not shown)
guest-summary:         psi.some.avg60 and the pgscan_direct rate outside the range in every known guest sample of the window
unknown-fields:        deltas.workingset_refault (not relied on)
verdict:               out-of-range-sustained
decision:              ask-owner-to-reduce
owner-response:        pending
rollback:              the owner restores the previous count when the owner chooses to
```

It does not show which job caused the pressure.

### Example 2: host memory or pagefile pressure

Baseline from two quiet 10-minute repeats in the same run:

| Indicator | Role | Baseline (range) |
| --- | --- | --- |
| `pagesInputPerSecond` | Pressure | 0 to 15 |
| `pagesOutputPerSecond` | Pressure | 0 to 10 |
| Guest `psi.some.avg60` | Pressure | 0.0 to 0.2 |
| `committedBytes` over `commitLimitBytes` (derived) | Context | 0.38 to 0.42 |
| `pageFilePercentUsage` | Context | 10.0 to 14.0 |

A sample from the observation window:

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
    "status": "partial",
    "error": "provider-unavailable",
    "metrics": {
      "memory": { "status": "ok", "unit": "kB", "total": 20971520, "available": 12582912 },
      "psi": { "status": "ok", "some": { "avg10": 0.1, "avg60": 0.0, "avg300": 0.0, "totalUsec": 1250000 } }
    }
  }
}
```

Both host paging rates are far above their baseline ranges. As context,
committed memory is about 96 percent of the commit limit (derived), against a
baseline near 40 percent, and the page file is heavily used, while the guest
reports ample available memory and `psi.some` at baseline, and the other relied-on
indicators are inside their ranges. That supports host memory or pagefile
pressure and weakens a guest-side reclaim hypothesis. If the
paging rates stay outside their ranges for more than half of the window's host
samples, the verdict is `out-of-range-sustained`: hold admissions and ask the
owner to consider reducing the running work. The next observation is another
window at the same admitted count.

### Example 3: storage saturation without current memory pressure

Baseline from two quiet 10-minute repeats in the same run:

| Indicator | Role | Baseline (range) |
| --- | --- | --- |
| `physicalTotal.queueLength` | Pressure | 0.0 to 1.5 |
| `pagesInputPerSecond`, `pagesOutputPerSecond` | Pressure | 0 to 15, 0 to 10 |
| Guest `psi.some.avg60` | Pressure | 0.0 to 0.2 |
| Guest `pgscan_direct` and `pswpin` rates | Pressure | 0 to 0 |
| Host `availableBytes` (bytes) | Context | 17179869184 to 21474836480 |

A sample from the observation window:

```json
{
  "sampleTimeUtc": "2000-01-01T02:09:00.0000000Z",
  "host": {
    "memory": {
      "status": "ok",
      "error": null,
      "metrics": {
        "availableBytes": 17179869184,
        "committedBytes": 21474836480,
        "commitLimitBytes": 53687091200,
        "pageFilePercentUsage": 12.0,
        "pagingRates": {
          "status": "ok",
          "counters": {
            "pagesInputPerSecond": { "status": "ok", "error": null, "value": 4.0 },
            "pagesOutputPerSecond": { "status": "ok", "error": null, "value": 2.0 }
          }
        }
      }
    },
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
      "counters": { "pgscan_direct": 48900000, "pswpin": 5000 },
      "deltas": {
        "pgscan_direct": { "status": "ok", "value": 0, "perSecond": 0 },
        "pswpin": { "status": "ok", "value": 0, "perSecond": 0 }
      }
    }
  }
}
```

The disk queue is far above its baseline range, with throughput high as
context. The host paging rates, the guest `psi`, and the reclaim and swap
deltas are inside their ranges, host available memory is inside its range, and
the large `counters` values did not change in the window, so they are history,
not current pressure.
All the required fields in the scenario table are known, so this supports
storage saturation without current memory pressure. It does not say that the
guest's disk is the saturated one, because the records cannot attribute the
volume to the guest (reading rule 6). If the queue stays outside its range for
more than half of the host samples, the verdict is `out-of-range-sustained`:
hold admissions, withhold the next one, and ask the owner to consider reducing
the running work.

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
healthy, and every later record in that run reads `probe-interval` (or
`inhibited`, if the collector could not verify its cleanup). The host's high
privileged CPU time is context, and it cannot be attributed to the guest or
cleared by it. With the host indicators in range (not shown), the verdict is
`unknown`: hold admissions. A guest `timeout` is
the recovery runbook's stalled-guest state, so this workflow stops here and the
runbook takes over; do not start another guest run from this guide. The
host-only records the run keeps writing can still show host memory and storage
pressure, and they can support a hold or a request to the owner, but never an
admission. Conflicting evidence works the same way: if the pressure indicators
disagree, for example `psi.some` out of range while the reclaim and swap deltas
sit at baseline, record `unavailable`, let the pressure indicators decide the
verdict, and observe the same count again. If two scenarios are supported at
once, list both in the record.

## Thresholds

- An **observed baseline** is a range you measured, with its source: the window
  label, its UTC start and end, and the statistic (median and range over all
  known samples). A threshold of this kind carries its source in the record.
- A **provisional value** is a starting point with no measurement behind it.
  Label any provisional value as such wherever you copy it.
- Calibrate against healthy observations before you rely on a value. Run the
  workflow with a light workload you know to be fine and confirm it returns
  `within-range`. If it does not, check the baseline and the relied-on set
  before blaming the workload, and never widen a range just to obtain the
  answer you expected.
- Do not turn a value into automatic enforcement. Anything that starts,
  throttles, or stops work on its own needs a separate, evidence-backed
  decision and its own issue.

Every number in this guide is one of the following:

| Number | Where | Status |
| --- | --- | --- |
| 5 seconds | Default sample interval | Collector default |
| 60 seconds | Spacing between guest probes | Collector constant, read from the script |
| 1 second and 2 seconds | Guest preflight and probe bounds | Collector constants, read from the script |
| 10 minutes | Gap after which a guest sample has no rates | Collector constant, read from the script |
| 10, 60, 300 seconds | `psi` averaging windows | Kernel definition |
| 20 GB | The effective memory cap of the operator this guide was written for | Observed configuration, unchanged |
| One heavy job | First admission | Provisional |
| 10 minutes, repeated once | Baseline length | Provisional |
| Three known samples | Minimum per indicator and window | Provisional |
| 90 percent of the eligible samples | Coverage needed for an indicator to count toward `within-range` | Provisional |
| One fifth and one half of the samples | Verdict boundaries | Provisional |
| Two consecutive windows | Hysteresis before resuming, and the limit on repeated brief or unknown windows | Provisional |
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
| Linux cgroup v2 `io.max` | Per block-device bandwidth and operation limits of one cgroup | CPU and memory; buffered writeback is attributed to a cgroup only where the filesystem supports it, otherwise to the root cgroup; I/O over a shared or network filesystem may not pass through a block device the limit can name | The `io` controller is enabled, delegation, and a block device the limit can name |
| Linux cgroup v2 `memory.high` | Throttling and reclaim pressure on one cgroup once its usage exceeds the value | CPU and I/O directly; it creates reclaim pressure on that cgroup by design, which costs CPU and can add swap and refault reads | The `memory` controller is enabled, and delegation |
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
  the 60-second guest probe spacing and its two sequential calls, the 10-minute
  no-rates gap, the exact counter names, and the partial-record behavior were
  read from them. The key paths of the example records were checked against
  records produced by the collector's own functions, and the guest helper was
  run against a fixture with split refault counters. Nothing was run on a
  Windows host.
- [WSL incident telemetry](wsl-incident-telemetry.md) for the collector
  options, the record fields, and the overhead check.
- [WSL incident recovery runbook](wsl-incident-recovery.md) for protecting
  existing evidence and for the bounded guest read.
- [Advanced settings configuration in WSL](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)
  for the `.wslconfig` `memory` and `processors` keys and for when a change
  applies.
- [Pressure Stall Information](https://docs.kernel.org/accounting/psi.html)
  for `some`, `full`, the `avg10`, `avg60`, and `avg300` percentages, and the
  cumulative `total` in microseconds.
- [Control Group v2](https://docs.kernel.org/admin-guide/cgroup-v2.html) for
  `cpu.max`, `io.max`, `memory.high`, controller enablement, delegation, and
  writeback attribution. Its `memory.stat` section lists the split
  `workingset_refault_anon` and `workingset_refault_file` entries; the check in
  reading rule 5 shows whether your guest's `/proc/vmstat` does the same.
