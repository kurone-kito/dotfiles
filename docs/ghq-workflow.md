# Using ghq with multiple accounts

This guide explains how to configure ghq so that each GitHub (or
GitLab) account automatically uses the correct SSH key, commit
identity, and GPG signing key.

## How the chain works

```
ghq get github.com/acme-corp/repo
        │
        ▼
  url.insteadOf          ← rewrites URL to SSH alias
  git@github-work:acme-corp/repo.git
        │
        ▼
  ~/.ssh/config           ← maps alias to hostname + key
  Host github-work
    HostName github.com
    IdentityFile ~/.ssh/id_ed25519_work
        │
        ▼
  clone lands in ~/ghq/github.com/acme-corp/repo/
        │
        ▼
  includeIf gitdir:       ← loads identity profile
  ~/.config/git/profiles/work
    user.name, user.email, user.signingkey
```

Each layer is configured in `chezmoi.toml` and deployed by
`chezmoi apply`. The key insight is that `url.insteadOf` bridges
the gap between the plain URL that ghq generates and the SSH host
alias that selects the right key.

## Prerequisites

- [ghq](https://github.com/x-motemen/ghq) installed
- Secret manager configured (see [secret-manager-setup.md])
- SSH keys and GPG keys deployed via `chezmoi apply`

## Configuration

### Step 1: Define identities

Edit `~/.config/chezmoi/chezmoi.toml`:

```toml
# Primary identity (used globally)
[data.git]
name = "Alice"
email = "alice@personal.dev"
signingkey = "AAAA1111BBBB2222"

# Work identity — overrides in ~/ghq/github.com/acme-corp/
[data.git.profiles.work]
name = "Alice Corporate"
email = "alice@acme.com"
signingkey = "CCCC3333DDDD4444"
gitdir = "~/ghq/github.com/acme-corp/"
sshhost = "github-work"
```

### Step 2: Configure SSH hosts

```toml
[data.secret.ssh.hosts.github-work]
hostname = "github.com"
user = "git"
identity = "id_ed25519_work"
```

### Step 3: Apply

```bash
chezmoi apply
```

This generates:

**`~/.gitconfig`** (excerpt):

```ini
[includeIf "gitdir:~/ghq/github.com/acme-corp/"]
  path = ~/.config/git/profiles/work
[url "git@github-work:acme-corp/"]
  insteadOf = https://github.com/acme-corp/
  insteadOf = git@github.com:acme-corp/
```

**`~/.ssh/config`** (excerpt):

```text
Host github-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_work
```

**`~/.config/git/profiles/work`**:

```ini
[user]
  email = "alice@acme.com"
  name = "Alice Corporate"
  signingkey = CCCC3333DDDD4444
[commit]
  gpgsign = true
```

### Step 4: Clone with ghq

```bash
# Just use the plain URL — insteadOf handles the rest
ghq get github.com/acme-corp/repo

# Verify identity
cd ~/ghq/github.com/acme-corp/repo
git config user.name    # → "Alice Corporate"
git config user.email   # → "alice@acme.com"

# Verify SSH key
ssh -T github-work      # → "Hi alice-work! You've successfully..."
```

## Complete two-account example

```toml
# ── Primary (personal) ──
[data.git]
name = "Alice"
email = "alice@personal.dev"
signingkey = "AAAA1111BBBB2222"

# ── Work ──
[data.git.profiles.work]
name = "Alice Corporate"
email = "alice@acme.com"
signingkey = "CCCC3333DDDD4444"
gitdir = "~/ghq/github.com/acme-corp/"
sshhost = "github-work"

# ── Secret manager ──
[data.secret]
manager = "bitwarden"

# GPG keys
[data.secret.gpg.personal]
item = "GPG Key - Personal"

[data.secret.gpg.work]
item = "GPG Key - Work"

# SSH keys
[data.secret.ssh.keys.personal]
item = "SSH Key - Personal"
filename = "id_ed25519_personal"

[data.secret.ssh.keys.work]
item = "SSH Key - Work"
filename = "id_ed25519_work"

# SSH hosts
[data.secret.ssh.hosts."github.com"]
hostname = "github.com"
user = "git"
identity = "id_ed25519_personal"

[data.secret.ssh.hosts.github-work]
hostname = "github.com"
user = "git"
identity = "id_ed25519_work"
```

In this setup:

| Account  | ghq get                             | SSH key                                       | Git identity           |
| -------- | ----------------------------------- | --------------------------------------------- | ---------------------- |
| Personal | `ghq get github.com/alice/repo`     | `id_ed25519_personal` (via `github.com` host) | Primary (`data.git.*`) |
| Work     | `ghq get github.com/acme-corp/repo` | `id_ed25519_work` (via `github-work` alias)   | Work profile           |

## How `sshhost` derives `url.insteadOf`

When a profile has `sshhost` set, the gitconfig template:

1. Looks up the SSH host's `hostname` (e.g., `github.com`)
2. Finds that hostname in the profile's `gitdir`
3. Extracts the path after the hostname as the org prefix
4. Generates `insteadOf` rules for both HTTPS and SSH URLs

```
gitdir  = "~/ghq/github.com/acme-corp/"
                  └─────┬─────┘└───┬───┘
                    hostname    org path

sshhost = "github-work"  →  hostname = "github.com"

Generated:
  [url "git@github-work:acme-corp/"]
    insteadOf = https://github.com/acme-corp/
    insteadOf = git@github.com:acme-corp/
```

If the hostname is not found in `gitdir`, no `insteadOf` rules
are generated (the profile still works for `includeIf`).

## Bulk clone repositories

You can configure chezmoi to automatically clone all non-archived,
non-fork repositories for specific GitHub users or organizations.
This runs as a `run_onchange_after` script during `chezmoi apply`.

### Prerequisites

- A GitHub Personal Access Token (PAT) with `repo` scope
- The PAT stored in your secret manager

### Configuration

Add the following to `~/.config/chezmoi/chezmoi.toml`:

```toml
[data.ghq.clone."personal"]
owner = "alice"
token_item = "GitHub PAT - Personal"
# hostname = "github.com"  # optional; defaults to github.com
# ssh      = true          # optional; false to use HTTPS instead of SSH
```

The table key (`"personal"`, `"work"`, etc.) is an arbitrary unique
label — it only appears in log messages and does not affect behaviour.

| Field        | Required | Description                                                    |
| ------------ | -------- | -------------------------------------------------------------- |
| `owner`      | Yes      | GitHub username or organization                                |
| `token_item` | Yes      | Secret manager item containing the PAT (stored as password)    |
| `hostname`   | No       | GitHub host (default: `github.com`; set for GHE instances)     |
| `ssh`        | No       | Clone via SSH (default: `true`); set `false` for HTTPS cloning |

### How it works

1. Retrieves the PAT from your secret manager via `get-secret`
2. Uses `gh repo list <owner> --no-archived --source` to enumerate
   visible repositories (including private ones)
3. For each repository:
   - **Skip** if the target directory already has `.git` (already cloned)
   - **Remove and re-clone** if the directory exists without `.git`
   - **Clone** via `ghq get` (respects `url.insteadOf` routing)

### Creating the PAT

1. Go to **GitHub → Settings → Developer settings → Personal access
   tokens → Tokens (classic)**
2. Create a token with `repo` scope (full access to private repos)
3. Store it in your secret manager:
   - **Bitwarden**: Create a Login item, paste the token as the
     password
   - **1Password**: Create a Login item with the token as password
   - **KeePassXC**: Create an entry with the token as password

### Multiple accounts

```toml
[data.ghq.clone."personal"]
owner = "alice"
token_item = "GitHub PAT - Personal"

[data.ghq.clone."work"]
owner = "acme-corp"
token_item = "GitHub PAT - Work"
```

Each account uses its own PAT, so this works even for multiple
accounts on the same GitHub host. Combined with `sshhost` profiles,
cloned repositories automatically use the correct SSH key and
git identity.

### SSH vs HTTPS cloning

By default, repositories are cloned over SSH (`ghq get -p`). This
works well with the `url.insteadOf` and `sshhost` configuration
described above.

To clone via HTTPS instead (for example, on a GHE instance that
requires HTTPS-only access), set `ssh = false` on the clone target:

```toml
[data.ghq.clone."ghe"]
owner = "internal-team"
token_item = "GHE PAT"
hostname = "github.example.com"
ssh = false
```

When `ssh` is `false`, `ghq get` runs without the `-p` flag,
using the HTTPS URL that `gh` provides. The credential helper
(configured via `GIT_CONFIG_*` environment variables in the script)
authenticates the HTTPS connection automatically.

### Execution order

The bulk clone script (`60-clone-ghq-repos`) runs after the mise
tool installation script (`50-install-mise-tools`), which ensures
that `ghq` and `gh` are available via mise before cloning begins.

### Standalone script

The clone logic is available as a standalone script at
`~/.local/bin/ghq-clone-user` (POSIX) /
`~/.local/bin/ghq-clone-user.ps1` (PowerShell).
You can re-run it outside `chezmoi apply` at any time:

```bash
# Clone all repos for a user via SSH (default)
ghq-clone-user alice

# Clone via HTTPS
ghq-clone-user alice --https

# Clone from a GitHub Enterprise instance
ghq-clone-user internal-team --hostname github.example.com

# Limit the number of repos listed
ghq-clone-user alice --limit 500
```

PowerShell equivalent:

```powershell
ghq-clone-user.ps1 -Owner alice
ghq-clone-user.ps1 -Owner alice -Https
ghq-clone-user.ps1 -Owner internal-team -Hostname github.example.com
```

**Prerequisites:** `gh` and `ghq` in PATH (or via mise shims), plus
`gh auth login` or `GH_TOKEN` for authentication.

The chezmoi `run_onchange_after` templates handle secret extraction
and environment setup, then delegate to these standalone scripts.

## Troubleshooting

### Wrong identity on commits

```bash
cd ~/ghq/github.com/acme-corp/repo
git config user.email
```

If it shows the primary email instead of the work email:

1. Check that `gitdir` ends with `/` (required by git)
2. Verify the path matches: `pwd` should be under the `gitdir`
3. Run `chezmoi apply` to regenerate profiles

### Wrong SSH key used

```bash
# Test which key is used
ssh -vT github-work 2>&1 | grep "Offering public key"
```

If the wrong key is offered:

1. Check `~/.ssh/config` for the correct `Host` entry
2. Verify the key file exists: `ls -la ~/.ssh/id_ed25519_work*`
3. Check `insteadOf` is active: `git config --get-urlmatch url.insteadOf https://github.com/acme-corp/`

### ghq clones to unexpected directory

`url.insteadOf` only affects how git connects — it does not change
the directory structure. ghq always uses the **original** URL to
determine the clone path:

```bash
ghq get github.com/acme-corp/repo
# Always clones to: ~/ghq/github.com/acme-corp/repo
# Even though git internally connects via github-work alias
```

This is the desired behavior: the directory structure stays
consistent regardless of which SSH key is used.

[secret-manager-setup.md]: secret-manager-setup.md
