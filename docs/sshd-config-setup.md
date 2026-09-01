---
type: guide
title: Deploying sshd_config
description: Explains how to manually deploy the chezmoi-generated hardened sshd_config to its system location on Linux, macOS, and Windows.
---

# Deploying sshd_config

This project generates a hardened `sshd_config` at
`~/.config/ssh/sshd_config` via chezmoi. Because the SSH daemon
configuration is system-level (requiring root/administrator
privileges), chezmoi does not deploy it automatically. This guide
explains how to manually deploy it.

## Why manual deployment?

chezmoi is a **user-level** dotfiles manager. The SSH daemon
configuration lives in system directories owned by root:

| Platform | System path                      | Privilege     |
| -------- | -------------------------------- | ------------- |
| Linux    | `/etc/ssh/sshd_config`           | root          |
| macOS    | `/etc/ssh/sshd_config`           | root          |
| Windows  | `C:\ProgramData\ssh\sshd_config` | Administrator |

Automatically escalating to root during `chezmoi apply` would
violate the principle of least privilege and could break the SSH
daemon if the configuration is invalid.

## What the template configures

The generated `sshd_config` includes only the settings that differ
from defaults:

| Setting                      | Value                                                                   | Purpose                                                       |
| ---------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------- |
| `PasswordAuthentication`     | `no`                                                                    | Disable password login                                        |
| `PermitEmptyPasswords`       | `no`                                                                    | Reject empty passwords                                        |
| `PermitRootLogin`            | `no`                                                                    | Block root SSH access (no effect on Windows; no root concept) |
| `PubkeyAuthentication`       | `yes`                                                                   | Enable public key authentication                              |
| `AuthenticationMethods`      | `publickey`                                                             | Enforce key-only authentication                               |
| `Subsystem sftp`             | `internal-sftp`                                                         | Cross-platform SFTP support                                   |
| `ClientAliveInterval`        | `300`                                                                   | Keepalive probe interval (seconds)                            |
| `ClientAliveCountMax`        | `5`                                                                     | Max missed probes before disconnect                           |
| `TCPKeepAlive`               | `yes`                                                                   | Enable TCP-level keepalive                                    |
| `Match Group administrators` | `AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys` | Windows only: route admin-group logins to the system key file |

The timeout values (`ClientAliveInterval × ClientAliveCountMax`)
default to approximately 25 minutes, suitable for mobile connections
with frequent congestion.

## Deployment steps

### Step 1: Generate the configuration

```bash
chezmoi apply
```

This renders `~/.config/ssh/sshd_config` from the template.

### Step 2: Validate the configuration

Always validate before deploying to avoid locking yourself out:

**Linux / macOS:**

```bash
sshd -t -f ~/.config/ssh/sshd_config
```

**Windows (PowerShell as Administrator):**

```powershell
& "$env:SystemRoot\System32\OpenSSH\sshd.exe" -t -f "$HOME\.config\ssh\sshd_config"
```

If the output is silent (no errors), the configuration is valid.

### Step 3: Back up the existing configuration

