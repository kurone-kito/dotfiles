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

Describe 'Get-DotfilesIddCritiqueNumericValue' {
  It 'passes through an int unchanged' {
    Get-DotfilesIddCritiqueNumericValue 3 | Should -Be 3
  }

  It 'defaults $null to 0' {
    Get-DotfilesIddCritiqueNumericValue $null | Should -Be 0
  }

  It 'defaults a nonnumeric (string) value to 0' {
    Get-DotfilesIddCritiqueNumericValue 'oops' | Should -Be 0
  }
}

Describe 'Get-DotfilesIddCritiqueTelemetrySummary' {
  BeforeEach {
    $script:LogFile = Join-Path $TestDrive ([Guid]::NewGuid().ToString()) 'log.jsonl'
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
}
