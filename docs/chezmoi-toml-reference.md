---
type: reference
title: chezmoi.toml Configuration Reference
description: Documents every chezmoi.toml configuration path, with each field's type, default, and a link to its deployment guide.
---

# chezmoi.toml Configuration Reference

This page is the complete field-by-field reference for
`~/.config/chezmoi/chezmoi.toml`, the file `.chezmoi.toml.tmpl` renders
from prompts plus any `[data.*]` overrides you add by hand. It documents
**shape only** — every table, field, type, default, and required status —
not deployment steps or rationale. Each section links to the guide that
covers *how* and *why* to use that feature; this page exists so you can
see every available field in one place before reading the guides for
detail.

Section keys written as `<label>` (e.g. `personal`, `work`) are
user-chosen identifiers; see
[Secret manager setup](secret-manager-setup.md)'s "Naming conventions"
for the cross-section consistency convention this repository uses.

## Git identity (`data.git`, `data.git.profiles.<label>`)

`[data.git]` is the **primary** identity, applied to every repository
unless a profile overrides it:

| Field            | Type   | Required | Default      | Purpose                                                                                                                                                                                   |
| ---------------- | ------ | -------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`           | string | yes      | —            | Git user name used for commits.                                                                                                                                                           |
| `email`          | string | yes      | —            | Git email address used for commits.                                                                                                                                                       |
| `signingkey`     | string | no       | `""`         | GPG signing key fingerprint; an empty string disables GPG signing.                                                                                                                        |
| `signing_format` | string | no       | `""` (unset) | Forces the **primary** signing backend to `"gpg"` or `"ssh"`; `"ssh"` is validated at render time and requires exactly one `data.secret.ssh.keys.*` entry with `signing_fallback = true`. |

`[data.git.profiles.<label>]` entries are **directory-scoped overrides**
for repositories under a given path:

| Field            | Type   | Required | Default      | Purpose                                                                                                                                                                                        |
| ---------------- | ------ | -------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`           | string | yes      | —            | Display name used for commits under `gitdir`.                                                                                                                                                  |
| `email`          | string | yes      | —            | Commit email used under `gitdir`.                                                                                                                                                              |
| `signingkey`     | string | no       | `""`         | GPG fingerprint for this profile; an empty string disables GPG signing for it.                                                                                                                 |
| `gitdir`         | string | yes      | —            | Repository path prefix (must end with `/`) that activates this profile.                                                                                                                        |
| `signing_format` | string | no       | `""` (unset) | Forces this profile's primary signing backend; `"ssh"` is validated at render time and requires exactly one `data.secret.ssh.keys.*` entry listing this profile's label in `signing_profiles`. |
| `sshhost`        | string | no       | `""`         | Optional SSH host alias; when set, `ghq` clones under `gitdir` route through it via `url.insteadOf`.                                                                                           |

See [Secret manager setup](secret-manager-setup.md) for the full identity
model (how `data.git.*` connects to `data.secret.gpg.*` and
`data.secret.ssh.*`) and
[Using ghq with multiple accounts](ghq-workflow.md) for `sshhost` routing.

## Secret manager (`data.secret`)

| Field       | Type   | Required | Default                       | Purpose                                                                      |
| ----------- | ------ | -------- | ----------------------------- | ---------------------------------------------------------------------------- |
| `manager`   | string | yes      | —                             | Secret backend: `bitwarden`, `onepassword`, `keepassxc`, `local`, or `none`. |
| `local_dir` | string | no       | `"~/.config/chezmoi/secrets"` | Local secrets directory; only used when `manager = "local"`.                 |

See [Secret manager setup](secret-manager-setup.md).

## GPG keys (`data.secret.gpg.<label>`)

| Field  | Type   | Required | Default | Purpose                                                          |
| ------ | ------ | -------- | ------- | ---------------------------------------------------------------- |
| `item` | string | yes      | —       | Secret manager item name holding the GPG key attachments/fields. |

See [Secret manager setup](secret-manager-setup.md).

## SSH keys (`data.secret.ssh.keys.<label>`)

