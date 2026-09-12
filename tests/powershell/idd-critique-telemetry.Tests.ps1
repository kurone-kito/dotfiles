# Tests for the PowerShell idd-critique-telemetry script: the Windows
# twin of executable_idd-critique-telemetry (POSIX sh), a fire-and-
# forget JSONL log sink for critiqueLoop.telemetryHook.command.
#
# Dot-sources the script under DOTFILES_TEST_..._SKIP_MAIN (mirroring
# coderabbit-critique.Tests.ps1's own pattern) and calls its functions
# directly, using Invoke-DotfilesIddCritiqueTelemetry's -InputText
# parameter instead of piping real stdin into a subprocess: a nested
# pwsh child reading Console.In via nested-process stdin redirection
# hung indefinitely in at least one sandboxed CI-like environment during
# authoring (no observed incident with plain function calls), so this
# suite exercises the exact same logic without ever spawning a child
# process or touching stdin.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/dot_local/bin/executable_idd-critique-telemetry.ps1'
  $env:DOTFILES_TEST_IDD_CRITIQUE_TELEMETRY_SKIP_MAIN = '1'
  . $script:Subject
}

AfterAll {
  Remove-Item Env:\DOTFILES_TEST_IDD_CRITIQUE_TELEMETRY_SKIP_MAIN -ErrorAction SilentlyContinue
}

Describe 'Resolve-DotfilesIddCritiqueStateDir' {
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
    $env:HOME = '/some/home'
    Resolve-DotfilesIddCritiqueStateDir | Should -Be (Join-Path '/some/xdg' 'idd-critique')
  }

  It 'falls back to $env:HOME/.local/state when XDG_STATE_HOME is unset' {
    Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
    $env:HOME = '/some/home'
    Resolve-DotfilesIddCritiqueStateDir | Should -Be (Join-Path '/some/home' '.local/state/idd-critique')
  }

  It 'falls back to $env:USERPROFILE/.local/state when XDG_STATE_HOME and HOME are both unset' {
    Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:\HOME -ErrorAction SilentlyContinue
    $env:USERPROFILE = '/some/userprofile'
    Resolve-DotfilesIddCritiqueStateDir | Should -Be (Join-Path '/some/userprofile' '.local/state/idd-critique')
  }

  It 'returns $null when none of XDG_STATE_HOME, HOME, or USERPROFILE is set' {
    Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:\HOME -ErrorAction SilentlyContinue
    Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue
    Resolve-DotfilesIddCritiqueStateDir | Should -BeNullOrEmpty
  }
}

