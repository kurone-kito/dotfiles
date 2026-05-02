# Guidelines for AI Agents

A collection of configuration files that we use.
This is a **git worktree** of
[kurone-kito/dotfiles](https://github.com/kurone-kito/dotfiles) on
the `migrate-to-chezmoi` branch — not a separate repository. CI
badges and workflow URLs correctly reference `kurone-kito/dotfiles`.

It is currently optimized for GitHub Copilot tooling, but `AGENTS.md`
exists so Codex can still receive the minimum project rules
immediately, without depending on a redirect.

## Immediate rules

- Match the conversational language to the user's language.
- Write comments and documentation in English unless there is a clear
  project-specific reason otherwise.
- If uncertainty, hidden risk, or missing context blocks a safe change,
  stop and ask a concise question before proceeding.
- Keep changes small and reviewable. If you create commits, follow the
  project's Conventional Commits rules and keep each commit atomic.
- Do not modify community documents (`CODE_OF_CONDUCT*`,
  `CONTRIBUTING*`) without explicit approval.

## Project standards

- **Indentation**: 2 spaces
- **Line endings**: LF only
- **Trailing whitespace**: trimmed except in Markdown
- **Final newline**: always present
- **File naming**: lowercase with hyphens unless a platform convention
  requires otherwise
- **PowerShell profile**: `conf.d/*.ps1` scripts are cross-platform
  (Windows + Unix pwsh) and PS5/PS7 dual-target. Use OS guards, use
  `[IO.Path]::PathSeparator`, and nest `Join-Path` for PS5. See
  the full rules in `.github/copilot-instructions.md`.

## Commit rules

This project follows
[Conventional Commits](https://www.conventionalcommits.org/).
A `.gitmessage` template is available at the repository root.
Write user-facing, lowercase subjects, keep them under 72 characters,
and split unrelated changes into separate atomic commits.

### Signing fallback

GPG signing is the default for plain `git commit`. The repository
also exposes opt-in **SSH signing aliases** (`git commit-ssh`,
`git tag-ssh`, `git rebase-ssh`) when a key sets
`signing_fallback = true` (or appears in `signing_profiles`) under
`[data.secret.ssh.keys.<label>]` (see `docs/secret-manager-setup.md`).
**Use that mechanism** instead of editing
`home/dot_config/git/config.tmpl` or any chezmoi template by hand;
ad-hoc edits to enable persistent SSH signing in those templates are
forbidden.

If the configured signing fails or hangs in the agent environment
(`pinentry`, missing TTY, `gpg-agent` issues, hardware-touch
timeout), try the SSH path in this order, with **one bounded
attempt** per step (no infinite loops on hardware-touch prompts):

1. If `git commit-ssh` (or the matching `tag-ssh` / `rebase-ssh`)
   alias is available, use it. This is the project-blessed path.
2. Otherwise fall back to a per-invocation transient SSH commit:
   `git -c gpg.format=ssh -c user.signingkey="<key>" commit -S`.
   Discover `<key>` without a fixed path: respect existing
   SSH-signing config if `git config gpg.format` is already `ssh`,
   else use `git config gpg.ssh.defaultKeyCommand` output, else use
   the first non-certificate public key from `ssh-add -L` (pass the
   whole line, including comment, as one quoted argument). Never
   write this fallback into `~/.gitconfig` or any chezmoi template.
3. If SSH signing is also unavailable, an unsigned commit is
   acceptable.

`git rebase-ssh` only signs the initial invocation; if the rebase
stops, continue with `git rebase-ssh --continue` (or `--abort` /
`--skip`) — plain `git rebase --continue` reverts to GPG.

SSH-signed commits may still appear **Unverified** on GitHub if the
key is not registered as a *signing* key on the user's profile.
Always report which path (GPG / `git commit-ssh` alias / transient
SSH / unsigned) was used; when unsigned, disclose both the GPG and
SSH failure reasons.

## Testing

Run tests after modifying any script in `home/`:

- **Bash** (Linux/macOS/WSL):
  `tests/bash/helpers/bats-core/bin/bats tests/bash/`
- **PowerShell** (Windows):
  `Invoke-Pester tests/powershell/ -Output Detailed`

On non-Windows `pwsh`, Windows-only Pester scopes are skipped. The
authoritative full PowerShell run remains Windows local execution and
Windows CI.

Ensure submodules are initialized first:
`git submodule update --init --recursive`

## Canonical reference

The full, Copilot-first project guidance lives in
[.github/copilot-instructions.md](.github/copilot-instructions.md).
When that file uses Copilot-specific workflow names, apply the intent
in Codex using Codex's own interaction model rather than following the
product terms literally.
