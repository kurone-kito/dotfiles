---
type: guide
title: WSL incident recovery runbook
description: Manual SSH checkpoint and evidence-preserving recovery runbook for a Windows host whose WSL guest stops answering.
tags: [wsl, ssh, recovery, diagnostics]
---

<!-- cspell:words wslconfig YYYYMMDDTHHMMSSZ -->

# WSL incident recovery runbook

This runbook is for one situation: a Windows host runs a WSL 2 guest, the
guest stops answering, and you must decide what to do next without losing
evidence or work. It is manual. Nothing here starts a service, registers a
task, changes a setting, or restarts anything on its own.

It connects three existing pieces and does not repeat them:

- [WSL incident telemetry](wsl-incident-telemetry.md) documents the
  collector, its limits, and its record schema.
- [Deploying sshd_config](sshd-config-setup.md) documents how SSH
  configuration reaches a machine. This runbook assumes SSH access is
  already set up and never changes credentials or configuration.
- [IDD Resume — Detail Reference](idd-resume-detail.md) and
  `.github/instructions/idd-resume.instructions.md` own how an interrupted
  IDD session is resumed.

This runbook does not diagnose a root cause. Evidence from one incident is
reported evidence, not a controlled reproduction, and correlation between
two counters does not name a culprit process.

## Ground rules

- Capture evidence before acting, and capture it from the host first. The
  host keeps answering when the guest does not.
- Bound every command with a time or count limit before you run it. Never
  run a command that can wait forever. A limit is a best effort on a stalled
  volume: `timeout` ends the call it started, but a process stuck in
  uninterruptible I/O can outlast it, and a host-side file read or copy can
  stall the same way. Where a snippet below has no bound of its own, run it as
  a child job (`Start-Job`, then `Wait-Job -Timeout`) with a wait timeout.
  Treat an expired limit as a failed step, note any leftover process by PID
  and start identity without ending it, and stop.
- Recovery is not a reason to reset, stash, clean, or force-checkout a
  working tree, to delete a lock or state file, or to take over another
  session's IDD claim. None of these is a default step anywhere below. The
  documented procedures that do these things are separately authorized
  branches: the IDD worktree recovery, which stashes work, removes a
  worktree and its claim lock, and the reconciliation of
  `inhibitions.json`, which ends by deleting that file.
- Never end a process by name or by pattern. An agent ends an individual
  process only if it started that process itself, by its recorded PID. Any
  other individual process is the operator's to end, and only after an exact
  match of PID and creation time recorded in the checkpoint and re-verified
  just before acting.
