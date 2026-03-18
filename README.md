# 🔴 My dotfiles

A collection of configuration files that we use.  
私が使用している設定ファイル集です。

## Deploying with chezmoi

### Quick Install

```sh
chezmoi init --apply kurone-kito/dotfiles
```

### Step by Step

```sh
# Initialize (will prompt for configuration)
chezmoi init kurone-kito/dotfiles

# Preview changes
chezmoi diff

# Apply
chezmoi apply
```

### Reconfigure

To change settings (e.g., switch secret manager, update GPG key):

```sh
chezmoi init --reconfigure
```

### Secret Manager Integration

This repository supports retrieving secrets (GPG keys, SSH keys,
SSH configs) from the following managers:

- [Bitwarden](https://bitwarden.com/)
- [1Password](https://1password.com/)
- [KeePassXC](https://keepassxc.org/)

During `chezmoi init`, you will be prompted to select a secret manager.
Configure the item IDs in `~/.config/chezmoi/chezmoi.toml` after
initialization.

### Legacy Setup

The old setup scripts are still available for reference:

```sh
./setup        # Unix/macOS
./setup.cmd    # Windows
```

The scripts work with the latest macOS and Windows.  
最新の macOS と Windows で動作確認しています。

## Thanks

- [holman/dotfiles](https://github.com/holman/dotfiles): It was helpful.
- <!-- cspell:disable-next-line -->
  [lysyi3m/macos-terminal-themes](https://github.com/lysyi3m/macos-terminal-themes):
  Included the terminal's color scheme settings. (customized)

## See also (Dependents)

- [kurone-kito/setup.macos](https://github.com/kurone-kito/setup.macos)
- [kurone-kito/setup.windows](https://github.com/kurone-kito/setup.windows)

## Contributing

Welcome to contribute to this repository! For more details,
please refer to [CONTRIBUTING.md](.github/CONTRIBUTING.md).

## License

[MIT](./LICENSE)
