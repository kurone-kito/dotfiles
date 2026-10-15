---
type: guide
title: Queueing heavy validation with pueue
description: Explains how scripts/with-pueue.sh serializes this repository's heavy lint and test commands through a pueue group, how to set its parallelism, and when it falls back to running the command directly.
---

# Queueing heavy validation with pueue

Several sessions often work in this repository at once, and each one
runs the same heavy validation: the Markdown and spelling pipeline
(`fix-validate`) and the bats and Pester suites (`pre-push-validate` and
`post-fix-validate`). Run together, they compete for the same cores and
memory. [pueue](https://github.com/Nukesor/pueue) is a small task queue;
this repository sends those three commands through one pueue group, so
only a few of them run at a time while the others wait their turn.

The three command strings live in `.github/idd/config.json` and in the
Project commands table of
`.github/instructions/idd-overview-core.instructions.md`. Each is one
call of `scripts/with-pueue.sh`:

| Command | String |
| ------- | ------ |
| `fix-validate` | `scripts/with-pueue.sh scripts/run-fix-validate.sh` |
| `pre-push-validate` | `scripts/with-pueue.sh scripts/run-validate.sh` |
| `post-fix-validate` | `scripts/with-pueue.sh scripts/run-validate.sh` |

`scripts/run-fix-validate.sh` holds the pipeline itself: it runs
`markdownlint-cli2 --fix`, `markdownlint-cli2` and `cspell`, and stops at
the first command that fails. `scripts/run-validate.sh` is unchanged and
still works as a direct dispatcher, including `--dry-run`.

## Setting the parallelism

The group is named `dotfiles`. How many of its tasks run at once is the
optional integer `parallelism` under `[data.pueue]` in your chezmoi
configuration (see the
[reference](chezmoi-toml-reference.md#pueue-validation-queue-datapueueparallelism)):

```toml
[data.pueue]
parallelism = 3
```

- **Default:** `2` when the key is omitted. This is a provisional
  default, not a measured capacity limit, and no policy upper bound is
  set. Raise or lower it for your machine.
- **Valid values:** a whole number from 1 to 9007199254740991. `0` is
  refused because pueue would read it as "unlimited". A negative number,
  a string, a boolean, a fraction, the TOML values `inf` and `nan`, and
  any number above 9007199254740991 (2^53 - 1, the largest integer a
  template can print exactly) are refused too. `chezmoi apply` and
  `chezmoi init` fail with an error that names `parallelism` instead of
  silently using `2`.
- **Where it lands:** chezmoi renders the value to
  `~/.config/dotfiles/pueue-parallelism`, one integer and one newline.
  The wrapper reads that file directly and never runs `chezmoi data`,
  which prints the whole data map, secrets included. A missing file means
  `2`. A file that is not exactly one positive whole number plus at most
  one trailing newline makes the wrapper stop with status 2 before it
  starts anything.

Each call sets the parallelism of the `dotfiles` group again from that
file, so editing it takes effect on the next run. The wrapper never
touches pueue's default group and never rewrites your `pueue.yml`.

## What the wrapper does

In this order:

1. It refuses a corrupt parallelism file (status 2), whatever else is
   true.
2. If `PUEUE_GROUP` is set and not empty, it runs the command directly.
   pueue sets that variable in every task it runs, so a validation
   command that itself calls the wrapper does not take a second slot of
   the group and cannot wait for itself.
3. If `pueue`, `pueued` or `jq` is missing, it runs the command directly.
   It also runs the command directly in a Windows shell (`uname -s`
   starts with `MINGW`, `MSYS` or `CYGWIN`): pueue runs a task through
   PowerShell there, so the POSIX-quoted command line the wrapper builds
   would not mean what it says. Use the wrapper from WSL, or call the
   script directly.
4. If the pueue daemon is not reachable, it starts the daemon once with
   `pueued -d` and checks again. If the daemon is still not reachable, it
   runs the command directly. The exit status of the start is not used:
   `pueued -d` can exit 0 and still fail to bind its socket. The start is
   made with all three standard streams detached, because the daemon
   would otherwise keep the caller's output pipe open and a caller that
   reads the wrapper's output would never see it end.
5. Otherwise it creates the `dotfiles` group when it is not listed,
   sets the group's parallelism, resumes the group if it is paused, adds
   the command as a task in the caller's working directory, waits for it,
   prints its output and returns its exit status. The wrapper does not
   parse pueue's rejection when a group already exists; it lists the
   groups to find out.

Every failure before the daemon accepts the task (a failed group listing,
a group that cannot be created, a failed parallelism update, a failed
enqueue) makes the wrapper exit non-zero **without** running the command:
none of them is a reason to fall back to the direct run. After the daemon
has accepted the task the command is never started a second time locally;
if the result cannot be read, the wrapper exits non-zero and leaves
the finished task in place, so `pueue log <id>` can still show what
happened.

## A paused group

pueue can pause a group by itself: with `daemon.pause_group_on_failure`
(or `pause_all_on_failure`) enabled in `pueue.yml`, one failed task pauses
its group, and a task queued in a paused group waits until someone resumes
it. A failed validation is routine here, and it would otherwise leave
every other session's validation waiting forever. The `dotfiles` group is
dedicated to the wrapper, so the wrapper resumes it: it looks at the group
before enqueueing and about every ten seconds while it waits, and runs
`pueue start --group dotfiles` when the listing says the group is paused
(with a note on standard error). If you want to stop validation, interrupt
the callers; pausing the group does not hold them back for long. The
default pueue group is never touched.

## Exit status, output and cleanup

- The wrapper returns the task's exit status: 0 for success and the
  command's own code for a failure. A task that ended in any other way
  (killed, failed to spawn) returns 1, and so does a code outside 1 to
  255.
- The output of the task (standard output and error, merged by pueue) is
  printed when the task is done.
- pueue sends the caller's environment and working directory with the
  task, so the command sees what a direct run would see. pueue keeps that
  environment in the task's state until the task is removed, so the
  wrapper removes its own finished task once it has read the result,
  retrying briefly. If the task stays, the wrapper prints a warning that
  names its id and the `pueue remove <id>` command, and still returns the
  command's exit status. It never runs `pueue clean`, which would also
  drop other sessions' tasks before they read them.
- An interrupt (`INT`, `TERM` or `HUP`) while enqueueing or waiting kills
  and removes that one task, so an abandoned call does not keep holding
  a slot. Every task carries a label of its own, formed like
  `with-pueue-<pid>-<time>-<random>`. The `pueue add` client runs in the
  background and is waited for, so an interrupt is acted on at once even
  if the client stalls. When the task id has not arrived yet, because the
  client died, was interrupted or failed after the daemon had accepted
  the task, the wrapper finds the task by its label in the queue state
  and removes it. A failed enqueue is cleaned up the same way: nothing
  the daemon accepted is left behind, and the command is not run.
- The wrapper assumes pueue's default task shell, a POSIX `sh -c` on
  Linux and macOS. A `shell_command` in your `pueue.yml` that is not
  POSIX-compatible would not parse the command line.

## Installing pueue

`home/dot_config/mise/config.toml` installs `pueue` and `pueued` through
mise. There is no service to set up: the first call starts the daemon on
demand. Without the binaries the wrapper simply runs the command, as
before this change.

## Troubleshooting

- `pueue status` lists the tasks, and `pueue group` the groups with their
  parallelism and whether they run. A task that never starts is waiting
  for a free slot in the `dotfiles` group, or the group is paused and the
  wrapper is about to resume it.
- To stop the daemon, run `pueue shutdown`.
- To run a command without the queue, call it directly, for example
  `scripts/run-validate.sh`.

## See also

- [chezmoi.toml Configuration Reference](chezmoi-toml-reference.md#pueue-validation-queue-datapueueparallelism)
  for the `data.pueue.parallelism` field.
- [IDD policy](idd-policy.md) for the `queued-validation-commands`
  divergence that records the edited Project commands table and what a
  re-import keeps of it.
