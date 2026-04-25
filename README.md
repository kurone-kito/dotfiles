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