- The separately authorized branches (see [Escalation](#escalation)) are the
  disruptive actions. Each needs the operator's explicit authorization in the
  current session,
  naming the exact command and target, after the checkpoint exists or after
  you have recorded why it cannot exist. An agent never authorizes itself,
  and attention alone is not approval. The operator, not an agent, executes
  every separately authorized branch except the IDD worktree recovery.
- Do not present an earlier multi-command intervention as a proven fix. A
  sequence of several changes made together cannot show which change, which
  elapsed time, or which workload change mattered.
- Keep the operator's effective WSL memory cap, reclaim settings, and
  sparse-VHD settings exactly as they are. See
  [Settings this runbook leaves alone](#settings-this-runbook-leaves-alone).
- Keep logs and checkpoints local and private. They can contain process
  identifiers, branch names, and issue numbers.

## Access states

Three ways to reach the machine matter, and they fail independently:

| Access | What it reaches | Typical failure |
| --- | --- | --- |
| Windows-host SSH | The Windows host's own `sshd`, a host-native shell | Service stopped, firewall, network |
| Guest SSH | An `sshd` inside the distribution | Guest hung or stopped |
| Local console | A keyboard and screen, or a remote console, at the host | Not available remotely |

Host SSH and guest SSH are different services. With mirrored networking,
which this repository's `home/dot_wslconfig` selects, the host and the guest
can share addresses, so never assume the same address and port reach the
same service. Write the two ports as separate placeholders,
`<host-ssh-port>` and `<guest-ssh-port>`, and confirm which service answers
each one while everything is healthy.

Host SSH is the path this runbook relies on when the guest is unavailable.
Installing or activating host SSH is out of scope here.

### Validate a host-native shell while healthy

Do this once while the guest is responsive, not during an incident. The goal
is to prove you can run the collector from a Windows-host SSH session
without replacing the SSH default shell and without an interactive desktop.

Windows OpenSSH uses `cmd.exe` as its login shell unless the machine was
changed (see
[Windows: Changing the default SSH shell](sshd-config-setup.md#windows-changing-the-default-ssh-shell)).
Do not change that shell for this check. Start PowerShell explicitly and use
`-File`, which avoids most quoting differences between login shells.

Every `ssh` example in this runbook carries `-o BatchMode=yes -o
ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3` and is
wrapped in a client-side `timeout` sized to the remote command plus a margin.
`ConnectTimeout` covers only connection setup. The keepalive options detect a
dead transport only: they end a session that goes silent, after about a
minute, but not a command that hangs on the host while the connection stays
up, because the keepalive replies keep arriving. For that case the wrapper is
the only bound on the whole call. A client-side timeout does not stop a
command that is already running on the host, so keep every remote command
short and bounded too.

If your client has no `timeout`, use an equivalent. `gtimeout` from GNU
coreutils on macOS ends the client at the deadline. On a Windows client, run
the `ssh` call as a child job with a wait timeout (`Start-Job`, then
`Wait-Job -Timeout`). That only stops you waiting: it does not end the job or
its `ssh` process, and the remote command can go on running. When the wait
expires, note the leftover `ssh` process by PID and creation time, end nothing,
and make no further host call until the operator has dealt with it. With no
equivalent at all, use another client that has one, or the local console. If
neither exists, run no host call from this client: write
`not preserved: no bounded client` for the evidence you could not collect, the
state-file copy and the collector run, and hand off. The collector's own
`-DurationSeconds` is not such a bound, because it is checked only once
sampling begins, so a start can stall earlier, on the state directory, the
lock, or the log folder, and the keepalive does not end a command that hangs
on the host.

The first check below shows the wrapped form:

```sh
timeout 30 ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p <host-ssh-port> <host-user>@<host> \
  "powershell.exe -NoLogo -NoProfile -NonInteractive -File C:\Users\<host-user>\.local\bin\wsl-incident-capture.ps1 -Help"
```

Adjust the quoting for your login shell and for spaces in the path. If a
restricted execution policy blocks the script, add `-ExecutionPolicy Bypass`
to that one invocation. It is a PowerShell host option, so it goes before
`-File`, as in `powershell.exe -NoLogo -NoProfile -NonInteractive
-ExecutionPolicy Bypass -File <script>`. Placed after the script path it is
passed to the script as an argument and bypasses nothing. It applies to that
process only. Do not change the machine or user policy for this.

In this runbook `<private-incident-dir>` is the new directory for one
collector run, different for every run, and `<private-scratch-dir>` is a
directory for checks and activity probes, which may be reused because it holds
no evidence. `<private-preserve-dir>` is the one private folder for copies you
must not lose: the collector state files, uncommitted work, and the output of
an IDD worktree recovery. It is a new directory on a host volume, which the
guest reaches as `/mnt/<drive>/...`, outside every worktree and outside `/tmp`
(a restart can clear `/tmp`, and it sits on the guest's own disk image). Create
it before an incident, readable by your account only. While healthy, check
that the guest can create and remove a file there and that no other ordinary
account has access (`icacls <path>` on the host lists who does; the system and
administrator accounts are inherited and expected), instead of assuming it.
Each of the three stands for one absolute path on a local volume that is not
synchronized or shared, for example under `C:\Users\<host-user>`. Choose paths
with no spaces and no characters a shell treats specially, so the commands need
no extra quoting. Use the same absolute form in every command, in the spelling
of the shell that runs it (`C:\Users\...` on the host, `/mnt/c/Users/...` in
the guest), because a relative path resolves against each session's current
directory.

Then confirm each of these. No checkpoint exists yet, so keep a private note
of the date and the cap and copy it into the first checkpoint:

1. `-Help` prints the usage text and the exit status is 0. That
   proves the file is deployed and runnable from a noninteractive session.
2. A short bounded host-only run works the same way and writes records. Give
   it its own scratch output directory, and copy the collector state files
   first, because any start rewrites them. The log byte budget covers a whole
   logs directory (see [Protect existing evidence](#protect-existing-evidence)),
   so a check that shares the real directory can delete real evidence:

   ```sh
   timeout 90 ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p <host-ssh-port> <host-user>@<host> \
     "powershell.exe -NoLogo -NoProfile -NonInteractive -File C:\Users\<host-user>\.local\bin\wsl-incident-capture.ps1 -IntervalSeconds 5 -DurationSeconds 10 -OutputDirectory <private-scratch-dir>"
   ```

   Then find the new `.jsonl` file under
   `<private-scratch-dir>\dotfiles-wsl-incident-telemetry`, using the review
   commands in
   [Find and review records](wsl-incident-telemetry.md#find-and-review-records).
   The collector reads host counters and has no window to show, but confirm
   on your own host that nothing in your SSH setup changes its output
   directory or access rights.
3. A read-only list of running distributions answers within a few seconds.
   This does not start a distribution:

   ```sh
   timeout 15 ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p <host-ssh-port> <host-user>@<host> "wsl.exe --list --running --quiet"
   ```

   Captured raw, that output can contain NUL characters that make names
   look spaced out. The collector strips them before matching.

   The wrapper bounds the client only, so the remote `wsl.exe` process can
   remain. Run this check only with a bounded client (see above), and skip it
   otherwise. Treat no answer as a failed check, do not run it again, and
   note the leftover process by PID and creation time. During an incident,
   prefer the collector's own preflight, which has a 1-second bound, to a
   manual call.

4. A short bounded run with a guest works and shows rates. Do this only when
   step 3 listed the distribution as running, and give the run its own scratch
   output directory. Copy the collector state files first, as in step 2. The
   collector reads the guest at most once every 60
   seconds, so a shorter run shows one guest reading and no rates. About 70
   seconds covers a second reading. Adjust the quoting for your login shell,
   and under a `cmd.exe` login shell pass the name without single quotes (see
   [Start](#start)):

   ```sh
   timeout 100 ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p <host-ssh-port> <host-user>@<host> \
     "powershell.exe -NoLogo -NoProfile -NonInteractive -File C:\Users\<host-user>\.local\bin\wsl-incident-capture.ps1 -IntervalSeconds 5 -DurationSeconds 70 -GuestDistro '<DistroName>' -OutputDirectory <private-scratch-dir>"
   ```

   Read the new file as in step 2. The first completed guest reading carries
   memory and swap values, and the next one, about a minute later, adds
   `guest.metrics.deltas` rates. `guest.status` is `ok`, or `partial` when the
   kernel lacks a counter the helper reads. A kernel that exposes
   `workingset_refault` only as separate `_anon` and `_file` counters, as the
   6.18 kernel this runbook was checked against does, reports `partial` and
   leaves that one delta `unavailable`. A partial reading still counts as
   working, and its `guest.error` reads `provider-unavailable`, as a pending
   record's does (see fixture 2): the collector fills that value for any status
   other than `ok` or `timeout` that comes with no listed error. The probe runs
   `$HOME/.local/bin/wsl-incident-guest-snapshot` inside the distribution
   through `/bin/sh`, and that helper needs `bash`. Only a chezmoi apply inside
   the distribution on Linux places it, so a missing or non-executable helper
   shows up here as `guest.error` `guest-output-invalid`. Fix that now, as its
   own change.

5. Read the machine's effective memory cap. Open the effective
   `%UserProfile%\.wslconfig` on the host, not this repository's source file,
   and note the `memory` value under `[wsl2]`. If the key is absent, record
   `default (key absent)`. Do not edit the file. Put the value in your private
   note, and copy it into the checkpoint's `effective-memory-cap` line when you
   write the checkpoint.

6. The listing of outstanding `wsl.exe` processes runs from a noninteractive
   session. Save the snippet from
   [Responsive guest and outstanding calls](#responsive-guest-and-outstanding-calls)
   as `list-wsl-processes.ps1` in `<private-scratch-dir>`, and run it in the
   same wrapped `-File` form as step 1. It prints a process id and a creation
   time for each running `wsl.exe`, and nothing when there is none.

If any step fails while healthy, fix it then, as its own change. Do not
discover it for the first time during an incident.

## The collector from SSH

The collector is the one in
[WSL incident telemetry](wsl-incident-telemetry.md). It has no
start, status, or stop subcommand. What it ships is a foreground run, a
`-Help` usage text, a finite duration, and a per-user lock. This section
states how to use exactly that from SSH.

### Protect existing evidence

The log byte budget is shared by every run that writes to the same logs
directory. At start, each run deletes the oldest collector log files there
until the directory fits its own `-MaximumLogBytes`, and a later segment or
record that would exceed the budget does the same. A new run in a directory
that already holds records can therefore delete them, including the
one-second run used to check whether a collector is active.

Do not share a logs directory. Give every run you start during an incident
its own new `-OutputDirectory`, never the default directory and never one an
earlier run used. The collector creates its logs in a
`dotfiles-wsl-incident-telemetry` subdirectory of it and applies its budget
only there, so records written elsewhere are never touched. Give checks,
smoke tests, and activity probes their own scratch directories for the same
reason. Record each run's directory in its entry of the checkpoint's
`telemetry-runs` list. Avoiding the shared directory needs no copy step.

The per-user state directory is different: every run shares it, whatever the
output directory. A start reads and rewrites `inhibitions.json` and replaces
`collector.lock.json`, which hold the cleanup and ownership evidence the later
sections rely on. The rewrite keeps every inhibition entry whose cleanup was
not verified, and drops only an entry whose cleanup was verified and whose
exact process has exited. The lock metadata it replaces is replaced only when
no collector is active, so it describes a run that is no longer active. Its
recorded process may still be running, for example an interactive PowerShell
host whose attempt to delete the lock file failed, so never read the metadata
as proof that the process has exited. Reading the
files is therefore for the checkpoint's record, and only a copy keeps the
evidence. They live in `%LOCALAPPDATA%\Dotfiles\wsl-incident-telemetry`.
Before any new run, read both files if they exist, without editing or
deleting them, as a child job with a wait timeout, as the ground rules say for
any host-side file read. Then copy each one, byte for byte, as the same kind
of child job, before the start. First create a new folder for that run under
`<private-preserve-dir>` with `New-Item -ItemType Directory -ErrorAction Stop`,
which fails if the folder exists, so no earlier copy is overwritten. If it
reports an error, stop, choose a new name, and copy nothing. Then copy each
file to an explicit name inside it, for example
`Copy-Item -LiteralPath <file> -Destination <folder>\<file-name>`, and check
that `Get-FileHash` gives the same value for the original and the copy. If the
values differ, stop: start no run, copy again into a new folder, and if they
still differ, record `not preserved: copy mismatch` for that file and leave the
decision to start to the operator. Copy a file that fails to parse too. The
collector replaces an unparseable `inhibitions.json`, and any entry whose
source it does not know or whose process identity is unusable, with a
placeholder entry (source `*`,
`processId` -1), so the original content is gone after the next start. Write
what you find, with the time you read it, in the
`state-before-start` field of that run's entry in the checkpoint's
`telemetry-runs` list, so each run keeps its own reading: for
`inhibitions.json`, the number of entries and each one's source and whether it
has a usable process identity, or `unparseable` for a file that fails to
parse; for the lock metadata, its `processId`, `startTimeTicks`, and `runId`,
or `unparseable`; for `copy`, the folder holding the copies, or
`not preserved: reason`. The
per-user lock is shared across output directories too, so a probe with a
scratch directory still answers `already-running`.

### Start

Always pass an explicit finite `-DurationSeconds` when you start it from SSH.
If the SSH connection drops, the run might end with it, leave an
`inhibitions.json` entry, or keep running. Do not assume which. Check the
newest log afterwards. From an SSH session:

```sh
timeout 660 ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p <host-ssh-port> <host-user>@<host> \
  "powershell.exe -NoLogo -NoProfile -NonInteractive -File C:\Users\<host-user>\.local\bin\wsl-incident-capture.ps1 -IntervalSeconds 5 -DurationSeconds 600 -OutputDirectory <private-incident-dir>"
```

From a PowerShell session on the host:

```powershell
$collector = Join-Path $HOME '.local\bin\wsl-incident-capture.ps1'
& $collector -IntervalSeconds 5 -DurationSeconds 600 -OutputDirectory <private-incident-dir>
```

Start host-only. Add a guest only under
[Bounded guest read](#bounded-guest-read-optional), with
`-GuestDistro '<DistroName>'` in PowerShell. Under a `cmd.exe` login shell
pass the name without single quotes, because `cmd.exe` hands them to
PowerShell as part of the name and the running-state match then fails. Use a
name placeholder in anything you share.

### Check whether a run is active

There is no status command. Use evidence in this order:

1. Newest log: list the `.jsonl` files in the `dotfiles-wsl-incident-telemetry`
   subdirectory of each output directory recorded in the checkpoint's
   `telemetry-runs` list (`<output-directory>\dotfiles-wsl-incident-telemetry`,
   one level below the directory you passed), and in the default logs folder
   named in the telemetry guide in case another session started a run.
   Compare the newest file's `LastWriteTimeUtc` with the current time. A run
   that is sampling every 5 seconds writes at least that often. A stale file
   means no sampling, or a stopped run. The lock metadata records a run id but
   not an output directory, so a run another session started in its own
   directory cannot be found from here. Ask its owner for their checkpoint's
   `telemetry-runs` list, and without it treat that run's records as not
   locatable. Do not search the volume for them.
2. A deliberately tiny second invocation. Never run a second invocation with
   default bounds: if no collector is active, it starts a real run whose
   default duration is 86400 seconds. Give it a scratch output directory, as
   [Protect existing evidence](#protect-existing-evidence) explains, and copy
   the state files first, as that section says, because a real start rewrites
   them.

   ```sh
   timeout 60 ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p <host-ssh-port> <host-user>@<host> \
     "powershell.exe -NoLogo -NoProfile -NonInteractive -File C:\Users\<host-user>\.local\bin\wsl-incident-capture.ps1 -IntervalSeconds 5 -DurationSeconds 1 -OutputDirectory <private-scratch-dir>"
   ```

   If another run holds the per-user lock, this prints
   `wsl-incident-capture: already-running` on standard error, exits 0, and
   does not touch the first run. If none is active, it runs for one second
   and writes one short log file in the scratch directory. The message goes
   to real process standard error. Run the invocation as a child process, as
   above. Calling the script in-process with `&` and `2>&1` inside a
   PowerShell session does not capture it.

### Exit statuses

| Status | Meaning | Message on standard error |
| ---: | --- | --- |
| 0 | A finished run, or `already-running` | `already-running`, or none |
| 0 | A finished run whose evidence is incomplete | `log-write-failed`, `log-budget-exhausted`, `log-segment-limit` |
| 1 | A real failure | `lock-state-unavailable`, `lock-metadata-ambiguous`, `collector-failed` |
| 1 | A value outside the documented range for `-IntervalSeconds`, `-DurationSeconds`, or `-MaximumLogBytes` | A PowerShell parameter error |
| 2 | Rejected before running | `invalid bounded option` (an over-long or control-character `-GuestDistro`), `output path rejected`, `Windows only` |

A status of 0 with one of the three log messages means records are missing or
cut short. Treat that run's evidence as incomplete. A status of 1 is never a
successful no-op. The status after Ctrl+C is not specified, so judge that run
by its log, not by its exit status. A status of 2 comes from validation that
runs before the lock, so a rejected `-OutputDirectory` returns 2 even while
another run is active. A second run's `-GuestDistro` is ignored when it
returns `already-running`.

### Stop

The clean stops are the end of the finite duration, and Ctrl+C in a
foreground console session. An SSH command that runs without a
pseudo-terminal may not be able to deliver Ctrl+C, so do not depend on it.
Size `-DurationSeconds` to the window you actually need instead.

The collector ships no procedure to stop another session's active run, so
the default is to let it expire. Do not stop a run by killing its process.
That skips the collector's own cleanup and can leave entries in
`inhibitions.json` that block sources on the next run. Never delete the lock
or state files by hand while a run may still be active. If waiting is not
possible, see
[Stop an active collector run](#stop-an-active-collector-run).

### Bounded behavior

These values are constants in the collector script, not a documented
interface. Re-check them after any collector change:

| Behavior | Bound |
| --- | --- |
| Wait for host counter workers each sample | The smaller of 1.5 seconds and the interval minus 0.5 seconds, never below 0.25 seconds |
| Guest running-state preflight (`wsl.exe --list --running --quiet`) | 1 second |
| Guest probe | 2 seconds |
| Cleanup grace for an owned process | 0.3 seconds |
| Spacing between guest probes | At least 60 seconds |
| Guest `wsl.exe` children at once | One |
| After a guest timeout (the preflight's included), an unverified cleanup of the `wsl.exe` client, or an internal failure while handling the probe | No more guest probes for the rest of that run |

Because of the first row, a 1-second interval leaves only half a second per
sample, which makes host sources prone to `timeout`. Use 5 seconds, as the
examples do.

Because of the last two rows, a guest field showing `unavailable` with the
error `probe-interval` is the normal value between probes and also the value
after a timeout. It is never a health verdict. A missing or timed-out guest
reading means unknown, not healthy. Any other guest error, such as
`preflight-failed` or `distro-not-running`, does not end probing by itself: the
collector tries again once the spacing has passed, so the same error can repeat
in later probes.

The collector never calls `wsl.exe --terminate` or `wsl.exe --shutdown`.

## Decision table

Pick the row that matches what you observe, then follow its steps in order.

| State | How to recognize it | Do, in order | Stop when |
| --- | --- | --- | --- |
| A. Host reachable, guest responsive | Host SSH works, and the guest answers a trivial command inside its bound (see [Responsive guest and outstanding calls](#responsive-guest-and-outstanding-calls)). | 1. Write the first checkpoint now, with what you already know. 2. Read and copy the collector state files and choose a new output directory (see [Protect existing evidence](#protect-existing-evidence)). 3. Add a pending entry to the checkpoint's `telemetry-runs` list with that directory and the state you read. 4. Start the host-only collector with a finite duration in that directory. 5. Fill in the entry's run id. If the start printed `already-running`, no run started, so mark the entry `not preserved: no run started`. 6. When the run ends, set the entry's window. 7. To add a guest probe, read and copy the state files again, add a second pending entry, then start a new bounded run in that other new output directory with `-GuestDistro` after the first run ends, because a second run is refused while one is active, and only under the prerequisites in [Bounded guest read](#bounded-guest-read-optional). 8. Ask each work owner to checkpoint their own work. | The window ends. No escalation is needed. |
| B. Host reachable, guest unavailable | Host SSH works. Guest SSH times out, or a `wsl.exe` command does not return. | 1. Do not start another `wsl.exe` call while one is outstanding. Only an authorization can make an exception (see [Separately authorized branches](#separately-authorized-branches)). 2. List the outstanding `wsl.exe` processes read-only, as [Responsive guest and outstanding calls](#responsive-guest-and-outstanding-calls) describes, and note them by PID and creation time in the checkpoint's `unended-processes` list. 3. Write the first checkpoint now, with `guest-evidence: unavailable` and the reason. 4. Read and copy the collector state files, choose a new output directory, and add a pending entry to the checkpoint's `telemetry-runs` list with that directory and the state you read. 5. Start the host-only collector in it. 6. Fill in the entry's run id. If the start printed `already-running`, no run started, so mark the entry `not preserved: no run started`. 7. Observe for the finite window, then set the entry's window. 8. Take the records and the checkpoint to the operator. | You would need a disruptive step. Go to [Escalation](#escalation) and wait for authorization. |
| C. Host unavailable | Host SSH does not connect. Guest SSH may or may not answer, and an answer does not replace host evidence. | 1. Record the time and what you tried. 2. Do not infer host state from a guest answer. 3. Capture host evidence only from the local console. The read-only git and claim checks can still run over guest SSH if it answers. The process-identity checks wait for host access. | Remote host capture cannot continue. When any access returns, read the host logs for the gap before touching anything. |

Stopped or unknown distributions are a separate case. A distribution that a
successful `wsl.exe --list --running --quiet` does not list is stopped or
unknown. A listing that timed out or exited non-zero is different: it proves
nothing, so the state stays unavailable and no guest command follows. Running
a command inside a distribution starts it if it is stopped, so diagnosis must
not do that.
`wsl.exe --list --verbose` is a list command that reports each
distribution's state. It is still a `wsl.exe` call, so apply the same
one-at-a-time limit and the same client-side `timeout 15` wrapper.

A guest running-state check followed by a guest command is not atomic. A
distribution that stops between the two can be started by the command. Use
host-only mode when that race is unacceptable.

### Responsive guest and outstanding calls

A guest is responsive only when it answers a trivial command inside a bound.
This check decides between rows A and B, so it runs before the collector does.
Over guest SSH, run `true` in the same wrapped form as the other examples,
`timeout 30 ssh ... -p <guest-ssh-port> <guest-user>@<host> "true"`, where
`<guest-user>` is the account on the guest's `sshd`. Without guest SSH, and
only when no `wsl.exe` call is outstanding and a successful
`wsl.exe --list --running --quiet` listed the distribution, ask through the
host's `sshd` instead:

```sh
timeout 15 ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p <host-ssh-port> <host-user>@<host> "wsl.exe --distribution <DistroName> --exec /bin/true"
```

Never send a `wsl.exe` command to a distribution that is not known to be
running, because it starts a stopped one. Prefer guest SSH: the `wsl.exe` form
is itself a `wsl.exe` call that can hang, so run it once and count it as
outstanding if it does not return. No answer inside the bound means the guest
is unavailable (row B). It is not a reason to retry.

To list the outstanding `wsl.exe` processes without their command lines, which
can hold private names, run this on the host:

```powershell
Get-Process -Name wsl -ErrorAction SilentlyContinue | Select-Object Id, @{ n = 'CreationTimeUtc'; e = { $_.StartTime.ToUniversalTime().ToString('o') } }
```

Run it in a PowerShell session on the host. Over SSH, save it beforehand as
`list-wsl-processes.ps1` in `<private-scratch-dir>` (healthy-time step 6 does
this) and run it with `-File`, as the other examples do, because the local
shell would expand the `$_` in a one-line command. `Get-Process` shows no
arguments and changes nothing. It lists every `wsl.exe` on the host, including
an interactive shell the operator opened, so note only the processes this
incident started or that began after the first symptom, and end none of them
(see the ground rules).

## Checkpoint

A checkpoint is a small private file that lets you or another session resume
safely. Write it as soon as an incident starts and update it after every
step. Keep it local and private by default: outside the repository, outside
any synchronized or shared folder, and never committed. Prefer a host volume,
for example inside `<private-preserve-dir>`, so that stopping a distribution
leaves it reachable. Store no secrets, no
command lines or arguments, and no raw log content.

```text
checkpoint-version: 1
telemetry-runs: <none | a list, one entry per collector run>
  - output-directory: <the run's private output directory | not preserved: reason>
    run-id: <run-id from the log file name | pending>
    window-utc: <first sampleTimeUtc> .. <last sampleTimeUtc> | incomplete | pending
    state-before-start: <read before this run, with the time you read it>
      inhibitions: <absent | unparseable | N entries, each with its source and
        whether it has a usable process identity>
      lock-metadata: <absent | unparseable | processId, startTimeTicks, runId>
      copy: <folder under the preserve directory with byte-for-byte copies of
        the files that exist | not preserved: reason>
access-validated: <date> via <host SSH | local console>
effective-memory-cap: <value read while healthy; never changed by recovery>
repository: <owner>/<name>
branch: <issue/N-slug>
worktree-path: <local path, kept private>
working-tree-status: <clean | dirty: N tracked, M untracked>
head-oid: <full commit id of HEAD at the last checkpoint update>
upstream-state: <ahead A behind B | no upstream>
uncommitted-work-preservation: <where a copy was written | not preserved: reason>
worktree-recovery-preserve-dir: <absolute path named in the authorization | none>
issue: <owner>/<name>#<N>
pr: <owner>/<name>#<N> | none
agent-session: <session label>
owner-session:
  kind: <multiplexer | process>
  multiplexer: <session name, creation time, and for tmux the session id and server pid, when kind is multiplexer>
  process: <the same fields as an owned-child-processes entry, listed here only>
claim: <agent-id> / <claim-id> | none
activation-nonce: <nonce | none>
last-completed-step: <IDD phase and step>
owned-child-processes:
  - namespace: <host | guest>
    pid: <number>
    creation-time-utc: <timestamp, host only>
    guest-distribution: <DistroName, guest only, kept private>
    guest-start-ticks: <starttime field of /proc/<pid>/stat, guest only>
    guest-boot-id: <value, guest only>
unended-processes: <none | a list: pid, start identity, and why it was left>
guest-evidence: <available | unavailable: reason>
authorized-stop-targets: <none | a list; an entry is only a candidate until
  the operator authorizes it>
  - pid: <host pid of another session's process, which only the operator
      may end>
    start-time-ticks: <startTimeTicks from the lock metadata>
    creation-time-utc: <that value as a UTC time>
next-safe-action: <one sentence, read-only unless authorized>
```

Fill the fields as follows. `worktree-path` is the `<worktree>` in every
command below. `claim` and `activation-nonce` supply `<claim-id>` and
`<nonce>`, `issue` supplies `<issue-number>`, and `<base-branch>` is
`developmentBranch` in `.github/idd/config.json`. The git state check compares
`working-tree-status` and `upstream-state` with the live values, and
`git worktree list --porcelain` must list `worktree-path` on `branch`.
`unended-processes` takes every process a step says to note without ending it,
and `guest-evidence` takes the reason the guest could not be read. The fields
`checkpoint-version`, `repository`, `agent-session`, and `next-safe-action`
identify and hand off the checkpoint, and no check reads them.

- **Telemetry runs.** Keep one list entry per collector run, so every retained
  log can be matched with its own run id, directory, and window, and a later
  run never overwrites an earlier one. The window is the first and last
  `sampleTimeUtc` across every segment of that run. Log files are named
  `wsl-capture-<UTC stamp>-<run-id>-<segment>.jsonl`, so the run id comes from
  the name. A long run rolls into numbered segments and removes the oldest ones
  when the byte budget fills, so the window starts at the first retained
  record, which can be later than the run start. To read the endpoints:

  1. List the run's segments in its `output-directory` plus
     `\dotfiles-wsl-incident-telemetry`, sorted by name,
     with `Get-ChildItem -Filter 'wsl-capture-*-<run-id>-*.jsonl'`, as the
     listing command in
     [Find and review records](wsl-incident-telemetry.md#find-and-review-records)
     does for the default folder.
  2. Read the first 50 lines of the lowest segment with
     `Get-Content -TotalCount 50`, and the last 50 lines of the highest with
     `Get-Content -Tail 50`.
  3. The endpoints are the first valid `host-sample` record of the first read
     and the last valid one of the second. A run interrupted mid-append can
     leave a truncated final line, so skip any line that does not parse and any
     record that is not a `host-sample`.
  4. If either endpoint has no valid record in the lines read, read more lines
     until both are found or the segment is exhausted. If one stays missing,
     write `incomplete` for the window rather than guessing.

  This reads your own private directory, so it needs no more than the bound
  the ground rules already require.
- **Uncommitted work.** Preserve by copying, never by stashing or resetting.
  Each capture goes into its own new folder, `<capture-dir>`, which is
  `<private-preserve-dir>/<utc-stamp>-<worktree-name>`. Write `<utc-stamp>` as
  `YYYYMMDDTHHMMSSZ`, with no colons, and `<worktree-name>` as the worktree's
  directory name. A repeat capture or a second worktree therefore never
  overwrites an earlier good copy, and discarding a failed output (below)
  discards only that capture's own. Create the folder first with
  `timeout -k 5 30 mkdir "<capture-dir>"`, which fails if it exists. If it
  reports an error, stop, choose a new name, and run nothing below. The folder
  is on a host volume that may be stalled, and the shell opens a redirection
  target before `timeout` starts, so each command below that writes a file
  keeps its redirection inside the bounded command, as `sh -c '...' sh` with
  the arguments after `sh` arriving as `$1`, `$2`, and `$3`. Every command
  writes to an absolute path in the folder. Write the tracked changes, staged
  and unstaged, then list the untracked files with NUL separators, because the
  default output quotes a name that has a newline or a quote in it, and copy
  exactly the listed files with a NUL-aware `tar`. The `-C` option must come
  before `-T`:

  ```sh
  timeout -k 5 60 sh -c 'git -C "$1" --no-optional-locks diff HEAD --binary > "$2"' \
    sh "<worktree>" "<capture-dir>/tracked.diff"
  timeout -k 5 60 sh -c 'git -C "$1" --no-optional-locks ls-files -z --others --exclude-standard > "$2"' \
    sh "<worktree>" "<capture-dir>/untracked.nul"
  timeout -k 5 300 tar -C "<worktree>" --null -T "<capture-dir>/untracked.nul" \
    -cf "<capture-dir>/untracked.tar"
  ```

  The top-level commands do not recurse into initialized submodules. List them
  first:

  ```sh
  timeout -k 5 30 sh -c 'git -C "$1" submodule status --recursive > "$2"' \
    sh "<worktree>" "<capture-dir>/submodules.txt"
  ```

  Then repeat the diff, the two listings, and the archives for each one with
  `-C "<worktree>/<submodule-path>"`, in `git` and in `tar` alike, so its
  relative paths resolve there. Give every output a name of its own in the same
  folder: `subN-tracked.diff`, `subN-untracked.nul`, `subN-untracked.tar`,
  `subN-ignored.nul`, `subN-ignored-escaped.nul`, `subN-ignored-selected.nul`,
  and `subN-ignored.tar`, where `N` is the submodule's line in
  `submodules.txt`. A submodule you cannot capture is recorded as
  `not preserved: submodule <path>`. Ignored files are not in either output,
  yet they can hold work you cannot recreate, such as local agent or editor
  settings. In the worktree and each submodule, list them into a NUL-delimited
  file, and show an escaped, numbered form for reading:

  ```sh
  timeout -k 5 60 sh -c 'git -C "$1" --no-optional-locks ls-files -z --others --ignored --exclude-standard --directory > "$2"' \
    sh "<worktree>" "<capture-dir>/ignored.nul"
  timeout -k 5 30 sh -c 'sed -z "$1" "$2" > "$3"' \
    sh 's/\\/\\\\/g; s/\n/\\n/g; s/[[:cntrl:]]/?/g' "<capture-dir>/ignored.nul" "<capture-dir>/ignored-escaped.nul"
  timeout -k 5 30 sh -c 'tr "\0" "\n" < "$1" | cat -n' sh "<capture-dir>/ignored-escaped.nul"
  ```

  The listing keeps a fully ignored directory as one entry. The `sed` writes a
  newline inside a name as `\n`, a backslash as `\\`, and any other control
  character, such as a carriage return or an escape, as `?`, into its own
  output file, so its exit status is not hidden by a pipe. If it exits non-zero
  or times out, discard that file and do not choose from the display. Once `tr`
  turns the NUL separators into line ends, each name is one numbered line.
  That form is for reading only, so a name cannot repaint the terminal, and a
  `?` may stand for a control character. `cat -A` on one record of
  `ignored.nul` shows its exact bytes. The number is the record's position in
  `ignored.nul`, so a displayed entry maps back to its
  exact original path, and you never retype a path. Choose the records to copy
  by number (the numbers below are an example, so use your own), keep the NUL
  separators, and archive that file with the same `tar --null -T` form:

  ```sh
  timeout -k 5 30 sh -c 'sed -z -n -e "$1" "$2" > "$3"' \
    sh '2p;4,6p' "<capture-dir>/ignored.nul" "<capture-dir>/ignored-selected.nul"
  timeout -k 5 300 tar -C "<worktree>" --null -T "<capture-dir>/ignored-selected.nul" \
    -cf "<capture-dir>/ignored.tar"
  ```

  Copy the ignored paths you cannot rebuild, and skip dependency and build
  directories you can. Record what you skipped, or write
  `not preserved: ignored files` if you copied none. If a command exits
  non-zero or times out (status 124 or 137), discard its output file and
  record `not preserved: <reason>` instead of keeping a partial copy. If the
  guest cannot be read, write `not preserved: guest unavailable`. That is a
  valid entry and a reason to stop, not a reason to improvise.
- **Worktree recovery copy.** Write the absolute `--preserve-dir` path here
  before an authorized IDD worktree recovery runs, and `none` otherwise. It is
  a path inside `<private-preserve-dir>` that does not exist yet (see
  [IDD worktree recovery](#idd-worktree-recovery)).
- **Owned child processes.** Record the PID together with its start identity,
  and mark whether it lives in the host or the guest. For a host process that
  is the creation time in UTC. For a guest process it is the `starttime`
  field of `/proc/<pid>/stat`, in clock ticks since boot, together with the
  boot identity from `/proc/sys/kernel/random/boot_id`, and the distribution
  it runs in, because the same numbers in another distribution name another
  process. The collector's logs do not keep that name, so write it here, in
  this private file only. PIDs are reused, and a guest start time means
  nothing without its boot. A recorded PID with a
  different start identity, or from a different boot, is a different process.
  Do not use `ps -o lstart`: it reports only whole seconds, so a reused PID
  can match it, and it never authorizes ending a process.
- **Owner session.** A multiplexer session name is not an identity by itself,
  because a new session can reuse a name after the old one exits, and a
  creation time has whole-second resolution. For tmux, record the name, the
  creation time, the session id, and the server pid, from
  `tmux list-sessions -F '#{session_name} #{session_created} #{session_id} #{pid}'`.
  A session id is not reused within one server, and a new server has a new
  pid, so a replacement session cannot match all four. For a
  multiplexer that does not show a creation time, record the process that owns
  the session instead, with the same fields as an owned child: its namespace,
  distribution and boot id for a guest process, PID, and start identity.
- **Effective memory cap.** Copy the value you read in the healthy-time
  check. Recovery never changes it.
- **Claim and nonce.** The IDD agent id, claim id, and activation nonce are
  public correlation tokens, not secrets. They are still local data here.

## Resume checks

Before starting any new agent or touching a worktree, compare the checkpoint
with the actual state. These checks change nothing in the repository, the
worktree, GitHub, or the claim. They are not free of network traffic:
`npx --yes` may download the pinned helper package, and the claim helper and
`gh` make read-only requests to GitHub. A failure from an unavailable network
says nothing about the machine's state. Stop at the first mismatch and report
it. Do not repair a mismatch as part of checking. The network commands run
under `timeout -k 5`. The kill-after sends a kill signal 5 seconds after the
deadline's termination signal, because `npx` and the helpers it starts can
ignore the termination signal and would otherwise keep the call open. A
timeout (status 124, or 137 after the kill) is a failed check, not a pass.

1. **Surviving sessions.** First verify the owning session itself, using the
   checkpoint's `owner-session`: the multiplexer session listed below, matched
   on every recorded value (for tmux the name, creation time, session id, and
   server pid), or the owner process, matched on every field of its entry,
   including the distribution and boot id for a guest process. A name alone
   does not count. A surviving child process does
   not prove a live owner, because a child can outlive the session that
   started it. Then, for each recorded process, compare the live PID and its
   start identity with the checkpoint: the creation time in UTC for a host
   process, the `starttime` ticks and the boot id for a guest process. Run the
   guest reads in the distribution the checkpoint records for that process,
   and only after `wsl.exe --list --running --quiet` shows it running. A
   distribution that is not running means the guest process is gone, so record
   that and do not start the distribution to check.

   ```powershell
   (Get-Process -Id <pid>).StartTime.ToUniversalTime().ToString('o')
   ```

   ```sh
   timeout -k 5 15 cat /proc/sys/kernel/random/boot_id
   timeout -k 5 15 sh -c "sed 's/^.*) //' /proc/<pid>/stat | cut -d ' ' -f 1,20"
   ```

   The second command prints the process state and the `starttime` ticks,
   fields 3 and 22 of `/proc/<pid>/stat`. The `timeout` wraps the whole
   pipeline, so a hung read ends with status 124 instead of being hidden by the
   exit status of `cut`. Stripping everything through the last `)` first keeps
   a process name that contains spaces from shifting the fields, so the state
   is then field 1 and the ticks are field 20. A state of `Z` (exited, not yet
   reaped) or `X` means the process is gone even though the entry still
   matches, so it is not a live owner. Otherwise the boot id and the ticks
   must both match the checkpoint. When you run them
   over SSH, wrap the client call in a `timeout` as well. A read that times
   out is an unknown identity: stop the check without retrying.

   If you use a terminal multiplexer, list its sessions read-only with
   `tmux list-sessions -F '#{session_name} #{session_created} #{session_id} #{pid}'`
   or `zellij list-sessions`. All the recorded values must match. A live,
   verified session is reattached to. It is
   not replaced by a new agent.
2. **Git state.**

   ```sh
   timeout -k 5 30 git -C "<worktree>" worktree list --porcelain
   timeout -k 5 30 git -C "<worktree>" symbolic-ref --short HEAD
   timeout -k 5 30 git -C "<worktree>" --no-optional-locks status --porcelain
   timeout -k 5 30 git -C "<worktree>" rev-parse HEAD
   timeout -k 5 30 git -C "<worktree>" rev-list --left-right --count @{u}...HEAD
   ```

   The `symbolic-ref` output must equal the checkpoint's `branch` exactly. A
   different branch or a detached HEAD means the path is not the worktree the
   checkpoint describes, so stop. The `rev-parse` output is compared with the
   checkpoint's `head-oid`. If check 1 verified the owning session itself, a
   different commit is normal progress: record the new commit, tell the owner,
   and continue read-only. If the owning session was not verified, even when a
   child process survives, a different commit means someone changed the
   revision, so stop and report it. Never resume
   from a guess. A matching path, status, and commit do not prove the
   uncommitted contents are unchanged, and this runbook cannot prove that
   without a verified owner. So when the owning session was not verified, the
   saved copy is the record of what the work was, and the operator decides
   whether the worktree is trusted. Nothing here modifies the worktree.

   Even a local `git` call can block on a stalled filesystem, so each runs
   under `timeout`, and a timeout is a failed check. `timeout` ends the call
   it started, but a process stuck in uninterruptible I/O can outlast the
   deadline, so the bound is not guaranteed on a stalled filesystem. A call
   that has not returned is not ended by name. Note it by PID and creation
   time. `--no-optional-locks` keeps `status` from refreshing the index. The
   last command prints the behind count and then the ahead count. When the
   branch has no upstream it fails. Count the commits since the base branch
   instead, and record `no upstream` in the checkpoint:

   ```sh
   timeout -k 5 30 git -C "<worktree>" \
     rev-list --count origin/<base-branch>..HEAD
   ```

3. **IDD claim state.** With this repository's helper runtime, read the
   claim state without changing it. `<issue-number>` is the `N` in the
   checkpoint's `issue` field, and `<owner>` and `<name>` come from the same
   field. Take `<helper-package-spec>` from `helperRuntime.packageSpec` in the
   config file at the last fetched base branch, not from the worktree's own
   copy. A dirty or unverified worktree may have changed that file, and
   `npx` runs whatever package it names, so a modified spec would run
   arbitrary code during a check that is meant to be read-only. Save that
   base-branch copy to a file outside the worktree and give the same file to
   the claim helper with `--policy`. Without `--policy` the helper reads
   `.github/idd/config.json` from the current directory, and if that file is
   absent it falls back silently to an empty trusted-actor list, so a run from
   the wrong directory would judge the claim by a different policy and say
   nothing. Both helpers list `--owner` and `--repo` in their `--help` output,
   and the repository comes from them instead of the directory you start in:

   ```sh
   policy_dir="$(timeout -k 5 30 mktemp -d)" &&
     policy_file="$policy_dir/config.json" &&
     timeout -k 5 30 sh -c 'git -C "$1" show "$2" > "$3"' sh "<clone-dir>" \
       origin/<base-branch>:.github/idd/config.json "$policy_file" &&
     helper_spec="$(timeout -k 5 30 jq -r '.helperRuntime.packageSpec // empty' "$policy_file")" &&
     [ -n "$helper_spec" ] &&
     echo "helper package spec: $helper_spec" >&2 &&
     (cd "<clone-dir>" && timeout -k 5 60 npx --prefix "$policy_dir" --yes \
       --package "$helper_spec" \
       idd-resume-claim-routing --issue <issue-number> --owner <owner> --repo <name> \
       --claim-id <claim-id> --nonce <nonce> --worktree "<worktree>" \
       --policy "$policy_file")
   echo "check 3 exit status: $?" >&2
   timeout -k 5 30 rm -rf -- "$policy_dir"
   ```

   The `&&` chain stops at the first failure, so the helper runs only with a
   policy file and a package spec taken from the base branch, and the temporary
   directory is removed either way. `mktemp` and the final `rm` run under
   `timeout` too, as does `jq`, because a stalled temporary filesystem would
   hang them, and a timeout is a failed check. The spec and the exit status go
   to standard error, so standard output stays the helper's JSON. The spec it
   prints is the `<helper-package-spec>` for check 4. `--prefix` makes `npx`
   read its project settings from that empty directory instead of from
   `<clone-dir>`, so a project `.npmrc` there does not apply to it, and only
   your user and machine npm settings do.

   Run the helper from inside the clone, as the subshell does. `<clone-dir>` is
   any worktree of the clone, preferably the primary worktree, the first entry
   of the `git worktree list` output in check 2, because the incident worktree
   may sit on the stalled filesystem, so the policy copy is read through it too.
   The helper's worktree-occupancy probe
   runs `git worktree list` in the current directory, and outside a clone the
   probe comes back unreadable, which fails the check. `--worktree` already
   points the owner-evidence reads at the incident worktree. A chain that
   stopped early, an empty spec, or a non-zero exit is a failed resume check.
   Read `state`, `action`, and `reason` from the JSON, and read
   `policy.trusted_marker_actors_source`: `none` means the trusted-actor
   list came out empty and the verdict rests on the viewer's own login. Omit
   `--nonce` when the checkpoint has none. When its `claim` is `none`, omit
   `--claim-id` and `--nonce` too. Without `--claim-id` the helper reports the
   issue's claim state and checks no ownership. Do not post a claim, a
   heartbeat, or a release while checking.
4. **Pull request and checks.** Skip this check when the checkpoint's `pr`
   field is `none`. Otherwise `<pr-number>` is the `N` in that field, which
   records `<owner>/<name>#<N>`. `gh` takes a number, a URL, or a branch, not
   that form:
   `timeout -k 5 30 gh pr view <pr-number> -R <owner>/<name> --json state,headRefOid`
   and the duplicate-safe, HEAD-pinned snapshot that
   `.github/instructions/idd-ci.instructions.md` requires, because plain
   `gh pr checks` can collapse same-named checks across workflows. The command
   runs from `<clone-dir>` with an empty `--prefix`, as check 3 does, so no
   project `.npmrc` applies and the incident worktree is not involved:

   ```sh
   ci_dir="$(timeout -k 5 30 mktemp -d)" &&
     (cd "<clone-dir>" && timeout -k 5 120 npx --prefix "$ci_dir" --yes \
       --package "<helper-package-spec>" \
       idd-ci-wait-state --pr <pr-number> --owner <owner> --repo <name>)
   echo "check 4 exit status: $?" >&2
   timeout -k 5 30 rm -rf -- "$ci_dir"
   ```

   The helper is read-only and exits 0 with JSON even when a check failed.
   Read the top-level `headRefOid`, which must equal the `headRefOid` from
   `gh pr view`, each check's `status` (`success`, `pending`, `failure`, or
   `unknown`) keyed by `checkName` and `workflowName`, and
   `requiredChecks.status`. Failed or pending checks are an observed state,
   routed in step 5. A non-zero exit status, invalid JSON, or a `headRefOid`
   that differs from the pull request's is a failed resume check.
5. **Route.** Follow `.github/instructions/idd-resume.instructions.md`
   (Steps 0 to 3) for the observed claim, branch, and PR state. Resuming as
   the owner of a live claim changes nothing destructive. The recovery of a
   stale or released claim that still has a local worktree is different:
   §LWR in `docs/idd-resume-detail.md` preserves uncommitted work by stashing
   it under a tagged entry, writes backup refs and copies, and then removes
   the worktree. Treat it as the separately authorized branch
   [IDD worktree recovery](#idd-worktree-recovery), never as a checking
   step.

If a session that owns the claim may still be running, a second agent must
not start. A claim that is not yet stale belongs to its owner.

## Escalation

The first three steps are ordered from least to most disruptive. Take a step
only when the one before it cannot answer the question, and stop at the first
stop condition. The separately authorized branches after them are not a
sequence. Choose one only for a question the earlier steps could not answer.
Observing and the bounded guest read run as the decision table says, under
the prerequisites listed in their own blocks. The graceful guest stop and
every separately authorized branch need the operator's authorization. None of
these steps is automated, scheduled, retried in a loop, or tied to a timer.
The repository rule is that an agent ends only the processes it started, and
operator authorization is not an exception to it. A shared host runs other
sessions' processes. So every separately authorized branch except the IDD
worktree recovery is executed by the operator: the agent collects the
evidence, and prepares the exact command, target, and impact for the operator
to run, but does not run it. That covers stopping another session's collector,
reconciling `inhibitions.json`, `wsl.exe --terminate`, `wsl.exe --shutdown`, a
host restart, memory, swap, or cache changes, and service or SSH changes. The
IDD worktree recovery is an IDD helper that changes git state, not processes,
so an agent may run it once the operator authorizes it.

### Observe with the host-only collector

- **Purpose:** same-window host evidence while the guest is unavailable.
- **Prerequisites:** validated host access, a new output directory, and a
  finite `-DurationSeconds`.
- **If it fails:** a status of 1 or 2, or a status of 0 with a log message
  (see [Exit statuses](#exit-statuses)). Record it and stop. A source
  reporting `unavailable` is unknown, not zero.
- **Deadline:** the run's own `-DurationSeconds`. Extend only by starting a
  new bounded run.
- **Impact:** a small read-only load on the host. No guest effect.
- **Stop condition:** two bounded runs show no usable host counters, or an
  `inhibited` source you cannot reconcile.

### Bounded guest read (optional)

- **Purpose:** guest memory pressure, swap, and reclaim rates.
- **Prerequisites:** the distribution is listed by
  `wsl.exe --list --running --quiet`, its work owner knows, no other
  `wsl.exe` call is outstanding, and no other collector run is active. The
  guest-side helper `wsl-incident-guest-snapshot` is installed and executable
  under `$HOME/.local/bin` in that distribution, and the healthy-time guest run
  in [Validate a host-native shell while healthy](#validate-a-host-native-shell-while-healthy)
  passed. Use `-GuestDistro '<DistroName>'` in a new bounded run.
- **If it fails:** a `timeout` (including `preflight-timeout`) or another error
  in the guest field. A timeout, a `wsl.exe` client that could not be verified
  as ended, or an internal failure while handling the probe ends probing for
  that run. Any other error, such as `preflight-failed`, does not: the
  collector tries again once the 60-second spacing has passed. Do not add a
  retry loop of your own.
- **Deadline:** the collector's own 1 second preflight and 2 second probe.
  A manual call runs under a client-side `timeout 15`, and no answer by then
  is a failure.
- **Impact:** a short noninteractive command runs inside a running guest.
  The check-then-launch race above can start a distribution that just
  stopped.
- **Stop condition:** any timeout, or an outstanding `wsl.exe` process.

### Graceful guest stop

- **Purpose:** let the work owner end a job through its own cleanup path.
- **Prerequisites:** the guest answers, the checkpoint exists (or the reason it
  cannot is recorded), and the work owner agrees. The operator authorizes the
  exact cleanup command and the named job or session it applies to. The owner
  runs that command, and only for a job the owner started. An agent does not
  end the job any other way.
- **If it fails:** no answer, or the owner declines. Do not force anything.
- **Deadline:** a wall-clock time agreed with the work owner before you ask.
  When it passes, stop and ask the operator.
- **Impact:** that owner's job ends. Other jobs are not touched.
- **Stop condition:** no answer, a decline, or any doubt about whose job it
  is.

### Separately authorized branches

Each branch below needs its own explicit authorization, taken after the
checkpoint exists or after you recorded why it cannot. Authorizing one does
not authorize another. The operator executes each branch except the IDD
worktree recovery. The agent prepares the command and impact for it. Each
authorization names a **deadline**, for example a wall-clock time. Without
one, do not run the step. A command that has not
returned by its deadline is not repeated, and it does not lead to another
branch without a new authorization.

**Outstanding `wsl.exe` calls.** The rule against a second `wsl.exe` call
while one is outstanding is a default, and the terminate and shutdown branches
each need one more call, so a hung `wsl.exe` would block both. The operator
settles it in the authorization, in one of two ways. Either the authorization
names each outstanding process by PID and creation time, taken from the
checkpoint's `unended-processes` list, says what that call is (a read-only
listing or probe, or an earlier terminate), and accepts that the new call can
hang the same way. Or it skips both branches and goes to
[Reboot the host](#reboot-the-host), which needs no `wsl.exe` call. An operator
who cannot say what an outstanding call is cannot authorize terminate or
shutdown. They can wait, or authorize the reboot branch separately. An
authorization that names an outstanding call also covers the read-only
`wsl.exe --list` calls the branch needs for its prerequisites and failure
checks. An authorization that does neither does not allow the call, and the
agent never chooses between them.

#### Stop an active collector run

- **Purpose:** end a collector run that cannot be allowed to expire.
- **Prerequisites:** the run belongs to another session or to the operator.
  An agent never ends a process it did not start, so the first choice is for
  the owner to press Ctrl+C in the console that owns the run, or to let the
  run expire. Only if neither works does the operator end it, after reading
  the owner's identity from `collector.lock.json` in the per-user state
  directory named in the telemetry guide. Read it only, and never edit it. Its
  layout is an internal detail of the current collector: `processId` is the
  PID and `startTimeTicks` is the process start time as UTC ticks. Record both
  as a candidate entry in the checkpoint's `authorized-stop-targets` list
  (`start-time-ticks`, and `creation-time-utc` from the ticks with
  `[DateTime]::new(<startTimeTicks>, 'Utc')`). It becomes an authorization only
  when the operator authorizes it.
- **Command (operator only):** one PID-targeted expression, run once, that
  checks the start time and stops only on a match. No retry, no other PID, and
  never a name or a pattern:

  ```powershell
  $p = Get-Process -Id <pid>
  $null = $p.Handle
  if ($p.StartTime.ToUniversalTime().Ticks -eq <startTimeTicks>) { Stop-Process -InputObject $p }
  ```

  Reading `Handle` first keeps a handle to the process that was found, so the
  check and the stop act on that process even if its PID is reused in
  between. A process object alone does not guarantee that, because it can
  re-open the process by PID. This behavior is not exercised on a Windows host
  here, and a small race can remain, which is one more reason the operator, not
  an agent, runs it.

- **If it fails:** the process remains, or `already-running` persists. Do not
  retry and do not act on a name. Record it. Any `inhibitions.json` entries
  are reconciled only through the separately authorized branch
  [Reconcile `inhibitions.json`](#reconcile-inhibitionsjson).
- **Deadline:** the one in the authorization.
- **Impact:** the collector's own cleanup is skipped. The recorded PID is the
  PowerShell process that runs the script, so ending a console run ends that
  owner's whole PowerShell session. A worker or guest `wsl.exe` child it
  started can outlive it. A partial last log line is repaired only when the
  next run uses the same logs directory, and unverified cleanup can leave
  `inhibitions.json` entries that block sources until reconciled.
- **Stop condition:** the PID and start time do not both match, you cannot
  establish the identity at all, or the one command did not end the process.

#### Reconcile `inhibitions.json`

- **Purpose:** clear source inhibitions that an unverified collector cleanup
  left behind, so those sources are sampled again.
- **Prerequisites:** no collector run is active and every collector session
  is closed. The operator executes this whole branch, including any process
  stop and the deletion of `inhibitions.json`. The agent only compares
  identities and prepares the exact commands and impact. Record each target's
  PID and creation time as its own entry in the checkpoint's
  `authorized-stop-targets` list and re-verify them just before ending it.
  For each entry, compare `processId` and `startTimeTicks` with the live
  process, and make an independent process-tree check for surviving collector
  descendants, exactly as the procedure under
  [Start and stop](wsl-incident-telemetry.md#start-and-stop) describes. The
  checkpoint exists, or the reason it cannot is recorded.
- **If it fails:** you cannot show that no collector-owned process remains.
  Keep the affected sources inhibited, record why, and stop.
- **Deadline:** the one in the authorization.
- **Impact:** the procedure can end a process whose PID and start time both
  match, and the operator ends it. Deleting `inhibitions.json` clears every
  inhibition at once, so a descendant that is still running is no longer
  guarded against.
- **Stop condition:** any identity mismatch, any entry with no usable process
  identity (a `processId` of -1 and `startTimeTicks` of 0, for any source and
  not only `*`) that you cannot resolve, or an active collector run. Such an
  entry means a launch or cleanup was ambiguous, so never clear the file while
  one remains.

#### Terminate one distribution

- **Purpose:** stop one hung distribution while the others keep running.
- **Prerequisites:** host evidence is captured, the checkpoint exists (or the
  reason it cannot is recorded), `<private-preserve-dir>` exists and holds the
  copies the checkpoint lists, the checkpoint and the incident output
  directories are on a host volume that a guest stop leaves alone, each work
  owner in that distribution was told, you know which other distributions are
  running, and no earlier `wsl.exe` call of this incident is still
  outstanding unless the authorization names it (see **Outstanding `wsl.exe`
  calls** above).
- **If it fails:** the command does not return by the deadline, or, once it
  has returned, the distribution is still listed as running. A call that has
  not returned stays
  outstanding, so run no further `wsl.exe` command, including the shutdown
  branch, until it ends. Record it, and let the operator decide between
  waiting, a new authorization that names this call, and a branch that needs
  no `wsl.exe` call, such as rebooting the host.
- **Deadline:** the one in the authorization.
- **Impact:** `wsl.exe --terminate <DistroName>` stops that distribution.
  Everything held only in its memory is lost, and its open sessions drop.
- **Stop condition:** doubt about which distribution is meant, or neither a
  checkpoint nor a recorded reason.

#### Shut down WSL

- **Purpose:** stop the whole WSL 2 environment when stopping one
  distribution is not enough or is not possible.
- **Prerequisites:** the same as terminating one distribution, for every
  running distribution, including that no earlier `wsl.exe` call of this
  incident is still outstanding unless the authorization names it.
- **If it fails:** the command does not return by the deadline, or, once it
  has returned, `wsl.exe --list --running --quiet` still lists a distribution.
  Record it and let the operator decide whether a host restart is warranted.
- **Deadline:** the one in the authorization.
- **Impact:** `wsl.exe --shutdown` immediately stops every running
  distribution and the WSL 2 utility VM. All in-memory state is lost, and any
  access that goes through a guest ends.
- **Stop condition:** any other distribution or session still matters.

#### Reboot the host

- **Purpose:** recover a host that no longer behaves, as a last resort.
- **Prerequisites:** local console access exists, host evidence is captured
  (or the reason it cannot be is recorded), the checkpoint exists (or the
  reason it cannot is recorded), `<private-preserve-dir>` exists and holds the
  copies the checkpoint lists, each work owner was told, `wsl.exe --terminate`
  and `wsl.exe --shutdown` were tried, are impossible, or were skipped under
  **Outstanding `wsl.exe` calls** (record which), and the checkpoint, the
  preserve folder, and the incident output directories are somewhere that
  survives a restart.
- **If it fails:** the host does not return. Only local console access can
  continue.
- **Deadline:** the one in the authorization.
- **Impact:** a restart ends every session on the machine. Remote access is
  gone until the host is back.
- **Stop condition:** no local console fallback.

#### Memory, swap, or cache changes

- **Purpose:** act on memory pressure that same-window evidence supports,
  for example `drop_caches`, `swapoff`, `swapon`, or editing `.wslconfig`.
  None of these is a proven fix for the reported incident.
- **Prerequisites:** a guest reading and a host reading over the same
  interval that support the action, and a rollback record of the setting you
  would change.
- **If it fails:** the pressure persists, or the command stalls. `swapoff` can
  be slow or fail when memory is short. Do not repeat it in a loop.
- **Deadline:** the one in the authorization.
- **Impact:** a `.wslconfig` change applies only after the VM has stopped,
  which is the shutdown branch. Removing swap or clearing caches changes the
  behavior of running workloads. Under memory pressure, `swapoff` can stall
  the guest or trigger out-of-memory kills, which lose work held only in
  memory. Clearing caches discards clean cache, so it cannot cause an
  out-of-memory kill, but later re-reads can stall. `swapon` re-enables swap
  and undoes nothing else.
- **Stop condition:** anything that would change the memory cap, the reclaim
  setting, or the sparse-VHD setting.

#### Service or SSH changes

- **Purpose:** restore a remote path to the host or the guest.
- **Prerequisites:** local console access, and a configuration that passed the
  validation steps in [Deploying sshd_config](sshd-config-setup.md).
- **If it fails:** you lose the path you were using. Continue from the local
  console, as the guide's troubleshooting section describes.
- **Deadline:** the one in the authorization.
- **Impact:** a restart or a bad setting can drop every SSH session.
- **Stop condition:** no local console fallback.

#### IDD worktree recovery

- **Purpose:** free a claimed worktree whose session is gone, through §LWR in
  `docs/idd-resume-detail.md`. The helper is `idd-local-worktree-recovery`,
  in the `ephemeral-npx` form that `docs/idd-helper-scripts.md` lists under
  "Local worktree recovery".
- **Prerequisites:** the claim is stale or released, and you have positive,
  independent evidence that no live session works in the worktree: a
  verified process identity, the multiplexer session list, and the owner's
  word. A PID list that has no match is not that evidence. The helper never
  checks liveness. Run its default dry-run first, and review the printed plan
  with the operator. When the target is a linked worktree, run it from the
  primary worktree, never from the target. The authorization names
  `--preserve-dir "<private-preserve-dir>/worktree-recovery-<utc-stamp>"`, a
  directory that does not exist yet. The helper creates it during `--apply`,
  before it removes the worktree, and refuses an existing one, so a retry after
  a failed linked-worktree attempt needs a new name. To resume an interrupted
  recovery of the primary worktree, pass the recorded directory again or omit
  the flag. As a child of the private folder it is outside the worktree and
  outside `/tmp`, and readable by your account only. Without the flag the
  helper copies into a temporary directory. Record the path in the checkpoint's
  `worktree-recovery-preserve-dir` line before the run, and pass the same
  `--preserve-dir` to the dry-run, so the plan the operator reviews names the
  real destination. Only then pass `--operator-confirmed-no-live-session`, an
  attestation the operator authorizes after seeing the evidence and which is
  required for any mutation, and `--apply`.
- **If it fails:** the helper reports a block or a verdict that is not
  ready, a claim or lock check disagrees, or `--apply` refuses because the
  platform lacks the secure-copy support it needs (native Windows Node is the
  documented case). Stop. Do not remove or stash anything by hand.
- **Deadline:** the one in the authorization.
- **Impact:** `--apply` stashes uncommitted work under a tagged entry in the
  shared clone, writes backup refs under `refs/idd-lwr/` for commits that
  exist only locally, and copies ignored files, which can include secrets,
  into the `--preserve-dir` the authorization names. It abandons an
  interrupted rebase, merge, cherry-pick, or bisect instead of resuming it.
  It then removes the worktree with `git worktree remove`, retrying with
  `--force` only after specific failures. For the primary worktree it removes
  nothing and checks out the development branch instead. Its dry-run changes
  nothing.
- **Stop condition:** a claim that is not stale, any sign of a live session,
  a plan the operator has not reviewed, or a worktree record that is not the
  claimed branch's own.

A terminal multiplexer or a checkpoint improves recovery after a disconnect.
It does not keep in-memory jobs alive when the VM ends. Stopping a
distribution or the VM ends them regardless.

## Fixture walkthroughs

These walkthroughs use synthetic values to check the decision logic. None
needs a real restart, a setting change, or a stress test. Field paths are
the ones in the collector's `host-sample` records. Each value would appear
under that path in the JSONL line. The first record of every run has no
previous sample, so its host rates read `unavailable` with `first-sample`.
The tables show later records unless they say otherwise.

### 1. Healthy guest

| Path | Value |
| --- | --- |
| `host.cpu.status` | `ok` |
| `host.cpu.totalPercent` | `31.5` |
| `host.cpu.privilegedPercent` | `9.0` |
| `host.disk.metrics.physicalTotal.queueLength` | `1` |
| `guest.status` | `ok` |
| `guest.metrics.psi.some.avg10` | `0.4` |
| `guest.metrics.deltas.workingset_refault.status` | `ok` |
| `guest.metrics.deltas.workingset_refault.perSecond` | `0` |
| `guest.metrics.swap.total` | `0` |

Between probes the guest field shows `unavailable` with `probe-interval`.
Rates appear only on the second successful probe, at least 60 seconds after
the first. Compare rates that cover the same window. A large cumulative
counter says nothing about current pressure.

**Next safe action:** let the finite run end, update the checkpoint, and
keep the incident output directories. Change nothing.

### 2. Hung guest

Shapes A and B are the two ways a hang starts, depending on which `wsl.exe`
call stops answering. Shape C is an outcome either can end in. All tables
assume a 5-second interval and `-GuestDistro` set.

Shape A: the guest probe itself hangs.

| Record | `host.cpu.status` | `guest.status` | `guest.error` |
| --- | --- | --- | --- |
| 1 | `unavailable` | `pending` | `provider-unavailable` |
| 2 | `ok` | `timeout` | `timeout` |
| 3 and later | `ok` | `unavailable` | `probe-interval` |

A `pending` guest record, a probe still in flight, carries
`provider-unavailable` in `guest.error`, and so does a `partial` one, because
the collector fills that value for any status other than `ok` or `timeout`
that comes with no listed error. It is not a provider failure.

Shape B: the read-only running-state check hangs first, so no probe starts.

| Record | `host.cpu.status` | `guest.status` | `guest.error` |
| --- | --- | --- | --- |
| 1 | `unavailable` | `timeout` | `preflight-timeout` |
| 2 and later | `ok` | `unavailable` | `probe-interval` |

Shape C: the timed-out `wsl.exe` client cannot be verified as ended within
its 0.3-second grace.

| Record | `host.cpu.status` | `guest.status` | `guest.error` |
| --- | --- | --- | --- |
| After the timeout | `ok` | `unavailable` | `inhibited` |

An `inhibitions.json` entry exists, and the guest stays inhibited. After the
run has ended and every collector session is closed, the entry is reconciled
only through the separately authorized branch
[Reconcile `inhibitions.json`](#reconcile-inhibitionsjson).

Host counters continue while the guest does not answer. The one `timeout`
record is the guest evidence. Everything after it is unknown, not healthy.
The `wsl.exe` process behind a timeout may still exist. Note it by PID and
creation time without ending it.

**Next safe action:** make no further `wsl.exe` call, keep the host-only run
to the end of its window, write the checkpoint with "guest evidence
unavailable", and give the operator the records and the checkpoint. A
graceful guest stop is not possible because the guest does not answer. Stop
there until an escalation branch is authorized.

### 3. Missing host SSH

| Observation | Value |
| --- | --- |
| `timeout 30 ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p <host-ssh-port> <host-user>@<host> "exit"` | exit status 255 (or 124 if the timeout fires) |
| Guest SSH on `<guest-ssh-port>` | no answer, or an answer from an unknown service |
| Collector records | none from this session |

An answer on the guest port does not stand in for host evidence, because the
two services are separate. If the guest does answer, the read-only
[Resume checks](#resume-checks) for git state and claim state can still be
done through it, and the checkpoint can say so. They are not host evidence.
The process-identity checks wait for host access, because they need the host
to confirm the recorded distribution is running, and guest SSH does not let
you choose which distribution you land in.

**Stop.** Remote host capture is not possible. Record the time and what you
tried in the checkpoint, and hand off to whoever has local console access.
Do not try to repair host SSH remotely. How host SSH is installed and enabled
is outside this runbook. See [Deploying sshd_config](sshd-config-setup.md)
for the manual deployment of its configuration.

### 4. Collector already running

| Observation | Value |
| --- | --- |
| Tiny second invocation, standard error | `wsl-incident-capture: already-running` |
| Tiny second invocation, exit status | 0 |
| Newest log `LastWriteTimeUtc` | within two sample intervals of now |

A run is active and sampling. Read its records, and do not start another run
or stop the first.

**Next safe action:** use the active run's records, wait for its duration to
end, and note its run id in the checkpoint. If the run belongs to another
session and its directory is unknown, record `output-directory: not preserved:
foreign run` with the lock metadata's `runId`, and ask that session's owner for
their checkpoint. If `already-running` keeps
appearing while the newest log stays stale for several intervals, the run may
be stuck. Report it and stop. Do not delete lock files, and do not end the
process by name. After the run has ended and every collector session is
closed, any `inhibitions.json` entries are reconciled only through the
separately authorized branch
[Reconcile `inhibitions.json`](#reconcile-inhibitionsjson). Keep the affected
sources inhibited whenever you cannot show that no collector-owned process
remains.

### 5. Interrupted IDD session

Checkpoint excerpt:

```text
branch: issue/1234-example-change
issue: <owner>/<name>#1234
head-oid: <commit id after commit 1>
owner-session:
  kind: multiplexer
  multiplexer: <session name, creation time, session id, server pid>
claim: <agent-id> / <claim-id>
last-completed-step: B3 commit 1 of 2 pushed
owned-child-processes:
  - namespace: guest
    pid: <number>
    guest-distribution: <DistroName>
    guest-start-ticks: <value>
    guest-boot-id: <value>
```

| Check | Observed |
| --- | --- |
| Owner session | listed by the multiplexer with the recorded name, creation time, session id, and server pid |
| Guest boot id | same as recorded |
| Recorded PID and guest start ticks | PID alive and not in state `Z` or `X`, start ticks match |
| `symbolic-ref --short HEAD` | equals the recorded branch |
| `rev-parse HEAD` | one commit past `head-oid`, the owner's second commit |
| `git status --porcelain` | two modified tracked files |
| `rev-list --left-right --count @{u}...HEAD` | `0` then `1` (one commit ahead) |
| `idd-resume-claim-routing` | `state` `already_owned`, `action` `keep` |

The session is still alive and the claim is still its own. The changed HEAD
is the owner's progress since the last checkpoint update, not a conflict.

**Next safe action:** reattach to that session read-only first and let it
continue. Do not start a second agent, do not run `git stash` or
`git reset`, and do not post a new claim. If instead the guest boot id
differs, the session did not survive, whether or not the PID still exists,
because a PID after a reboot belongs to a different process. The worktree
state and the claim are then the facts to resume from, through
`.github/instructions/idd-resume.instructions.md`, with the checkpoint's
`uncommitted-work-preservation` entry as the safety record. Stop if the
claim belongs to another session or is not provably yours.

## Settings this runbook leaves alone

This repository's `home/dot_wslconfig` sets `autoMemoryReclaim=gradual`,
`sparseVhd=true`, mirrored networking, and `-1` for `vmIdleTimeout` and
`instanceIdleTimeout`. It has no `memory` or `swap` key. The operator's
effective memory cap is whatever the machine's own effective file sets, not
this repository. For the operator this runbook was written for, that cap is
20 GB. Identify yours while everything is healthy, record it in the
checkpoint's `effective-memory-cap` line, and keep it, the reclaim setting,
and the sparse-VHD setting unchanged. Do not raise the cap, and do not run a broad
chezmoi apply or overwrite the effective file as part of recovery.

Configured swap and observed swap can differ. Configured swap is whatever
the effective `.wslconfig` says, and Microsoft documents `0` as no swap file
and 25 percent of host memory as the default when the key is absent. Observed
swap is what the running guest reports: the collector's
`guest.metrics.swap.total` and `used` come from the swap totals in
`/proc/meminfo`, and a manual read of `/proc/swaps` lists the active swap
areas. Record a difference as an observation. Restoring any setting is an
operator decision under the memory, swap, or cache branch of
[Escalation](#memory-swap-or-cache-changes). It is never a step in this
runbook.

The memory cap can differ the same way, because the file applies only when the
VM starts and the running VM can still hold an older value. When the key is
present, compare the cap you recorded with the guest's observed total, the
collector's `guest.metrics.memory.total` (in kB) or `MemTotal` in
`/proc/meminfo`. The observed total sits a little below the cap, because the
kernel keeps some of it: on a machine with a 20 GB cap the guest reported
20479660 kB, about 2 percent under 20 GiB (20971520 kB), which is how this
comparison reads a `memory` value. A total above the cap, or well beyond that
gap below it, means the running VM was not started with the value in the file.
Record that as an observation. Changing it is the same operator decision,
never a step here.

## Sources

- [Basic commands for WSL](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
  for `--list`, `--terminate`, and `--shutdown`.
- [Advanced settings configuration in WSL](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)
  for when `.wslconfig` changes apply and for the `memory` and `swap` keys.
- The collector script and its tests in this repository. The limits,
  messages, and exit statuses above were read from the script. The field
  paths were checked against records produced by its own functions, and the
  recovery behavior was not exercised on a Windows host. The NUL-delimited
  listing, numbering, selection, and archive steps were run against a scratch
  repository whose ignored names held a newline, a quote, and non-ASCII
  characters, with GNU sed 4.9 and GNU tar 1.35. The behavior of the
  resume-claim and worktree-recovery helpers named above was read from the
  pinned helper package's source.
