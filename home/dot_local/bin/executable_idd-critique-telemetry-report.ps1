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

function global:Get-DotfilesIddCritiqueCaseSensitiveValue {
  # PowerShell's dot-notation property access and its
  # -contains/-notcontains operators are case-INSENSITIVE by default,
  # so a foreign/malformed record spelled e.g. `Round` or
  # `FindingsCount` would otherwise be picked up here even though the
  # POSIX jq twin's case-sensitive field lookups correctly ignore it,
  # producing platform-dependent totals for the same log (empirically
  # confirmed for both `round` and the three counter fields). Every
  # field this script reads from a parsed record goes through this
  # exact case-sensitive (`-ceq`) name match instead.
  param($InputObject, [Parameter(Mandatory)] [string] $Name)

  $property = $InputObject.PSObject.Properties | Where-Object { $_.Name -ceq $Name } | Select-Object -First 1
  if ($null -eq $property) { return $null }
  return $property.Value
}

function global:Get-DotfilesIddCritiqueNumericValue {
  param($Value)

  if ($null -eq $Value) { return 0 }
  if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
    return $Value
  }
  # A present-but-wrong-type field (e.g. a string) defaults to 0, the
  # same guard the POSIX twin's `(.findingsCount | type) == "number"`
  # check applies -- a nonnumeric counter must not abort the summary.
  return 0
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
      $roundValue = Get-DotfilesIddCritiqueCaseSensitiveValue -InputObject $parsed -Name 'round'
      if ($null -eq $roundValue) { continue }
      $roundIsNumeric = $roundValue -is [int] -or $roundValue -is [long] -or
        $roundValue -is [double] -or $roundValue -is [decimal]
      if (-not $roundIsNumeric -or $roundValue -lt 1) { continue }
      $records += $parsed
    }
  }

  $totalRounds = $records.Count
  $totalFindings = 0
  $totalAccepted = 0
  $totalRejected = 0
  $loopCount = 0
  foreach ($record in $records) {
    $totalFindings += (Get-DotfilesIddCritiqueNumericValue (Get-DotfilesIddCritiqueCaseSensitiveValue -InputObject $record -Name 'findingsCount'))
    $totalAccepted += (Get-DotfilesIddCritiqueNumericValue (Get-DotfilesIddCritiqueCaseSensitiveValue -InputObject $record -Name 'acceptedCount'))
    $totalRejected += (Get-DotfilesIddCritiqueNumericValue (Get-DotfilesIddCritiqueCaseSensitiveValue -InputObject $record -Name 'rejectedCount'))
    # $records already only contains entries with a validated round
    # (above), so this re-derives the same value via the same
    # case-sensitive lookup rather than trusting a weaker recheck.
    if ((Get-DotfilesIddCritiqueCaseSensitiveValue -InputObject $record -Name 'round') -eq 1) {
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
