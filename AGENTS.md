# Guidelines for AI Agents

A collection of configuration files that we use.

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
- When synchronizing user-global guidance, preserve OpenCode's compact
  default and `data.opencode.extendedInstructions = true` opt-in; verify
  both OpenCode renders and that the shared spans stay identical in the
  other agents' renders (see `docs/ai-strategy.md`).
- Do not modify community documents (`CODE_OF_CONDUCT*`,
  `CONTRIBUTING*`) without explicit approval.
- End only the processes you started, by a recorded PID or process
  group, never by name or pattern (`pkill`, `killall`), and put the
  same rule in the prompts you hand to critique and review subagents
  (reason, the `gpgconf` exception and the `pgrep -P` allowance: see
  Guardrails in `.github/copilot-instructions.md`).

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
   - **No-TTY pre-check.** Only when no TTY is attached (`tty -s` /
     `[ -t 0 ]` fails), GPG is the configured method, and the effective
     `gpg.conf` does not set `pinentry-mode loopback`, run this probe
     once, under the agent's command timeout. It is not a signing attempt
     and does not count toward the three-attempt bound:

     ```sh
     printf probe | "$(git config gpg.openpgp.program || git config gpg.program || echo gpg)" \
       --batch --pinentry-mode error --status-fd 2 \
       --local-user "$(git config user.signingkey || git config user.email)" \
       --clearsign > /dev/null
     ```

     Only the status line `[GNUPG:] FAILURE sign 67108949` on stderr (no
     pinentry is available; the line does not depend on the locale) is
     pre-classified as category (P). The skipped GPG attempt still counts
     as attempt 1, and no signing call is made. A probe that exits 0 means
     the signature needs no prompt: attempt GPG as normal. Any other probe
     result (a missing secret key, an unreachable agent, a timeout) is not
     pre-classified: attempt GPG as normal and classify from its stderr.
     The probe changes no configuration; never configure loopback pinentry
     automatically. A TTY present, or `pinentry-mode loopback` configured,
     means attempt GPG as normal.
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
   `rebase-ssh`) alias when available — check with
   `git config --get alias.commit-ssh` (a non-zero exit
   status means it is not defined for the current scope;
   expect empty output too); otherwise, with no further
   search, retry, or asking, use the transient
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

## Testing

Ensure submodules are initialized first (a plain command, not queued;
the test runner lives in them):
`git submodule update --init --recursive`

After modifying any script in `home/` or any documentation, run the
full checks through the queue wrapper, so that parallel sessions do not
overload the host (see
[docs/pueue-validation-queue.md](docs/pueue-validation-queue.md)):

- **Lint and spelling** (Markdown lint with auto-fix, then cspell):
  `scripts/with-pueue.sh scripts/run-fix-validate.sh`
- **Tests** (bats, plus Pester when the branch touches a
  PowerShell-relevant path):
  `scripts/with-pueue.sh scripts/run-validate.sh`

Without `pueue` the wrapper simply runs the command, unless the
rendered `~/.config/dotfiles/pueue-parallelism` file is corrupt: then it
stops with status 2 first. It is a bash script: on Windows, use it from
WSL to get the queue (in Git Bash it runs the command directly).

`scripts/run-validate.sh` runs both suites, but skips the PowerShell
one when the current branch's diff touches no PowerShell-relevant
path — this is what `pre-push-validate`/`post-fix-validate` invoke
(through the wrapper).

On non-Windows `pwsh`, Windows-only Pester scopes are skipped. The
authoritative full PowerShell run remains Windows local execution and
Windows CI: the required `PowerShell tests (Pester)` job (PowerShell 7)
and the advisory `PowerShell 5.1 tests (Pester)` job (Windows
PowerShell 5.1). The Unix-scoped tests (marked
`-Skip:($IsWindows -ne $false)`) run on Linux in the advisory
`PowerShell tests (Pester, Linux)` job.

These are the suites that `scripts/run-validate.sh` runs. Run them
directly (not queued) only for a single file or a single suite, never
as the full run:

- **Bash** (Linux/macOS/WSL):
  `tests/bash/helpers/bats-core/bin/bats tests/bash/`
  and, for one file only:
  `tests/bash/helpers/bats-core/bin/bats tests/bash/with-pueue.bats`
- **PowerShell** (Windows):
  `Invoke-Pester tests/powershell/ -Output Detailed`

## IDD Workflow

This project uses Issue-Driven Development (IDD) with parallel AI
agents. Start with [docs/idd-workflow.md](docs/idd-workflow.md) for
the cross-agent entry path and phase routing.

Before starting IDD work, run the user-global `idd-activation` from
the repository root and read its JSON output. If it is not on `PATH`,
run `~/.local/bin/idd-activation` on POSIX. In Windows PowerShell,
run `& "$HOME\.local\bin\idd-activation.cmd"`; in Command Prompt,
run `"%USERPROFILE%\.local\bin\idd-activation.cmd"`. If activation
cannot run or produce valid JSON, stop without running IDD helpers or
changing repository state. When `active` is `true`,
open `.github/instructions/idd-overview-core.instructions.md` beneath
the reported `instructionsRoot`, then open each routed phase file
beneath that same root when the current step changes, and read the
[repository-specific IDD policy overlay](docs/idd-local-policy-overlay.md)
for rules retained across import retirement. When `active` is `false`,
do no IDD-specific work.

For the confirmed policy matrix (merge policy, review profile, claim
timing, CI wait, helper runtime, and the rest of the eleven
decisions), see [docs/idd-policy.md](docs/idd-policy.md).

## Canonical reference

The full, Copilot-first project guidance lives in
[.github/copilot-instructions.md](.github/copilot-instructions.md).
When that file uses Copilot-specific workflow names, apply the intent
in Codex using Codex's own interaction model rather than following the
product terms literally.
