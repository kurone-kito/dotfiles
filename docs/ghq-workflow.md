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
