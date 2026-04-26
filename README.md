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

## Git user/profile management

This repository manages `~/.config/git/config` via
`home/dot_config/git/config.tmpl`.

- `[user]` is rendered from `data.git` in `~/.config/chezmoi/chezmoi.toml`
- GPG signing settings are enabled only when `signingkey` is non-empty
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
