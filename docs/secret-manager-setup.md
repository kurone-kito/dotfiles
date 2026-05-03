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
| Local files                         |                 | `output` (reads via `cat` / `Get-Content`)                 |

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
7. **`run_onchange_after_70-deploy-env-files`** — deploys `.env`
   files from the secret manager into cloned project directories
   (re-runs when env deploy configuration or secret content changes)

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

## Local file storage

Set `manager = "local"` to read secrets from a local directory
instead of an external secret manager. This is useful for
air-gapped machines or environments where cloud storage is
prohibited.

### Directory structure

Secrets are organized as `<local_dir>/<item>/<param>`, where
`<item>` matches the `item` field in `chezmoi.toml` and `<param>`
is determined by the template being called:

```txt
~/.config/chezmoi/secrets/         # default local_dir
├── gpg-personal/
│   └── private.asc                # GPG private key (armored)
├── ssh-personal/
│   ├── private                    # SSH private key (PEM/OpenSSH)
│   └── public                     # SSH public key
├── github-pat/
│   └── password                   # GitHub PAT (single value)
└── myapp-env/
    └── .env                       # .env file content
```

**Mapping rules:**

| Template                | Parameter                          | File read                        |
| ----------------------- | ---------------------------------- | -------------------------------- |
| `get-secret`            | `field` (e.g., `"password"`)       | `<local_dir>/<item>/password`    |
| `get-secret-attachment` | `filename` (e.g., `"private.asc"`) | `<local_dir>/<item>/private.asc` |
| `get-ssh-key`           | `type` (`"private"` or `"public"`) | `<local_dir>/<item>/private`     |

### Configuration

```toml
[data.secret]
manager = "local"
local_dir = "~/.config/chezmoi/secrets"  # optional; this is the default

# Item names are subdirectory names within local_dir
[data.secret.gpg.personal]
item = "gpg-personal"

[data.secret.ssh.keys.personal]
item = "ssh-personal"
filename = "id_ed25519_personal"

[data.secret.ssh.hosts.github-personal]
hostname = "github.com"
user = "git"
identity = "id_ed25519_personal"

[data.ghq.clone.personal]
owner = "alice"
token_item = "github-pat"
```

### Setup steps

1. Create the secrets directory:

   ```bash
   mkdir -p ~/.config/chezmoi/secrets
   chmod 700 ~/.config/chezmoi/secrets
   ```

2. Populate with your secrets:

   ```bash
   # GPG key
   mkdir -p ~/.config/chezmoi/secrets/gpg-personal
   gpg --export-secret-keys --armor KEY_ID \
     > ~/.config/chezmoi/secrets/gpg-personal/private.asc

   # SSH key pair
   mkdir -p ~/.config/chezmoi/secrets/ssh-personal
   cp ~/.ssh/id_ed25519 ~/.config/chezmoi/secrets/ssh-personal/private
   cp ~/.ssh/id_ed25519.pub ~/.config/chezmoi/secrets/ssh-personal/public

   # GitHub PAT
   mkdir -p ~/.config/chezmoi/secrets/github-pat
   echo -n 'ghp_xxxxxxxxxxxx' > ~/.config/chezmoi/secrets/github-pat/password

   # Global secret file (e.g., AWS credentials)
   mkdir -p ~/.config/chezmoi/secrets/aws-credentials
   cp ~/.aws/credentials ~/.config/chezmoi/secrets/aws-credentials/credentials
   ```

3. Set restrictive permissions:

   ```bash
   chmod -R go-rwx ~/.config/chezmoi/secrets
   ```

   On Windows (PowerShell, no admin required):

   ```powershell
   $dir = "$env:USERPROFILE\.config\chezmoi\secrets"
   icacls $dir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null
   ```

4. Run `chezmoi apply` as normal.

### Security recommendations

- The local secrets directory contains **plaintext files**. Encryption
  is your responsibility.
- Consider placing secrets on an encrypted partition (LUKS, FileVault,
  BitLocker, VeraCrypt).
- Ensure `local_dir` is excluded from backups and version control.
- Add `secrets/` to your global gitignore if `local_dir` is under
  `~/.config/chezmoi/`.
- If a configured file is missing, `chezmoi apply` fails immediately
  with a clear error — no partial or empty secrets are deployed.

## Deploying user-global secret files

