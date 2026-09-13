# Tests for the PowerShell idd-critique-telemetry-report script: the
# Windows twin of executable_idd-critique-telemetry-report (POSIX sh),
# which summarizes the JSONL log written by idd-critique-telemetry.
#
# Dot-sources the script under DOTFILES_TEST_..._SKIP_MAIN (mirroring
# idd-critique-telemetry.Tests.ps1 and coderabbit-critique.Tests.ps1)
# and calls its functions directly -- no subprocess needed, since this
# script's own logic never touches stdin.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/dot_local/bin/executable_idd-critique-telemetry-report.ps1'
  $env:DOTFILES_TEST_IDD_CRITIQUE_TELEMETRY_REPORT_SKIP_MAIN = '1'
  . $script:Subject
}

AfterAll {
  Remove-Item Env:\DOTFILES_TEST_IDD_CRITIQUE_TELEMETRY_REPORT_SKIP_MAIN -ErrorAction SilentlyContinue
}

Describe 'Resolve-DotfilesIddCritiqueReportStateDir' {
  BeforeEach {
    $script:OriginalXdgStateHome = $env:XDG_STATE_HOME
    $script:OriginalHome = $env:HOME
    $script:OriginalUserProfile = $env:USERPROFILE
  }

  AfterEach {
    if ($null -eq $script:OriginalXdgStateHome) {
      Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
    } else {
      $env:XDG_STATE_HOME = $script:OriginalXdgStateHome
    }
    if ($null -eq $script:OriginalHome) {
      Remove-Item Env:\HOME -ErrorAction SilentlyContinue
    } else {
      $env:HOME = $script:OriginalHome
    }
    if ($null -eq $script:OriginalUserProfile) {
      Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue
    } else {
      $env:USERPROFILE = $script:OriginalUserProfile
    }
  }

  It 'prefers XDG_STATE_HOME when set' {
    $env:XDG_STATE_HOME = '/some/xdg'
    Resolve-DotfilesIddCritiqueReportStateDir | Should -Be (Join-Path '/some/xdg' 'idd-critique')
  }

  It 'falls back to $env:HOME/.local/state when XDG_STATE_HOME is unset' {
    Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
    $env:HOME = '/some/home'
    Resolve-DotfilesIddCritiqueReportStateDir | Should -Be (Join-Path '/some/home' '.local/state/idd-critique')
  }

  It 'falls back to $env:USERPROFILE/.local/state when XDG_STATE_HOME and HOME are both unset' {
    Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:\HOME -ErrorAction SilentlyContinue
    $env:USERPROFILE = '/some/userprofile'
    Resolve-DotfilesIddCritiqueReportStateDir | Should -Be (Join-Path '/some/userprofile' '.local/state/idd-critique')
  }

  It 'returns $null when none of XDG_STATE_HOME, HOME, or USERPROFILE is set' {
    Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:\HOME -ErrorAction SilentlyContinue
    Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue
    Resolve-DotfilesIddCritiqueReportStateDir | Should -BeNullOrEmpty
  }
}

