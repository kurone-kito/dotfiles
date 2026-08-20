---
type: guide
title: Configuring the systemd-tmpfiles /tmp cleanup age
description: Explains how to manually deploy the chezmoi-generated tmpfiles.d override that shortens the /tmp cleanup age on Linux, and why deployment stays manual.
---

# Configuring the systemd-tmpfiles /tmp cleanup age

This project generates a `tmp.conf` override at
`~/.config/tmpfiles.d/tmp.conf` via chezmoi. Because the effective
configuration lives in a system directory (`/etc/tmpfiles.d/`),
chezmoi does not deploy it automatically. This guide explains the
masking semantics involved, how to deploy it manually, and what this
setting can and cannot fix.

## Why manual deployment?

chezmoi is a **user-level** dotfiles manager. `systemd-tmpfiles`
reads its configuration from system directories owned by root:

| Path | Owner | Role |
| ------------------------------ | ----- | ---------------------------------------------- |
| `/usr/lib/tmpfiles.d/tmp.conf` | root | Distro-shipped default `/tmp` cleanup rules |
| `/etc/tmpfiles.d/tmp.conf` | root | Local override (same filename **masks** the shipped file) |

Automatically escalating to root during `chezmoi apply` would violate
the principle of least privilege, so this follows the same
manual-deployment shape as [`docs/sshd-config-setup.md`](sshd-config-setup.md).

## Masking semantics — read before deploying

`systemd-tmpfiles` resolves configuration by filename across a
priority-ordered set of directories. A file in `/etc/tmpfiles.d/`
**fully replaces** (masks) any file of the same name in
`/usr/lib/tmpfiles.d/` — it does not merge with it. The shipped
file's own comment documents this: "Clear tmp directories separately,
to make them easier to override."

Because masking replaces the *whole file*, the generated `tmp.conf`
reproduces **both** of the shipped rules, with only the `/tmp` age
configurable:

```text
q /tmp 1777 root root "<age>"
#q /var/tmp 1777 root root 30d
```

The `/tmp` age is quoted so a multi-component systemd time span
containing a space (e.g. `"1d 12h"`, valid `systemd.time(7)` syntax)
still parses as one field — unquoted, systemd-tmpfiles treats the
extra token as an unexpected argument and silently ignores the whole
age instead ("q lines don't take argument fields, ignoring"),
falling back to its own built-in default.

`/var/tmp`'s `30d` line stays **commented out by default** — not a
configurable field, and deliberately not force-enabled either. The
exact shipped ruleset varies by distro and systemd version: on Ubuntu
24.04, for example, the shipped `/usr/lib/tmpfiles.d/tmp.conf` itself
ships `/var/tmp` cleanup commented out (`#q /var/tmp 1777 root root
30d`), while other distros/versions ship it active. Because masking
fully replaces the file, unconditionally enabling this line would
silently start deleting untouched `/var/tmp` contents on any host
whose shipped default had it disabled — always diff your own host's
file first (Step 2 below) and uncomment the line only if your shipped
default already had it active.