You can deploy secret files from the secret manager to arbitrary
home-relative paths. This is useful for credentials that live outside
project repositories, such as `~/.aws/credentials`,
`~/.docker/config.json`, `~/.npmrc`, or `~/.kube/config`.

Store each file as an **attachment** on a secret manager item. The
deployment script creates parent directories with restrictive
permissions and writes the file with mode `600` (Linux/macOS) or
user-only ACL (Windows).

### Configuring secret file deployment

Edit `~/.config/chezmoi/chezmoi.toml`:

```toml
[data.secret.files.aws-credentials]
item = "AWS Credentials"
target = ".aws/credentials"
attachment = "credentials"

[data.secret.files.docker-auth]
item = "Docker Registry Auth"
target = ".docker/config.json"
attachment = "config.json"

[data.secret.files.npmrc]
item = "npm Registry Token"
target = ".npmrc"
```

**Fields:**

| Field        | Required | Default              | Description                                  |
| ------------ | -------- | -------------------- | -------------------------------------------- |
| `item`       | yes      |                      | Secret manager item name                     |
| `target`     | yes      |                      | Home-relative path (forward slashes only)    |
| `attachment` | no       | basename of `target` | Attachment name override in secret manager   |

### Path requirements

- Paths must be **relative** to `$HOME` (no leading `/`)
- Paths must use **forward slashes** (`/`) — even on Windows
- Paths must **not** contain `..` (path traversal is rejected)
- Parent directories are created automatically with mode `700`

### Storing files in Bitwarden

1. Create any item type (Secure Note recommended) in Bitwarden
2. Name it descriptively (e.g., `AWS Credentials`)
3. Attach the credentials file (e.g., `credentials`)
4. Use the attachment filename as `attachment` in the config

### Security notes

- Files are deployed with **mode 600** (Linux/macOS) or **user-only
  ACL** (Windows) — no admin elevation required
- Parent directories are created with **mode 700** / user-only ACL
- Secret content is embedded in the rendered chezmoi script at
  `chezmoi apply` time (same as .env deployment). The script files
  themselves are not persisted to disk after execution
- The feature is designed for **text-based** secret files. Binary
  files are not supported
- When `secret.manager` is `"none"`, the script skips entirely —
  no files are created or overwritten

### Re-deploying secret files

The `run_onchange_after` script re-runs when the **rendered script
content** changes (i.e., when secret data or config changes). To
force re-deployment:

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

## Deploying .env files to projects

You can deploy `.env` files from the secret manager into cloned
project directories. Store each `.env` file as an **attachment** on
a secret manager item. The deployment script runs after ghq clone
and writes the file with restrictive permissions (mode `600`).

### Storing .env files in Bitwarden

1. Create a **Secure Note** (or any item type) in Bitwarden
2. Name it descriptively (e.g., `MyApp - .env`)
3. Add the `.env` file as an **attachment**
4. The attachment filename should match the target (e.g., `.env`)

### Configuring .env deployment

Edit `~/.config/chezmoi/chezmoi.toml`:

```toml
# Label is user-defined; repo is the ghq-style path
[data.env.deploy.myapp-env]
repo = "github.com/your-user/myapp"
item = "MyApp - .env"

# Deploy a second .env to the same project
[data.env.deploy.myapp-env-local]
repo = "github.com/your-user/myapp"
item = "MyApp - .env.local"
filename = ".env.local"

# Deploy to a subdirectory
[data.env.deploy.myapp-api-env]
repo = "github.com/your-user/myapp"
item = "MyApp API - .env"
subpath = "packages/api"
```

**Fields:**

| Field        | Required | Default            | Description                                           |
| ------------ | -------- | ------------------ | ----------------------------------------------------- |
| `repo`       | yes      |                    | ghq-style repo path (e.g., `github.com/user/project`) |
| `item`       | yes      |                    | Secret manager item name                              |
| `filename`   | no       | `.env`             | Target filename                                       |
| `subpath`    | no       | *(root)*           | Subdirectory within the repo                          |
| `attachment` | no       | same as `filename` | Attachment name override in the secret manager        |

### Security notes

- Files are deployed with **mode 600** (Linux/macOS) or **user-only
  ACL** (Windows) — no admin elevation required
- The script warns if `.gitignore` in the target project does not
  list the target filename; verify before committing
- Secret content is never logged; only filenames and status are shown
- The script is a `run_onchange_after` template — it re-runs
  automatically when secret content or configuration changes

