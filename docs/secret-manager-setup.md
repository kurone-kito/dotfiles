# Secret manager setup

This guide explains how to configure chezmoi to retrieve GPG keys,
SSH keys, and SSH host configuration from an external secret manager.

## Identity model

This dotfiles setup supports **multiple identities** (e.g., personal,
work, open source). Understanding how the pieces connect is key to
configuring secrets correctly.

### How identities map across sections

```txt
┌─────────────────────────────────────────────────────────────────┐
│ data.git.*  (PRIMARY identity — used globally by default)       │
│   name, email, signingkey ──────┐                               │
│                                 │ GPG fingerprint               │
│ data.git.profiles.<key>         │ matches the key               │
│   (directory-scoped overrides)  │ imported from:                │
│   name, email, signingkey ──┐   │                               │
│   sshhost (optional) ──┐    │   │                               │
│                        │    │   │                               │
├────────────────────────┼────┼───┼───────────────────────────────┤
│ url.insteadOf          │    │   │                               │
│   (auto-generated when │    │   │                               │
│   sshhost is set;      │    │   │                               │
│   routes ghq clones    │    │   │                               │
│   through SSH alias) ──┘    │   │                               │
├─────────────────────────────┼───┼───────────────────────────────┤
│ data.secret.gpg.<label>     │   │                               │
│   item ─── secret manager ──┼───┘  imports private key whose    │
│            item name        │      fingerprint matches          │
│                             │      a signingkey above           │
├─────────────────────────────┼───────────────────────────────────┤
│ data.secret.ssh.keys.<label>│                                   │
│   item ─── secret manager item name                             │
│   filename ─── target file under ~/.ssh/  ──┐                   │
│                                             │ referenced by     │
│ data.secret.ssh.hosts.<alias>               │                   │
│   hostname, user, port (optional)           │                   │
│   identity ─── must match a filename above ─┘                   │
├─────────────────────────────────────────────────────────────────┤
│ data.ghq.clone.<label>  (optional — bulk clone)                 │
│   owner ─── GitHub user/org to clone from                       │
│   token_item ─── secret manager item for GitHub PAT             │
│   hostname ─── GitHub host (default: github.com)                │
└─────────────────────────────────────────────────────────────────┘
```

- **`data.git.*`** is the **primary** identity. It applies to all
  repositories unless overridden by a profile.
- **`data.git.profiles.*`** are **directory-scoped overrides**.
  Repositories under the specified `gitdir` path use the profile's
  name, email, and signing key instead. When `sshhost` is set, ghq
  clones are automatically routed through the matching SSH alias
  (see [ghq-workflow.md](./ghq-workflow.md)).
- **`data.secret.gpg.*`** lists GPG key items to import. Each
  corresponds to a `signingkey` fingerprint in git config.
- **`data.secret.ssh.keys.*`** lists SSH key pairs to deploy. The
  `filename` determines the file written under `~/.ssh/`.
- **`data.secret.ssh.hosts.*`** maps host aliases to SSH keys via
  the `identity` field, which must match a `filename` above.

### Naming conventions

The `<label>` in each TOML section (e.g., `gpg.personal`,
`ssh.keys.work`) is a **user-chosen identifier**. It:

- Has no effect on the secret manager or deployed files
- Must be a valid TOML bare key (lowercase, hyphens, underscores)
- Should be **consistent across sections** for traceability
  (e.g., use `work` for `gpg.work`, `ssh.keys.work`,
  and `ssh.hosts.github-work`)

For SSH hosts serving multiple identities, use the pattern
`<service>-<identity>` (e.g., `github-personal`, `gitlab-work`).

You can add as many identities as needed — just repeat the pattern
with a new label.

> **TOML key quoting:** If a key contains **dots** (e.g., a domain
> name like `github.com`), you must **quote** it in the TOML section
> header. Otherwise TOML interprets dots as nested table delimiters.
>
> ```toml
> # ✗ Wrong — TOML parses this as hosts → github → com
> [data.secret.ssh.hosts.github.com]
>
> # ✓ Correct — quoted key preserves the literal dot
> [data.secret.ssh.hosts."github.com"]
> ```

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

For each SSH key pair, create a Bitwarden **SSH key** item
(not a regular item with attachments):