**Linux / macOS:**

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
```

**Windows (PowerShell as Administrator):**

```powershell
Copy-Item C:\ProgramData\ssh\sshd_config C:\ProgramData\ssh\sshd_config.bak
```

### Step 4: Deploy

**Linux / macOS:**

```bash
sudo cp ~/.config/ssh/sshd_config /etc/ssh/sshd_config
```

**Windows (PowerShell as Administrator):**

```powershell
Copy-Item "$HOME\.config\ssh\sshd_config" C:\ProgramData\ssh\sshd_config
```

### Step 5: Reload the SSH daemon

**Linux (systemd):**

```bash
sudo systemctl reload sshd
```

**macOS:**

```bash
sudo launchctl kickstart -k system/com.openssh.sshd
```

**Windows (PowerShell as Administrator):**

```powershell
Restart-Service sshd
```

> **Warning:** Before closing your current SSH session, open a
> **new** SSH connection in a separate terminal to verify the new
> configuration works. If it fails, revert from the backup.

## Customization

### Timeout values

Override the defaults in `~/.config/chezmoi/chezmoi.toml`:

```toml
[data.ssh.server]
clientAliveInterval = 600  # 10-minute probe interval
clientAliveCountMax = 3    # 3 missed probes → ~30 min total
```

Then re-run `chezmoi apply` and redeploy.

### Platform notes

- **`PermitRootLogin`** is emitted unconditionally, including on
  Windows, since the directive is harmless there (the root user
  concept does not exist, so `sshd` has nothing to block). Use
  Windows group policies or `DenyGroups` to restrict administrator
  access instead.
- **Windows administrator accounts** use
  `C:\ProgramData\ssh\administrators_authorized_keys` by default,
  not `%USERPROFILE%\.ssh\authorized_keys`. The rendered Windows
  config wires this up directly with a trailing `Match Group
  administrators` block whose `AuthorizedKeysFile` points at that
  system-level file — this is why the block must stay the last
  section of the file (a `Match` block scopes every directive that
  follows it, not just the ones immediately under it).
- **`Subsystem sftp internal-sftp`** uses the OpenSSH built-in
  SFTP server (available since OpenSSH 4.9), avoiding
  platform-specific binary paths.
- All other settings not listed above use the OpenSSH defaults
  for the installed version.

## Windows: Sync administrator authorized_keys

Windows OpenSSH treats administrator accounts specially. When the SSH
login user belongs to `BUILTIN\Administrators`, the service reads
`C:\ProgramData\ssh\administrators_authorized_keys` instead of the
per-user `%USERPROFILE%\.ssh\authorized_keys` file.

This repository still generates `~/.ssh/authorized_keys` from your
deployed public keys so the key list remains user-managed. For Windows
administrator accounts, sync that file into the system location after
key changes:

```powershell
# Run as Administrator
& "$HOME\.local\bin\sync-openssh-authorized-keys.ps1"
```

**Preview changes without applying (dry run):**

```powershell
& "$HOME\.local\bin\sync-openssh-authorized-keys.ps1" -WhatIf
```

**Specify a custom source file:**

```powershell
& "$HOME\.local\bin\sync-openssh-authorized-keys.ps1" `
  -Source "$HOME\.ssh\authorized_keys"
```

The helper script:

1. Verifies the current session has administrator privileges
2. Copies `~/.ssh/authorized_keys` to
   `C:\ProgramData\ssh\administrators_authorized_keys`
3. Resets the ACL to `Administrators` + `SYSTEM` only

Re-run the helper whenever `chezmoi apply` updates your public keys.

## Windows: Changing the default SSH shell

By default, Windows OpenSSH uses `cmd.exe` as the login shell. This
project includes a helper script that can switch it to PowerShell (7
`pwsh` or legacy `powershell`), or reset it back to `cmd.exe`. Its
default resolution is declarative and driven by
`[data.ssh.server].defaultShell` in `chezmoi.toml`.

### Why a separate script?

The default shell is controlled by a machine-wide registry key
(`HKLM:\SOFTWARE\OpenSSH\DefaultShell`) that requires administrator
privileges. chezmoi deploys the script to `~/.local/bin/`, but you
must run it manually with elevation -- chezmoi never applies this
registry change automatically.

### Configuring `chezmoi.toml`

Add to `[data.ssh.server]` in `chezmoi.toml`:

```toml
[data.ssh.server]
defaultShell = "modern-powershell"    # "cmd", "legacy-powershell", or
                                       # "modern-powershell"
defaultShellFallbackToLegacy = false  # ignored unless defaultShell is
                                       # "modern-powershell"
```

`defaultShell` controls what the script's **bare invocation** (no
`-Shell` / `-Reset` flag) resolves to:

| `defaultShell` | Bare invocation behavior |
| --- | --- |
| *(absent)* | No-op: prints guidance and exits without touching the registry. |
| `"cmd"` | Equivalent to `-Reset` -- removes the `DefaultShell` / `DefaultShellCommandOption` registry values. |
| `"legacy-powershell"` | Resolves and sets `powershell.exe`. Fails loudly if it isn't found. |
| `"modern-powershell"` | Resolves and sets `pwsh.exe`. Fails loudly if it isn't found, unless `defaultShellFallbackToLegacy = true`, in which case it falls back to `powershell.exe` (and still fails loudly if that is also missing). |

