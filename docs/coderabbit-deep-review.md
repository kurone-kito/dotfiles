---
type: guide
title: CodeRabbit critique delegate and review mode
description: Opt in to the CodeRabbit critique delegate, and to its lite or deep review mode, from the chezmoi configuration.
---

# CodeRabbit critique delegate and review mode

The CodeRabbit critique delegate is **off by default**. A machine that applies
this repository deploys no `coderabbit-critique` launcher and wires no
user-global `critiqueLoop.delegate` until the operator opts in, because the
delegate may send the current branch diff to CodeRabbit, an external service.

## Enable it

Add this section to `~/.config/chezmoi/chezmoi.toml`:

    [data.coderabbit]
    review = true   # false (default) | true | "lite" | "deep"

`true` means `"lite"`. To select the longer deep-review depth instead, set
`review = "deep"`. Then apply the configuration and start a new shell:

    chezmoi apply

Each mode deploys the following:

| `review`           | Launchers in `~/.local/bin` | `critiqueLoop.delegate` in `~/.config/idd-skill/config.json` | `CODERABBIT_CRITIQUE_DEEP` in the shell profiles |
| ------------------ | --------------------------- | ------------------------------------------------------------ | ------------------------------------------------ |
| `false` (default)  | none                        | not rendered                                                 | no assignment                                    |
| `true` or `"lite"` | `coderabbit-critique`, `coderabbit-critique.ps1`, and on Windows `coderabbit-critique.cmd` | rendered (`mode: "combined"`) | no assignment |
| `"deep"`           | the same as `"lite"`        | rendered (`mode: "combined"`)                                | `export CODERABBIT_CRITIQUE_DEEP=1` (POSIX shells) or `$env:CODERABBIT_CRITIQUE_DEEP = '1'` (PowerShell) |

`"lite"` runs CodeRabbit at its standard review depth and `"deep"` selects the
longer deep-review mode. Neither changes the delegate's accepted values,
timeout, fallback behavior, or machine-level persistence. The
`critiqueLoop.telemetryHook` in the same file is a separate observability sink
and is rendered in every mode.

## Disable it

Set `review = false` (it wins over the deprecated `deepReview`) or remove both
`review` and `deepReview`, run `chezmoi apply`, and start a new shell. The next
apply renders `~/.config/idd-skill/config.json` without the delegate and the
profiles without the assignment. If `CODERABBIT_CRITIQUE_DEEP` is still set in
the parent shell, including by a previous profile, also run
`unset CODERABBIT_CRITIQUE_DEEP` in POSIX shells or
`Remove-Item Env:CODERABBIT_CRITIQUE_DEEP` in PowerShell before starting the
new shell. The same applies when you switch from `"deep"` to `"lite"`.

Launchers that an earlier apply already deployed are **not** removed
automatically. Chezmoi only stops managing a path it now ignores, so delete
them by hand if you want them gone. In POSIX shells:

    rm -f ~/.local/bin/coderabbit-critique ~/.local/bin/coderabbit-critique.ps1 ~/.local/bin/coderabbit-critique.cmd

In PowerShell:

    Remove-Item -Force -ErrorAction SilentlyContinue "$HOME/.local/bin/coderabbit-critique", "$HOME/.local/bin/coderabbit-critique.ps1", "$HOME/.local/bin/coderabbit-critique.cmd"

## Machines that relied on the old always-on deployment

Earlier versions deployed the launchers and the user-global delegate on every
machine. A machine that still wants them must set `review = true` (or
`"lite"` or `"deep"`) and run `chezmoi apply`; without it the next apply
renders the delegate out of `~/.config/idd-skill/config.json`. An IDD C1 pass
then falls back to the per-agent critique mechanism, as it does in a cloud
session.

## The deprecated `deepReview` key

`deepReview = true` from the earlier deep-review setting still works as an
alias for `review = "deep"`, but it is deprecated: every template that reads
it prints a notice on stderr naming `review = "deep"`, so one `chezmoi apply`
prints it once per rendered file. `review` wins whenever both keys are set.
`review` must be `false`, `true`, `"lite"` or `"deep"`, and `deepReview` must
be a Boolean; any other value fails the render with a message naming the key.
See the [resolution table](chezmoi-toml-reference.md#coderabbit-review-datacoderabbit)
for every combination.

## What this does not change

This repository's own IDD sessions use the repo-local `critiqueLoop.delegate`
and `critiqueLoop.telemetryHook` in `.github/idd/config.json`, which this
setting does not touch. Without a deployed `coderabbit-critique` the
repo-local delegate is not found, and C1 falls through to the per-agent
mechanism.