Describe 'Get-DotfilesIddCritiqueValidRound' {
  It 'returns the value for a genuine positive numeric round' {
    $obj = ConvertFrom-Json -InputObject '{"round":3}'
    Get-DotfilesIddCritiqueValidRound -InputObject $obj | Should -Be 3
  }

  It 'returns $null when round is absent' {
    $obj = ConvertFrom-Json -InputObject '{}'
    Get-DotfilesIddCritiqueValidRound -InputObject $obj | Should -BeNullOrEmpty
  }

  It 'returns $null when round is nonpositive' {
    $obj = ConvertFrom-Json -InputObject '{"round":0}'
    Get-DotfilesIddCritiqueValidRound -InputObject $obj | Should -BeNullOrEmpty
  }

  It 'returns $null when round is nonnumeric' {
    $obj = ConvertFrom-Json -InputObject '{"round":"x"}'
    Get-DotfilesIddCritiqueValidRound -InputObject $obj | Should -BeNullOrEmpty
  }

  It 'returns $null when round is spelled with different case' {
    $obj = ConvertFrom-Json -InputObject '{"Round":1}'
    Get-DotfilesIddCritiqueValidRound -InputObject $obj | Should -BeNullOrEmpty
  }

  It 'returns $null when round is an array-valued (regression)' {
    # An earlier version returned the raw property value across a
    # function boundary: PowerShell's single-element-array enumeration
    # silently unwrapped `"round":[1]`'s value to the bare number `1`
    # on `return`, so a later numeric-type check could no longer tell
    # it apart from a genuine scalar `"round":1` (empirically
    # confirmed). This function's own shape check must reject it
    # before any such boundary is crossed.
    $obj = ConvertFrom-Json -InputObject '{"round":[1]}'
    Get-DotfilesIddCritiqueValidRound -InputObject $obj | Should -BeNullOrEmpty
  }

  It 'returns $null when round is NaN (regression)' {
    # ConvertFrom-Json accepts the bare `NaN` token (not valid JSON,
    # but reachable via the appender's own raw fallback) as a genuine
    # System.Double, which would otherwise pass an `-is [double]`
    # check -- and .NET arithmetic propagates NaN through any later
    # `+=`, silently poisoning the whole running total (empirically
    # confirmed; kept in parity with the POSIX jq twin's identical
    # isnan/isinfinite guard).
    $obj = ConvertFrom-Json -InputObject '{"round":NaN}'
    Get-DotfilesIddCritiqueValidRound -InputObject $obj | Should -BeNullOrEmpty
  }

  It 'returns $null when round is Infinity (regression)' {
    $obj = ConvertFrom-Json -InputObject '{"round":Infinity}'
    Get-DotfilesIddCritiqueValidRound -InputObject $obj | Should -BeNullOrEmpty
  }

  It 'returns $null when round is fractional (regression)' {
    # round is a whole-number domain by the v0.11 payload contract --
    # a finite-but-fractional value (e.g. 1.5) previously passed the
    # plain finite-number check.
    $obj = ConvertFrom-Json -InputObject '{"round":1.5}'
    Get-DotfilesIddCritiqueValidRound -InputObject $obj | Should -BeNullOrEmpty
  }
}

Describe 'Get-DotfilesIddCritiqueValidCounterValue' {
  It 'returns the value for a genuine numeric counter' {
    $obj = ConvertFrom-Json -InputObject '{"findingsCount":3}'
    Get-DotfilesIddCritiqueValidCounterValue -InputObject $obj -Name 'findingsCount' | Should -Be 3
  }

  It 'defaults to 0 when the field is absent' {
    $obj = ConvertFrom-Json -InputObject '{}'
    Get-DotfilesIddCritiqueValidCounterValue -InputObject $obj -Name 'findingsCount' | Should -Be 0
  }

  It 'defaults to 0 for a nonnumeric (string) value' {
    $obj = ConvertFrom-Json -InputObject '{"findingsCount":"oops"}'
    Get-DotfilesIddCritiqueValidCounterValue -InputObject $obj -Name 'findingsCount' | Should -Be 0
  }

  It 'defaults to 0 when spelled with different case' {
    $obj = ConvertFrom-Json -InputObject '{"FindingsCount":3}'
    Get-DotfilesIddCritiqueValidCounterValue -InputObject $obj -Name 'findingsCount' | Should -Be 0
  }

  It 'defaults to 0 for an array-valued counter (regression)' {
    $obj = ConvertFrom-Json -InputObject '{"findingsCount":[7]}'
    Get-DotfilesIddCritiqueValidCounterValue -InputObject $obj -Name 'findingsCount' | Should -Be 0
  }

  It 'defaults to 0 for a NaN counter (regression)' {
    $obj = ConvertFrom-Json -InputObject '{"findingsCount":NaN}'
    Get-DotfilesIddCritiqueValidCounterValue -InputObject $obj -Name 'findingsCount' | Should -Be 0
  }

  It 'defaults to 0 for an Infinity counter (regression)' {
    $obj = ConvertFrom-Json -InputObject '{"findingsCount":Infinity}'
    Get-DotfilesIddCritiqueValidCounterValue -InputObject $obj -Name 'findingsCount' | Should -Be 0
  }

  It 'defaults to 0 for a negative counter (regression)' {
    # Counters are a nonnegative-integer domain -- a finite-but-negative
    # value previously passed the plain finite-number check.
    $obj = ConvertFrom-Json -InputObject '{"findingsCount":-4}'
    Get-DotfilesIddCritiqueValidCounterValue -InputObject $obj -Name 'findingsCount' | Should -Be 0
  }

  It 'defaults to 0 for a fractional counter (regression)' {
    $obj = ConvertFrom-Json -InputObject '{"findingsCount":0.25}'
    Get-DotfilesIddCritiqueValidCounterValue -InputObject $obj -Name 'findingsCount' | Should -Be 0
  }
}

