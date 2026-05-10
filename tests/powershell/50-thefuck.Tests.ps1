# Tests for the PowerShell thefuck initialization script.
# Exercises: early exit, alias evaluation, exception handling, cleanup.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '50-thefuck.ps1'
}

Describe '50-thefuck' {

  BeforeEach {
    Remove-Variable _tfAlias -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable TheFuckInitialized -Scope Script -ErrorAction SilentlyContinue
  }

  AfterEach {
    Remove-Variable _tfAlias -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable TheFuckInitialized -Scope Script -ErrorAction SilentlyContinue
    Remove-Item Function:\thefuck -ErrorAction SilentlyContinue
  }

  It 'returns early without error when thefuck is not available' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'thefuck' }

    { . $script:Subject } | Should -Not -Throw
  }

  It 'evaluates alias output when thefuck is available' {
    function thefuck {
      '$script:TheFuckInitialized = $true'
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'thefuck'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'thefuck' }

    . $script:Subject

    $script:TheFuckInitialized | Should -BeTrue
  }

  It 'handles thefuck --alias throwing an exception gracefully' {
    function thefuck { throw 'Python error' }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'thefuck'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'thefuck' }

    { . $script:Subject } | Should -Not -Throw
  }

  It 'cleans up the _tfAlias variable after execution' {
    function thefuck {
      '$script:TheFuckInitialized = $true'
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'thefuck'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'thefuck' }

    . $script:Subject

    Get-Variable _tfAlias -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
  }
}
