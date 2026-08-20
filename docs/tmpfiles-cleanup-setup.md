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
q /tmp 1777 root root <age>
q /var/tmp 1777 root root 30d
```

`/var/tmp`'s `30d` is a **literal**, not a configurable field —
customizing it is out of scope for this template; it is reproduced
only because masking requires the whole file to be present. The exact
shipped ruleset varies by distro and systemd version, so always diff
your own host's file before trusting this override (see Step 2
below).

**Do not deploy this file under any name other than `tmp.conf`.** A
different filename would *add* a second, independent `/tmp` rule
alongside the shipped one instead of replacing it — a documented
source of duplicate/conflicting-rule warnings on every
`systemd-tmpfiles-clean.timer` run, not a safe alternative.

## What the template configures

| Setting | Value | Purpose |
| ------- | --------------------------------------- | --------------------------------------- |
| `/tmp` age | configurable, default `10d` (matches the systemd-shipped default) | How long an untouched file under `/tmp` survives before cleanup |
| `/var/tmp` age | fixed `30d` (not configurable) | Reproduced verbatim because masking replaces the whole file |

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
materially, adapt before deploying.

### Step 3: Back up the existing override (if any)

```bash
sudo test -f /etc/tmpfiles.d/tmp.conf && \
  sudo cp /etc/tmpfiles.d/tmp.conf /etc/tmpfiles.d/tmp.conf.bak
```

### Step 4: Deploy

```bash
sudo cp ~/.config/tmpfiles.d/tmp.conf /etc/tmpfiles.d/tmp.conf
```

Use this exact destination filename — see the masking-semantics
caution above.

### Step 5: Validate before applying for real

```bash
sudo systemd-tmpfiles --create --dry-run /etc/tmpfiles.d/tmp.conf
```

This exits `0` and reports the actions it would take without
performing them. Only proceed once this reports no unexpected errors.

`--dry-run` requires a sufficiently recent `systemd-tmpfiles` — check
with `systemd-tmpfiles --help | grep dry-run` first. If it reports
`unrecognized option '--dry-run'`, that flag isn't available on this
host; skip straight to Step 6, having reviewed the rendered file by
eye beforehand.

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

If the new override causes problems, restore the backup:

```bash
sudo cp /etc/tmpfiles.d/tmp.conf.bak /etc/tmpfiles.d/tmp.conf
sudo systemd-tmpfiles --create /etc/tmpfiles.d/tmp.conf
```

If no backup exists (no prior override was present), remove the file
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