Describe 'Get-DotfilesIddCritiqueTelemetrySummary' {
  BeforeEach {
    # Nested calls, not a single 3-positional-argument Join-Path: this
    # suite also runs under Windows PowerShell 5.1 CI, whose Join-Path
    # only accepts two positional arguments (PowerShell 6+'s
    # -AdditionalChildPath is what adds support for more).
    $testDirectory = Join-Path -Path $TestDrive -ChildPath ([Guid]::NewGuid().ToString())
    $script:LogFile = Join-Path -Path $testDirectory -ChildPath 'log.jsonl'
  }

  It 'reports all-zero stats when the log file does not exist' {
    Test-Path -LiteralPath $script:LogFile | Should -BeFalse

    $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $script:LogFile

    $summary.TotalRounds | Should -Be 0
    $summary.AverageRoundsPerLoop | Should -Be 0
  }

  It 'reports all-zero stats when the log file exists but is empty' {
    New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile -Parent) | Out-Null
    Set-Content -Path $script:LogFile -Value ''

    $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $script:LogFile

    $summary.TotalRounds | Should -Be 0
  }

  It 'aggregates findings/accepted/rejected and computes average rounds per loop across two loops' {
    New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile -Parent) | Out-Null
    @(
      '{"round":1,"findingsCount":3,"acceptedCount":2,"rejectedCount":1}'
      '{"round":2,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
      '{"round":1,"findingsCount":0,"acceptedCount":0,"rejectedCount":0}'
    ) | Set-Content -Path $script:LogFile

    $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $script:LogFile

    $summary.TotalRounds | Should -Be 3
    $summary.TotalFindings | Should -Be 4
    $summary.TotalAccepted | Should -Be 3
    $summary.TotalRejected | Should -Be 1
    $summary.AverageRoundsPerLoop | Should -Be 1.5
  }

  It 'tolerates a syntactically malformed line by skipping it' {
    New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile -Parent) | Out-Null
    @(
      '{"round":1,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
      'not json at all'
      '{"round":2,"findingsCount":2,"acceptedCount":1,"rejectedCount":1}'
    ) | Set-Content -Path $script:LogFile

    $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $script:LogFile

    $summary.TotalRounds | Should -Be 2
    $summary.TotalFindings | Should -Be 3
  }

  It 'tolerates a line that is valid JSON but not an object (bare scalar)' {
    New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile -Parent) | Out-Null
    @(
      '{"round":1,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
      '12345'
      '{"round":2,"findingsCount":2,"acceptedCount":2,"rejectedCount":0}'
    ) | Set-Content -Path $script:LogFile

    $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $script:LogFile

    $summary.TotalRounds | Should -Be 2
    $summary.TotalAccepted | Should -Be 3
  }

  It 'rejects an array-wrapped single object instead of accepting it as a bare object (regression)' {
    # ConvertFrom-Json enumerates a JSON array's elements onto the
    # pipeline, so a one-element array like `[{"round":1}]` assigns to
    # a bare PSCustomObject on simple variable assignment -- the
    # PSCustomObject type check alone cannot tell that apart from a
    # genuine bare object. Checking the raw line's first non-whitespace
    # character catches this before ConvertFrom-Json's own pipeline
    # behavior destroys the shape information.
    New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile -Parent) | Out-Null
    @(
      '[{"round":1,"findingsCount":1}]'
      '{"round":2,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
    ) | Set-Content -Path $script:LogFile

    $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $script:LogFile

    $summary.TotalRounds | Should -Be 1
  }

  It 'rejects a telemetry object with no round field (regression: must not inflate totals)' {
    New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile -Parent) | Out-Null
    @(
      '{}'
      '{"round":1,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
    ) | Set-Content -Path $script:LogFile

    $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $script:LogFile

    $summary.TotalRounds | Should -Be 1
  }

  It 'rejects a telemetry object with a nonpositive or nonnumeric round' {
    New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile -Parent) | Out-Null
    @(
      '{"round":0,"findingsCount":1}'
      '{"round":"x","findingsCount":1}'
      '{"round":1,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
    ) | Set-Content -Path $script:LogFile

    $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $script:LogFile

    $summary.TotalRounds | Should -Be 1
  }

  It 'ignores differently-cased counter fields via exact case-sensitive match (regression)' {
    # Same class of gap as the round-field regression above, for the
    # findingsCount/acceptedCount/rejectedCount fields: a foreign or
    # malformed record spelled e.g. `FindingsCount` must not be picked
    # up by PowerShell's default case-insensitive property access,
    # since the POSIX jq twin's case-sensitive lookups ignore it too.
    New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile -Parent) | Out-Null
    @(
      '{"round":1,"FindingsCount":99,"AcceptedCount":99,"RejectedCount":99}'
      '{"round":2,"findingsCount":1,"acceptedCount":1,"rejectedCount":1}'
    ) | Set-Content -Path $script:LogFile

    $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $script:LogFile

    $summary.TotalRounds | Should -Be 2
    $summary.TotalFindings | Should -Be 1
    $summary.TotalAccepted | Should -Be 1
    $summary.TotalRejected | Should -Be 1
  }

  It 'rejects a differently-cased round property via exact case-sensitive match (regression)' {
    # PowerShell's -contains/-notcontains operators and dot-notation
    # property access are both case-INSENSITIVE by default, so a
    # foreign/malformed entry spelled `Round` would otherwise be
    # accepted here even though the POSIX jq twin's case-sensitive
    # `.round` correctly rejects the same entry (empirically confirmed).
    New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile -Parent) | Out-Null
    @(
      '{"Round":1,"findingsCount":1}'
      '{"round":1,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
    ) | Set-Content -Path $script:LogFile

    $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $script:LogFile

    $summary.TotalRounds | Should -Be 1
  }

  It 'treats a payload with no round-1 entry as a single loop (no divide-by-zero)' {
    New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile -Parent) | Out-Null
    @(
      '{"round":2,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
      '{"round":3,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
    ) | Set-Content -Path $script:LogFile

    $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $script:LogFile

    $summary.TotalRounds | Should -Be 2
    $summary.AverageRoundsPerLoop | Should -Be 2
  }

  It 'defaults a nonnumeric counter value to 0 instead of aborting (regression)' {
    New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile -Parent) | Out-Null
    @(
      '{"round":1,"findingsCount":1,"acceptedCount":"oops","rejectedCount":0}'
      '{"round":2,"findingsCount":2,"acceptedCount":2,"rejectedCount":0}'
    ) | Set-Content -Path $script:LogFile

    $summary = Get-DotfilesIddCritiqueTelemetrySummary -LogFile $script:LogFile

    $summary.TotalRounds | Should -Be 2
    $summary.TotalFindings | Should -Be 3
    $summary.TotalAccepted | Should -Be 2
  }
}