An unrecognized `defaultShell` value fails loudly and lists the three
valid choices.

### Usage

**Set the default shell from `chezmoi.toml` (config-driven):**

Set `defaultShell` as shown above, run `chezmoi apply` to re-render
the script, then run it bare as Administrator:

```powershell
# Run as Administrator
& "$HOME\.local\bin\set-openssh-default-shell.ps1"
```

**Preview changes without applying (dry run):**

```powershell
& "$HOME\.local\bin\set-openssh-default-shell.ps1" -WhatIf
```

**Specify a custom shell path (explicit, config-independent override):**

```powershell
& "$HOME\.local\bin\set-openssh-default-shell.ps1" -Shell "C:\Program Files\PowerShell\7\pwsh.exe"
```

**Reset to the system default (`cmd.exe`), explicit override:**

```powershell
& "$HOME\.local\bin\set-openssh-default-shell.ps1" -Reset
```

**Skip sshd restart:**

```powershell
& "$HOME\.local\bin\set-openssh-default-shell.ps1" -NoRestart
```

`-Shell <path>` and `-Reset` always take priority over `chezmoi.toml`
and behave identically regardless of what (if anything) `defaultShell`
is set to; only a bare invocation (both flags omitted) resolves
`defaultShell`.

### What it does

1. Verifies the current session has administrator privileges
2. On a bare invocation, resolves `[data.ssh.server].defaultShell` per
   the table above (explicit `-Shell` / `-Reset` skip this step)
3. Sets `HKLM:\SOFTWARE\OpenSSH\DefaultShell` to the resolved shell
   path, or removes it (and `DefaultShellCommandOption`) when
   resetting
4. Sets `HKLM:\SOFTWARE\OpenSSH\DefaultShellCommandOption` to
   `-NoLogo -NoProfile` for a clean startup when setting a shell
5. Restarts the `sshd` service (unless `-NoRestart` is specified)

### Notes

- New SSH sessions use the updated shell immediately after sshd
  restarts. Existing sessions are unaffected.
- The `-Reset` flag (and `defaultShell = "cmd"`) removes both registry
  values, reverting to the Windows default (`cmd.exe`).
- This setting is system-wide (all SSH users). Per-user shell
  overrides are not supported by Windows OpenSSH.
- **Behavior change**: previously, a bare invocation (no arguments)
  implicitly preferred `pwsh.exe`, falling back to `powershell.exe`,
  and threw if neither was found. That implicit preference is
  superseded by the explicit `defaultShell` resolution table above --
  a bare invocation with no `defaultShell` configured is now a no-op
  instead of an implicit `pwsh`/`powershell` preference.

## Troubleshooting

### Locked out after deploying

If you cannot connect after deploying:

1. Use a local console or out-of-band access (IPMI, cloud console)
2. Restore the backup:

   ```bash
   sudo cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
   sudo systemctl reload sshd
   ```

### `sshd -t` reports errors

Common causes:

- **`Unsupported option`**: The OpenSSH version is too old for a
  directive. Check `sshd -V` for the installed version.
- **`AuthenticationMethods`** requires OpenSSH 6.0+.
- **`internal-sftp`** requires OpenSSH 4.9+.

### Windows: `Permission denied (publickey)` for admin accounts

If Windows service mode rejects key auth but `sshd -d` from a local
foreground prompt succeeds, check whether the login account is in the
local `Administrators` group.

In that case, the most common cause is that `sshd` is looking for
`C:\ProgramData\ssh\administrators_authorized_keys` while your key only
exists in `%USERPROFILE%\.ssh\authorized_keys`.

Fix it by re-syncing the administrator key file from an elevated prompt:

```powershell
& "$HOME\.local\bin\sync-openssh-authorized-keys.ps1"
```

If the account is **not** an administrator, ensure
`%USERPROFILE%\.ssh\authorized_keys` exists and still grants read access
to `SYSTEM`.

### Connection drops on mobile

If connections still drop frequently, reduce the probe interval:

```toml
[data.ssh.server]
clientAliveInterval = 60   # probe every minute
clientAliveCountMax = 10   # tolerate 10 minutes of silence
```
