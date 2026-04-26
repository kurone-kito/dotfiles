# Tests for the PowerShell worktrunk initialization script.
# Exercises: early exit, command fallback, init evaluation, trailing-zero
# stripping, and cleanup.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '45-worktrunk.ps1'
}

Describe '45-worktrunk' {

  BeforeEach {
    Remove-Variable __wtCmd -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __wtInit -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkInitialized -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkCommand -Scope Script -ErrorAction SilentlyContinue

    Mock Get-Command { $null } -ParameterFilter { $Name -in @('git-wt', 'wt') }
  }

  AfterEach {
    Remove-Variable __wtCmd -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __wtInit -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkInitialized -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkCommand -Scope Script -ErrorAction SilentlyContinue
    Remove-Item Function:\git-wt -ErrorAction SilentlyContinue
    Remove-Item Function:\wt -ErrorAction SilentlyContinue
  }

  It 'returns early without error when neither git-wt nor wt is available' {
    { . $script:Subject } | Should -Not -Throw
  }

  It 'evaluates init output when git-wt is available' {
    function git-wt {
      @('$script:WorktrunkInitialized = $true', '$script:WorktrunkCommand = "git-wt"')
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
    $script:WorktrunkCommand | Should -Be 'git-wt'
  }

  It 'falls back to wt when git-wt is not available' {
    function wt {
      @('$script:WorktrunkInitialized = $true', '$script:WorktrunkCommand = "wt"')
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'wt'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
    $script:WorktrunkCommand | Should -Be 'wt'
  }

  It 'prefers git-wt when both git-wt and wt are available' {
    function git-wt {
      @('$script:WorktrunkInitialized = $true', '$script:WorktrunkCommand = "git-wt"')
    }
    function wt {
      @('$script:WorktrunkInitialized = $true', '$script:WorktrunkCommand = "wt"')
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'git-wt' }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'wt'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
    $script:WorktrunkCommand | Should -Be 'git-wt'
  }

  It 'strips trailing zero lines from init output before evaluation' {
    function git-wt {
      @('$script:WorktrunkInitialized = $true', '0')
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
  }

  It 'cleans up temporary variables after execution' {
    function git-wt {
      '$script:WorktrunkInitialized = $true'
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    Get-Variable __wtCmd -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __wtInit -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
  }
}
