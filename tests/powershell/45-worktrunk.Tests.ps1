# Tests for the PowerShell worktrunk (git-wt) initialization script.
# Exercises: early exit, init evaluation, trailing-zero stripping, cleanup.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '45-worktrunk.ps1'
}

Describe '45-worktrunk' {

  BeforeEach {
    Remove-Variable __wtInit -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkInitialized -Scope Script -ErrorAction SilentlyContinue
  }

  AfterEach {
    Remove-Variable __wtInit -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkInitialized -Scope Script -ErrorAction SilentlyContinue
    Remove-Item Function:\git-wt -ErrorAction SilentlyContinue
  }

  It 'returns early without error when git-wt is not available' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'git-wt' }

    { . $script:Subject } | Should -Not -Throw
  }

  It 'evaluates init output when git-wt is available' {
    function git-wt {
      '$script:WorktrunkInitialized = $true'
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
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

  It 'cleans up the __wtInit variable after execution' {
    function git-wt {
      '$script:WorktrunkInitialized = $true'
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    Get-Variable __wtInit -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
  }
}
