# Documentation Index

<!-- dotfiles-divergence: local-docs-index -->

This index currently covers only this repository's own
locally-authored `docs/` pages. At the next template re-import, once
the 17 upstream-synced pages gain OKF frontmatter of their own (see
[docs/idd-policy.md](idd-policy.md)'s "Pinned upstream commit" note),
this index should be reconciled to cover the full `docs/` bundle
instead of staying local-only.

Use this page as the entry point to this repository's own `docs/`
bundle. If you are an agent with no prior familiarity with this
repository, start here rather than listing the directory directly —
the table below groups every locally-authored page by type and links
straight to it.

## The OKF convention

Every page below (except this one) carries
[OKF](https://okf.md/) (Open Knowledge Format v0.1) frontmatter: a
required `type` field from a closed vocabulary (`index`, `guide`,
`concept`, `reference`, `workflow`, `design`, `investigation`,
`tutorial`), a required `title` field that matches the page's own `#`
heading exactly, a required `description` field (one sentence ending
in a period), and an optional `tags` list of lowercase-hyphenated
strings. `index.md` is itself a reserved OKF filename — this page
intentionally carries no frontmatter of its own, since it is the
generated-by-convention topic map rather than a page the convention
describes.

## Reference Map

<!-- dprint-ignore-start -->
| Type | Page | Description |
| ---- | ---- | ----------- |
| guide | [AI tooling strategy](ai-strategy.md) | Explains why this repository prioritizes GitHub Copilot for AI tooling and how its instruction-file layers relate to each other. |
| guide | [Using ghq with multiple accounts](ghq-workflow.md) | Explains how to configure ghq so each GitHub or GitLab account automatically uses the correct SSH key, commit identity, and GPG signing key. |
| guide | [Repairing Git Bash under Windows mandatory ASLR](git-bash-aslr-repair.md) | Explains how to diagnose and repair Git Bash fork() failures caused by Windows mandatory ASLR, and what the chezmoi apply warning means. |
| guide | [Opt-in local development CA setup (mkcert)](mkcert-local-ca.md) | Explains how to opt into registering a local mkcert CA into the Windows certificate trust store during chezmoi apply, and why it stays off by default. |
| guide | [Secret manager setup](secret-manager-setup.md) | Explains how to configure chezmoi to retrieve GPG keys, SSH keys, and SSH host configuration from an external secret manager. |
| guide | [Tool ownership boundary with setup.windows](setup-windows-boundary.md) | Explains which layer — this repository's mise, WinGet/DSC in kurone-kito/setup.windows, or Chocolatey — owns each Windows tool and why. |
| guide | [Deploying sshd_config](sshd-config-setup.md) | Explains how to manually deploy the chezmoi-generated hardened sshd_config to its system location on Linux, macOS, and Windows. |
| guide | [Configuring the systemd-tmpfiles /tmp cleanup age](tmpfiles-cleanup-setup.md) | Explains how to manually deploy the chezmoi-generated tmpfiles.d override that shortens the /tmp cleanup age on Linux, and why deployment stays manual. |
| guide | [VS Code Integrated Terminal](vscode-terminal.md) | Explains how this dotfiles PowerShell profile adapts to VS Code's integrated terminal and lists recommended VS Code settings. |
| guide | [Declaring WinGet package directories in the User PATH](winget-user-path.md) | Explains how to declare a WinGet portable package's real directory so it is registered in the managed User PATH independent of WinGet's symlinks. |
| guide | [Zellij Web Client — Mobile Usage Guide](zellij-web-mobile.md) | Covers known limitations and recommended workarounds for using the Zellij web client from mobile devices. |
| reference | [IDD Policy Configuration](idd-policy.md) | Records this repository's confirmed IDD policy decisions alongside their machine-readable mirror in .github/idd/config.json. |
<!-- dprint-ignore-end -->
