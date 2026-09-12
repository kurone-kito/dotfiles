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

  # Require the payload to parse as exactly one JSON value.
  # ConvertFrom-Json throws on trailing content after a complete value
  # (empirically confirmed: "Additional text encountered after finished
  # reading JSON content"), so two concatenated top-level values (e.g.
  # `{"a":1}` immediately followed by `{"b":2}`) already fails here and
  # falls through to the raw fallback below -- the same "exactly one
  # JSON value per invocation" invariant the POSIX twin's slurp-mode jq
  # guard enforces. A single well-formed value of any JSON type (object,
  # array, or bare scalar) parses fine and is re-serialized compactly,
  # matching `jq -c .`'s behavior for a single value.
  try {
    $parsed = $Payload | ConvertFrom-Json -ErrorAction Stop
  } catch {
    return $null
  }
  return ($parsed | ConvertTo-Json -Compress -Depth 20)
}

function global:Invoke-DotfilesIddCritiqueTelemetry {
  # -InputText lets tests exercise this function's full state-dir /
  # canonicalize / write logic directly (dot-sourced, no subprocess and
  # no stdin plumbing needed) -- omit it to read real stdin, the normal
  # top-level invocation path below. The whole body is wrapped in its
  # own try/catch so this function is fire-and-forget on its own terms
  # -- self-contained regardless of caller -- not only via the top-level
  # guard below.
  param([string] $InputText = $null)

  try {
    $stateDir = Resolve-DotfilesIddCritiqueStateDir
    if (-not $stateDir) {
      return
    }

    $payload = if ($null -ne $InputText) { $InputText } else { [Console]::In.ReadToEnd() }
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
    New-Item -ItemType Directory -Force -Path $stateDir -ErrorAction Stop | Out-Null
    Add-Content -Path $logFile -Value $line -Encoding utf8 -ErrorAction Stop
  } catch {
    # Fire-and-forget: never let any failure surface as a thrown error.
  }
}

if ($env:DOTFILES_TEST_IDD_CRITIQUE_TELEMETRY_SKIP_MAIN -ne '1') {
  Invoke-DotfilesIddCritiqueTelemetry
  exit 0
}
