# Tests for ghq-clone-user.ps1 standalone script.
BeforeAll {
  $Script = Join-Path $PSScriptRoot '..\..\home\dot_local\bin\executable_ghq-clone-user.ps1'
}

Describe 'ghq-clone-user.ps1' {
  BeforeEach {
    $testRoot = Join-Path $TestDrive 'ghq-root'
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
  }

  Context 'when gh is not available' {
    BeforeAll {
      Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gh' }
      Mock Get-Command { $null } -ParameterFilter { $Name -eq 'mise' }
      Mock Get-Command {
        [PSCustomObject]@{ Source = 'ghq' }
      } -ParameterFilter { $Name -eq 'ghq' }
    }

    It 'exits with an error' {
      { & $Script -Owner testuser } | Should -Throw '*gh not found*'
    }
  }

  Context 'when ghq is not available' {
    BeforeAll {
      Mock Get-Command { $null } -ParameterFilter { $Name -eq 'ghq' }
      Mock Get-Command { $null } -ParameterFilter { $Name -eq 'mise' }
      Mock Get-Command {
        [PSCustomObject]@{ Source = 'gh' }
      } -ParameterFilter { $Name -eq 'gh' }
    }

    It 'exits with an error' {
      { & $Script -Owner testuser } | Should -Throw '*ghq not found*'
    }
  }

  Context 'parameter validation' {
    It 'rejects mutually exclusive --Ssh and --Https' {
      { & $Script -Owner testuser -Ssh -Https } |
        Should -Throw '*mutually exclusive*'
    }
  }

  Context 'when both tools are available' {
    BeforeAll {
      function script:MockGhq {
        param([Parameter(ValueFromRemainingArguments)]$args)
        if ($args[0] -eq 'root') { return $testRoot }
      }
      function script:MockGh {
        param([Parameter(ValueFromRemainingArguments)]$args)
        if ($args[0] -eq 'repo' -and $args[1] -eq 'list') {
          return "testuser/repo-a`ntestuser/repo-b"
        }
      }
    }

    It 'requires Owner parameter' {
      { & $Script } | Should -Throw
    }
  }
}
