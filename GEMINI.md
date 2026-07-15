# Guidelines for AI Agents

A collection of configuration files that we use.

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

GPG signing is the default for plain `git commit`. The repository
also exposes opt-in **SSH signing aliases** (`git commit-ssh`,
`git tag-ssh`, `git rebase-ssh`) when a key sets
`signing_fallback = true` (or appears in `signing_profiles`) under
`[data.secret.ssh.keys.<label>]` (see `docs/secret-manager-setup.md`).
**Use that mechanism** instead of editing
`home/dot_config/git/config.tmpl` or any chezmoi template by hand;
ad-hoc edits to enable persistent SSH signing in those templates are
forbidden.

When GPG signing fails or hangs, follow this bounded ladder. The
whole ladder is **at most three signing attempts**; each step is a
**single bounded attempt**. Never loop on hardware-touch prompts.

1. **GPG (attempt 1).** Try the configured GPG signing once.
2. **Classify the failure** by category, not by exact strings:
   **(P)** pinentry / TTY / passphrase prompt failure;
   **(C)** missing / unusable secret key (configuration);
   **(A)** agent / socket / IPC error or generic
   `signing failed: Timeout` (any locale, e.g. `タイムアウトです`)
   without pinentry evidence; **(U)** runner timeout with no useful
   stderr.
3. **gpg-agent restart + GPG retry (attempt 2, categories A and U
   only).** Run `gpgconf --kill gpg-agent` once and retry. **Skip
   this step entirely** when `gpgconf` is not on `PATH`, when
   `$SSH_AUTH_SOCK` matches `gpgconf --list-dirs agent-ssh-socket`
   (gpg-agent backs SSH and would also be killed), or in
   non-interactive CI.
4. **SSH fallback (attempt 3, allowed for any category).** Prefer
   the project-blessed `git commit-ssh` (or `tag-ssh` /
   `rebase-ssh`) alias when available; otherwise transient
   `git -c gpg.format=ssh -c user.signingkey="<key>" commit -S`.
   Discover `<key>` without a fixed path: respect existing
   SSH-signing config if `git config gpg.format` is already `ssh`,
   else use `git config gpg.ssh.defaultKeyCommand` output, else use
   the first non-certificate public key from `ssh-add -L` (pass the
   whole line, including comment, as one quoted argument). Never
   write this fallback into `~/.gitconfig` or any chezmoi template.
5. **Unsigned (final, accepted fallback).** If SSH also fails or no
   usable key is available, an unsigned commit is acceptable so that
   work is not blocked by signing failures alone.

`git rebase-ssh` only signs the initial invocation; if the rebase
stops, continue with `git rebase-ssh --continue` (or `--abort` /
`--skip`) — plain `git rebase --continue` reverts to GPG.

SSH-signed commits may still appear **Unverified** on GitHub if the
key is not registered as a *signing* key on the user's profile.
Always report which path (GPG / GPG-after-restart / `git commit-ssh`
alias / transient SSH / unsigned) was used; when unsigned, disclose
the GPG cause, whether the gpg-agent restart was attempted or
skipped (and why), and the SSH cause.

## IDD Workflow

This project uses Issue-Driven Development (IDD) with parallel AI
agents. Start with [docs/idd-workflow.md](docs/idd-workflow.md) for
the cross-agent entry path and phase routing.

Before starting IDD work, open
[`.github/instructions/idd-overview.instructions.md`](.github/instructions/idd-overview.instructions.md).
Open the routed phase file manually when the current step changes.

For the confirmed policy matrix (merge policy, review profile, claim
timing, CI wait, helper runtime, and the rest of the eleven
decisions), see [docs/idd-policy.md](docs/idd-policy.md).

## Canonical reference

The full, Copilot-first project guidance lives in
[.github/copilot-instructions.md](.github/copilot-instructions.md).
When that file uses Copilot-specific workflow names, apply the intent
in Gemini CLI using its own interaction model rather than following
the product terms literally.