Describe 'Invoke-DotfilesIddCritiqueTelemetryReport' {
  It 'returns 1 and writes to stderr when none of XDG_STATE_HOME, HOME, or USERPROFILE is set' {
    $originalXdg = $env:XDG_STATE_HOME
    $originalHome = $env:HOME
    $originalUserProfile = $env:USERPROFILE
    Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:\HOME -ErrorAction SilentlyContinue
    Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue
    try {
      $result = Invoke-DotfilesIddCritiqueTelemetryReport
      $result | Should -Be 1
    } finally {
      if ($null -ne $originalXdg) { $env:XDG_STATE_HOME = $originalXdg }
      if ($null -ne $originalHome) { $env:HOME = $originalHome }
      if ($null -ne $originalUserProfile) { $env:USERPROFILE = $originalUserProfile }
    }
  }

  It 'returns 0 when a state directory resolves, even with no log file yet' {
    $stateHome = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
    $originalXdg = $env:XDG_STATE_HOME
    $env:XDG_STATE_HOME = $stateHome
    try {
      $result = Invoke-DotfilesIddCritiqueTelemetryReport
      $result | Should -Be 0
    } finally {
      if ($null -eq $originalXdg) {
        Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
      } else {
        $env:XDG_STATE_HOME = $originalXdg
      }
    }
  }

  It 'returns 1 and writes to stderr when the log path exists but is not a regular file (regression)' {
    # Distinguish "exists but wrong type" (this script cannot do its
    # job) from "genuinely absent" (a valid all-zero state) -- both
    # used to report all-zero stats via the same -PathType Leaf check.
    # Capture [Console]::Error and assert its text too, not just the
    # return code: a bare return-code assertion would still pass if the
    # diagnostic itself were removed or changed.
    $stateHome = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path (Join-Path $stateHome 'idd-critique/log.jsonl') | Out-Null
    $originalXdg = $env:XDG_STATE_HOME
    $env:XDG_STATE_HOME = $stateHome
    $originalError = [Console]::Error
    $capturedError = [System.IO.StringWriter]::new()
    try {
      [Console]::SetError($capturedError)
      $result = Invoke-DotfilesIddCritiqueTelemetryReport
      $result | Should -Be 1
      $capturedError.ToString() | Should -Match 'exists but is not a regular file'
    } finally {
      [Console]::SetError($originalError)
      if ($null -eq $originalXdg) {
        Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
      } else {
        $env:XDG_STATE_HOME = $originalXdg
      }
    }
  }
}