| Field              | Type            | Required | Default | Purpose                                                                                                                   |
| ------------------ | --------------- | -------- | ------- | ------------------------------------------------------------------------------------------------------------------------- |
| `item`             | string          | yes      | —       | Secret manager item (SSH Key type) holding the key pair.                                                                  |
| `filename`         | string          | yes      | —       | Target filename written under `~/.ssh/`.                                                                                  |
| `signing_fallback` | boolean         | no       | `false` | Registers this key for the `commit-ssh`/`tag-ssh`/`rebase-ssh` **global** fallback aliases; at most one key may set this. |
| `signing_profiles` | `array<string>` | no       | `[]`    | Profile labels (matching `data.git.profiles.*`) that also get scope-local fallback aliases.                               |

See [Secret manager setup](secret-manager-setup.md).

## SSH hosts (`data.secret.ssh.hosts.<label>`)

| Field      | Type    | Required | Default                                 | Purpose                                                         |
| ---------- | ------- | -------- | --------------------------------------- | --------------------------------------------------------------- |
| `hostname` | string  | yes      | —                                       | Remote host address.                                            |
| `user`     | string  | no       | `"git"`                                 | SSH user.                                                       |
| `identity` | string  | yes      | —                                       | Filename of an SSH key declared under `data.secret.ssh.keys.*`. |
| `port`     | integer | no       | `0` (omitted; SSH default `22` applies) | Non-default SSH port.                                           |

Quote the `<label>` (e.g. `"github.com"`) when it contains dots, so TOML
does not parse it as nested tables. See
[Secret manager setup](secret-manager-setup.md) and
[Using ghq with multiple accounts](ghq-workflow.md).

## Secret files (`data.secret.files.<label>`)

| Field        | Type   | Required | Default              | Purpose                                                                  |
| ------------ | ------ | -------- | -------------------- | ------------------------------------------------------------------------ |
| `item`       | string | yes      | —                    | Secret manager item holding the file attachment.                         |
| `target`     | string | yes      | —                    | Home-relative destination path (forward slashes; must not contain `..`). |
| `attachment` | string | no       | basename of `target` | Attachment name override in the secret manager.                          |

See [Secret manager setup](secret-manager-setup.md).

## Bulk repo cloning (`data.ghq.clone.<label>`)

| Field        | Type    | Required | Default        | Purpose                                          |
| ------------ | ------- | -------- | -------------- | ------------------------------------------------ |
| `owner`      | string  | yes      | —              | GitHub/GitLab user or org to bulk-clone.         |
| `token_item` | string  | yes      | —              | Secret manager item holding the PAT.             |
| `hostname`   | string  | no       | `"github.com"` | Git host.                                        |
| `ssh`        | boolean | no       | `true`         | Clone over SSH; `false` uses HTTPS instead.      |
| `mise_trust` | boolean | no       | `false`        | Auto-trust `mise` configs found in cloned repos. |

See [Using ghq with multiple accounts](ghq-workflow.md).

## WinGet User PATH packages (`data.wingetUserPath.packages.<label>`)

This repository ships default entries for `mise`, `chezmoi`, `ffmpeg`,
`sqlite`, and `ngrok`, merged under any user-declared entries of the same
key (field-level merge, so overriding just `enabled` does not require
restating `id`/`bin`).

| Field     | Type    | Required | Default | Purpose                                                                                          |
| --------- | ------- | -------- | ------- | ------------------------------------------------------------------------------------------------ |
| `id`      | string  | yes      | —       | WinGet package id (`Packages\<id>_*` prefix).                                                    |
| `bin`     | string  | no       | `""`    | Subpath within the package directory to add to PATH; may contain one `*` version-suffix segment. |
| `enabled` | boolean | no       | `true`  | Set `false` to disable an inherited (repo-default or previously-declared) entry of this key.     |

See
[Declaring WinGet package directories in the User PATH](winget-user-path.md).

## SSH server hardening (`data.ssh.server`)

| Field                          | Type    | Required | Default               | Purpose                                                                                                         |
| ------------------------------ | ------- | -------- | --------------------- | --------------------------------------------------------------------------------------------------------------- |
| `clientAliveInterval`          | integer | no       | `300`                 | Seconds between SSH keepalive probes.                                                                           |
| `clientAliveCountMax`          | integer | no       | `5`                   | Missed probes tolerated before disconnect.                                                                      |
| `defaultShell`                 | string  | no       | `""` (absent = no-op) | Windows sshd default shell: `"cmd"`, `"legacy-powershell"`, or `"modern-powershell"`.                           |
| `defaultShellFallbackToLegacy` | boolean | no       | `false`               | When `defaultShell = "modern-powershell"`, fall back to `powershell.exe` if `pwsh.exe` is missing/unresolvable. |