1. In Bitwarden, select **New** → **SSH key**
2. Import or paste your private key (OpenSSH or PKCS#8 format)
3. Bitwarden automatically derives the public key and fingerprint
4. Name the item descriptively (e.g., `SSH Key - Personal`)

The deploy script retrieves the structured `sshKey.privateKey` and
`sshKey.publicKey` fields directly — no attachments needed.

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

# Label is user-defined; add as many as needed
[data.secret.gpg.personal]
item = "GPG Key - Personal"

[data.secret.gpg.work]
item = "GPG Key - Work"

[data.secret.gpg.oss]
item = "GPG Key - OSS"
```

The `item` value must match the **exact item name** in your Bitwarden
vault.

### Adding SSH keys

```toml
# Label is user-defined; filename is the target file under ~/.ssh/
[data.secret.ssh.keys.personal]
item = "SSH Key - Personal"
filename = "id_ed25519_personal"

[data.secret.ssh.keys.work]
item = "SSH Key - Work"
filename = "id_ed25519_work"

[data.secret.ssh.keys.oss]
item = "SSH Key - OSS"
filename = "id_ed25519_oss"
```

- `item` — Bitwarden SSH Key item name (native SSH key type)
- `filename` — target filename under `~/.ssh/` (without path)

### Adding SSH hosts

```toml
# Alias is user-defined; identity must match a filename above
[data.secret.ssh.hosts.github-personal]
hostname = "github.com"
user = "git"
identity = "id_ed25519_personal"

[data.secret.ssh.hosts.gitlab-work]
hostname = "gitlab.example.com"
user = "git"
identity = "id_ed25519_work"
port = 2222

[data.secret.ssh.hosts.github-oss]
hostname = "github.com"
user = "git"
identity = "id_ed25519_oss"
```

- `hostname` — remote host address
- `user` — SSH user (defaults to `git` if omitted)
- `identity` — filename of the SSH key (must match a `filename` in
  `ssh.keys`)
- `port` — SSH port number (optional; omit for default 22)

To **override the default connection** for a domain (e.g., use a
specific key for all `github.com` access), quote the domain name
as the alias:

```toml
# Overrides the default SSH connection to github.com
[data.secret.ssh.hosts."github.com"]
hostname = "github.com"
user = "git"
identity = "id_ed25519_personal"
```

This generates:

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_personal
```

> **Note:** When overriding a real hostname, you can only bind **one
> key** to that host. If you need multiple identities for the same
> service (e.g., two GitHub accounts), use distinct aliases like
> `github-personal` and `github-work` instead.

This generates `~/.ssh/config` entries like:

```text
Host github-personal
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_personal

Host gitlab-work
  HostName gitlab.example.com
  Port 2222
  User git
  IdentityFile ~/.ssh/id_ed25519_work
```

### Complete multi-identity example

Below is a full `chezmoi.toml` configuration with three identities.
The **primary** identity (`data.git.*`) is used globally; the others
override it in specific directories.

```toml
# Primary (default) git identity
[data.git]
name = "Alice"
email = "alice@personal.dev"
signingkey = "AAAA1111BBBB2222"  # GPG fingerprint

# Work identity — overrides in ~/work/ repositories
[data.git.profiles.work]
name = "Alice Corporate"
email = "alice@example.com"
signingkey = "CCCC3333DDDD4444"
gitdir = "~/work/"
sshhost = "github-work"   # optional — routes ghq clones via this SSH alias

# OSS identity — overrides in ~/oss/ repositories
[data.git.profiles.oss]
name = "alice-dev"
email = "alice-dev@users.noreply.github.com"
signingkey = "EEEE5555FFFF6666"
gitdir = "~/oss/"

# GPG keys — one per signingkey fingerprint
[data.secret]
manager = "bitwarden"

[data.secret.gpg.personal]
item = "GPG Key - Personal"      # imports key AAAA1111BBBB2222

[data.secret.gpg.work]
item = "GPG Key - Work"          # imports key CCCC3333DDDD4444

[data.secret.gpg.oss]
item = "GPG Key - OSS"           # imports key EEEE5555FFFF6666

# SSH keys — filename is the target file under ~/.ssh/
[data.secret.ssh.keys.personal]
item = "SSH Key - Personal"
filename = "id_ed25519_personal"

[data.secret.ssh.keys.work]
item = "SSH Key - Work"
filename = "id_ed25519_work"

[data.secret.ssh.keys.oss]
item = "SSH Key - OSS"
filename = "id_ed25519_oss"

# SSH hosts — identity references a filename above
[data.secret.ssh.hosts.github-personal]
hostname = "github.com"
user = "git"
identity = "id_ed25519_personal"

[data.secret.ssh.hosts.gitlab-work]
hostname = "gitlab.example.com"
user = "git"
identity = "id_ed25519_work"
port = 2222

[data.secret.ssh.hosts.github-oss]
hostname = "github.com"
user = "git"
identity = "id_ed25519_oss"
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
4. **`run_onchange_after_generate-authorized-keys`** — concatenates
   deployed `.pub` files into `~/.ssh/authorized_keys` (re-runs
   automatically when SSH key configuration changes)
5. **`run_onchange_after_50-install-mise-tools`** — runs `mise install`
   to install declared tools (re-runs when mise config changes)
6. **`run_onchange_after_60-clone-ghq-repos`** — bulk-clones
   repositories for configured GitHub accounts via ghq (re-runs
   when ghq clone configuration changes; see [ghq-workflow.md](./ghq-workflow.md))

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
item = "Private/SSH Key - Personal"
filename = "id_ed25519_personal"
```

For SSH keys, create a **SSH Key** item in 1Password. The deploy
script reads the `private key` and `public key` fields via
`op://` URIs automatically.

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

For SSH keys, store the private and public key content as named
attributes `privateKey` and `publicKey` on the KeePassXC entry.

> **Note:** For KeePassXC GPG key attachments, store the key
> content as a named attribute (base64-encoded if binary). The
> attribute name must match the `filename` parameter.
