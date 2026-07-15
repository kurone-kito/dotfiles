# Declaring WinGet package directories in the User PATH

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
  WinGet packages do).
- `enabled` defaults to `true`; set to `false` to disable a
  repo-shipped default entry without deleting it (the repo ships an
  empty default map today, so this mainly matters if a future repo
  default gets added and you want to opt out). A disabled entry stays
  in the rendered manifest — it is skipped when adding directories to
  `PATH`, but its `<id>_*` pattern is still recognized so a previously
  added directory is cleaned up as stale on the next reconciliation.

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
`data.ghq.clone` or `data.secret.ssh.keys` entries do. The repository
itself ships this map **empty** — there are no repo-wide default
package declarations today, so every entry is something you add
yourself, on the machine(s) where you need it.

## How discovery works

For each enabled declared package, the shared managed-path source
(`home/dot_config/powershell/lib/managed-paths.ps1`) looks for
directories under `%LOCALAPPDATA%\Microsoft\WinGet\Packages\`
matching `<id>_*`, appends `bin` if set, and includes any that
currently exist on disk — ahead of `WinGet\Links` and any other
static managed entries. Directories that no longer exist are simply
not included on the next reconciliation, and any stale entry
previously registered for a declared package (matching the same
`<id>_*` pattern) is recognized as managed and removed even if its
directory is gone.

Undeclared or absent packages contribute nothing, and unrelated
`PATH` entries are always preserved.

To remove a package cleanly, set `enabled = false` first and run
`chezmoi apply` (this removes its directory from `PATH` while it
stays recognized as managed) before deleting the declaration
outright. Deleting the entry directly skips that step: once it is
gone from the manifest, its `<id>_*` pattern is no longer recognized,
so any directory already added to `PATH` for it is left in place
rather than cleaned up.