See [Deploying sshd_config](sshd-config-setup.md).

## systemd-tmpfiles cleanup age (`data.tmpfiles.age`)

| Field | Type   | Required | Default | Purpose                                                                           |
| ----- | ------ | -------- | ------- | --------------------------------------------------------------------------------- |
| `age` | string | no       | `"10d"` | systemd-tmpfiles time-span for `/tmp` cleanup (Linux with systemd-tmpfiles only). |

See
[Configuring the systemd-tmpfiles /tmp cleanup age](tmpfiles-cleanup-setup.md).

## mkcert local CA (`data.mkcert.install`)

| Field     | Type    | Required | Default | Purpose                                                   |
| --------- | ------- | -------- | ------- | --------------------------------------------------------- |
| `install` | boolean | no       | `false` | Runs `mkcert -install` on Windows during `chezmoi apply`. |

See [Opt-in local development CA setup (mkcert)](mkcert-local-ca.md).

## .env deployment (`data.env.deploy.<label>`)

| Field        | Type   | Required | Default            | Purpose                                               |
| ------------ | ------ | -------- | ------------------ | ----------------------------------------------------- |
| `repo`       | string | yes      | —                  | ghq-style repo path (e.g. `github.com/user/project`). |
| `item`       | string | yes      | —                  | Secret manager item holding the `.env` attachment.    |
| `filename`   | string | no       | `".env"`           | Target filename written into the repo.                |
| `subpath`    | string | no       | `""` (repo root)   | Subdirectory within the repo.                         |
| `attachment` | string | no       | same as `filename` | Attachment name override in the secret manager.       |

See [Secret manager setup](secret-manager-setup.md).

## Zellij Web (`data.zellij`, `data.zellij.web`)

`[data.zellij]`:

| Field           | Type    | Required | Default | Purpose                                                                                                      |
| --------------- | ------- | -------- | ------- | ------------------------------------------------------------------------------------------------------------ |
| `simplified_ui` | boolean | no       | `false` | Replaces Nerd Font glyphs with ASCII in the shared keybinding/plugin config, for clients without Nerd Fonts. |

`[data.zellij.web]`:

| Field                          | Type    | Required | Default                                               | Purpose                                                                                    |
| ------------------------------ | ------- | -------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `server`                       | boolean | no       | `true`                                                | Enables the built-in Zellij web server.                                                    |
| `sharing`                      | string  | no       | `"on"`                                                | Session-sharing policy passed through to `web_sharing`.                                    |
| `bind`                         | string  | no       | `"127.0.0.1"`                                         | Address the local web server listens on.                                                   |
| `port`                         | integer | no       | `8082`                                                | Port the local web server listens on.                                                      |
| `cert`                         | string  | no       | `""` (required off localhost)                         | TLS certificate file path; only required when `bind` is not on `127.0.0.0/8`.              |
| `key`                          | string  | no       | `""` (required off localhost)                         | TLS key file path; only required when `bind` is not on `127.0.0.0/8`.                      |
| `base_url`                     | string  | no       | `""`                                                  | Optional reverse-proxy subpath.                                                            |
| `enforce_https_on_localhost`   | boolean | no       | `false`                                               | Enforce HTTPS even when bound to `127.0.0.0/8` (always enforced off-localhost).            |
| `client_font`                  | string  | no       | `"'HackGen Console NF', 'Hack Nerd Font', monospace"` | Web client terminal font stack.                                                            |
| `client_cursor_blink`          | boolean | no       | `true`                                                | Web client cursor blink.                                                                   |
| `client_cursor_style`          | string  | no       | `"bar"`                                               | Web client cursor style: `"block"`, `"bar"`, or `"underline"`.                             |
| `client_cursor_inactive_style` | string  | no       | `"outline"`                                           | Web client cursor style while inactive: `"outline"`, `"block"`, `"bar"`, or `"underline"`. |

`[data.zellij.web.tailscale]`:

| Field        | Type    | Required | Default | Purpose                                                                                                                                                       |
| ------------ | ------- | -------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `enabled`    | boolean | no       | `false` | Publish the web server through `tailscale serve`. Requires `data.zellij.web.bind` to remain `"127.0.0.1"` — the `ensure-zellij-web` wrapper throws otherwise. |
| `https_port` | integer | no       | `443`   | Tailnet HTTPS port used for the published route.                                                                                                              |