Describe 'ConvertTo-DotfilesIddCritiqueJsonLine' {
  It 'compacts a well-formed single-line JSON object' {
    ConvertTo-DotfilesIddCritiqueJsonLine -Payload '{"phase":"C","round":1,"findingsCount":3}' |
      Should -Be '{"phase":"C","round":1,"findingsCount":3}'
  }

  It 'compacts a pretty-printed multi-line JSON object' {
    $payload = "{`n  `"round`": 2,`n  `"findingsCount`": 1`n}"
    ConvertTo-DotfilesIddCritiqueJsonLine -Payload $payload | Should -Be '{"round":2,"findingsCount":1}'
  }

  It 'passes through a single bare scalar JSON value unchanged' {
    ConvertTo-DotfilesIddCritiqueJsonLine -Payload '12345' | Should -Be '12345'
  }

  It 'passes through a single JSON array value unchanged' {
    ConvertTo-DotfilesIddCritiqueJsonLine -Payload '[1,2,3]' | Should -Be '[1,2,3]'
  }

  It 'preserves a one-element array''s shape instead of collapsing it to a bare object (regression)' {
    # ConvertFrom-Json enumerates a JSON array's elements onto its own
    # output rather than emitting the array as one object, so a
    # one-element array collapses to a bare object on simple
    # assignment unless the original text's top-level shape is
    # separately consulted (empirically confirmed) -- an array-wrapped
    # payload must not silently become a bare object in the log, which
    # would defeat downstream shape validation expecting it to still
    # look like an array.
    ConvertTo-DotfilesIddCritiqueJsonLine -Payload '[{"round":1}]' | Should -Be '[{"round":1}]'
  }

  It 'preserves an empty array''s shape' {
    ConvertTo-DotfilesIddCritiqueJsonLine -Payload '[]' | Should -Be '[]'
  }

  It 'returns $null for two concatenated top-level JSON values (not exactly one value)' {
    # Regression case: a strict single-value guard must not let a
    # multi-record payload silently split into multiple telemetry
    # records (mirrors the POSIX twin's slurp-mode jq fix for the same
    # finding).
    ConvertTo-DotfilesIddCritiqueJsonLine -Payload "{`"round`":1}`n{`"round`":2}" | Should -BeNullOrEmpty
  }

  It 'returns $null for syntactically malformed input' {
    ConvertTo-DotfilesIddCritiqueJsonLine -Payload 'not json at all' | Should -BeNullOrEmpty
  }
}

Describe 'Invoke-DotfilesIddCritiqueTelemetry' {
  BeforeEach {
    $script:StateHome = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path $script:StateHome | Out-Null
    $env:XDG_STATE_HOME = $script:StateHome
    $script:LogFile = Join-Path $script:StateHome 'idd-critique/log.jsonl'
  }

  AfterEach {
    Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
  }

  It 'appends a well-formed JSON payload as one JSONL line' {
    Invoke-DotfilesIddCritiqueTelemetry -InputText '{"phase":"C","round":1,"findingsCount":3}'

    # @(...) forces array context: Get-Content returns a scalar string
    # (not a 1-element array) for an exactly-one-line file, and indexing
    # a scalar string with [0] gives its first CHARACTER, not "the
    # first line" -- a real pitfall this suite hit empirically.
    $lines = @(Get-Content -LiteralPath $script:LogFile)
    $lines.Count | Should -Be 1
    $lines[0] | Should -Be '{"phase":"C","round":1,"findingsCount":3}'
  }

  It 'compacts a pretty-printed multi-line payload to one JSONL line' {
    $payload = "{`n  `"round`": 2,`n  `"findingsCount`": 1`n}"
    Invoke-DotfilesIddCritiqueTelemetry -InputText $payload

    (@(Get-Content -LiteralPath $script:LogFile))[0] | Should -Be '{"round":2,"findingsCount":1}'
  }

  It 'appends one line per invocation, in order' {
    Invoke-DotfilesIddCritiqueTelemetry -InputText '{"round":1}'
    Invoke-DotfilesIddCritiqueTelemetry -InputText '{"round":2}'

    $lines = @(Get-Content -LiteralPath $script:LogFile)
    $lines[0] | Should -Be '{"round":1}'
    $lines[1] | Should -Be '{"round":2}'
  }

  It 'creates the parent state directory when it does not already exist' {
    Test-Path -LiteralPath (Split-Path $script:LogFile -Parent) | Should -BeFalse

    Invoke-DotfilesIddCritiqueTelemetry -InputText '{"round":1}'

    Test-Path -LiteralPath (Split-Path $script:LogFile -Parent) | Should -BeTrue
  }

  It 'appends correctly when the state directory contains PowerShell wildcard characters (regression)' {
    # Add-Content resolves a plain -Path as a wildcard pattern against
    # the log file's *existing* parent directory, so a state/log path
    # containing `[`/`]` (plausible in an unusual username or
    # directory name) could silently fail to append, or target another
    # matching path, with the surrounding try/catch swallowing it
    # either way -- -LiteralPath must be used instead (empirically
    # confirmed both the failure and the fix).
    $wildcardStateHome = Join-Path $TestDrive "wild[card]$([Guid]::NewGuid().ToString())"
    New-Item -ItemType Directory -Force -Path $wildcardStateHome | Out-Null
    $wildcardLogFile = Join-Path $wildcardStateHome 'idd-critique/log.jsonl'
    $env:XDG_STATE_HOME = $wildcardStateHome

    Invoke-DotfilesIddCritiqueTelemetry -InputText '{"round":1,"findingsCount":5}'

    Test-Path -LiteralPath $wildcardLogFile | Should -BeTrue
    (@(Get-Content -LiteralPath $wildcardLogFile))[0] | Should -Be '{"round":1,"findingsCount":5}'
  }

  It 'writes nothing for an empty payload' {
    Invoke-DotfilesIddCritiqueTelemetry -InputText ''

    Test-Path -LiteralPath $script:LogFile | Should -BeFalse
  }

  It 'writes nothing for a whitespace-only payload' {
    Invoke-DotfilesIddCritiqueTelemetry -InputText "   `n `t `n"

    Test-Path -LiteralPath $script:LogFile | Should -BeFalse
  }

  It 'falls back to $env:HOME/.local/state when XDG_STATE_HOME is unset' {
    Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
    $originalHome = $env:HOME
    $env:HOME = $script:StateHome
    try {
      Invoke-DotfilesIddCritiqueTelemetry -InputText '{"round":1}'
      Test-Path -LiteralPath (Join-Path $script:StateHome '.local/state/idd-critique/log.jsonl') | Should -BeTrue
    } finally {
      if ($null -eq $originalHome) {
        Remove-Item Env:\HOME -ErrorAction SilentlyContinue
      } else {
        $env:HOME = $originalHome
      }
    }
  }

  It 'does nothing (no throw) when none of XDG_STATE_HOME, HOME, or USERPROFILE is set' {
    Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue
    $originalHome = $env:HOME
    $originalUserProfile = $env:USERPROFILE
    Remove-Item Env:\HOME -ErrorAction SilentlyContinue
    Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue
    try {
      { Invoke-DotfilesIddCritiqueTelemetry -InputText '{"round":1}' } | Should -Not -Throw
    } finally {
      if ($null -ne $originalHome) {
        $env:HOME = $originalHome
      }
      if ($null -ne $originalUserProfile) {
        $env:USERPROFILE = $originalUserProfile
      }
    }
  }

  It 'does not throw when the state directory cannot be created' {
    New-Item -ItemType Directory -Force -Path $script:StateHome | Out-Null
    Set-Content -Path (Join-Path $script:StateHome 'idd-critique') -Value ''

    { Invoke-DotfilesIddCritiqueTelemetry -InputText '{"round":1}' } | Should -Not -Throw
  }

  It 'falls back to the raw payload, newlines flattened, when the payload is not exactly one JSON value' {
    Invoke-DotfilesIddCritiqueTelemetry -InputText "{`"round`":1}`n{`"round`":2}"

    (@(Get-Content -LiteralPath $script:LogFile))[0] | Should -Be '{"round":1} {"round":2}'
  }

  It 'writes an array-wrapped payload to the log with its array shape preserved (regression)' {
    Invoke-DotfilesIddCritiqueTelemetry -InputText '[{"round":1}]'

    (@(Get-Content -LiteralPath $script:LogFile))[0] | Should -Be '[{"round":1}]'
  }

  It 'reads real stdin (Console.In) when -InputText is not supplied at all (regression: critical)' {
    # PowerShell coerces a $null default assigned to a [string]-typed
    # parameter into an empty string as soon as the parameter binds --
    # even when the caller never passed -InputText -- so comparing
    # against $null (`if ($null -ne $InputText) ...`) always took the
    # "use $InputText" branch and never reached Console.In.ReadToEnd()
    # at all, silently dropping every real telemetry event on Windows
    # (empirically confirmed). This is the real top-level invocation
    # shape: no -InputText bound, exactly like `.cmd`/`pwsh -File` with
    # piped stdin. Substituting Console.In directly (rather than
    # spawning a real subprocess) keeps this test fast and avoids a
    # nested-pwsh stdin hang observed elsewhere in this suite's history.
    $originalIn = [Console]::In
    try {
      [Console]::SetIn([System.IO.TextReader] (New-Object System.IO.StringReader('{"round":1,"findingsCount":5}')))
      Invoke-DotfilesIddCritiqueTelemetry
    } finally {
      [Console]::SetIn($originalIn)
    }

    (@(Get-Content -LiteralPath $script:LogFile))[0] | Should -Be '{"round":1,"findingsCount":5}'
  }
}
