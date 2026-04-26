# 🔴 My dotfiles

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Linting](https://github.com/kurone-kito/dotfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/kurone-kito/dotfiles/actions/workflows/lint.yml)
[![CodeRabbit](https://img.shields.io/badge/review-CodeRabbit-green?logo=coderabbit)](https://www.coderabbit.ai/)

A collection of configuration files that we use.

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

## Contributing

Welcome to contribute to this repository! For more details,
please refer to [CONTRIBUTING.md](.github/CONTRIBUTING.md).

## License

[MIT](./LICENSE)