The `/tmp` line uses the `q` type letter (create-if-missing; a
`--remove` pass does **not** empty existing contents), not `D` (same,
but `--remove` **does** empty contents). Some distros ship `D` for
`/tmp` — Ubuntu 24.04, for example, ships `D /tmp 1777 root root 30d`,
and its `systemd-tmpfiles-setup.service` runs `systemd-tmpfiles
--create --remove --boot`, so that shipped `D` line fully empties
`/tmp` on every boot. Masking it with this template's `q` line
silently disables that boot-time wipe. `q` is kept as the default
specifically because it avoids adding that boot-time wipe behavior on
top of whatever the vendor rule already did — this is narrower than a
general "less-destructive" claim: deploying a shorter age (or the
project's `10d` default on a host whose vendor age is longer) still
deletes files sooner than before, regardless of `q` vs `D`. Check your
diffed vendor file's own type letter (Step 2) and change the generated
`q` to `D` if you need to preserve an existing boot-time wipe; check
the age separately (previous section).

**Do not deploy this file under any name other than `tmp.conf`.** A
different filename would *add* a second, independent `/tmp` rule
alongside the shipped one instead of replacing it — a documented
source of duplicate/conflicting-rule warnings on every
`systemd-tmpfiles-clean.timer` run, not a safe alternative.

## What the template configures

| Setting | Value | Purpose |
| ------- | --------------------------------------- | --------------------------------------- |
| `/tmp` age | configurable, project default `10d` | How long an untouched file under `/tmp` survives before cleanup. **`10d` is this project's own chosen default, not necessarily your distro's shipped default** — e.g. Ubuntu 24.04 ships `30d`. Deploying the default without diffing your host's shipped file first can change (not just document) your retention policy. |
| `/var/tmp` age | commented out by default (not force-enabled) | Reproduced as an inactive placeholder line because masking replaces the whole file; uncomment manually if your host's shipped default already had it active |

## Deployment steps

### Step 1: Generate the configuration

```bash
chezmoi apply
```

This renders `~/.config/tmpfiles.d/tmp.conf` from the template.

### Step 2: Diff against the shipped file

```bash
cat /usr/lib/tmpfiles.d/tmp.conf
```

Compare this against the generated file to confirm your distro ships
the same two-rule shape this template assumes. If it differs
materially, adapt before deploying:

- **`/var/tmp` activation**: check whether the shipped `/var/tmp` line
  is active or commented out. If it's active on your host, edit
  `~/.config/tmpfiles.d/tmp.conf` to uncomment the `#q /var/tmp 1777
  root root 30d` line before continuing — otherwise leave it commented
  (the default) so this override doesn't change `/var/tmp` behavior
  your host wasn't already applying.
- **`/tmp` type letter**: check whether the shipped `/tmp` line uses
  `q` or `D`. If it uses `D` (as Ubuntu 24.04 does), edit the generated
  `/tmp` line to use `D` instead of `q` to preserve an existing
  boot-time wipe — see the masking-semantics section above.
- **`/tmp` age**: note your host's actual shipped age before deploying
  the project default. Deploying `10d` unmodified changes (not just
  documents) your retention policy when your host's shipped age
  differs — see the table above.

### Step 3: Back up the existing override (if any)

`/etc/tmpfiles.d/tmp.conf` may already exist as either a regular file
or a **symlink** — the standard way to fully mask a vendor tmpfiles
file is a symlink to `/dev/null`. Bash's `test -f` follows symlinks
and requires the resolved target to be a *regular file*, so it
evaluates false for a symlink to `/dev/null` (a character device) —
naively backing up only when `-f` is true silently skips backing up a
symlink-based mask, and Step 5's `--remove-destination` then deletes
that symlink permanently with no way to restore it. Detect and handle
both cases:

Each backup form is mutually exclusive with the other and with any
prior round's backup — remove the alternate form when writing either,
so at most one backup exists and Rollback always restores the
*immediately previous* configuration rather than a stale one left over
from an earlier round where the override's type differed:

```bash
if sudo test -L /etc/tmpfiles.d/tmp.conf; then
  sudo rm -f /etc/tmpfiles.d/tmp.conf.bak
  sudo readlink /etc/tmpfiles.d/tmp.conf | \
    sudo tee /etc/tmpfiles.d/tmp.conf.bak.symlink-target > /dev/null
elif sudo test -f /etc/tmpfiles.d/tmp.conf; then
  sudo rm -f /etc/tmpfiles.d/tmp.conf.bak.symlink-target
  sudo cp /etc/tmpfiles.d/tmp.conf /etc/tmpfiles.d/tmp.conf.bak
fi
```

### Step 4: Validate the staged copy before deploying

Validate `~/.config/tmpfiles.d/tmp.conf` — the staged copy, not yet
installed — **before** Step 5 overwrites the live vendor file.
Validating only after deploying (as an earlier revision of this guide
did) means a syntax error in a hand-edited staged file already masked
the valid vendor config by the time validation catches it, and
`systemd-tmpfiles-clean.timer`'s own service
(`systemd-tmpfiles-clean.service`) reads whatever is active at
`/etc/tmpfiles.d/tmp.conf` on its own schedule — it does not re-run
Step 6 itself, so a bad override deployed early could be picked up by
that timer before you notice:

```bash
systemd-tmpfiles --create --dry-run ~/.config/tmpfiles.d/tmp.conf
```

This exits `0` and reports the actions it would take without
performing them (no `sudo` needed — it targets your own staged copy).
Only proceed to Step 5 once this reports no unexpected errors.

`--dry-run` requires a sufficiently recent `systemd-tmpfiles` — check
with `systemd-tmpfiles --help | grep dry-run` first. If it reports
`unrecognized option '--dry-run'`, that flag isn't available on this
host; skip straight to Step 5, having reviewed the staged file by eye
beforehand.

### Step 5: Deploy

```bash
sudo cp --remove-destination ~/.config/tmpfiles.d/tmp.conf /etc/tmpfiles.d/tmp.conf
```

Use this exact destination filename — see the masking-semantics
caution above. `--remove-destination` matters because a plain `cp`
follows an existing destination symlink and writes through it (to
`/dev/null`, silently discarding the new content and leaving the mask
in place — or to whatever else the symlink targets), so Step 6's
apply could report success while the new policy was never actually
installed. `--remove-destination` deletes the destination path itself
(symlink or not) before writing, ensuring a real regular file lands at
`/etc/tmpfiles.d/tmp.conf`.

### Step 6: Apply

```bash
sudo systemd-tmpfiles --create /etc/tmpfiles.d/tmp.conf
```

`systemd-tmpfiles-clean.timer` (roughly daily by default) picks up the
new age on its next run; no reload or restart is required.

## Customization

Override the default in `~/.config/chezmoi/chezmoi.toml`:

```toml
[data.tmpfiles]
age = "2d"  # systemd time-span syntax, e.g. "2d", "36h"
```

Then re-run `chezmoi apply` and redeploy (Steps 1–6 above).

## Rollback

If the new override causes problems, restore whichever backup Step 3
produced:

**A symlink-target backup exists** (the prior override was a symlink,
e.g. a `/dev/null` mask):

```bash
sudo ln -sf "$(sudo cat /etc/tmpfiles.d/tmp.conf.bak.symlink-target)" \
  /etc/tmpfiles.d/tmp.conf
```

Re-running `systemd-tmpfiles --create` afterward is unnecessary here —
a symlink to `/dev/null` masks the file entirely rather than defining
active rules.

**A regular-file backup exists**:

```bash
sudo cp --remove-destination /etc/tmpfiles.d/tmp.conf.bak /etc/tmpfiles.d/tmp.conf
sudo systemd-tmpfiles --create /etc/tmpfiles.d/tmp.conf
```

**No backup exists** (no prior override was present), remove the file
to fall back to the shipped default:

```bash
sudo rm /etc/tmpfiles.d/tmp.conf
sudo systemd-tmpfiles --create /usr/lib/tmpfiles.d/tmp.conf
```

## Limitations

A shorter `age` **shrinks the retention window**, but it does **not**
increase cleanup **frequency** beyond
`systemd-tmpfiles-clean.timer`'s own schedule (roughly once a day by
default). `systemd-tmpfiles-clean.timer` runs on that fixed cadence
regardless of the configured `age`, so a shorter age only means more
files qualify for reclamation on each run — not that reclamation runs
more often. If inode or disk exhaustion happens faster than that
timer's cadence, this setting alone will not fully resolve it; check
the timer's actual schedule with
`systemctl list-timers systemd-tmpfiles-clean.timer` and consider a
more frequent custom timer if needed.

## Platform notes

This feature is Linux-only by construction — macOS does not use
`systemd-tmpfiles`, and the chezmoi source is excluded via
`home/.chezmoiignore.tmpl` on any non-Linux OS or on a Linux host
missing the `systemd-tmpfiles` binary.
