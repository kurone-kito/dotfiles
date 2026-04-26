# Secret manager setup

This guide explains how to configure chezmoi to retrieve GPG keys,
SSH keys, and SSH host configuration from an external secret manager.

## Supported secret managers

| Manager                             | CLI tool        | chezmoi functions                                          |
| ----------------------------------- | --------------- | ---------------------------------------------------------- |
| [Bitwarden](https://bitwarden.com/) | `bw`            | `bitwarden`, `bitwardenFields`, `bitwardenAttachmentByRef` |
| [1Password](https://1password.com/) | `op`            | `onepasswordRead`, `onepasswordDocument`                   |
| [KeePassXC](https://keepassxc.org/) | `keepassxc-cli` | `keepassxc`, `keepassxcAttribute`                          |

## Prerequisites

1. Install and configure your secret manager CLI
2. Authenticate before running `chezmoi apply`

### Bitwarden example

```bash
# Install (via package manager or download)
sudo apt install bitwarden-cli   # Debian/Ubuntu
brew install bitwarden-cli       # macOS
winget install Bitwarden.CLI     # Windows

# Log in and unlock
bw login
export BW_SESSION="$(bw unlock --raw)"
```

> **Tip:** chezmoi caches `BW_SESSION` during a single `chezmoi apply`
> run, so you only need to unlock once per session.

## Organizing secrets in Bitwarden

Create items with descriptive names and store keys as **attachments**:

### GPG keys

For each GPG identity, create a Bitwarden item:

- **Item name:** `GPG Key - Personal` (or `GPG Key - Work`, etc.)
- **Attachments:**
  - `private.asc` — armored GPG private key
    (`gpg --export-secret-keys --armor KEY_ID > private.asc`)
  - `public.asc` — armored GPG public key
    (`gpg --export --armor KEY_ID > public.asc`)

### SSH keys

For each SSH key pair, create a Bitwarden item:

- **Item name:** `SSH Key - Personal` (or `SSH Key - Work`, etc.)
- **Attachments:**
  - `id_ed25519` (or your key filename) — SSH private key
  - `id_ed25519.pub` — SSH public key

## Configuring chezmoi

### First-time setup

During `chezmoi init`, you will be prompted for the secret manager:

```text
Secret manager (bitwarden, onepassword, keepassxc, none): bitwarden
```

### Adding GPG keys

Edit `~/.config/chezmoi/chezmoi.toml`:

```toml
[data.secret]
manager = "bitwarden"

[data.secret.gpg.personal]
item = "GPG Key - Personal"

[data.secret.gpg.work]
item = "GPG Key - Work"
```

The `item` value must match the **exact item name** in your Bitwarden
vault.

### Adding SSH keys

```toml
[data.secret.ssh.keys.personal]
item = "SSH Key - Personal"
filename = "id_ed25519_personal"

[data.secret.ssh.keys.work]
item = "SSH Key - Work"
filename = "id_ed25519_work"
```

- `item` — Bitwarden item name containing the key attachments
- `filename` — target filename under `~/.ssh/` (without path)

### Adding SSH hosts

```toml
[data.secret.ssh.hosts.github-personal]
hostname = "github.com"
user = "git"
identity = "id_ed25519_personal"

[data.secret.ssh.hosts.work-gitlab]
hostname = "gitlab.example.com"
user = "git"
identity = "id_ed25519_work"
```

- `hostname` — remote host address
- `user` — SSH user (defaults to `git` if omitted)
- `identity` — filename of the SSH key (must match a `filename` in
  `ssh.keys`)

This generates `~/.ssh/config` entries like:

```text
Host github-personal
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_personal
```

## Applying

```bash
# Ensure secret manager is unlocked
export BW_SESSION="$(bw unlock --raw)"

# Apply (first run imports GPG keys and deploys SSH keys)
chezmoi apply
```

### What happens on first apply

1. **`run_once_before_10-import-gpg-keys`** — imports GPG private
   keys into the local keyring via `gpg --import`
2. **`run_once_before_20-deploy-ssh-keys`** — writes SSH key files
   to `~/.ssh/` with correct permissions (skips if files exist)
3. **`~/.ssh/config`** — generated from host entries in chezmoi.toml

### Re-running import scripts

The `run_once_before` scripts only execute once (tracked in chezmoi
state). To force a re-run:

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

## Running without a secret manager

Set `manager = "none"` to skip all secret retrieval. You can
manually place GPG keys and SSH files, then run `chezmoi apply`
for the remaining configuration.

## 1Password configuration

Use `op://` URIs as item identifiers:

```toml
[data.secret]
manager = "onepassword"

[data.secret.gpg.personal]
item = "op://Private/GPG Key - Personal"

[data.secret.ssh.keys.personal]
item = "SSH Key - Personal"
filename = "id_ed25519_personal"
```

Authenticate with `eval $(op signin)` before `chezmoi apply`.

## KeePassXC configuration

Use KeePassXC entry paths as item identifiers:

```toml
[data.secret]
manager = "keepassxc"

[data.secret.gpg.personal]
item = "/Keys/GPG Key - Personal"

[data.secret.ssh.keys.personal]
item = "/Keys/SSH Key - Personal"
filename = "id_ed25519_personal"
```

> **Note:** For KeePassXC file attachments, store the key content
> as a named attribute (base64-encoded if binary). The attribute
> name must match the `filename` parameter.
