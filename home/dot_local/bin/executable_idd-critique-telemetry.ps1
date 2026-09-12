#!/usr/bin/env pwsh
# Windows twin of executable_idd-critique-telemetry (POSIX sh): a
# fire-and-forget IDD critique-loop telemetry sink for
# critiqueLoop.telemetryHook.command, for a native Windows IDD agent
# session where the bare `idd-critique-telemetry` command would
# otherwise resolve only to the extensionless POSIX script and silently
# fail to record telemetry (see dotfiles issue #389 and roadmap #419;
# mirrors the executable_coderabbit-critique / .ps1 / .cmd split
# already used for critiqueLoop.delegate in this same directory). Reads
# one JSON payload from stdin per invocation and appends it as one
# JSONL line to a local state log.
#
# This is a pure observability side channel, never a control-flow gate:
# it must never let its own failure surface as a nonzero exit that the
# C-phase loop could notice. Every step is wrapped so the script always
# exits 0.
$ErrorActionPreference = 'Stop'

function global:Resolve-DotfilesIddCritiqueStateDir {
  # Reads $env:HOME / $env:USERPROFILE, not the automatic $HOME
  # variable: $HOME is read-only and a snapshot taken once at session
  # start, so it does not track a later `$env:HOME = ...` change (this
  # matters for tests, which set the env vars directly to isolate each
  # case) -- and it cannot be reassigned to simulate "unset" either.
  # $env:USERPROFILE is the fallback for a native Windows session where
  # $env:HOME is typically unset (pwsh's own $HOME resolution falls back
  # to it there too).
  if ($env:XDG_STATE_HOME) {
    return (Join-Path $env:XDG_STATE_HOME 'idd-critique')
  }
  if ($env:HOME) {
    return (Join-Path $env:HOME '.local/state/idd-critique')
  }
  if ($env:USERPROFILE) {
    return (Join-Path $env:USERPROFILE '.local/state/idd-critique')
  }
  return $null
}

function global:ConvertTo-DotfilesIddCritiqueJsonLine {
  param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Payload)

  $trimmed = $Payload.Trim()
  if ($trimmed.Length -eq 0) {
    return $null
  }

  # Require the payload to parse as exactly one JSON value.
  # ConvertFrom-Json throws on trailing content after a complete value
  # (empirically confirmed: "Additional text encountered after finished
  # reading JSON content"), so two concatenated top-level values (e.g.
  # `{"a":1}` immediately followed by `{"b":2}`) already fails here and
  # falls through to the raw fallback below -- the same "exactly one
  # JSON value per invocation" invariant the POSIX twin's slurp-mode jq
  # guard enforces. -InputObject (not a pipe) is used throughout so
  # ConvertFrom-Json's own output-enumeration behavior (below) is the
  # only source of array unwrapping to account for.
  try {
    $parsed = ConvertFrom-Json -InputObject $trimmed -ErrorAction Stop
  } catch {
    return $null
  }

  # ConvertFrom-Json enumerates a JSON array's elements onto its own
  # output rather than emitting the array as one object: a one-element
  # array like `[{"round":1}]` therefore collapses $parsed to the bare
  # inner object, and an empty array `[]` collapses it to $null --
  # both indistinguishable from a genuine bare object/absence unless
  # the ORIGINAL text's top-level shape is also consulted.
  #
  # A second, PS5.1-specific divergence compounds this: for a JSON
  # array that does NOT collapse (2+ elements), Windows PowerShell
  # 5.1's ConvertFrom-Json returns a `System.Collections.ArrayList`,
  # not a `System.Object[]` -- so it never satisfies `-is [array]`
  # (confirmed via Windows CI: `PowerShell 5.1 tests (Pester)` failed
  # on exactly this while the PS7 job stayed green). The old check
  # here (`-isnot [array]`) treated that ArrayList exactly like the
  # bare-scalar collapse case above and wrapped the WHOLE ArrayList as
  # a single array element (`, $parsed`) instead of enumerating its
  # actual items -- and PS5.1's ConvertTo-Json separately mishandles a
  # bare ArrayList (and a 1-element array, which it unwraps, dropping
  # the outer brackets) by serializing it as a generic object with
  # `value`/`Count` properties instead of a JSON array
  # (PowerShell/PowerShell#3153; fixed for pwsh 6+ but never
  # backported to 5.1/Desktop edition) -- together producing exactly
  # the observed `{"value":[...],"Count":N}` output instead of `[...]`.
  #
  # `@()` (the array subexpression operator) sidesteps both PS5.1
  # quirks in one step: it enumerates ANY IEnumerable input --
  # `System.Object[]` (PS7's shape), `ArrayList` (PS5.1's shape), or a
  # bare scalar/PSCustomObject (the collapsed-1-element case, wrapped
  # as a genuine 1-element array) -- into a fresh, plain
  # `System.Object[]` with no residual collection-type baggage, so
  # ConvertTo-Json always receives an unambiguous array regardless of
  # which shape ConvertFrom-Json handed back on this PowerShell
  # version. `$null` needs its own branch first: `@($null)` produces a
  # 1-element array containing `$null`, not an empty array, since `@()`
  # counts "one output value that is $null" as one item.
  $isArrayShaped = $trimmed[0] -eq '['
  if ($isArrayShaped) {
    if ($null -eq $parsed) {
      $parsed = @()
    } else {
      $parsed = @($parsed)
    }
  }

  return (ConvertTo-Json -InputObject $parsed -Compress -Depth 20)
}

