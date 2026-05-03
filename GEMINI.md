# Guidelines for AI Agents

A collection of configuration files that we use.
This is a **git worktree** of
[kurone-kito/dotfiles](https://github.com/kurone-kito/dotfiles) on
the `migrate-to-chezmoi` branch — not a separate repository. CI
badges and workflow URLs correctly reference `kurone-kito/dotfiles`.

It is currently optimized for GitHub Copilot tooling, but `GEMINI.md`
exists so Gemini CLI can still receive the minimum project rules
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

GPG signing is configured by default. The repository also supports
**declarative opt-in to persistent SSH signing** via
`primary_signing` and `signing_profiles` on
`[data.secret.ssh.keys.<label>]` (see `docs/secret-manager-setup.md`).
**Use that mechanism** instead of editing
`home/dot_config/git/config.tmpl` or any chezmoi template by hand;
ad-hoc edits to enable SSH signing in those templates are forbidden.

If the configured signing (GPG, or declaratively configured SSH)
fails or hangs in the agent environment (`pinentry`, missing TTY,
`gpg-agent` issues, hardware-touch timeout), make **one bounded
retry** with transient SSH signing for that commit only via
`git -c gpg.format=ssh -c user.signingkey="<key>" commit -S`. This
fallback must stay per-invocation; never write it into
`~/.gitconfig` or any chezmoi template.

Discover the SSH key without a fixed path: respect existing
SSH-signing config if `git config gpg.format` is already `ssh`,
else use `git config gpg.ssh.defaultKeyCommand` output, else use
the first non-certificate public key from `ssh-add -L` (pass the
whole line, including comment, as one quoted argument).

SSH-signed commits may still appear **Unverified** on GitHub if the
key is not registered as a signing key on the user's profile. If
SSH signing is also unavailable, an unsigned commit is acceptable.
Always report which path (configured / SSH fallback / unsigned) was
used; when unsigned, disclose both the primary and SSH failure
reasons.

## Onboarding detection

When starting a session, check whether this repository is the base
template or a derived project:

- If the repository name is exactly `template`, it is the base
  template — no action needed.
- If the name differs **and** this file still contains the phrase
  `language-independent generic project template`, the guidelines
  have not been customized yet.

In that case, **proactively propose an onboarding workflow** to
customize the project's documentation, tooling, and AI guidelines.
See the full onboarding checklist in
[.github/copilot-instructions.md](.github/copilot-instructions.md).

## Canonical reference

The full, Copilot-first project guidance lives in
[.github/copilot-instructions.md](.github/copilot-instructions.md).
When that file uses Copilot-specific workflow names, apply the intent
in Gemini CLI using its own interaction model rather than following
the product terms literally.
