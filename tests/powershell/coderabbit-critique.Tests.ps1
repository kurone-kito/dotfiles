# Tests for the PowerShell coderabbit-critique script: a read-only C1
# critiqueLoop.delegate findings adapter wrapping CodeRabbit CLI.
# Exercises: PATH detection, auth-status parsing, timeout/base-branch
# resolution, the bounded-execution primitive against a real process, and
# the top-level orchestration's success/failure branches.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/dot_local/bin/executable_coderabbit-critique.ps1'
  # On a Windows machine with only the built-in Windows PowerShell 5.1
  # (no pwsh installed) -- exactly the environment the delegate itself now
  # supports -- Get-Command pwsh returns nothing, which would otherwise
  # leave the mandatory -FilePath parameter unbound below. Fall back to
  # powershell.exe: the -NoProfile/-Command flags and the plain PowerShell
  # syntax these tests pass are identical on both hosts.
  $script:PwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
  if (-not $script:PwshPath) {
    $script:PwshPath = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
  }
}

Describe 'coderabbit-critique' {

  BeforeEach {
    $script:OriginalSkip = $env:DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN
    $script:OriginalTimeout = $env:CODERABBIT_CRITIQUE_TIMEOUT
    $script:OriginalBase = $env:CODERABBIT_CRITIQUE_BASE
    $env:DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN = '1'
    Remove-Item Env:\CODERABBIT_CRITIQUE_TIMEOUT -ErrorAction SilentlyContinue
    Remove-Item Env:\CODERABBIT_CRITIQUE_BASE -ErrorAction SilentlyContinue
    # Every diagnostic in Invoke-DotfilesCoderabbitCritique now goes through
    # [Console]::Error.WriteLine rather than Write-Warning -- deliberately,
    # so a non-interactive `pwsh -File` host can't reroute it onto real
    # stdout (see the function's own comment). That also means it bypasses
    # PowerShell's own stream redirection (`3>&1` below no longer captures
    # anything), so the in-process orchestration tests below would
    # otherwise print every diagnostic straight to this test run's real
    # console/CI log. Swap in a throwaway StringWriter for the duration of
    # each in-process test to keep that output out of the log; the
    # "Full script as a real subprocess" contexts are unaffected, since
    # they read a genuine child process's own redirected OS-level stderr,
    # not this parent process's [Console]::Error.
    $script:OriginalConsoleError = [Console]::Error
    [Console]::SetError([System.IO.TextWriter]::Synchronized([System.IO.StringWriter]::new()))
    . $script:Subject
  }

  AfterEach {
    [Console]::SetError($script:OriginalConsoleError)
    $env:DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN = $script:OriginalSkip
    if ($null -eq $script:OriginalTimeout) {
      Remove-Item Env:\CODERABBIT_CRITIQUE_TIMEOUT -ErrorAction SilentlyContinue
    } else {
      $env:CODERABBIT_CRITIQUE_TIMEOUT = $script:OriginalTimeout
    }
    if ($null -eq $script:OriginalBase) {
      Remove-Item Env:\CODERABBIT_CRITIQUE_BASE -ErrorAction SilentlyContinue
    } else {
      $env:CODERABBIT_CRITIQUE_BASE = $script:OriginalBase
    }

    foreach ($name in @(
      'Get-DotfilesCoderabbitCommand'
      'Test-DotfilesCoderabbitAuthenticated'
      'Resolve-DotfilesCoderabbitTimeoutSeconds'
      'Resolve-DotfilesCoderabbitBaseBranch'
      'ConvertTo-DotfilesWindowsQuotedArgument'
      'ConvertTo-DotfilesQuotedArgumentString'
      'Start-DotfilesProcessWithTimeout'
      'Invoke-DotfilesCoderabbitReviewWithTimeout'
      'Test-DotfilesActionRequiredType'
      'Invoke-DotfilesCoderabbitCritique'
      'script:coderabbit'
      'script:git'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  Context 'Get-DotfilesCoderabbitCommand' {
    It 'returns $null when coderabbit is not in PATH' {
      Mock Get-Command { $null } -ParameterFilter { $Name -eq 'coderabbit' }

      Get-DotfilesCoderabbitCommand | Should -BeNullOrEmpty
    }
  }

  Context 'Test-DotfilesCoderabbitAuthenticated' {
    It 'returns $false when auth status reports signed out' {
      function script:coderabbit {
        if ($args[0] -eq 'auth' -and $args[1] -eq 'status') {
          'Status       : signed out'
        }
      }
      $cmd = [pscustomobject]@{ Name = 'coderabbit' }

      Test-DotfilesCoderabbitAuthenticated -CoderabbitCommand $cmd | Should -BeFalse
    }

    It 'returns $true when auth status shows account info without signed out' {
      function script:coderabbit {
        if ($args[0] -eq 'auth' -and $args[1] -eq 'status') {
          'Account      : test-user'
        }
      }
      $cmd = [pscustomobject]@{ Name = 'coderabbit' }

      Test-DotfilesCoderabbitAuthenticated -CoderabbitCommand $cmd | Should -BeTrue
    }
  }

  Context 'Resolve-DotfilesCoderabbitTimeoutSeconds' {
    It 'defaults to 300 when unset' {
      Resolve-DotfilesCoderabbitTimeoutSeconds | Should -Be 300
    }

    It 'uses CODERABBIT_CRITIQUE_TIMEOUT when a positive integer' {
      $env:CODERABBIT_CRITIQUE_TIMEOUT = '30'

      Resolve-DotfilesCoderabbitTimeoutSeconds | Should -Be 30
    }

    It 'falls back to 300 for a non-numeric value' {
      $env:CODERABBIT_CRITIQUE_TIMEOUT = 'not-a-number'

      Resolve-DotfilesCoderabbitTimeoutSeconds | Should -Be 300
    }

    It 'falls back to 300 for a zero or negative value' {
      $env:CODERABBIT_CRITIQUE_TIMEOUT = '0'

      Resolve-DotfilesCoderabbitTimeoutSeconds | Should -Be 300
    }
  }

  Context 'Resolve-DotfilesCoderabbitBaseBranch' {
    It 'uses CODERABBIT_CRITIQUE_BASE when set, without calling git' {
      $env:CODERABBIT_CRITIQUE_BASE = 'develop'
      function script:git { throw 'git must not be called when CODERABBIT_CRITIQUE_BASE is set' }
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git'; CommandType = 'Function' }
      } -ParameterFilter { $Name -eq 'git' }

      Resolve-DotfilesCoderabbitBaseBranch | Should -Be 'develop'
    }

    It 'returns $null when git is not in PATH' {
      Mock Get-Command { $null } -ParameterFilter { $Name -eq 'git' }

      Resolve-DotfilesCoderabbitBaseBranch | Should -BeNullOrEmpty
    }

    It 'strips the origin/ prefix from the symbolic-ref result' {
      function script:git {
        if ($args[0] -eq 'symbolic-ref') {
          $global:LASTEXITCODE = 0
          'origin/main'
        }
      }
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git'; CommandType = 'Function' }
      } -ParameterFilter { $Name -eq 'git' }

      Resolve-DotfilesCoderabbitBaseBranch | Should -Be 'main'
    }

    It 'falls back to origin/main when no symbolic-ref is set' {
      function script:git {
        if ($args[0] -eq 'symbolic-ref') {
          $global:LASTEXITCODE = 1
          return
        }
        if ($args[0] -eq 'rev-parse' -and $args[3] -eq 'origin/main') {
          $global:LASTEXITCODE = 0
          return
        }
        $global:LASTEXITCODE = 1
      }
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git'; CommandType = 'Function' }
      } -ParameterFilter { $Name -eq 'git' }

      Resolve-DotfilesCoderabbitBaseBranch | Should -Be 'main'
    }

    It 'returns $null (fails closed) when both origin/main and origin/master resolve without a symbolic-ref' {
      function script:git {
        if ($args[0] -eq 'symbolic-ref') {
          $global:LASTEXITCODE = 1
          return
        }
        if ($args[0] -eq 'rev-parse') {
          $global:LASTEXITCODE = 0
          return
        }
        $global:LASTEXITCODE = 1
      }
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git'; CommandType = 'Function' }
      } -ParameterFilter { $Name -eq 'git' }

      Resolve-DotfilesCoderabbitBaseBranch | Should -BeNullOrEmpty
    }

    It 'returns $null when neither symbolic-ref nor origin/main nor origin/master resolve' {
      function script:git { $global:LASTEXITCODE = 1 }
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git'; CommandType = 'Function' }
      } -ParameterFilter { $Name -eq 'git' }

      Resolve-DotfilesCoderabbitBaseBranch | Should -BeNullOrEmpty
    }
  }

  Context 'ConvertTo-DotfilesWindowsQuotedArgument (CommandLineToArgvW escaping)' {
    # This is the actual algorithm .NET's own ArgumentList uses internally
    # on newer runtimes to build a native Windows command line -- doubling
    # embedded quotes (an earlier version of this function) is a CSV/SQL
    # convention, not how CommandLineToArgvW decodes a quoted argument, and
    # does not reliably preserve an embedded quote. A git branch name can
    # contain an embedded double quote (git check-ref-format accepts it,
    # confirmed empirically) but never a backslash (git check-ref-format
    # rejects it); CODERABBIT_CRITIQUE_BASE is unconstrained by git's
    # ref-name rules at all, so both the quote-escaping and the
    # backslash-run-doubling parts of the algorithm are exercised, not
    # just quote-wrapping.
    It 'returns a simple argument unquoted' {
      ConvertTo-DotfilesWindowsQuotedArgument -Argument 'review' | Should -Be 'review'
    }

    It 'quotes an argument containing a space' {
      ConvertTo-DotfilesWindowsQuotedArgument -Argument 'with space' | Should -Be '"with space"'
    }

    It 'backslash-escapes an embedded double quote' {
      ConvertTo-DotfilesWindowsQuotedArgument -Argument 'with"quote' | Should -Be '"with\"quote"'
    }

    It 'doubles a backslash run immediately before an embedded quote' {
      ConvertTo-DotfilesWindowsQuotedArgument -Argument 'quote"then\backslash' |
        Should -Be '"quote\"then\backslash"'
    }

    It 'leaves a trailing backslash with no adjacent quote unquoted (no whitespace or quote present)' {
      ConvertTo-DotfilesWindowsQuotedArgument -Argument 'trailing\' | Should -Be 'trailing\'
    }

    It 'represents an empty argument as two double quotes' {
      ConvertTo-DotfilesWindowsQuotedArgument -Argument '' | Should -Be '""'
    }

    It 'round-trips space, quote, and backslash-quote arguments through a real process' {
      $echoScript = Join-Path $TestDrive 'echo-arg.ps1'
      Set-Content -Path $echoScript `
        -Value '$args[0] | Out-File -FilePath $env:ECHO_ARG_OUT -Encoding utf8 -NoNewline'
      $quotedScript = ConvertTo-DotfilesWindowsQuotedArgument -Argument $echoScript

      foreach ($case in @('with space', 'with"quote', 'quote"then\backslash')) {
        $outFile = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
        $quotedCase = ConvertTo-DotfilesWindowsQuotedArgument -Argument $case
        $psi = [Diagnostics.ProcessStartInfo]::new($script:PwshPath)
        $psi.Arguments = "-NoProfile -File $quotedScript $quotedCase"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['ECHO_ARG_OUT'] = $outFile
        $proc = [Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Close()
        $null = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        Get-Content -LiteralPath $outFile -Raw | Should -Be $case
      }
    }
  }

  Context 'ConvertTo-DotfilesQuotedArgumentString' {
    It 'joins per-argument quoting with a space, quoting only where needed' {
      ConvertTo-DotfilesQuotedArgumentString -ArgumentList @('review', '--agent', '--base', 'with space') |
        Should -Be 'review --agent --base "with space"'
    }

    It 'returns an empty string for an empty argument list' {
      ConvertTo-DotfilesQuotedArgumentString -ArgumentList @() | Should -Be ''
    }
  }

  Context 'Start-DotfilesProcessWithTimeout (real process)' {
    It 'captures stdout and a zero exit code for a fast command' {
      $result = Start-DotfilesProcessWithTimeout -FilePath $script:PwshPath `
        -ArgumentList @('-NoProfile', '-Command', 'Write-Output "hello"; exit 0') `
        -TimeoutSeconds 10

      $result.TimedOut | Should -BeFalse
      $result.ExitCode | Should -Be 0
      $result.Stdout | Should -Match 'hello'
    }

    It 'captures a non-zero exit code' {
      $result = Start-DotfilesProcessWithTimeout -FilePath $script:PwshPath `
        -ArgumentList @('-NoProfile', '-Command', 'exit 7') `
        -TimeoutSeconds 10

      $result.TimedOut | Should -BeFalse
      $result.ExitCode | Should -Be 7
    }

    It 'kills a hanging process and reports TimedOut once the bound elapses' {
      $result = Start-DotfilesProcessWithTimeout -FilePath $script:PwshPath `
        -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30') `
        -TimeoutSeconds 1

      $result.TimedOut | Should -BeTrue
    }

    It 'captures stdout and stderr as separate fields, without cross-contamination' {
      $result = Start-DotfilesProcessWithTimeout -FilePath $script:PwshPath `
        -ArgumentList @(
          '-NoProfile', '-Command',
          "Write-Output 'stdout-marker-text'; [Console]::Error.WriteLine('stderr-marker-text')"
        ) -TimeoutSeconds 10

      $result.Stdout | Should -Match 'stdout-marker-text'
      $result.Stdout | Should -Not -Match 'stderr-marker-text'
      $result.Stderr | Should -Match 'stderr-marker-text'
      $result.Stderr | Should -Not -Match 'stdout-marker-text'
    }
  }

  Context 'Invoke-DotfilesCoderabbitReviewWithTimeout' {
    It 'invokes the bounded primitive with the coderabbit review --agent --base arguments' {
      Mock Start-DotfilesProcessWithTimeout {
        [pscustomobject]@{ TimedOut = $false; ExitCode = 0; Stdout = '{}'; Stderr = '' }
      }
      $cmd = [pscustomobject]@{ Name = '/usr/bin/coderabbit' }

      Invoke-DotfilesCoderabbitReviewWithTimeout -CoderabbitCommand $cmd `
        -BaseBranch 'main' -TimeoutSeconds 42 | Out-Null

      Should -Invoke Start-DotfilesProcessWithTimeout -Times 1 -ParameterFilter {
        $FilePath -eq '/usr/bin/coderabbit' -and
        $TimeoutSeconds -eq 42 -and
        ($ArgumentList -join ' ') -eq 'review --agent --base main'
      }
    }
  }

  Context 'Test-DotfilesActionRequiredType' {
    It 'returns $false for an empty string' {
      Test-DotfilesActionRequiredType -Text '' | Should -BeFalse
    }

    It 'returns $false for non-JSON text' {
      Test-DotfilesActionRequiredType -Text 'diagnostic noise on stderr' |
        Should -BeFalse
    }

    It 'returns $true for a compact top-level action_required object' {
      Test-DotfilesActionRequiredType `
        -Text '{"type":"action_required","phase":"billing"}' | Should -BeTrue
    }

    It 'returns $true for a pretty-printed action_required object with whitespace around the marker' {
      $text = "{`n  `"type`" : `"action_required`",`n  `"phase`": `"billing`"`n}"
      Test-DotfilesActionRequiredType -Text $text | Should -BeTrue
    }

    It 'returns $false for a top-level finding, even with a nested action_required type field' {
      $text = '{"type":"finding","message":"example",' +
        '"example":{"type":"action_required","phase":"billing"}}'
      Test-DotfilesActionRequiredType -Text $text | Should -BeFalse
    }

    It 'returns $false when the top-level type does not case-sensitively match' {
      Test-DotfilesActionRequiredType -Text '{"type":"Action_Required"}' |
        Should -BeFalse
    }

    It 'returns $false for a single-element top-level array wrapping an action_required object' {
      # Regression guard: ConvertFrom-Json's pipeline output silently
      # unwraps a single-element array into a bare object on assignment,
      # so a naive `-is [pscustomobject]` check on the *parsed* result
      # alone would wrongly treat this the same as a genuine top-level
      # object (see the function's own comment).
      Test-DotfilesActionRequiredType `
        -Text '[{"type":"action_required","reason":"a"}]' | Should -BeFalse
    }

    It 'returns $false for a multi-element top-level array containing an action_required object' {
      Test-DotfilesActionRequiredType `
        -Text '[{"type":"action_required"},{"type":"finding"}]' |
        Should -BeFalse
    }

    It 'returns $false when the top-level key differs from "type" only by case' {
      # Regression guard: PowerShell property access (`$parsed.type`) is
      # case-insensitive and would resolve a "Type" key just as readily,
      # but jq's `.type` key lookup on the shell twin would not -- a
      # bare value-comparison fix alone would leave this diverging from
      # the shell twin (see the function's own comment).
      Test-DotfilesActionRequiredType -Text '{"Type":"action_required"}' |
        Should -BeFalse
    }

    It 'returns $false for an array-valued top-level type property' {
      # Regression guard (CodeRabbit review on this PR): PowerShell's
      # `-ceq` performs an element-wise comparison when its left operand
      # is a collection, so an unguarded comparison against
      # `$typeProperty.Value` would return a truthy (non-empty) result
      # for `{"type":["action_required"]}` even though the top-level
      # `type` property is not itself the string `action_required`.
      Test-DotfilesActionRequiredType -Text '{"type":["action_required"]}' |
        Should -BeFalse
    }

    It 'returns $false for a number-valued top-level type property' {
      Test-DotfilesActionRequiredType -Text '{"type":42}' | Should -BeFalse
    }

    It 'returns $false for a boolean-valued top-level type property' {
      Test-DotfilesActionRequiredType -Text '{"type":true}' | Should -BeFalse
    }
  }

  Context 'Invoke-DotfilesCoderabbitCritique (orchestration)' {
    It 'fails when coderabbit is not found' {
      Mock Get-DotfilesCoderabbitCommand { $null }

      $result = Invoke-DotfilesCoderabbitCritique 3>&1
      ($result | Where-Object { $_ -is [pscustomobject] }).Success | Should -BeFalse
    }

    It 'fails without attempting a review when not authenticated' {
      Mock Get-DotfilesCoderabbitCommand { [pscustomobject]@{ Name = 'coderabbit' } }
      Mock Test-DotfilesCoderabbitAuthenticated { $false }
      Mock Invoke-DotfilesCoderabbitReviewWithTimeout { throw 'must not be called' }

      $result = Invoke-DotfilesCoderabbitCritique 3>&1
      ($result | Where-Object { $_ -is [pscustomobject] }).Success | Should -BeFalse
    }

    It 'fails when the base branch cannot be resolved' {
      Mock Get-DotfilesCoderabbitCommand { [pscustomobject]@{ Name = 'coderabbit' } }
      Mock Test-DotfilesCoderabbitAuthenticated { $true }
      Mock Resolve-DotfilesCoderabbitBaseBranch { $null }
      Mock Invoke-DotfilesCoderabbitReviewWithTimeout { throw 'must not be called' }

      $result = Invoke-DotfilesCoderabbitCritique 3>&1
      ($result | Where-Object { $_ -is [pscustomobject] }).Success | Should -BeFalse
    }

    It 'fails when the review times out' {
      Mock Get-DotfilesCoderabbitCommand { [pscustomobject]@{ Name = 'coderabbit' } }
      Mock Test-DotfilesCoderabbitAuthenticated { $true }
      Mock Resolve-DotfilesCoderabbitBaseBranch { 'master' }
      Mock Invoke-DotfilesCoderabbitReviewWithTimeout {
        [pscustomobject]@{ TimedOut = $true; ExitCode = -1; Stdout = ''; Stderr = '' }
      }

      $result = Invoke-DotfilesCoderabbitCritique 3>&1
      ($result | Where-Object { $_ -is [pscustomobject] }).Success | Should -BeFalse
    }

    It 'fails when the review exits non-zero' {
      Mock Get-DotfilesCoderabbitCommand { [pscustomobject]@{ Name = 'coderabbit' } }
      Mock Test-DotfilesCoderabbitAuthenticated { $true }
      Mock Resolve-DotfilesCoderabbitBaseBranch { 'master' }
      Mock Invoke-DotfilesCoderabbitReviewWithTimeout {
        [pscustomobject]@{ TimedOut = $false; ExitCode = 1; Stdout = ''; Stderr = 'boom' }
      }

      $result = Invoke-DotfilesCoderabbitCritique 3>&1
      ($result | Where-Object { $_ -is [pscustomobject] }).Success | Should -BeFalse
    }

    It 'rejects an action_required response' {
      Mock Get-DotfilesCoderabbitCommand { [pscustomobject]@{ Name = 'coderabbit' } }
      Mock Test-DotfilesCoderabbitAuthenticated { $true }
      Mock Resolve-DotfilesCoderabbitBaseBranch { 'master' }
      Mock Invoke-DotfilesCoderabbitReviewWithTimeout {
        [pscustomobject]@{
          TimedOut = $false; ExitCode = 0
          Stdout   = '{"type":"action_required","phase":"billing"}'
          Stderr   = ''
        }
      }

      $result = Invoke-DotfilesCoderabbitCritique 3>&1
      ($result | Where-Object { $_ -is [pscustomobject] }).Success | Should -BeFalse
    }

    It 'rejects a pretty-printed action_required response with whitespace around the marker' {
      Mock Get-DotfilesCoderabbitCommand { [pscustomobject]@{ Name = 'coderabbit' } }
      Mock Test-DotfilesCoderabbitAuthenticated { $true }
      Mock Resolve-DotfilesCoderabbitBaseBranch { 'master' }
      Mock Invoke-DotfilesCoderabbitReviewWithTimeout {
        [pscustomobject]@{
          TimedOut = $false; ExitCode = 0
          Stdout   = "{`n  `"type`" : `"action_required`",`n  `"phase`": `"billing`"`n}"
          Stderr   = ''
        }
      }

      $result = Invoke-DotfilesCoderabbitCritique 3>&1
      ($result | Where-Object { $_ -is [pscustomobject] }).Success | Should -BeFalse
    }

    It 'rejects an action_required response found only on stderr' {
      Mock Get-DotfilesCoderabbitCommand { [pscustomobject]@{ Name = 'coderabbit' } }
      Mock Test-DotfilesCoderabbitAuthenticated { $true }
      Mock Resolve-DotfilesCoderabbitBaseBranch { 'master' }
      Mock Invoke-DotfilesCoderabbitReviewWithTimeout {
        [pscustomobject]@{
          TimedOut = $false; ExitCode = 0
          Stdout   = ''
          Stderr   = '{"type":"action_required","phase":"billing"}'
        }
      }

      $result = Invoke-DotfilesCoderabbitCritique 3>&1
      ($result | Where-Object { $_ -is [pscustomobject] }).Success | Should -BeFalse
    }

    It 'does not trip on an unescaped nested action_required type field inside a finding' {
      Mock Get-DotfilesCoderabbitCommand { [pscustomobject]@{ Name = 'coderabbit' } }
      Mock Test-DotfilesCoderabbitAuthenticated { $true }
      Mock Resolve-DotfilesCoderabbitBaseBranch { 'master' }
      Mock Invoke-DotfilesCoderabbitReviewWithTimeout {
        [pscustomobject]@{
          TimedOut = $false; ExitCode = 0
          Stdout   = '{"type":"finding","message":"example","example":{"type":"action_required","phase":"billing"}}'
          Stderr   = ''
        }
      }

      $result = Invoke-DotfilesCoderabbitCritique 3>&1
      $outcome = $result | Where-Object { $_ -is [pscustomobject] }
      $outcome.Success | Should -BeTrue
      $outcome.Output | Should -Match '"type":"finding"'
    }

    It 'succeeds and passes through a clean structured-findings response' {
      Mock Get-DotfilesCoderabbitCommand { [pscustomobject]@{ Name = 'coderabbit' } }
      Mock Test-DotfilesCoderabbitAuthenticated { $true }
      Mock Resolve-DotfilesCoderabbitBaseBranch { 'master' }
      Mock Invoke-DotfilesCoderabbitReviewWithTimeout {
        [pscustomobject]@{
          TimedOut = $false; ExitCode = 0
          Stdout   = '{"type":"finding","message":"example issue"}'
          Stderr   = ''
        }
      }

      $result = Invoke-DotfilesCoderabbitCritique

      $result.Success | Should -BeTrue
      $result.Output | Should -Match '"type":"finding"'
    }

    It 'keeps stderr out of the successful findings output' {
      Mock Get-DotfilesCoderabbitCommand { [pscustomobject]@{ Name = 'coderabbit' } }
      Mock Test-DotfilesCoderabbitAuthenticated { $true }
      Mock Resolve-DotfilesCoderabbitBaseBranch { 'master' }
      Mock Invoke-DotfilesCoderabbitReviewWithTimeout {
        [pscustomobject]@{
          TimedOut = $false; ExitCode = 0
          Stdout   = '{"type":"finding","message":"stdout marker text"}'
          Stderr   = 'stderr marker text'
        }
      }

      # This asserts only that Output excludes Stderr text -- it cannot
      # also assert that Stderr is actually forwarded somewhere, since
      # the production code forwards it via [Console]::Error directly
      # (bypassing PowerShell's own streams entirely, precisely so a
      # non-interactive pwsh host can't silently reroute it onto real
      # stdout the way Write-Warning used to -- see the comment at the top
      # of Invoke-DotfilesCoderabbitCritique). That real-fd-level
      # forwarding is covered instead by the Unix-only "Full script as a
      # real subprocess" context below, which spawns a genuine OS process
      # and reads its actual redirected stderr handle; on Windows this
      # specific forwarding path is
      # exercised only up to this mock boundary (see that context's own
      # comment for why a Windows-real-process equivalent isn't safe to
      # add here).
      $result = Invoke-DotfilesCoderabbitCritique

      $result.Success | Should -BeTrue
      $result.Output | Should -Match 'stdout marker text'
      $result.Output | Should -Not -Match 'stderr marker text'
    }
  }

  Context 'Full script as a real subprocess (stdout/stderr separation, Unix pwsh)' -Skip:($IsWindows -ne $false) {
    # Every other test in this file dot-sources the script with
    # DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN=1 and mocks internal
    # functions -- necessary because the script's own top-level `exit`
    # would otherwise terminate the whole Pester run if invoked in-process
    # (`&`/dot-sourcing a script that calls `exit` kills the host, not
    # just that script's scope). Proving the real OS-level stdout/stderr
    # separation this issue is about requires a genuine child process, so
    # this context spawns $script:PwshPath -File $script:Subject as an
    # actual subprocess instead, with a fake `coderabbit` executable
    # placed on $env:PATH. This composes two patterns already proven
    # elsewhere in this repo rather than inventing new infrastructure: the
    # $env:PATH save/restore-in-finally idiom (from
    # 90-reconcile-claude-code.Tests.ps1) and process-spawn-with-
    # redirected-streams (already used by this file's own "real process"
    # tests above).
    #
    # Unix-only (mirrors the existing "02-cargo (Unix pwsh)" -Skip
    # convention): a Windows fake-`coderabbit` fixture would need a
    # `.cmd` batch file, since arbitrary script content can't be an
    # `.exe`, but `Start-DotfilesProcessWithTimeout` launches the
    # reviewed process via raw `[Diagnostics.Process]::Start()` with
    # `UseShellExecute = $false` -- and per CreateProcess's own
    # documented contract, that path never runs `.bat`/`.cmd` files
    # directly; only cmd.exe itself can (the same limitation Node's
    # `cross-spawn` package exists to paper over). Unlike
    # 90-reconcile-claude-code.Tests.ps1's `claude.cmd` fixture, which
    # this script's own comment (elsewhere in this repo) launches via the
    # `&` call operator, this script's `[Diagnostics.Process]::Start()`
    # call cannot be swapped for `&` here (that's the exact mechanism it
    # deliberately bypasses to sidestep PowerShell function-shadowing),
    # so a `.cmd`-based fixture would not exercise the real path and
    # could not be verified from this repo's Linux-only implementation
    # environment. Whether the production `coderabbit` review path itself
    # can invoke an npm-style `.cmd` shim on Windows is a separate,
    # pre-existing question outside this issue's scope.
    BeforeEach {
      $script:FakeBinDir = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
      New-Item -ItemType Directory -Path $script:FakeBinDir -Force | Out-Null
      $script:FakeCoderabbitPath = Join-Path $script:FakeBinDir 'coderabbit'
      $content = "#!/bin/sh`n" +
        "if [ `"`$1`" = auth ] && [ `"`$2`" = status ]; then`n" +
        "  echo `"Account: fake-user`"`n" +
        "  exit 0`n" +
        "fi`n" +
        "echo STDOUT_MARKER_TEXT`n" +
        "echo STDERR_MARKER_TEXT >&2`n" +
        "exit 0`n"
      [System.IO.File]::WriteAllText($script:FakeCoderabbitPath, $content, [System.Text.ASCIIEncoding]::new())
      & chmod +x $script:FakeCoderabbitPath
    }

    It 'keeps the reviewed process''s stderr out of the delegate''s own stdout on success' {
      $originalPath = $env:PATH
      $originalSkip = $env:DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN
      try {
        $env:PATH = "$script:FakeBinDir$([IO.Path]::PathSeparator)$env:PATH"
        # The outer BeforeEach sets this to '1' for every other test in
        # this file so dot-sourcing never runs main; this child process
        # must NOT inherit that, or its own top-level exit-guarded block
        # -- the only place that produces real process output -- never
        # runs at all.
        Remove-Item Env:\DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN -ErrorAction SilentlyContinue
        $env:CODERABBIT_CRITIQUE_BASE = 'master'

        $psi = [Diagnostics.ProcessStartInfo]::new($script:PwshPath)
        $psi.Arguments = ConvertTo-DotfilesQuotedArgumentString `
          -ArgumentList @('-NoProfile', '-File', $script:Subject)
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $proc = [Diagnostics.Process]::Start($psi)
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()
        $stdoutText = $stdoutTask.GetAwaiter().GetResult()
        $stderrText = $stderrTask.GetAwaiter().GetResult()
      } finally {
        $env:PATH = $originalPath
        if ($originalSkip) {
          $env:DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN = $originalSkip
        }
      }

      $proc.ExitCode | Should -Be 0
      $stdoutText | Should -Match 'STDOUT_MARKER_TEXT'
      $stdoutText | Should -Not -Match 'STDERR_MARKER_TEXT'
      $stderrText | Should -Match 'STDERR_MARKER_TEXT'
    }
  }

  Context 'Full script as a real subprocess (diagnostic-to-stderr scenarios, Unix pwsh)' -Skip:($IsWindows -ne $false) {
    # Same rationale and Unix-only constraint as the "Full script as a real
    # subprocess" context above: only a genuine child process, run under
    # `pwsh -File`'s actual host routing, can prove a diagnostic never
    # leaks onto real stdout -- the in-process dot-sourced mocks every
    # other test in this file uses cannot reproduce that host quirk. This
    # context drives one configurable fake `coderabbit` fixture (behavior
    # selected via environment variables) through each of the 6 scenarios
    # that used to call `Write-Warning` before this issue's fix converted
    # them to `[Console]::Error.WriteLine`, instead of one fixture file
    # per scenario.
    BeforeAll {
      # Spawns $script:Subject as a real subprocess with an isolated,
      # scenario-specific environment, and returns its captured
      # ExitCode/Stdout/Stderr. Always clears
      # DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN/CODERABBIT_CRITIQUE_BASE/
      # CODERABBIT_CRITIQUE_TIMEOUT first -- the outer file-level BeforeEach
      # sets the SKIP_MAIN one for every in-process test in this file, but
      # this child process must not inherit it, or its own top-level
      # exit-guarded block (the only place that produces real process
      # output) never runs -- then applies $EnvironmentOverrides on top.
      function script:Invoke-DotfilesSubjectAsSubprocess {
        param([hashtable] $EnvironmentOverrides = @{})

        # The fake coderabbit fixture's own scenario-selector variables --
        # cleared unconditionally before every run (not just restored to
        # their prior value like the three named ones below) so a variable
        # set by one scenario's $EnvironmentOverrides can never leak into
        # the next scenario's run.
        $fakeVarNames = @(
          'FAKE_AUTH_SIGNED_OUT', 'FAKE_REVIEW_SLEEP', 'FAKE_REVIEW_STDOUT',
          'FAKE_REVIEW_STDERR', 'FAKE_REVIEW_EXIT'
        )

        $originalPath = $env:PATH
        $originalSkip = $env:DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN
        $originalBase = $env:CODERABBIT_CRITIQUE_BASE
        $originalTimeout = $env:CODERABBIT_CRITIQUE_TIMEOUT
        try {
          Remove-Item Env:\DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN -ErrorAction SilentlyContinue
          Remove-Item Env:\CODERABBIT_CRITIQUE_BASE -ErrorAction SilentlyContinue
          Remove-Item Env:\CODERABBIT_CRITIQUE_TIMEOUT -ErrorAction SilentlyContinue
          foreach ($name in $fakeVarNames) {
            Remove-Item "Env:\$name" -ErrorAction SilentlyContinue
          }
          foreach ($key in $EnvironmentOverrides.Keys) {
            Set-Item -Path "Env:\$key" -Value $EnvironmentOverrides[$key]
          }

          $psi = [Diagnostics.ProcessStartInfo]::new($script:PwshPath)
          $psi.Arguments = ConvertTo-DotfilesQuotedArgumentString `
            -ArgumentList @('-NoProfile', '-File', $script:Subject)
          $psi.WorkingDirectory = $TestDrive
          $psi.UseShellExecute = $false
          $psi.RedirectStandardOutput = $true
          $psi.RedirectStandardError = $true
          $psi.CreateNoWindow = $true
          $proc = [Diagnostics.Process]::Start($psi)
          $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
          $stderrTask = $proc.StandardError.ReadToEndAsync()
          $proc.WaitForExit()
          return [pscustomobject]@{
            ExitCode = $proc.ExitCode
            Stdout   = $stdoutTask.GetAwaiter().GetResult()
            Stderr   = $stderrTask.GetAwaiter().GetResult()
          }
        } finally {
          $env:PATH = $originalPath
          # $null checks, not truthiness -- matching the outer AfterEach's
          # own pattern below. A truthy check (`if ($original...)`) would
          # treat a captured empty string the same as unset and skip
          # restoring it, silently changing the environment from what the
          # test actually started with.
          if ($null -eq $originalSkip) {
            Remove-Item Env:\DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN -ErrorAction SilentlyContinue
          } else {
            $env:DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN = $originalSkip
          }
          if ($null -eq $originalBase) {
            Remove-Item Env:\CODERABBIT_CRITIQUE_BASE -ErrorAction SilentlyContinue
          } else {
            $env:CODERABBIT_CRITIQUE_BASE = $originalBase
          }
          if ($null -eq $originalTimeout) {
            Remove-Item Env:\CODERABBIT_CRITIQUE_TIMEOUT -ErrorAction SilentlyContinue
          } else {
            $env:CODERABBIT_CRITIQUE_TIMEOUT = $originalTimeout
          }
          foreach ($name in $fakeVarNames) {
            Remove-Item "Env:\$name" -ErrorAction SilentlyContinue
          }
        }
      }
    }

    BeforeEach {
      # A single fixture covers scenarios 2, 4, 5, and 6 below (auth,
      # timeout, non-zero exit, action_required) by branching on env vars
      # the test sets before each subprocess run; scenario 1 (not found)
      # and 3 (base branch unresolved) rely on this fixture's *absence*
      # from PATH instead (or, for 3, `git`'s absence -- see that test).
      $script:FakeBinDir = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
      New-Item -ItemType Directory -Path $script:FakeBinDir -Force | Out-Null
      $script:FakeCoderabbitPath = Join-Path $script:FakeBinDir 'coderabbit'
      $content = @'
#!/bin/sh
if [ "$1" = auth ] && [ "$2" = status ]; then
  if [ -n "$FAKE_AUTH_SIGNED_OUT" ]; then
    echo "Status       : signed out"
  else
    echo "Account: fake-user"
  fi
  exit 0
fi
if [ -n "$FAKE_REVIEW_SLEEP" ]; then
  sleep "$FAKE_REVIEW_SLEEP"
fi
if [ -n "$FAKE_REVIEW_STDOUT" ]; then
  printf '%s' "$FAKE_REVIEW_STDOUT"
fi
if [ -n "$FAKE_REVIEW_STDERR" ]; then
  printf '%s' "$FAKE_REVIEW_STDERR" >&2
fi
exit "${FAKE_REVIEW_EXIT:-0}"
'@
      [System.IO.File]::WriteAllText($script:FakeCoderabbitPath, $content, [System.Text.ASCIIEncoding]::new())
      & chmod +x $script:FakeCoderabbitPath

      # An isolated, empty directory: guarantees no real `coderabbit` (or
      # `git`, for scenario 3) can be found on PATH regardless of what the
      # host running these tests happens to have installed.
      $script:EmptyBinDir = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
      New-Item -ItemType Directory -Path $script:EmptyBinDir -Force | Out-Null
    }

    It 'produces no stdout when coderabbit is not found in PATH' {
      $result = Invoke-DotfilesSubjectAsSubprocess -EnvironmentOverrides @{
        PATH = $script:EmptyBinDir
      }

      $result.ExitCode | Should -Be 1
      $result.Stdout | Should -BeNullOrEmpty
      $result.Stderr | Should -Match 'coderabbit not found in PATH'
    }

    It 'produces no stdout when coderabbit is not authenticated' {
      $result = Invoke-DotfilesSubjectAsSubprocess -EnvironmentOverrides @{
        PATH                 = $script:FakeBinDir
        FAKE_AUTH_SIGNED_OUT = '1'
      }

      $result.ExitCode | Should -Be 1
      $result.Stdout | Should -BeNullOrEmpty
      $result.Stderr | Should -Match 'coderabbit is not authenticated'
    }

    It 'produces no stdout when the base branch cannot be resolved' {
      # No `git` on PATH (the fake bin dir holds only `coderabbit`) and no
      # CODERABBIT_CRITIQUE_BASE override: Get-Command git returns $null
      # inside Resolve-DotfilesCoderabbitBaseBranch, so this fails
      # deterministically regardless of the real host's own git/branch
      # state.
      $result = Invoke-DotfilesSubjectAsSubprocess -EnvironmentOverrides @{
        PATH = $script:FakeBinDir
      }

      $result.ExitCode | Should -Be 1
      $result.Stdout | Should -BeNullOrEmpty
      $result.Stderr | Should -Match 'could not determine the default base branch'
    }

    It 'produces no stdout when the review times out' {
      # Unlike the other scenarios, the fake fixture's own `sleep` call
      # needs a real `sleep` binary resolvable on PATH, so this one
      # prepends the fixture dir to the real PATH instead of isolating it
      # -- real `git` being reachable is harmless here since
      # CODERABBIT_CRITIQUE_BASE is set explicitly, short-circuiting any
      # git lookup.
      $result = Invoke-DotfilesSubjectAsSubprocess -EnvironmentOverrides @{
        PATH                        = "$script:FakeBinDir$([IO.Path]::PathSeparator)$env:PATH"
        CODERABBIT_CRITIQUE_BASE    = 'master'
        CODERABBIT_CRITIQUE_TIMEOUT = '1'
        FAKE_REVIEW_SLEEP           = '10'
      }

      $result.ExitCode | Should -Be 1
      $result.Stdout | Should -BeNullOrEmpty
      $result.Stderr | Should -Match 'coderabbit review timed out after 1s'
    }

    It 'produces no stdout when the review exits non-zero' {
      $result = Invoke-DotfilesSubjectAsSubprocess -EnvironmentOverrides @{
        PATH                     = $script:FakeBinDir
        CODERABBIT_CRITIQUE_BASE = 'master'
        FAKE_REVIEW_EXIT         = '7'
      }

      $result.ExitCode | Should -Be 1
      $result.Stdout | Should -BeNullOrEmpty
      $result.Stderr | Should -Match 'coderabbit review failed \(exit 7\)'
    }

    It 'produces no stdout when the review reports action_required' {
      $result = Invoke-DotfilesSubjectAsSubprocess -EnvironmentOverrides @{
        PATH                     = $script:FakeBinDir
        CODERABBIT_CRITIQUE_BASE = 'master'
        FAKE_REVIEW_STDOUT       = '{"type":"action_required","phase":"billing"}'
      }

      $result.ExitCode | Should -Be 1
      $result.Stdout | Should -BeNullOrEmpty
      $result.Stderr | Should -Match 'coderabbit review requires operator action'
    }
  }

  Context 'No git mutation' {
    It 'never invokes a git subcommand other than symbolic-ref/rev-parse across the orchestration' {
      $script:GitCalls = [System.Collections.Generic.List[string]]::new()
      function script:coderabbit {
        if ($args[0] -eq 'auth') { 'Account: test'; return }
        '{"type":"finding"}'
      }
      function script:git {
        $script:GitCalls.Add(($args -join ' '))
        $global:LASTEXITCODE = 1
      }
      Mock Get-Command {
        [pscustomobject]@{ Name = 'coderabbit'; CommandType = 'Function' }
      } -ParameterFilter { $Name -eq 'coderabbit' }
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git'; CommandType = 'Function' }
      } -ParameterFilter { $Name -eq 'git' }

      Invoke-DotfilesCoderabbitCritique 3>&1 | Out-Null

      $script:GitCalls.Count | Should -BeGreaterThan 0
      $script:GitCalls | ForEach-Object {
        $_ | Should -Match '^(symbolic-ref|rev-parse)\b'
      }
    }
  }
}
