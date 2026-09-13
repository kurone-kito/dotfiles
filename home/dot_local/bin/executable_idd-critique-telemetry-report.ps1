#!/usr/bin/env pwsh
# Windows twin of executable_idd-critique-telemetry-report (POSIX sh):
# summarizes the JSONL log written by idd-critique-telemetry (or its
# .ps1 twin) for the effect-measurement use case
# critiqueLoop.telemetryHook exists for -- the fire-and-forget, per-
# round JSONL payload contract this repository adopts from upstream
# kurone-kito/idd-skill (see dotfiles issue #389 and roadmap #419):
# total rounds, total findings, total accepted/rejected, and average
# rounds per loop (loop boundaries are inferred from `round == 1`
# entries; a log with no such entry is treated as one loop, to avoid a
# divide-by-zero).
#
# Unlike the fire-and-forget appender, this script is an explicit,
# interactively-run report -- it fails loudly (nonzero exit, message on
# stderr) when it cannot do its job, rather than degrading silently.
$ErrorActionPreference = 'Stop'

function global:Resolve-DotfilesIddCritiqueReportStateDir {
  # Reads $env:HOME / $env:USERPROFILE, not the automatic $HOME
  # variable -- see the appender twin's identical function for why
  # (read-only, session-start snapshot; not test-overridable).
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

# Both helpers below do their own property lookup, shape check, and
# type check entirely within one function scope, and only ever return
# a value already confirmed to be a genuine (non-array) scalar or a
# fixed sentinel ($null / 0). This is deliberate: an earlier version
# split "find the property" and "validate the value" into separate
# functions connected by a `return`/pipe boundary, which is exactly
# where PowerShell's single-element-array enumeration silently
# discards shape information (confirmed for ConvertFrom-Json, `return`,
# and pipe alike -- e.g. a `"round":[1]` value's `.Value` unwraps to
# the bare number `1` on `return`, so a later `-is [int]` check could
# no longer tell it apart from a genuine scalar `"round":1`). Folding
# lookup and validation into one scope means no partially-validated
# raw value ever crosses such a boundary.
function global:Test-DotfilesIddCritiqueFiniteNumber {
  # A genuine (non-array) int/long/double/decimal that is also not
  # NaN or +/-Infinity: ConvertFrom-Json accepts the bare `NaN` /
  # `Infinity` tokens (not valid JSON, but reachable via the
  # appender's own raw-fallback path, which preserves malformed input
  # verbatim) as a real System.Double, which then passes an
  # `-is [double]` check -- and .NET arithmetic propagates NaN through
  # any later `+=`, silently poisoning the whole running total (kept
  # in parity with the POSIX jq twin's identical `isnan`/`isinfinite`
  # guard; empirically confirmed for both platforms).
  param($Value)

  if ($Value -is [array]) { return $false }
  if ($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) {
    return $false
  }
  if ($Value -is [double] -and ([double]::IsNaN($Value) -or [double]::IsInfinity($Value))) {
    return $false
  }
  return $true
}

function global:Test-DotfilesIddCritiqueWholeNumber {
  # Assumes -Value already passed Test-DotfilesIddCritiqueFiniteNumber.
  # A fractional-but-finite value (e.g. 1.5) must not pass as a round
  # or counter -- both are whole-number domains by the v0.11 payload
  # contract (kept in parity with the POSIX jq twin's identical
  # `floor == .` check).
  param($Value)
  return ([Math]::Floor([double] $Value) -eq [double] $Value)
}

function global:Get-DotfilesIddCritiqueValidRound {
  # Returns the record's `round` value only when there is exactly one
  # case-sensitive (`-ceq`) `round` property whose value is a genuine
  # finite positive whole-number scalar; otherwise $null.
  param($InputObject)

  $matchingProperties = @($InputObject.PSObject.Properties | Where-Object { $_.Name -ceq 'round' })
  if ($matchingProperties.Count -ne 1) { return $null }
  $value = $matchingProperties[0].Value
  if (-not (Test-DotfilesIddCritiqueFiniteNumber -Value $value)) { return $null }
  if ($value -lt 1) { return $null }
  if (-not (Test-DotfilesIddCritiqueWholeNumber -Value $value)) { return $null }
  return $value
}

function global:Get-DotfilesIddCritiqueValidCounterValue {
  # Returns the named counter field's value when there is exactly one
  # case-sensitive (`-ceq`) property by that name whose value is a
  # genuine finite nonnegative whole-number scalar; otherwise 0 -- the
  # same fire-and-forget-friendly default the POSIX twin's
  # `is_nonneg_integer` guard applies for a missing, wrong-shape,
  # nonnumeric, non-finite, fractional, or negative counter.
  param($InputObject, [Parameter(Mandatory)] [string] $Name)

  $matchingProperties = @($InputObject.PSObject.Properties | Where-Object { $_.Name -ceq $Name })
  if ($matchingProperties.Count -ne 1) { return 0 }
  $value = $matchingProperties[0].Value
  if (-not (Test-DotfilesIddCritiqueFiniteNumber -Value $value)) { return 0 }
  if ($value -lt 0) { return 0 }
  if (-not (Test-DotfilesIddCritiqueWholeNumber -Value $value)) { return 0 }
  return $value
}

function global:Get-DotfilesIddCritiqueTelemetrySummary {
  param([Parameter(Mandatory)] [string] $LogFile)

  $records = @()
  if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
    foreach ($rawLine in Get-Content -LiteralPath $LogFile) {
      $trimmedLine = $rawLine.Trim()
      if ($trimmedLine.Length -eq 0) { continue }
      # Require the first non-whitespace character to be `{` before
      # parsing: `ConvertFrom-Json` enumerates a JSON array's elements
      # onto the pipeline, so a one-element array (e.g. `[{"round":1}]`)
      # assigns to $parsed as a bare PSCustomObject -- the later
      # PSCustomObject type check alone cannot tell that apart from a
      # genuine bare object, and would wrongly accept an array-wrapped
      # payload (empirically confirmed). Checking the raw text first
      # catches this before ConvertFrom-Json's own pipeline behavior
      # destroys the shape information.
      if ($trimmedLine[0] -ne '{') { continue }
      try {
        $parsed = $rawLine | ConvertFrom-Json -ErrorAction Stop
      } catch {
        # A syntactically malformed line -- which the appender's own
        # raw-payload fallback can produce -- is skipped instead of
        # failing the whole summary.
        continue
      }
      # Drop a line that is valid JSON but not an object (e.g. a bare
      # scalar): a shape mismatch, not only a syntax error, must not
      # crash the whole report either.
      if ($parsed -isnot [System.Management.Automation.PSCustomObject]) {
        continue
      }
      # Reject a telemetry object with no positive numeric `round`
      # (the v0.11 payload contract always includes one): an object
      # like `{}` must not silently inflate TotalRounds /
      # AverageRoundsPerLoop.
      $roundValue = Get-DotfilesIddCritiqueValidRound -InputObject $parsed
      if ($null -eq $roundValue) { continue }
      $records += $parsed
    }
  }

  $totalRounds = $records.Count
  $totalFindings = 0
  $totalAccepted = 0
  $totalRejected = 0
  $loopCount = 0
  foreach ($record in $records) {
    $totalFindings += (Get-DotfilesIddCritiqueValidCounterValue -InputObject $record -Name 'findingsCount')
    $totalAccepted += (Get-DotfilesIddCritiqueValidCounterValue -InputObject $record -Name 'acceptedCount')
    $totalRejected += (Get-DotfilesIddCritiqueValidCounterValue -InputObject $record -Name 'rejectedCount')
    # $records already only contains entries with a validated round
    # (above), so this re-derives the same value via the same
    # validator rather than trusting a weaker recheck.
    if ((Get-DotfilesIddCritiqueValidRound -InputObject $record) -eq 1) {
      $loopCount++
    }
  }
  if ($loopCount -eq 0) {
    $loopCount = 1
  }
  $average = if ($totalRounds -eq 0) { 0 } else { $totalRounds / $loopCount }

  return [pscustomobject]@{
    TotalRounds          = $totalRounds
    TotalFindings        = $totalFindings
    TotalAccepted        = $totalAccepted
    TotalRejected        = $totalRejected
    AverageRoundsPerLoop = $average
  }
}

