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

- [fzf](https://junegunn.github.io/fzf/) — fuzzy finder with key bindings,
  installed via mise
- [Homebrew](https://brew.sh/) — package manager PATH setup
- [mise](https://mise.jdx.dev/) — polyglot runtime manager
- [thefuck](https://github.com/nvbn/thefuck) — command correction
- Python venv — auto-activation helper

### Git

- [Git](https://git-scm.com/) — aliases, LFS, GPG signing, multi-profile
- [delta](https://github.com/dandavison/delta) — diff viewer, installed
  via mise; pinned to `0.18.2` on macOS since upstream stopped shipping
  `x86_64-apple-darwin` builds at v0.19.0 (mise has no per-arch
  restriction, so the pin covers Apple Silicon too), while Linux and
  Windows track `latest` (revisit around 2028-12)

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

### Task management

- [Taskwarrior](https://taskwarrior.org/) — task management; this
  repository only ships its config
  ([`home/dot_config/task/taskrc`](home/dot_config/task/taskrc)), not
  a mise-installed tool

### CLI tools (via mise)

- [fastfetch](https://github.com/fastfetch-cli/fastfetch) — system
  information display (the first `mise install` may time out fetching
  the upstream release list; re-run it if that happens)
- [jq](https://jqlang.org/) — JSON processor
- [mkcert](https://github.com/FiloSottile/mkcert) — local TLS
  certificates (opt-in local CA setup on Windows; see
  [docs/mkcert-local-ca.md](docs/mkcert-local-ca.md))
- [tealdeer](https://github.com/tealdeer-rs/tealdeer) — `tldr` client
  (the installed command is `tldr`, not `tealdeer`)
- [Terraform](https://www.terraform.io/) — infrastructure as code
- [ttyd](https://github.com/tsl0922/ttyd) — terminal-sharing web server
  (also required by `vhs` below at runtime; not mise-managed on macOS
  since its aqua-registry entry has no macOS build — install it
  another way there, e.g. via Homebrew)
- [vhs](https://github.com/charmbracelet/vhs) — terminal session
  recorder, renders `.tape` scripts to GIF/video (requires `ttyd` and
  `ffmpeg` on `PATH` at runtime)
- [yq](https://github.com/mikefarah/yq) — YAML/JSON/XML processor
  (`mikefarah/yq`; not the unrelated Python `kislyuk/yq`)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) — video/audio downloader
  (youtube-dl fork)

### AI coding assistants (via mise)

- [Antigravity CLI](https://antigravity.google/product/antigravity-cli)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli/)
- [Grok Build](https://grok.com/)
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

For why CLI tools and language runtimes live in mise instead of
[`kurone-kito/setup.windows`](https://github.com/kurone-kito/setup.windows)'s
WinGet/DSC definitions, and which tools stay on which side, see
[docs/setup-windows-boundary.md](docs/setup-windows-boundary.md).

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
- SSH commit signing is exposed as opt-in fallback aliases
  (`git commit-ssh`, `git tag-ssh`, `git rebase-ssh`) via
  `secret.ssh.keys.<label>.signing_fallback` (global) and
  `signing_profiles` (per-profile). Plain `git commit` keeps using
  GPG; the SSH aliases are intended for CI, AI agents, and
  pinentry-blocked sessions. See
  [docs/secret-manager-setup.md](docs/secret-manager-setup.md) for
  the schema, resolution policy, and the
  `git rebase-ssh --continue` caveat
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

### Claude Code autoupdater vs. mise

When `mise` is on `PATH`, `chezmoi apply` sets
`env.DISABLE_AUTOUPDATER = "1"` in `~/.claude/settings.json` (merging
only that one key; any other settings already there are left
untouched) — this whole reconciliation step is skipped, with no
changes to `settings.json`, on systems where `mise` is unavailable.
This is necessary because Claude
Code's own background autoupdater runs `npm install -g
@anthropic-ai/claude-code@latest` against whatever `npm` is currently
active, which resolves to mise-managed Node.js's own global install
location — not the isolated copy mise manages at
`npm:@anthropic-ai/claude-code`. Left unchecked, the autoupdater writes
a second, mise-invisible copy of `@anthropic-ai/claude-code` directly
into that global install location — wherever the mise-managed `npm`
itself reports as its configured prefix (`npm config get prefix`),
resolved on both POSIX and Windows rather than assumed to equal the
Node.js install directory, since a user-level `.npmrc` or
`NPM_CONFIG_PREFIX` can override it on either platform, and npm's
Windows default (`%AppData%\npm`) diverges from the Node.js install
directory even without any override — and PATH ordering makes that
stray copy win over the mise-managed one — so `claude --version` and
`mise ls --current` can silently disagree. The same `chezmoi apply`
also detects and removes that stray copy when it finds one, but only
once the mise-managed `npm:@anthropic-ai/claude-code` copy is
confirmed present, resolvable, and actually runs (`claude --version`
succeeds through it), so a repair can never leave `claude`
non-functional. If the npm prefix itself cannot be resolved, the
stray-copy check is skipped entirely rather than guessing a path.

`DISABLE_AUTOUPDATER` disables only the background autoupdate check;
manual `claude update` keeps working. The stronger `DISABLE_UPDATES`
(which also blocks manual updates) is deliberately not used, so you can
still update Claude Code by hand when needed.

`home/dot_config/mise/config.toml`'s `npm:@anthropic-ai/claude-code`
entry also sets `allow_builds = ["@anthropic-ai/claude-code"]`. mise's
npm backend now installs through its embedded `aube` installer by
default, which — unlike the npm CLI — does not run a dependency's
lifecycle scripts unless the package is explicitly allow-listed.
Without that opt-in, `@anthropic-ai/claude-code`'s `postinstall` never
runs, so the platform-native `claude` binary is never placed over the
placeholder `bin/claude.exe` the package ships, and `claude` cannot
start at all.

An install that predates this opt-in is stuck with that broken
placeholder: `mise install` treats an already-installed version as
done and does not rebuild it just because a tool option changed, so
the broken install has to be removed and reinstalled explicitly:

```bash
mise uninstall "npm:@anthropic-ai/claude-code" --all
mise install "npm:@anthropic-ai/claude-code"
mise reshim
```

Run this once per existing machine after updating to a `config.toml`
that carries the `allow_builds` opt-in. These double-quoted commands
are also what you need on Windows: `cmd.exe` has no single-quote
string syntax at all — it passes `'...'` through literally instead of
stripping the quotes — so keep the double quotes exactly as shown on
PowerShell and `cmd.exe` alike, rather than reflexively rewriting them
to single quotes.

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

On non-Windows `pwsh`, Windows-only Pester scopes are skipped. The
authoritative full PowerShell run remains Windows local execution and
Windows CI.

CI runs both suites automatically on every push and pull request.

## Contributing

Welcome to contribute to this repository! For more details,
please refer to [CONTRIBUTING.md](.github/CONTRIBUTING.md).

## License

[MIT](./LICENSE)