`[data.zellij.web.windows]`, `[data.zellij.web.linux]`, and
`[data.zellij.web.macos]` each carry a single field:

| Field       | Type   | Required | Default      | Purpose                                                                                                                                                    |
| ----------- | ------ | -------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `autostart` | string | no       | `"disabled"` | Windows: `"onlogon"` registers a per-user Scheduled Task. Linux: `"systemd-user"` installs a user service. macOS: `"launchagent"` registers a LaunchAgent. |

See the [Zellij Web](../README.md#zellij-web) section of the README.

## Complete example

The example below combines every optional section above at once. No
single machine needs all of it simultaneously (for example, only one of
`data.zellij.web.windows` / `.linux` / `.macos` applies per OS); this is
a shape reference, not a recommended starting configuration.

```toml
# Primary git identity
[data.git]
name = "Alice"
email = "alice@personal.dev"
signingkey = "AAAA1111BBBB2222"  # GPG fingerprint; empty string disables signing
# signing_format = "ssh"  # optional; forces "gpg" or "ssh" as the primary backend

# Work identity — overrides in ~/work/ repositories
[data.git.profiles.work]
name = "Alice Corporate"
email = "alice@example.com"
signingkey = "CCCC3333DDDD4444"
gitdir = "~/work/"
sshhost = "github-work"  # routes ghq clones under gitdir via this SSH alias

# OSS identity — overrides in ~/oss/ repositories
[data.git.profiles.oss]
name = "alice-dev"
email = "alice-dev@users.noreply.github.com"
signingkey = "EEEE5555FFFF6666"
gitdir = "~/oss/"

[data.secret]
manager = "bitwarden"
# local_dir = "~/.config/chezmoi/secrets"  # only used when manager = "local"

[data.secret.gpg.personal]
item = "GPG Key - Personal"

[data.secret.gpg.work]
item = "GPG Key - Work"

[data.secret.ssh.keys.personal]
item = "SSH Key - Personal"
filename = "id_ed25519_personal"

[data.secret.ssh.keys.work]
item = "SSH Key - Work"
filename = "id_ed25519_work"
signing_fallback = true      # registers the commit-ssh/tag-ssh/rebase-ssh aliases
signing_profiles = ["work"]  # also scopes the aliases to the work profile

[data.secret.ssh.hosts.github-personal]
hostname = "github.com"
user = "git"
identity = "id_ed25519_personal"

[data.secret.ssh.hosts.github-work]
hostname = "github.com"
user = "git"
identity = "id_ed25519_work"

[data.secret.ssh.hosts.gitlab-work]
hostname = "gitlab.example.com"
user = "git"
identity = "id_ed25519_work"
port = 2222

[data.secret.files.aws-credentials]
item = "AWS Credentials"
target = ".aws/credentials"
attachment = "credentials"

[data.ghq.clone.personal]
owner = "your-github-username"
token_item = "GitHub PAT"
hostname = "github.com"
ssh = true
mise_trust = false

[data.wingetUserPath.packages.mise]
id = "jdx.mise"
bin = "mise/bin"

[data.wingetUserPath.packages.ffmpeg]
id = "Gyan.FFmpeg"
bin = "ffmpeg-*-full_build/bin"
enabled = true

[data.ssh.server]
clientAliveInterval = 300
clientAliveCountMax = 5
defaultShell = "modern-powershell"
defaultShellFallbackToLegacy = false

[data.tmpfiles]
age = "2d"

[data.mkcert]
install = true

[data.env.deploy.myapp-env]
repo = "github.com/your-user/myapp"
item = "MyApp - .env"
filename = ".env"
subpath = ""
attachment = ".env"

[data.zellij]
simplified_ui = false

[data.zellij.web]
server = true
sharing = "on"
bind = "127.0.0.1"
port = 8082
# cert = ""  # required when bind is not on 127.0.0.0/8
# key = ""   # required when bind is not on 127.0.0.0/8
base_url = ""
enforce_https_on_localhost = false
client_font = "'HackGen Console NF', 'Hack Nerd Font', monospace"
client_cursor_blink = true
client_cursor_style = "bar"
client_cursor_inactive_style = "outline"

[data.zellij.web.tailscale]
enabled = true
https_port = 443

[data.zellij.web.windows]
autostart = "onlogon"

[data.zellij.web.linux]
autostart = "systemd-user"

[data.zellij.web.macos]
autostart = "launchagent"
```