function global:Invoke-DotfilesIddCritiqueTelemetryReport {
  $stateDir = Resolve-DotfilesIddCritiqueReportStateDir
  if (-not $stateDir) {
    [Console]::Error.WriteLine('idd-critique-telemetry-report: none of XDG_STATE_HOME, HOME, or USERPROFILE is set; cannot locate the telemetry log')
    return 1
  }

  $logFile = Join-Path $stateDir 'log.jsonl'
  # Distinguish "the log path exists but is not a regular file" (e.g. a
  # directory) from "no telemetry recorded yet" (genuinely absent):
  # Get-DotfilesIddCritiqueTelemetrySummary's own `-PathType Leaf` check
  # treats both the same way (all-zero stats), which is misleading
  # here -- especially since the appender's own fire-and-forget
  # contract silently drops events for the exact same condition. This
  # script's own contract is to fail loudly when it cannot do its job,
  # so only a genuinely absent path gets the zero report.
  if ((Test-Path -LiteralPath $logFile) -and -not (Test-Path -LiteralPath $logFile -PathType Leaf)) {
    [Console]::Error.WriteLine("idd-critique-telemetry-report: $logFile exists but is not a regular file")
    return 1
  }
  $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $logFile

  # Write directly to the real console output stream rather than
  # `Write-Output`: this function's return value (the exit code below)
  # is meant to be consumed via `exit (Invoke-...)`, an expression
  # context that would otherwise capture every `Write-Output` emission
  # as part of that same expression's value instead of ever reaching
  # the terminal -- silently swallowing the report text.
  [Console]::Out.WriteLine("Total rounds: $($summary.TotalRounds)")
  [Console]::Out.WriteLine("Total findings: $($summary.TotalFindings)")
  [Console]::Out.WriteLine("Total accepted: $($summary.TotalAccepted)")
  [Console]::Out.WriteLine("Total rejected: $($summary.TotalRejected)")
  [Console]::Out.WriteLine("Average rounds per loop: $($summary.AverageRoundsPerLoop)")
  return 0
}

if ($env:DOTFILES_TEST_IDD_CRITIQUE_TELEMETRY_REPORT_SKIP_MAIN -ne '1') {
  exit (Invoke-DotfilesIddCritiqueTelemetryReport)
}