### Re-deploying .env files

The `run_onchange_after` script re-runs when the **rendered script
content** changes (i.e., when secret data or config changes). To
force re-deployment:

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

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

## Troubleshooting deployment status

After every `chezmoi apply`, a one-line digest summarizes the state of
all configured deploy targets:

```text
secret-status: OK 11 / DRIFT 1 / WARN 1 / MISSING 0 / UNKNOWN 1 (total 14)
```

For a full breakdown, run the standalone command at any time:

```bash
secret-status            # colored table (Linux/macOS)
secret-status --summary  # one-line digest only
secret-status --json     # machine-readable JSON
secret-status --no-color # plain text
```

```powershell
secret-status.ps1            # colored table (Windows)
secret-status.ps1 -Summary
secret-status.ps1 -Json
secret-status.ps1 -NoColor
```

Both commands read a manifest rendered by `chezmoi apply` at
`~/.config/chezmoi/secret-deploy-manifest.json` (mode 600), so they
work even when `mise` / `ghq` are not on `PATH`.

### Status taxonomy

| Status    | Meaning                                                     |
| --------- | ----------------------------------------------------------- |
| `OK`      | Target is present, has the expected mode/ACL, (for GPG) the fingerprint is in the keyring, and (when a deploy fingerprint is recorded) the file content still matches what was last deployed. |
| `DRIFT`   | Target is present with the correct mode but the SHA-256 of its content no longer matches the fingerprint recorded by the last deploy. Typically caused by a manual edit or by answering `s` (skip) at a chezmoi `has changed since chezmoi last wrote it` prompt. Re-deploy with `chezmoi apply --force` to overwrite, or accept the local edit by re-recording the state (delete the entry from `~/.config/chezmoi/secret-deploy-state.json` and re-run `chezmoi apply`). |
| `WARN`    | Target is present but with the wrong permissions, or `.gitignore` is missing the env filename, or the SSH host alias is missing the expected `IdentityFile`. Takes precedence over `DRIFT`. |
| `MISSING` | Target is configured but not deployed. Re-run `chezmoi apply` after fixing the secret-manager entry. |
| `UNKNOWN` | The check could not run — e.g., `gpg`/`ssh` are not on `PATH`, the manifest lacks an expected fingerprint, or `ghq root` could not be resolved. |

### Listing DRIFT/MISSING/UNKNOWN details

The colored table view shows the per-row note for every non-`OK`
row, but it can be hard to spot a single offender among dozens of
green rows. Filter the JSON output with `jq` (bash) or
`Where-Object` (pwsh) to list only the rows that need attention:

```bash
secret-status --json | jq '.rows[] | select(.status != "OK")'
secret-status --json | jq -r '.rows[] | select(.status=="DRIFT") | "\(.target)\t\(.note)"'
```

```powershell
secret-status.ps1 -Json | ConvertFrom-Json |
  Select-Object -ExpandProperty rows |
  Where-Object status -ne 'OK' |
  Format-Table status, label, target, note
```

The deploy-state file at
`~/.config/chezmoi/secret-deploy-state.json` (mode 600) records the
SHA-256 fingerprint, mode, and timestamp of every secret the deploy
scripts wrote. It is rewritten on every successful deploy and is
safe to delete at any time — the next `chezmoi apply` re-seeds it,
and `secret-status` simply skips DRIFT detection for paths that
have no recorded fingerprint.

### Exit codes

- `0` — every row is `OK`.
- `1` — at least one `DRIFT`, `WARN`, `MISSING`, or `UNKNOWN` row.
- `2` — the manifest is missing or unreadable. Re-run `chezmoi apply`.

### Known limitations

- **Freshness against the secret manager is not checked.**
  `DRIFT` tells you the file changed _after_ deploy, but it cannot
  tell you whether the Bitwarden / 1Password / KeePassXC entry has
  been rotated upstream. Re-run `chezmoi apply` to refresh content
  from the manager.
- **SSH keys are skip-if-exists.** The deploy script does not overwrite
  `~/.ssh/<filename>` when it already exists. If you rotate a key in
  the secret manager, delete the local file before running
  `chezmoi apply`.
- **Windows mode check uses ACLs.** `WARN: ACL allows non-owners`
  appears when an ACE other than the current user, `Administrators`,
  or `SYSTEM` has access. Other heuristics (group, integrity level)
  are not inspected.
