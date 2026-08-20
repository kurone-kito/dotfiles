---
type: guide
title: Declaring WinGet package directories in the User PATH
description: Explains how to declare a WinGet portable package's real directory so it is registered in the managed User PATH independent of WinGet's symlinks.
---

# Declaring WinGet package directories in the User PATH

The packages declared below are the WinGet portables that stay on the
[`kurone-kito/setup.windows`](https://github.com/kurone-kito/setup.windows)
side rather than moving to mise; see
[docs/setup-windows-boundary.md](setup-windows-boundary.md) for the
mise-vs-WinGet ownership decision itself. This page covers the PATH
mechanism only.

WinGet installs portable tools under
`%LOCALAPPDATA%\Microsoft\WinGet\Packages\<id>_<publisher-hash>\` and
exposes them via symlinks in `%LOCALAPPDATA%\Microsoft\WinGet\Links`.
Those symlinks do not resolve in every session — notably inbound SSH
sessions to Windows — which makes every WinGet-installed portable
tool disappear from `PATH` in that context.

This mechanism lets you declare a WinGet package's real package
directory so it gets registered directly in the managed User PATH,
ordered ahead of `WinGet\Links`, independent of whether the symlinks
resolve.

## Declaring a package

Add an entry to `~/.config/chezmoi/chezmoi.toml`:

```toml
[data.wingetUserPath.packages.<label>]  # <label> is any unique name
id      = "jdx.mise"       # WinGet package id (Packages\<id>_* prefix)
bin     = "mise/bin"       # optional; subpath within the package dir
enabled = true             # optional; false disables an inherited entry
```

- `<label>` is your own identifier for this declaration (used as the
  TOML table key only; it has no effect on discovery).
- `id` must match the WinGet package id, which is the prefix of the
  directory chezmoi should find under
  `%LOCALAPPDATA%\Microsoft\WinGet\Packages\` (WinGet appends a
  publisher-specific hash, e.g. `jdx.mise_Microsoft.Winget.Source_...`;
  matching is done by prefix, so the exact suffix does not need to be
  known or kept up to date across package updates).
- `bin` is an optional path, relative to the package directory, to
  append before adding the directory to `PATH` (use this when the
  executable lives in a subdirectory of the package, as most portable
  WinGet packages do). A path segment may contain a `*` wildcard to
  match a version-suffixed subdirectory whose exact name changes on
  every WinGet update (e.g. `ffmpeg-*-full_build/bin`, matching
  `ffmpeg-9.0-full_build/bin` today and whatever version directory
  WinGet extracts next). When more than one directory matches, the
  lexicographically last one (by full path, plain string sort — not
  version-aware) wins. A wildcard segment with no match on disk
  contributes nothing for that package, the same as an absent package
  directory.
- `enabled` defaults to `true`; set to `false` to disable a
  repo-shipped default entry (see below) without deleting it. A
  disabled entry stays in the rendered manifest — it is skipped when
  adding directories to `PATH`, but its `<id>_*` pattern is still
  recognized so a previously added directory is cleaned up as stale
  on the next reconciliation.

Run `chezmoi apply` after editing. Both the session PATH
(`conf.d/01-path.ps1`) and the persisted registry User PATH
(`run_onchange_after_35-register-path.ps1.tmpl`) pick up the change;
the registry writer re-runs automatically because it hashes the
effective declaration and re-triggers when it changes.

## Merge behavior

`data.wingetUserPath.packages` is a **map**, not a list. Chezmoi's
config template (`.chezmoi.toml.tmpl`) re-emits whatever entries
already exist in your `chezmoi.toml` on every `chezmoi init`/re-init,
so per-machine entries you add persist across re-inits the same way
`data.ghq.clone` or `data.secret.ssh.keys` entries do.

The repository ships five default entries, merged underneath whatever
you declare: a field you set on the same label (e.g. `enabled` or a
different `bin`) overrides the repo default field-by-field, so you
never need to restate `id`/`bin` just to disable it or add other
packages alongside it. A label you don't touch at all falls back to
the shipped default in full.

| Label     | `id`              | `bin`                                  |
| --------- | ----------------- | -------------------------------------- |
| `mise`    | `jdx.mise`        | `mise/bin`                             |
| `chezmoi` | `twpayne.chezmoi` | _(none — directly in the package dir)_ |
| `ffmpeg`  | `Gyan.FFmpeg`     | `ffmpeg-*-full_build/bin`              |
| `sqlite`  | `SQLite.SQLite`   | _(none — directly in the package dir)_ |
| `ngrok`   | `Ngrok.Ngrok`     | _(none — directly in the package dir)_ |

Both `.chezmoi.toml.tmpl` (which persists the effective declaration
into your `chezmoi.toml` on `chezmoi init`/re-init) and
`winget-user-path-packages.json.tmpl` (the runtime manifest) apply
this same repo-default merge, so `chezmoi apply` alone — without a
prior re-init — already reflects it.

## How discovery works

For each enabled declared package, the shared managed-path source
(`home/dot_config/powershell/lib/managed-paths.ps1`) looks for
directories under `%LOCALAPPDATA%\Microsoft\WinGet\Packages\`
matching `<id>_*`, resolves `bin` if set (including any `*` wildcard
segment, against directories actually present on disk), and includes
any resulting path that currently exists — ahead of `WinGet\Links` and
any other static managed entries. Directories that no longer exist are
simply not included on the next reconciliation, and any stale entry
previously registered for a declared package (matching the same
`<id>_*` pattern, independent of its current `bin` resolution) is
recognized as managed and removed even if its directory is gone — this
is how a wildcard `bin` re-resolving to a new version directory after
a WinGet update also drops the old version's directory from `PATH`.

Undeclared or absent packages contribute nothing, and unrelated
`PATH` entries are always preserved.

To remove a package cleanly, set `enabled = false` first and run
`chezmoi apply` (this removes its directory from `PATH` while it
stays recognized as managed) before deleting the declaration
outright. Deleting the entry directly skips that step: once it is
gone from the manifest, its `<id>_*` pattern is no longer recognized,
so any directory already added to `PATH` for it is left in place
rather than cleaned up.

## Bootstrapping chezmoi itself over SSH

chezmoi is itself installed via WinGet's portable `twpayne.chezmoi`
package, so it is subject to the exact symlink problem this mechanism
solves — `chezmoi.exe`'s only PATH-resolvable location is normally the
`WinGet\Links` symlink, which does not resolve from an inbound SSH
session. The `chezmoi` default entry above fixes this, but only takes
effect once `chezmoi apply` has already run at least once (it is the
apply run that registers the package's real directory in the managed
User PATH).

This leaves a one-time bootstrapping gap: a machine that has never run
`chezmoi apply` still cannot run its very first apply over SSH, since
nothing has registered `chezmoi.exe`'s real path yet. For that first
run only, invoke the package's real path directly instead of relying
on `PATH`:

```powershell
& (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\twpayne.chezmoi_*\chezmoi.exe")[0].FullName init --apply kurone-kito
```

Run this from the SSH session itself, or complete the first apply from
a local or RDP interactive session instead. Either way, only the very
first `chezmoi apply` on a given machine needs this workaround — every
apply after that resolves `chezmoi.exe` through the managed User PATH
like any other declared package.

That first apply only updates the **persisted registry** User PATH
(`run_onchange_after_35-register-path.ps1.tmpl`); it does not modify
the already-running session's `$env:PATH` (only
`conf.d/01-path.ps1`, which runs on profile load, does that). If you
ran the bootstrap command from an existing SSH shell, reconnect (or
otherwise start a fresh session) before relying on plain `chezmoi`
commands by name — the current shell still can't resolve `chezmoi`
by name until then, even though the registry is already fixed for
every future session.
