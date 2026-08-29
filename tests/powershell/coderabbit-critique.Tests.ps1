# Tests for the PowerShell coderabbit-critique script: a read-only C1
# critiqueLoop.delegate findings adapter wrapping CodeRabbit CLI.
# Exercises: PATH detection, auth-status parsing, timeout/base-branch
# resolution, the bounded-execution primitive against a real process, and
# the top-level orchestration's success/failure branches.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/dot_local/bin/executable_coderabbit-critique.ps1'
  $script:PwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
}

Describe 'coderabbit-critique' {

  BeforeEach {
    $script:OriginalSkip = $env:DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN
    $script:OriginalTimeout = $env:CODERABBIT_CRITIQUE_TIMEOUT
    $script:OriginalBase = $env:CODERABBIT_CRITIQUE_BASE
    $env:DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN = '1'
    Remove-Item Env:\CODERABBIT_CRITIQUE_TIMEOUT -ErrorAction SilentlyContinue
    Remove-Item Env:\CODERABBIT_CRITIQUE_BASE -ErrorAction SilentlyContinue
    . $script:Subject
  }

  AfterEach {
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
      'Start-DotfilesProcessWithTimeout'
      'Invoke-DotfilesCoderabbitReviewWithTimeout'
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

    It 'returns $null when neither symbolic-ref nor origin/main nor origin/master resolve' {
      function script:git { $global:LASTEXITCODE = 1 }
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git'; CommandType = 'Function' }
      } -ParameterFilter { $Name -eq 'git' }

      Resolve-DotfilesCoderabbitBaseBranch | Should -BeNullOrEmpty
    }
  }

  Context 'Start-DotfilesProcessWithTimeout (real process)' {
    It 'captures stdout and a zero exit code for a fast command' {
      $result = Start-DotfilesProcessWithTimeout -FilePath $script:PwshPath `
        -ArgumentList @('-NoProfile', '-Command', 'Write-Output "hello"; exit 0') `
        -TimeoutSeconds 10

      $result.TimedOut | Should -BeFalse
      $result.ExitCode | Should -Be 0
      $result.Output | Should -Match 'hello'
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
  }

  Context 'Invoke-DotfilesCoderabbitReviewWithTimeout' {
    It 'invokes the bounded primitive with the coderabbit review --agent --base arguments' {
      Mock Start-DotfilesProcessWithTimeout {
        [pscustomobject]@{ TimedOut = $false; ExitCode = 0; Output = '{}' }
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
        [pscustomobject]@{ TimedOut = $true; ExitCode = -1; Output = '' }
      }

      $result = Invoke-DotfilesCoderabbitCritique 3>&1
      ($result | Where-Object { $_ -is [pscustomobject] }).Success | Should -BeFalse
    }

    It 'fails when the review exits non-zero' {
      Mock Get-DotfilesCoderabbitCommand { [pscustomobject]@{ Name = 'coderabbit' } }
      Mock Test-DotfilesCoderabbitAuthenticated { $true }
      Mock Resolve-DotfilesCoderabbitBaseBranch { 'master' }
      Mock Invoke-DotfilesCoderabbitReviewWithTimeout {
        [pscustomobject]@{ TimedOut = $false; ExitCode = 1; Output = 'boom' }
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
          Output   = '{"type":"action_required","phase":"billing"}'
        }
      }

      $result = Invoke-DotfilesCoderabbitCritique 3>&1
      ($result | Where-Object { $_ -is [pscustomobject] }).Success | Should -BeFalse
    }

    It 'succeeds and passes through a clean structured-findings response' {
      Mock Get-DotfilesCoderabbitCommand { [pscustomobject]@{ Name = 'coderabbit' } }
      Mock Test-DotfilesCoderabbitAuthenticated { $true }
      Mock Resolve-DotfilesCoderabbitBaseBranch { 'master' }
      Mock Invoke-DotfilesCoderabbitReviewWithTimeout {
        [pscustomobject]@{
          TimedOut = $false; ExitCode = 0
          Output   = '{"type":"finding","message":"example issue"}'
        }
      }

      $result = Invoke-DotfilesCoderabbitCritique

      $result.Success | Should -BeTrue
      $result.Output | Should -Match '"type":"finding"'
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
