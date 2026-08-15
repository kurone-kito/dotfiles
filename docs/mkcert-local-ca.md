# Opt-in local development CA setup (mkcert)

This project can register a local development root CA into the
Windows certificate trust store by running `mkcert -install` as part
of `chezmoi apply`. This is **opt-in and disabled by default** — see
[Why opt-in](#why-opt-in) below.

## Why opt-in

`mkcert -install` registers a locally-generated root CA into the OS
trust store (and, depending on `TRUST_STORES`, the Java and NSS/Firefox
stores too). Doing this unconditionally on every machine this
repository's dotfiles touch — including work machines — is not
appropriate: it is a trust-store mutation, not a package installation.

This repository already uses the same "declared then enabled" shape
for other opt-in, potentially sensitive features
(`data.ssh.server`, `data.zellij.web`,
`data.wingetUserPath.packages`), so the local CA setup follows the
same convention: nothing happens unless you explicitly declare
`data.mkcert.install = true`.

## Declaring the opt-in

Add to `~/.config/chezmoi/chezmoi.toml`:

```toml
[data.mkcert]
install = true
```

Then run `chezmoi apply`. As with the other opt-in sections in this
repository's `.chezmoi.toml.tmpl`, this declaration is re-emitted on
every `chezmoi init`/re-init, so it is not lost by a re-init.

Setting it back to `false` (or removing the section) stops the script
from calling `mkcert -install` on future applies, but does **not**
retroactively remove the CA that was already registered — mkcert does
not provide an automated "uninstall" hook here beyond `mkcert
-uninstall`, which this repository does not run automatically (running
an uninstall automatically on a flag flip carries the same
trust-store-mutation concern as installing does, so it is left to you
to run manually if desired: `mkcert -uninstall`).

## What the script does

`home/run_onchange_after_57-setup-mkcert-ca.ps1.tmpl` is a
**Windows-only** chezmoi `run_onchange` script (guarded by `{{- if eq
.chezmoi.os "windows" }}`, mirroring
`run_onchange_after_35-register-path.ps1.tmpl`'s OS guard). There is no
POSIX counterpart.

On each `chezmoi apply`:

1. If `data.mkcert.install` is not `true`, it prints a message and
   exits `0` — no-op.
2. If `mkcert` is not resolvable via `Get-Command` (not on `PATH`), it
   prints a warning and exits **non-zero**. This is deliberate: chezmoi
   only records a `run_onchange` script as done when it exits `0`, so a
   non-zero exit here guarantees the **next** `chezmoi apply` retries
   once `mkcert` actually becomes resolvable, instead of the script
   being silently treated as permanently complete.
3. Otherwise it runs `mkcert -install` unconditionally. Upstream mkcert
   already treats this as a no-op once the CA is trusted, so this
   script does not implement its own trust-state detection.

The opt-in flag itself is folded into the script's rendered content
(and therefore into chezmoi's `run_onchange` content hash), so flipping
`data.mkcert.install` between `false` and `true` changes the rendered
script and forces `run_onchange` to re-run on the next apply,
regardless of any previously recorded "done" state.

### mkcert itself

This change does not alter how `mkcert` is obtained. On this
repository, `mkcert` is declared cross-platform (including Windows) in
`home/dot_config/mise/config.toml` (`mkcert = "latest"`), so it is
typically already available via mise's shims once mise has installed
it. The script only assumes `mkcert` is resolvable on `PATH` — it does
not special-case mise, winget, or any other install mechanism.

**First-apply ordering note**: `run_onchange_after_57-setup-mkcert-ca`
(57) runs after `run_onchange_after_50-install-mise-tools` (50) in the
same `chezmoi apply` invocation, so on an established machine `mkcert`
is normally already on `PATH` by the time this script runs. On a
genuinely first-ever apply with the opt-in already enabled, PATH
visibility for a tool mise *just* installed in the same run may not
yet have propagated to this script's own child process. This is
exactly the case the non-zero-exit-and-retry design above exists for:
simply re-run `chezmoi apply` (ideally after opening a fresh shell so
the updated `PATH` is picked up) once `mkcert` is confirmed on `PATH`.

## `$CAROOT` and `TRUST_STORES`

Both are upstream mkcert environment variables, not something this
repository manages or reads:

- **`$CAROOT`**: overrides where mkcert stores/looks for its root CA
  (default: an OS-specific application-data directory; run `mkcert
  -CAROOT` to see the effective path). Set it yourself before running
  `chezmoi apply` if you want a non-default location.
- **`TRUST_STORES`**: a comma-separated subset of `system`, `java`,
  `nss` (the last covers Firefox) restricting which stores `mkcert
  -install` touches. Unset means "all detected stores." Set it in your
  own shell/profile before `chezmoi apply` if you want to scope
  installation to just the system store, for example.

This script sets neither — it defers entirely to mkcert's own defaults
and whatever environment the user has configured, matching upstream's
documented behavior.

## Why `rootCA-key.pem` is never distributed

mkcert's own README is explicit that `rootCA-key.pem` "gives complete
power to intercept secure requests from your machine. Do not share
it." This repository's secret-manager integration
(`data.secret.files`, see [docs/secret-manager-setup.md](secret-manager-setup.md))
is deliberately **not** used to distribute it, and no such mechanism is
planned. If you want multiple machines to trust the same CA, upstream's
documented approach is to copy `rootCA.pem` (the public certificate
only) between machines, point `$CAROOT` at it, and run `mkcert
-install` on each — never to copy or sync the private key.

## Non-interactive sessions (e.g. inbound SSH)

<!-- FINDINGS: filled in after the CI empirical check; see the PR for
     the workflow run this section's conclusion is based on. -->

## Scope

Obtaining the `mkcert` binary itself is out of scope for this feature —
see `home/dot_config/mise/config.toml` for how it's currently
installed. This script's only precondition is that `mkcert` is already
resolvable on `PATH`.
