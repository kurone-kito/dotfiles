---
type: guide
title: WSL incident recovery runbook
description: Manual SSH checkpoint and evidence-preserving recovery runbook for a Windows host whose WSL guest stops answering.
tags: [wsl, ssh, recovery, diagnostics]
---

<!-- cspell:words wslconfig -->

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
  run a command that can wait forever.
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
- Disruptive actions (see [Escalation](#escalation)) are separate branches.
  Each needs the operator's explicit authorization in the current session,
  naming the exact command and target, after the checkpoint exists or after
  you have recorded why it cannot exist. An agent never authorizes itself,
  and attention alone is not approval.
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
ConnectTimeout=10`, so a dead path fails in seconds instead of prompting or
waiting. A client-side timeout does not stop a command that is already
running on the host, so keep every remote command short and bounded too:

```sh
ssh -o BatchMode=yes -o ConnectTimeout=10 -p <host-ssh-port> <host-user>@<host> \
  "powershell.exe -NoLogo -NoProfile -NonInteractive -File C:\Users\<host-user>\.local\bin\wsl-incident-capture.ps1 -Help"
```

Adjust the quoting for your login shell and for spaces in the path. If a
restricted execution policy blocks the script, add `-ExecutionPolicy Bypass`
to that one invocation. It is a PowerShell host option, so it goes before
`-File`, as in `powershell.exe -NoLogo -NoProfile -NonInteractive
-ExecutionPolicy Bypass -File <script>`. Placed after the script path it is
passed to the script as an argument and bypasses nothing. It applies to that
process only. Do not change the machine or user policy for this.

Then confirm each of these, and record the date and the cap in the
checkpoint:

1. `-Help` prints the four-line usage text and the exit status is 0. That
   proves the file is deployed and runnable from a noninteractive session.
2. A short bounded host-only run works the same way and writes records. Give
   it its own scratch output directory. The log byte budget covers a whole
   logs directory (see [Protect existing evidence](#protect-existing-evidence)),
   so a check that shares the real directory can delete real evidence:

   ```sh
   ssh -o BatchMode=yes -o ConnectTimeout=10 -p <host-ssh-port> <host-user>@<host> \
     "powershell.exe -NoLogo -NoProfile -NonInteractive -File C:\Users\<host-user>\.local\bin\wsl-incident-capture.ps1 -IntervalSeconds 5 -DurationSeconds 10 -OutputDirectory C:\Users\<host-user>\<private-scratch-dir>"
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
   timeout 15 ssh -o BatchMode=yes -o ConnectTimeout=10 -p <host-ssh-port> <host-user>@<host> "wsl.exe --list --running --quiet"
   ```

   Captured raw, that output can contain NUL characters that make names
   look spaced out. The collector strips them before matching.

   `ConnectTimeout` bounds only the connection, not this remote command. Run
   this check only with a client-side timeout, as above, and skip it if your
   client has none. The timeout
   bounds the client only, so the remote `wsl.exe` process can remain. Treat no
   answer as a failed check, do not run it again, and note the leftover
   process by PID and creation time. During an incident, prefer the
   collector's own preflight, which has a 1-second bound, to a manual call.

4. Read the machine's effective memory cap. Open the effective
   `%UserProfile%\.wslconfig` on the host, not this repository's source file,
   and note the `memory` value under `[wsl2]`. If the key is absent, record
   `default (key absent)`. Do not edit the file. Put the value in the
   checkpoint's `effective-memory-cap` line.

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
until the directory fits its own `-MaximumLogBytes`, and a later segment or record
that would exceed the budget does the same. A new run therefore can delete
an older run's records, including the one-second run used to check whether a
collector is active.

Before any new run in the real logs directory, copy every existing collector
log file to a private place, and record that place in the checkpoint:

```powershell
$ErrorActionPreference = 'Stop'
$logs = Join-Path $env:LOCALAPPDATA 'Dotfiles\wsl-incident-telemetry\logs\dotfiles-wsl-incident-telemetry'
$archive = '<private-archive-dir>'
New-Item -ItemType Directory -Force -Path $archive | Out-Null
$pattern = '^wsl-capture-[0-9TZ-]+-[a-f0-9]{32}(?:-[0-9]{4})?\.jsonl(?:\.tmp|\.partial)?$'
Get-ChildItem -LiteralPath $logs -File -Force |
  Where-Object { $_.Name -match $pattern } |
  Copy-Item -Destination $archive
```

The pattern is the collector's own log-file name set. It includes the
temporary and partial files that a start can repair or delete, not only
finished `.jsonl` files. If the logs directory does not exist yet, there is
nothing to copy. If any copy fails, stop and do not start another run.

Run checks, smoke tests, and activity probes with their own scratch
`-OutputDirectory`. The per-user lock is shared across output directories,
so a probe with a scratch directory still answers `already-running`.

### Start

Always pass an explicit finite `-DurationSeconds` when you start it from SSH.
If the SSH connection drops, the run might end with it, leave an
`inhibitions.json` entry, or keep running. Do not assume which. Check the
newest log afterwards. From an SSH session:

```sh
ssh -o BatchMode=yes -o ConnectTimeout=10 -p <host-ssh-port> <host-user>@<host> \
  "powershell.exe -NoLogo -NoProfile -NonInteractive -File C:\Users\<host-user>\.local\bin\wsl-incident-capture.ps1 -IntervalSeconds 5 -DurationSeconds 600"
```

From a PowerShell session on the host:

```powershell
$collector = Join-Path $HOME '.local\bin\wsl-incident-capture.ps1'
& $collector -IntervalSeconds 5 -DurationSeconds 600
```

Start host-only. Add a guest only under
[Bounded guest read](#bounded-guest-read-optional), with
`-GuestDistro '<DistroName>'` in PowerShell. Under a `cmd.exe` login shell
pass the name without single quotes, because `cmd.exe` hands them to
PowerShell as part of the name and the running-state match then fails. Use a
name placeholder in anything you share.

### Check whether a run is active

There is no status command. Use evidence in this order:

1. Newest log: list the `.jsonl` files under the logs folder named in the
   telemetry guide and compare the newest file's `LastWriteTimeUtc` with the
   current time. A run that is sampling every 5 seconds writes at least that
   often. A stale file means no sampling, or a stopped run.
2. A deliberately tiny second invocation. Never run a second invocation with
   default bounds: if no collector is active, it starts a real run whose
   default duration is 86400 seconds. Give it a scratch output directory, as
   [Protect existing evidence](#protect-existing-evidence) explains.

   ```sh
   ssh -o BatchMode=yes -o ConnectTimeout=10 -p <host-ssh-port> <host-user>@<host> \
     "powershell.exe -NoLogo -NoProfile -NonInteractive -File C:\Users\<host-user>\.local\bin\wsl-incident-capture.ps1 -IntervalSeconds 5 -DurationSeconds 1 -OutputDirectory C:\Users\<host-user>\<private-scratch-dir>"
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
| After a guest timeout | No more guest probes for the rest of that run |

Because of the first row, a 1-second interval leaves only half a second per
sample, which makes host sources prone to `timeout`. Use 5 seconds, as the
examples do.

Because of the last two rows, a guest field showing `unavailable` with the
error `probe-interval` is the normal value between probes and also the value
after a timeout. It is never a health verdict. A missing or timed-out guest
reading means unknown, not healthy.

The collector never calls `wsl.exe --terminate` or `wsl.exe --shutdown`.

## Decision table

Pick the row that matches what you observe, then follow its steps in order.

| State | How to recognize it | Do, in order | Stop when |
| --- | --- | --- | --- |
| A. Host reachable, guest responsive | Host SSH works. Guest SSH or a bounded guest command answers. | 1. Copy existing logs (see [Protect existing evidence](#protect-existing-evidence)). 2. Start the host-only collector with a finite duration. 3. Write the checkpoint. 4. To add a guest probe, copy the logs again, then start a new bounded run with `-GuestDistro` after the first run ends, because a second run is refused while one is active. 5. Ask each work owner to checkpoint their own work. | The window ends. No escalation is needed. |
| B. Host reachable, guest unavailable | Host SSH works. Guest SSH times out, or a `wsl.exe` command does not return. | 1. Do not start another `wsl.exe` call while one is outstanding. 2. Note any outstanding `wsl.exe` processes by PID and creation time, read-only. 3. Copy existing logs. 4. Start the host-only collector. 5. Write the checkpoint with "guest evidence unavailable". 6. Observe for the finite window. 7. Take the records and the checkpoint to the operator. | You would need a disruptive step. Go to [Escalation](#escalation) and wait for authorization. |
| C. Host unavailable | Host SSH does not connect. Guest SSH may or may not answer, and an answer does not replace host evidence. | 1. Record the time and what you tried. 2. Do not infer host state from a guest answer. 3. Capture host evidence only from the local console. Read-only resume checks can still run over guest SSH if it answers. | Remote host capture cannot continue. When any access returns, read the host logs for the gap before touching anything. |

Stopped or unknown distributions are a separate case. A distribution that
`wsl.exe --list --running --quiet` does not list is stopped or unknown.
Running a command inside it starts it, so diagnosis must not do that.
`wsl.exe --list --verbose` is a list command that reports each
distribution's state. It is still a `wsl.exe` call, so apply the same
one-at-a-time limit and the same client-side `timeout 15` wrapper.

A guest running-state check followed by a guest command is not atomic. A
distribution that stops between the two can be started by the command. Use
host-only mode when that race is unacceptable.

## Checkpoint

A checkpoint is a small private file that lets you or another session resume
safely. Write it as soon as an incident starts and update it after every
step. Keep it local and private by default: outside the repository, outside
any synchronized or shared folder, and never committed. Store no secrets, no
command lines or arguments, and no raw log content.

```text
checkpoint-version: 1
observation-window-utc: <first sampleTimeUtc> .. <last sampleTimeUtc>
telemetry-run-id: <run-id from the log file name>
redacted-log-location: <private folder or archive label>
access-validated: <date> via <host SSH | local console>
effective-memory-cap: <value read while healthy; never changed by recovery>
repository: <owner>/<name>
branch: <issue/N-slug>
worktree-path: <local path, kept private>
working-tree-status: <clean | dirty: N tracked, M untracked>
upstream-state: <ahead A behind B | no upstream>
uncommitted-work-preservation: <where a copy was written | not preserved: reason>
issue: <owner>/<name>#<N>
pr: <owner>/<name>#<N> | none
agent-session: <session label>
claim: <agent-id> / <claim-id> | none
activation-nonce: <nonce | none>
last-completed-step: <IDD phase and step>
owned-child-processes:
  - namespace: <host | guest>
    pid: <number>
    creation-time-utc: <timestamp, host only>
    guest-start-ticks: <starttime field of /proc/<pid>/stat, guest only>
    guest-boot-id: <value, guest only>
authorized-stop-target: <none | host pid and creation-time-utc of another
  session's process, which only the operator may end>
next-safe-action: <one sentence, read-only unless authorized>
```

Fill the fields as follows:

- **Observation window.** The first and last `sampleTimeUtc` across every
  segment of one run. Log files are named
  `wsl-capture-<UTC stamp>-<run-id>-<segment>.jsonl`, so the run id comes
  from the name. A long run rolls into numbered segments and removes the
  oldest ones when the byte budget fills. The window therefore starts at the
  first retained record, which can be later than the run start.

  ```powershell
  $files = Get-ChildItem -LiteralPath $logs -Filter 'wsl-capture-*-<run-id>-*.jsonl' |
    Sort-Object Name
  $first = Get-Content -LiteralPath $files[0].FullName -TotalCount 1 | ConvertFrom-Json
  $last = Get-Content -LiteralPath $files[-1].FullName -Tail 1 | ConvertFrom-Json
  $first.sampleTimeUtc
  $last.sampleTimeUtc
  ```

  If the first or last line is not a `host-sample` record, use the nearest
  `host-sample` record instead.
- **Uncommitted work.** Preserve by copying, never by stashing or resetting.
  For example, write
  `timeout -k 5 60 git -C <worktree> --no-optional-locks diff HEAD --binary`
  output, which includes staged and unstaged tracked changes, and the output
  of
  `timeout -k 5 60 git -C <worktree> --no-optional-locks ls-files --others --exclude-standard`
  to a private folder, and copy those files. If a command exits non-zero or
  times out (status 124 or 137), discard its output file and record
  `not preserved: <reason>` instead of keeping a partial copy. If the guest
  cannot be read, write `not preserved: guest unavailable`. That is a valid
  entry and a reason to stop, not a reason to improvise.
- **Owned child processes.** Record the PID together with its start identity,
  and mark whether it lives in the host or the guest. For a host process that
  is the creation time in UTC. For a guest process it is the `starttime`
  field of `/proc/<pid>/stat`, in clock ticks since boot, together with the
  boot identity from `/proc/sys/kernel/random/boot_id`. PIDs are reused, and
  a guest start time means nothing without its boot. A recorded PID with a
  different start identity, or from a different boot, is a different process.
  Do not use `ps -o lstart`: it reports only whole seconds, so a reused PID
  can match it, and it never authorizes ending a process.
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
under `timeout`, and a timeout is a failed check, not a pass.

1. **Surviving sessions.** For each recorded process, compare the live PID
   and its start identity with the checkpoint: the creation time in UTC for a
   host process, the `starttime` ticks and the boot id for a guest process.

   ```powershell
   (Get-Process -Id <pid>).StartTime.ToUniversalTime().ToString('o')
   ```

   ```sh
   cat /proc/sys/kernel/random/boot_id
   sed 's/^.*) //' /proc/<pid>/stat | cut -d ' ' -f 20
   ```

   The second command prints the `starttime` ticks, which is field 22 of
   `/proc/<pid>/stat`. Stripping everything through the last `)` first keeps
   a process name that contains spaces from shifting the fields, so the value
   is then field 20. Both the boot id and the ticks must match the
   checkpoint.

   If you use a terminal multiplexer, list its sessions read-only with
   `tmux list-sessions` or `zellij list-sessions`. A live, verified session
   is reattached to. It is not replaced by a new agent.
2. **Git state.**

   ```sh
   timeout -k 5 30 git worktree list --porcelain
   timeout -k 5 30 git -C <worktree> --no-optional-locks status --porcelain
   timeout -k 5 30 git -C <worktree> rev-parse HEAD
   timeout -k 5 30 git -C <worktree> rev-list --left-right --count @{u}...HEAD
   ```

   Even a local `git` call can block on a stalled filesystem, so each runs
   under `timeout`, and a timeout is a failed check. `timeout` ends the call
   it started, but a process stuck in uninterruptible I/O can outlast the
   deadline, so the bound is not guaranteed on a stalled filesystem. A call
   that has not returned is not ended by name. Note it by PID and creation
   time. `--no-optional-locks` keeps `status` from refreshing the index. The
   last command prints the behind count and then the ahead count. When the
   branch has no upstream it fails. Use
   `timeout -k 5 30 git -C <worktree> rev-list --count origin/<base-branch>..HEAD`
   and record `no upstream` in the checkpoint.
3. **IDD claim state.** With this repository's helper runtime, read the
   claim state without changing it. `<issue-number>` is the `N` in the
   checkpoint's `issue` field. Take `<helper-package-spec>` from
   `helperRuntime.packageSpec` in `.github/idd/config.json`:

   ```sh
   timeout 60 npx --yes --package <helper-package-spec> \
     idd-resume-claim-routing --issue <issue-number> --claim-id <claim-id> --nonce <nonce> --worktree <worktree>
   ```

   Read `state`, `action`, and `reason` from the JSON. Omit `--nonce` when the
   checkpoint has none. When its `claim` is `none`, omit `--claim-id` and
   `--nonce` too. Without `--claim-id` the helper reports the issue's claim
   state and checks no ownership. Do not post a claim, a heartbeat, or a
   release while checking.
4. **Pull request and checks.** Skip this check when the checkpoint's `pr`
   field is `none`. Otherwise `<pr-number>` is the `N` in that field, which
   records `<owner>/<name>#<N>`. `gh` takes a number, a URL, or a branch, not
   that form:
   `timeout 30 gh pr view <pr-number> -R <owner>/<name> --json state,headRefOid`
   and `timeout 30 gh pr checks <pr-number> -R <owner>/<name>`.
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
Authorization lets an agent run a command the operator names. It never lets
an agent end an individual process it did not start. The commands named in
the branches below (`wsl.exe --terminate`, `wsl.exe --shutdown`, a host
restart, an `sshd` restart) end processes as a side effect, and an agent runs
one only when the operator names that exact command and target. Stopping
another session's collector, and ending any process found while reconciling,
are the operator's own actions.

### Observe with the host-only collector

- **Purpose:** same-window host evidence while the guest is unavailable.
- **Prerequisites:** validated host access, existing logs copied, and a
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
  `wsl.exe` call is outstanding, and no other collector run is active. Use
  `-GuestDistro '<DistroName>'` in a new bounded run.
- **If it fails:** a `timeout` or `preflight-*` error in the guest field.
  Do not retry in a loop. The collector stops probing for that run.
- **Deadline:** the collector's own 1 second preflight and 2 second probe.
  A manual call runs under a client-side `timeout 15`, and no answer by then
  is a failure.
- **Impact:** a short noninteractive command runs inside a running guest.
  The check-then-launch race above can start a distribution that just
  stopped.
- **Stop condition:** any timeout, or an outstanding `wsl.exe` process.

### Graceful guest stop

- **Purpose:** let the work owner end a job through its own cleanup path.
- **Prerequisites:** the guest answers, the checkpoint exists, and the work
  owner agrees. The operator authorizes the exact cleanup command and the
  named job or session it applies to, and the owner runs that command. An
  agent does not end the job any other way.
- **If it fails:** no answer, or the owner declines. Do not force anything.
- **Deadline:** a wall-clock time agreed with the work owner before you ask.
  When it passes, stop and ask the operator.
- **Impact:** that owner's job ends. Other jobs are not touched.
- **Stop condition:** no answer, a decline, or any doubt about whose job it
  is.

### Separately authorized branches

Each branch below needs its own explicit authorization, taken after the
checkpoint exists or after you recorded why it cannot. Authorizing one does
not authorize another. Each authorization names a **deadline**, for example a
wall-clock time. Without one, do not run the step. A command that has not
returned by its deadline is not repeated, and it does not lead to another
branch without a new authorization.

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
  in the checkpoint's `authorized-stop-target` line, converting the ticks to
  a UTC time with `[DateTime]::new(<startTimeTicks>, 'Utc')`.
- **Command (operator only):** one PID-targeted expression, run once, that
  checks the start time and stops only on a match. No retry, no other PID, and
  never a name or a pattern:

  ```powershell
  $p = Get-Process -Id <pid>
  if ($p.StartTime.ToUniversalTime().Ticks -eq <startTimeTicks>) { Stop-Process -Id $p.Id }
  ```

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
  is closed. The operator, not an agent, performs any process stop in this
  procedure. Record each target's PID and creation time in the checkpoint
  and re-verify them just before ending it. For each entry, compare
  `processId` and `startTimeTicks` with the live process, and make an
  independent process-tree check for surviving collector descendants,
  exactly as the procedure under
  [Start and stop](wsl-incident-telemetry.md#start-and-stop) describes. The
  checkpoint exists.
- **If it fails:** you cannot show that no collector-owned process remains.
  Keep the affected sources inhibited, record why, and stop.
- **Deadline:** the one in the authorization.
- **Impact:** the procedure can end a process whose PID and start time both
  match, and the operator ends it. Deleting `inhibitions.json` clears every
  inhibition at once, so a descendant that is still running is no longer
  guarded against.
- **Stop condition:** any identity mismatch, a `*` entry with no usable
  process identity that you cannot resolve, or an active collector run.

#### Terminate one distribution

- **Purpose:** stop one hung distribution while the others keep running.
- **Prerequisites:** host evidence is captured, the checkpoint exists, each
  work owner in that distribution was told, and you know which other
  distributions are running.
- **If it fails:** the command does not return by the deadline, or the
  distribution is still listed as running. Record it and let the operator
  decide the next branch.
- **Deadline:** the one in the authorization.
- **Impact:** `wsl.exe --terminate <DistroName>` stops that distribution.
  Everything held only in its memory is lost, and its open sessions drop.
- **Stop condition:** doubt about which distribution is meant, or no
  checkpoint.

#### Shut down WSL

- **Purpose:** stop the whole WSL 2 environment when stopping one
  distribution is not enough or is not possible.
- **Prerequisites:** the same as terminating one distribution, for every
  running distribution.
- **If it fails:** the command does not return by the deadline, or
  `wsl.exe --list --running --quiet` still lists a distribution. Record it
  and let the operator decide whether a host restart is warranted.
- **Deadline:** the one in the authorization.
- **Impact:** `wsl.exe --shutdown` immediately stops every running
  distribution and the WSL 2 utility VM. All in-memory state is lost, and any
  access that goes through a guest ends.
- **Stop condition:** any other distribution or session still matters.

#### Reboot the host

- **Purpose:** recover a host that no longer behaves, as a last resort.
- **Prerequisites:** local console access exists, and the checkpoint and the
  copied logs are somewhere that survives a restart.
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
  primary worktree, never from the target. Only then pass
  `--operator-confirmed-no-live-session`, an attestation the operator
  authorizes after seeing the evidence and which is required for any
  mutation, and `--apply`.
- **If it fails:** the helper reports a block or a verdict that is not
  ready, a claim or lock check disagrees, or `--apply` refuses because the
  platform lacks the secure-copy support it needs (native Windows Node is the
  documented case). Stop. Do not remove or stash anything by hand.
- **Deadline:** the one in the authorization.
- **Impact:** `--apply` stashes uncommitted work under a tagged entry in the
  shared clone, writes backup refs under `refs/idd-lwr/` for commits that
  exist only locally, and copies ignored files, which can include secrets,
  into `--preserve-dir` (a temporary directory by default). It abandons an
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
archive the logs. Change nothing.

### 2. Hung guest

Shapes A and B are the two ways a hang starts, depending on which `wsl.exe`
call stops answering. Shape C is an outcome either can end in. All tables
assume a 5-second interval and `-GuestDistro` set.

Shape A: the guest probe itself hangs.

| Record | `host.cpu.status` | `guest.status` | `guest.error` |
| --- | --- | --- | --- |
| 1 | `unavailable` | `pending` | none |
| 2 | `ok` | `timeout` | `timeout` |
| 3 and later | `ok` | `unavailable` | `probe-interval` |

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
| `ssh -o BatchMode=yes -o ConnectTimeout=10 -p <host-ssh-port> <host-user>@<host> "exit"` | exit status 255 |
| Guest SSH on `<guest-ssh-port>` | no answer, or an answer from an unknown service |
| Collector records | none from this session |

An answer on the guest port does not stand in for host evidence, because the
two services are separate. If the guest does answer, the read-only
[Resume checks](#resume-checks) for git state and claim state can still be
done through it, and the checkpoint can say so. They are not host evidence.

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
end, and note its run id in the checkpoint. If `already-running` keeps
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
claim: <agent-id> / <claim-id>
last-completed-step: B3 commit 1 of 2 pushed
owned-child-processes:
  - namespace: guest
    pid: <number>
    guest-start-ticks: <value>
    guest-boot-id: <value>
```

| Check | Observed |
| --- | --- |
| Guest boot id | same as recorded |
| Recorded PID and guest start ticks | PID alive, start ticks match |
| `git status --porcelain` | two modified tracked files |
| `rev-list --left-right --count @{u}...HEAD` | `0` then `1` (one commit ahead) |
| `idd-resume-claim-routing` | `state` `already_owned`, `action` `keep` |

The session is still alive and the claim is still its own.

**Next safe action:** reattach to that session read-only first and let it
continue. Do not start a second agent, do not run `git stash` or
`git reset`, and do not post a new claim. If instead the guest boot id
differs and the PID is gone, the session did not survive. The worktree
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

## Sources

- [Basic commands for WSL](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
  for `--list`, `--terminate`, and `--shutdown`.
- [Advanced settings configuration in WSL](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)
  for when `.wslconfig` changes apply and for the `memory` and `swap` keys.
- The collector script and its tests in this repository. The limits,
  messages, and exit statuses above were read from the script. The field
  paths were checked against records produced by its own functions, and the
  recovery behavior was not exercised on a Windows host.
