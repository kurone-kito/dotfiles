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

## Testing

Run tests after modifying any script in `home/`:

- **Bash** (Linux/macOS/WSL):
  `tests/bash/helpers/bats-core/bin/bats tests/bash/`
- **PowerShell** (Windows):
  `Invoke-Pester tests/powershell/ -Output Detailed`

Ensure submodules are initialized first:
`git submodule update --init --recursive`

## Canonical reference

The full, Copilot-first project guidance lives in
[.github/copilot-instructions.md](.github/copilot-instructions.md).
When that file uses Copilot-specific workflow names, apply the intent
in Codex using Codex's own interaction model rather than following the
product terms literally.
