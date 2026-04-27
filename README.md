# 🔴 My dotfiles

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Linting](https://github.com/kurone-kito/dotfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/kurone-kito/dotfiles/actions/workflows/lint.yml)
[![CodeRabbit](https://img.shields.io/badge/review-CodeRabbit-green?logo=coderabbit)](https://www.coderabbit.ai/)

A collection of configuration files that we use.

## What's included

### Shell environments

- [bash](https://www.gnu.org/software/bash/) — interactive options,
  history, globbing
- [PowerShell](https://learn.microsoft.com/powershell/) — PSReadLine,
  profile shims for PS5/PS7/VS Code
- [zsh](https://www.zsh.org/) — completion, keybindings, XDG-compliant
  `ZDOTDIR`

### Shell plugins & prompt

- [sheldon](https://sheldon.cli.rs/) — zsh plugin manager
- [starship](https://starship.rs/) — cross-shell prompt theme

### Development tools

- [fzf](https://junegunn.github.io/fzf/) — fuzzy finder with key bindings
- [Homebrew](https://brew.sh/) — package manager PATH setup
- [mise](https://mise.jdx.dev/) — polyglot runtime manager
- [thefuck](https://github.com/nvbn/thefuck) — command correction
- Python venv — auto-activation helper

### Git

- [Git](https://git-scm.com/) — aliases, delta, LFS, GPG signing,
  multi-profile

### Editors & terminal

- [GNU Readline](https://tiswww.cwru.edu/php/chet/readline/rltop.html) —
input line editing
- [psmux](https://github.com/psmux/psmux) — Windows-native tmux-compatible
  multiplexer
- [tmux](https://github.com/tmux/tmux) — terminal multiplexer
- [Vim](https://www.vim.org/) — editor configuration

### Network tools

- [curl](https://curl.se/) — transfer defaults
- [Wget](https://www.gnu.org/software/wget/) — download defaults

### Security

- [GnuPG](https://gnupg.org/) — agent and pinentry configuration
- [OpenSSH](https://www.openssh.com/) — host and identity configuration

### Containers

- [Docker](https://www.docker.com/) — daemon settings

### Productivity (via mise)

- [ghq](https://github.com/x-motemen/ghq) — remote repository management
- [GitHub CLI](https://cli.github.com/) — GitHub from the terminal
- [gwq](https://github.com/d-kuro/gwq) — Git worktree manager
- [Taskwarrior](https://taskwarrior.org/) — task management

### AI coding assistants (via mise)

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli/)
- [OpenAI Codex CLI](https://github.com/openai/codex)

## Requirements

- [chezmoi](https://www.chezmoi.io/)
- [git](https://git-scm.com/)

Platform-specific runtime for profile generation scripts:

- **Windows**: [PowerShell 7+ (`pwsh`)](https://learn.microsoft.com/powershell/)
- **Linux/macOS/WSL**: `bash`

## Quick start

Initialize from this repository and apply once:

```bash
chezmoi init kurone-kito/dotfiles --apply
```

During init, chezmoi generates `~/.config/chezmoi/chezmoi.toml` from
`.chezmoi.toml.tmpl` and prompts for:

- `git.name`
- `git.email`
- `git.signingkey` (optional, can be empty)

After initialization, apply updates with:

```bash
chezmoi apply
```

### Windows note for mise

This repository owns the PowerShell profile through generated loader
shims. On Windows, `chezmoi apply` rewrites the standard profile files
to load `~/.config/powershell/profile.ps1`, so installer-added lines in
those files are replaced by design.

For `mise`, use a Windows install path that is already supported by this
repository before the first apply. `WinGet\Links` may be missing even
when `jdx.mise` is installed, so this repo also falls back to the actual
package bin directory:

- `%LOCALAPPDATA%\Microsoft\WinGet\Links`
- `%LOCALAPPDATA%\Microsoft\WinGet\Packages\jdx.mise_*\mise\bin`
- `%USERPROFILE%\.local\bin`

Custom `MISE_INSTALL_PATH` values are still not auto-detected today.

### Windows note for psmux

This repository deploys a dedicated `~/.psmux.conf` on Windows. `psmux`
checks that file before `~/.tmux.conf`, so the wrapper sources the shared
`~/.tmux.conf` first and then enables `set -g allow-predictions on`.

That keeps PSReadLine inline predictions available inside `psmux` panes
without putting the psmux-only `allow-predictions` option in the shared
`~/.tmux.conf`, which standard tmux does not understand.

### Zellij Web

The shared Zellij config enables the built-in web server and session sharing
by default. For tailnet-only access from phones or other remote devices,
prefer keeping Zellij itself on `127.0.0.1` and publishing it through
`tailscale serve`.

Add the following to `~/.config/chezmoi/chezmoi.toml`:

```toml
[data.zellij.web]
server = true
sharing = "on"
bind = "127.0.0.1"
port = 8082
base_url = ""
enforce_https_on_localhost = false

[data.zellij.web.tailscale]
enabled = true
https_port = 443

[data.zellij.web.windows]
autostart = "onlogon"
```

Then apply:

```bash
chezmoi apply
```

On Windows, `autostart = "onlogon"` registers a per-user Scheduled Task that
calls `~/.local/bin/ensure-zellij-web.ps1` after logon. When
`[data.zellij.web.tailscale].enabled = true`, the same wrapper also reconciles
`tailscale serve` so the tailnet route keeps pointing at the local Zellij
listener. The wrapper can also be used manually over Microsoft OpenSSH after a
reboot without requiring a separate Windows service:

```powershell
pwsh ~/.local/bin/ensure-zellij-web.ps1
```

On Ubuntu native (non-WSL), you can instead opt into a user service:

```toml
[data.zellij.web.linux]
autostart = "systemd-user"
```

This installs `~/.config/systemd/user/zellij-web.service` and a
`run_onchange_after` helper that enables and restarts it with
`systemctl --user`. For persistence after logout or reboot without an
interactive login, enable linger once:

```bash
sudo loginctl enable-linger "$USER"
```

On macOS, the future equivalent is:

```toml
[data.zellij.web.macos]
autostart = "launchagent"
```

which deploys `~/Library/LaunchAgents/com.kurone-kito.zellij-web.plist` and
loads it with `launchctl`.

Create a login token with:

```bash
zellij web --create-token
```

Verify the published tailnet endpoint with:

```bash
tailscale serve status
```

If `base_url` is set, the wrapper publishes the same subpath via
`tailscale serve --set-path`, so a config such as `base_url = "/zellij"`
becomes `https://<machine>.ts.net/zellij`.

If you intentionally bind beyond `127.0.0.1`, configure `cert` and `key`
instead and treat that as a separate direct-LAN/TLS setup. For smartphone
access, prefer a private network such as Tailscale over direct Internet
exposure.

## Git user/profile management

This repository manages `~/.config/git/config` via
`home/dot_config/git/config.tmpl`.

- `[user]` is rendered from `data.git` in `~/.config/chezmoi/chezmoi.toml`
- GPG signing settings are enabled only when `signingkey` is non-empty
- Run `gpg-cache` once per session when you want to warm `gpg-agent`
  before long signing-heavy workflows
- Directory-based identities are handled with `includeIf`

### Add directory-specific Git profiles

Edit `~/.config/chezmoi/chezmoi.toml` and add one or more profiles:

```toml
[data.git.profiles.work]
name = "Work Name"
email = "work@example.com"
signingkey = "" # optional
gitdir = "~/ghq/github.com/your-org/" # must end with /
```

Then run:

```bash
chezmoi apply
```

If you use GPG commit signing and want to avoid repeated prompts during
an extended session, warm the agent cache once up front:

```bash
gpg-cache
```

This performs a throwaway signature to unlock the key cache without
creating a real Git object.

Generated profile files:

- `~/.config/git/profiles/<profile-name>`

Script selection is OS-aware:

- Windows uses `run_onchange_after_generate-git-profiles.ps1.tmpl`
- Linux/macOS/WSL uses `run_onchange_after_generate-git-profiles.sh.tmpl`

## Secret management

GPG keys, SSH keys, and SSH host configuration can be automatically
deployed from an external secret manager (Bitwarden, 1Password, or
KeePassXC). See [docs/secret-manager-setup.md](docs/secret-manager-setup.md)
for detailed setup instructions.

## Troubleshooting

If `chezmoi apply` uses unexpected or outdated templates, verify the active
source directory:

```bash
chezmoi source-path
```

If it is not this repository, re-initialize source and apply again:

```bash
chezmoi init <your-repo-or-local-path> --apply
```

## Testing

Platform-specific unit tests verify the profile generation scripts.

### Prerequisites

Bash tests use [bats-core](https://github.com/bats-core/bats-core)
installed as git submodules:

```bash
git submodule update --init --recursive
```

PowerShell tests use [Pester 5+](https://pester.dev/). Install it if
it is not already available:

```powershell
Install-Module Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck
```

### Running tests

**Bash** (Linux/macOS/WSL):

```bash
tests/bash/helpers/bats-core/bin/bats tests/bash/
```

**PowerShell** (Windows):

```powershell
Invoke-Pester tests/powershell/ -Output Detailed
```

CI runs both suites automatically on every push and pull request.

## Contributing

Welcome to contribute to this repository! For more details,
please refer to [CONTRIBUTING.md](.github/CONTRIBUTING.md).

## License

[MIT](./LICENSE)
