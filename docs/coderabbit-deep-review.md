---
type: guide
title: CodeRabbit deep-review mode
description: Opt in to CodeRabbit deep reviews from the chezmoi configuration.
---

# CodeRabbit deep-review mode

CodeRabbit review runs use the standard review depth by default. To opt in
to the longer deep-review mode on both POSIX shells and PowerShell, add this
section to `~/.config/chezmoi/chezmoi.toml`:

    [data.coderabbit]
    deepReview = true

Then apply the configuration and start a new shell:

    chezmoi apply

When enabled, the generated profiles export or set
`CODERABBIT_CRITIQUE_DEEP=1`. When the field is omitted or set to false,
the generated profiles contain no assignment. This preserves an environment
value supplied by the caller instead of unsetting or overriding it.

To return to standard review depth, remove the section or set
`deepReview = false`, run `chezmoi apply`, and start a new
shell. If the variable is set in the parent shell, including by a previous
profile, also run
`unset CODERABBIT_CRITIQUE_DEEP` in POSIX shells or
`Remove-Item Env:CODERABBIT_CRITIQUE_DEEP` in PowerShell before
starting the new shell. This setting only selects the review depth; it does
not change the delegate's accepted values, timeout, fallback behavior, or
machine-level persistence.
