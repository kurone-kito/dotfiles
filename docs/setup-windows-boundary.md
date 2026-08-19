---
type: guide
title: Tool ownership boundary with setup.windows
description: Explains which layer — this repository's mise, WinGet/DSC in kurone-kito/setup.windows, or Chocolatey — owns each Windows tool and why.
---

# Tool ownership boundary with setup.windows

[`kurone-kito/setup.windows`](https://github.com/kurone-kito/setup.windows)
provisions a Windows machine via WinGet/DSC and Chocolatey. This
repository (via [mise](https://mise.jdx.dev/)) owns a delegated slice
of that provisioning: CLI tools and language runtimes, plus the
Windows User `PATH` that makes them reachable. This page is the
counterpart to setup.windows's own
[`docs/dotfiles-boundary.md`](https://github.com/kurone-kito/setup.windows/blob/master/docs/dotfiles-boundary.md):
read it if you want the full cross-repo investigation; read this page
if you just want to know which repository owns a given tool, and why.

## Ownership at a glance

| Layer | Owns | Examples |
| ------------------------------------- | ----------------------------------------------------------- | --------------------------------------------------------------------- |
| WinGet / DSC (setup.windows) | GUI apps, MSI/Inno/WiX/burn-style installers, OS settings | Git, 7-Zip, GnuPG, Neovim, .NET SDK, Steam, Unity Hub |
| mise (this repository) | Delegated CLI tools, language runtimes | Node.js, GitHub CLI, ghq, GitHub Copilot CLI, git-vrc, and more below |
| managed User `PATH` (this repository) | The Windows User `PATH` | `mise\shims`, `WinGet\Links`, `data.wingetUserPath.packages` entries |
| Chocolatey (setup.windows) | Fonts, audio drivers | HackGen, VB-CABLE |

This repository is the only **intentional** writer of the persistent
Windows User `PATH`; see
[docs/winget-user-path.md](winget-user-path.md) for the mechanism. The
one documented exception is a third-party side effect, not code either
repository writes on purpose: setup.windows's Unity CLI installer step
invokes Unity's own `install.ps1`, which persists its own User `PATH`
entry as a documented side effect of that upstream installer.

## Why CLI tools live in mise, not WinGet

Three problems push CLI tools and language runtimes off WinGet's
`portable` installer type and onto mise:

1. **WinGet `portable` packages cannot run over an SSH session.**
   WinGet extracts a `portable` package under
   `%LOCALAPPDATA%\Microsoft\WinGet\Packages\` and, with Developer
   Mode enabled, links its executable into
   `%LOCALAPPDATA%\Microsoft\WinGet\Links\` as an NTFS symlink.
   Windows OpenSSH's public-key-authenticated sessions use a network
   logon token, and that token cannot traverse an NTFS reparse point:
   the symlinked executable fails with `ERROR_UNTRUSTED_MOUNT_POINT`
   (448, "the path cannot be traversed because it contains an
   untrusted mount point"). `fsutil behavior set SymlinkEvaluation
   R2L:1 R2R:1` does not fix it. See
   [ajeetdsouza/zoxide#1180](https://github.com/ajeetdsouza/zoxide/issues/1180)
   for this exact failure.
   [PowerShell/Win32-OpenSSH#1047](https://github.com/PowerShell/Win32-OpenSSH/issues/1047)
   is cited only as background on how a public-key session's network
   logon token behaves more restrictively in general (it documents a
   separate SMB-share restriction, closed "By Design") — it is not
   independent proof of this symlink-traversal failure.
2. **PATH growth when Developer Mode is off.** With Developer Mode
   disabled, symlink creation fails outright and WinGet instead adds
   each portable package's own install directory to `PATH`
   individually — roughly 115-170 characters per entry — pushing
   toward `cmd.exe`'s 8191-character limit
   ([KB830473](https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/command-line-string-limitation)).
   `cmd.exe` does not truncate a `PATH` value past that limit; it
   discards the variable entirely, breaking `PATH` resolution
   wherever a tool launches `cmd.exe` as its script shell.
3. **mise's Windows shims avoid both failures.** mise's default
   Windows shim mode copies a real `mise-shim.exe` binary as
   `<tool>.exe` under a single `%LOCALAPPDATA%\mise\shims` `PATH`
   entry — a plain file, not a symlink or reparse point, so an SSH
   session can execute it directly, and adding tools through mise
   never grows `PATH` per-package the way WinGet `portable` entries
   do.

Portable packages that stay in WinGet (see
[What stays in WinGet](#what-stays-in-winget) below) keep SSH
reachability through a different mechanism instead of moving to mise:
this repository declares their install directories in
`data.wingetUserPath.packages`, and the managed User `PATH`
reconciler adds each declared directory as a normal string `PATH`
entry — see [docs/winget-user-path.md](winget-user-path.md) for the
full mechanism.

### Operational rule: run `winget upgrade` from an interactive session

`data.wingetUserPath.packages` fixes `PATH` *resolution* for an
already-installed portable package. It does not fix the separate
problem that `winget` itself — running `install`, `upgrade`, or
`uninstall` against a package it already tracks as `portable` — still
tries to traverse that package's own `WinGet\Links` symlink and fails
with the same `ERROR_UNTRUSTED_MOUNT_POINT`, confirmed live in
[microsoft/winget-cli#4936](https://github.com/microsoft/winget-cli/issues/4936)
(reproduced there against `junegunn.fzf`'s `WinGet\Links\fzf.exe`
entry). **Run `winget upgrade` — and any other `winget` command that
touches an already-installed portable package — from a local or RDP
interactive session, never over SSH.**

## What this repository owns via mise

This inventory reflects every `[tools]` key in
`home/dot_config/mise/config.toml` as read while writing this page; it
is grouped by *why* each tool lives here rather than in WinGet, not
merely listed as "moved here."

### First-wave exclusive

setup.windows [issue 111](https://github.com/kurone-kito/setup.windows/issues/111)
named these five as the first delegation wave; setup.windows's own
winget/DSC definitions no longer include them.

| Tool | mise key |
| -------------------- | --------------------------- |
| Node.js | `node` |
| GitHub CLI | `github:cli/cli` |
| ghq | `github:x-motemen/ghq` |
| GitHub Copilot CLI | `npm:@github/copilot` |
| git-vrc | `github:anatawa12/git-vrc` |

### Added here (this repository also owns install, not only config)

The aqua wave (see [#257](https://github.com/kurone-kito/dotfiles/issues/257))
plus one Windows-only addition:

| Tool | mise key |
| ---------- | -------------------- |
| jq | `jq` |
| yq | `yq` |
| delta | `delta` |
| fastfetch | `fastfetch` |
| tealdeer | `tealdeer` |
| fzf | `fzf` |
| mkcert | `mkcert` |
| Terraform | `terraform` |
| pstop (Windows-only) | `github:psmux/pstop` |

`pstop` (a `htop`-style Windows CLI, no WinGet equivalent) uses the
`github` backend under a project rename (from `marlocarlo/pstop` to
`psmux/pstop`) since mise's `ubi` backend is scheduled for removal.

### Always-here

Never a WinGet `portable` duplicate on the setup.windows side — these
did not "move," they were only ever defined here:

`pnpm`, `github:d-kuro/gwq` (gwq), `aqua:anomalyco/opencode`,
`aqua:google-antigravity/antigravity-cli`, `aqua:x.ai/cli/grok`,
`npm:@anthropic-ai/claude-code`, `npm:@bitwarden/cli`,
`npm:@executeautomation/playwright-mcp-server`,
`npm:@google/gemini-cli`, `npm:@microsoft/inshellisense`,
`npm:@openai/codex`, `npm:@playwright/cli`,
`npm:bash-language-server`, `npm:fast-cli`.

### Current overlap

`dotnet = "latest"` in this repository's mise config is a **current,
non-exclusive** overlap, not a delegation: setup.windows still ships
`Microsoft.DotNet.SDK.8` and `Microsoft.DotNet.SDK.10` as WinGet/DSC
MSI installers, and setup.windows issue 111 explicitly deferred a
decision on `dotnet`. Describe this as today's dual-install state, not
as exclusive to either repository.

## What stays in WinGet

Five packages stay WinGet-only by design, per the rationale setup.windows
issue 111 recorded:

- **`jdx.mise`** — the bootstrap portable. This repository manages
  mise *tools*, not the mise binary itself, so `jdx.mise` stays in the
  stay-in-WinGet set.
- **`twpayne.chezmoi`** — structurally cannot move. The mechanism that
  fixes SSH reachability for every *other* portable package
  (`data.wingetUserPath.packages`, applied by `chezmoi apply`) only
  runs once chezmoi itself is already reachable, so chezmoi cannot be
  the thing that fixes its own reachability.
- **`Gyan.FFmpeg` / `SQLite.SQLite`** — mise's registry only exposes
  these via the `conda:` backend, and mise's `conda` backend installs
  a single package without resolving its dependencies (FFmpeg needs
  roughly 30; SQLite needs its own `libsqlite` DLL), so neither would
  actually start correctly under mise today.
- **`Ngrok.Ngrok`** — no GitHub release or aqua-registry source that
  versions; distribution is a fixed, unversioned URL, so mise has
  nothing to pin a version against.

See [docs/winget-user-path.md](winget-user-path.md) for how this
repository keeps these five reachable over SSH without moving them.

## Today's dual-install overlap

As of 2026-08-19T00:21Z (UTC), reading
[`kurone-kito/setup.windows`](https://github.com/kurone-kito/setup.windows)
at commit `67a211ad4de50c2948098e1db9217d3c80c8306d` (`master`),
`configurations/packages.dsc.yaml` still lists the aqua-wave WinGet
IDs — `jqlang.jq`, `MikeFarah.yq`, `dandavison.delta`,
`Fastfetch-cli.Fastfetch`, `dbrgn.tealdeer`, `junegunn.fzf`,
`FiloSottile.mkcert`, `Hashicorp.Terraform` — even though this
repository now installs those same commands via mise. This is today's
overlap, not a completed migration; their eventual WinGet opt-out
belongs to setup.windows roadmap issue 111, not this page.

## `chezmoi apply` is required after `setup.cmd`

This repository installs mise-managed tools only when
`run_onchange_after_50-install-mise-tools` runs as part of
`chezmoi apply`. `setup.cmd` alone no longer installs the first-wave
tools above. See setup.windows's own
["`chezmoi apply` is required after `setup.cmd`"](https://github.com/kurone-kito/setup.windows#chezmoi-apply-is-required-after-setupcmd)
README section for the full prerequisite wording rather than this page
restating its package list.

## mkcert: settings ownership, not exclusive takeover

This repository owns an opt-in local CA setup
(`data.mkcert.install`; see [docs/mkcert-local-ca.md](mkcert-local-ca.md)).
The `mkcert` binary itself is mise-managed here, but that does not
mean setup.windows has stopped installing it: setup.windows
[issue 112](https://github.com/kurone-kito/setup.windows/issues/112)
(still open at write time) covers delegating the local-CA post-install
step, and until it lands, setup.windows's own post-install script may
still also run `mkcert -install`.

## Decision tree for a new Windows CLI tool

1. Does mise have a backend that installs the tool faithfully? Prefer
   mise, and restrict the entry with an `os` key when the upstream
   tool is Windows-only.
2. If no faithful mise backend exists, the tool stays a WinGet
   portable: add a `data.wingetUserPath.packages` declaration here
   (see [docs/winget-user-path.md](winget-user-path.md)) instead of
   writing the Windows User `PATH` from setup.windows.
3. Never put chezmoi or the mise binary itself on mise — see
   [What stays in WinGet](#what-stays-in-winget) above for why.

## See also

- setup.windows [`docs/dotfiles-boundary.md`](https://github.com/kurone-kito/setup.windows/blob/master/docs/dotfiles-boundary.md)
- setup.windows [README ownership table](https://github.com/kurone-kito/setup.windows#ownership-boundary)
- setup.windows [issue 111](https://github.com/kurone-kito/setup.windows/issues/111)
- [docs/winget-user-path.md](winget-user-path.md)
- [docs/mkcert-local-ca.md](mkcert-local-ca.md)