function global:Invoke-DotfilesIddCritiqueTelemetry {
  # -InputText lets tests exercise this function's full state-dir /
  # canonicalize / write logic directly (dot-sourced, no subprocess and
  # no stdin plumbing needed) -- omit it to read real stdin, the normal
  # top-level invocation path below. The whole body is wrapped in its
  # own try/catch so this function is fire-and-forget on its own terms
  # -- self-contained regardless of caller -- not only via the top-level
  # guard below.
  #
  # No `= $null` default, and $PSBoundParameters (not `$null -ne
  # $InputText`) decides whether -InputText was supplied: PowerShell
  # coerces a $null default assigned to a [string]-typed parameter into
  # an empty string as soon as the parameter is bound, even when the
  # caller never passed -InputText at all -- so $InputText is never
  # actually $null when omitted, and comparing against $null always
  # took this branch, meaning the real top-level invocation (no
  # -InputText, real piped stdin) silently read as an empty payload and
  # never reached [Console]::In.ReadToEnd() at all (empirically
  # confirmed: a critical regression -- this dropped every real
  # telemetry event on Windows since -InputText was added).
  param([string] $InputText)

  try {
    $stateDir = Resolve-DotfilesIddCritiqueStateDir
    if (-not $stateDir) {
      return
    }

    $payload = if ($PSBoundParameters.ContainsKey('InputText')) { $InputText } else { [Console]::In.ReadToEnd() }
    if ([string]::IsNullOrWhiteSpace($payload)) {
      return
    }

    $line = ConvertTo-DotfilesIddCritiqueJsonLine -Payload $payload
    if (-not $line) {
      # jq-unavailable-equivalent raw fallback: flatten embedded newlines
      # onto a single line, matching the POSIX twin -- a JSON string
      # value can never legally contain a raw newline, so this cannot
      # change a well-formed payload's meaning, and it keeps a malformed
      # one on a single JSONL line too.
      $line = ($payload -replace "`r`n|`n|`r", ' ')
    }

    $logFile = Join-Path $stateDir 'log.jsonl'
    # New-Item has no -LiteralPath parameter at all (verified: it isn't
    # in its parameter set), but that's fine here -- New-Item resolves
    # -Path against *existing* items for wildcard matching, and a
    # not-yet-created directory has nothing to match, so it creates the
    # literal path either way (verified empirically). Add-Content is
    # the real risk: it resolves -Path as a wildcard pattern against
    # the log file's *existing* parent directory, so a state/log path
    # containing PowerShell wildcard characters (e.g. `[` or `]`,
    # plausible in an unusual username or directory name) could
    # silently fail to append or target another matching path, with
    # the surrounding catch swallowing it either way -- use
    # -LiteralPath there, as the report script's own reads already do.
    New-Item -ItemType Directory -Force -Path $stateDir -ErrorAction Stop | Out-Null
    Add-Content -LiteralPath $logFile -Value $line -Encoding utf8 -ErrorAction Stop
  } catch {
    # Fire-and-forget: never let any failure surface as a thrown error.
  }
}

if ($env:DOTFILES_TEST_IDD_CRITIQUE_TELEMETRY_SKIP_MAIN -ne '1') {
  Invoke-DotfilesIddCritiqueTelemetry
  exit 0
}
