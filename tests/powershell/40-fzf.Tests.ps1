# Tests for the PowerShell PSFzf integration script.
# Exercises: startup-helper registration and direct fallback bindings.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '40-fzf.ps1'
}

Describe '40-fzf' {

  AfterEach {
    Remove-Item Function:\Invoke-DotfilesPSReadLineStartupAction -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-PsFzfOption -ErrorAction SilentlyContinue
  }

  It 'registers PSFzf chords through the startup helper when available' {
    function Invoke-DotfilesPSReadLineStartupAction {
      param([string]$Name, [scriptblock]$Action)
    }

    function Set-PsFzfOption {
      param(
        [string]$PSReadlineChordProvider,
        [string]$PSReadlineChordReverseHistory
      )
    }

    Mock Get-Command { [pscustomobject]@{ Name = 'fzf' } } -ParameterFilter {
      $Name -eq 'fzf'
    }
    Mock Get-Module { [pscustomobject]@{ Name = 'PSFzf' } } -ParameterFilter {
      $Name -eq 'PSFzf' -and $ListAvailable
    }
    Mock Import-Module { }
    Mock Invoke-DotfilesPSReadLineStartupAction {
      param([string]$Name, [scriptblock]$Action)
      & $Action | Out-Null
      $true
    }
    Mock Set-PsFzfOption { }

    . $script:Subject

    Assert-MockCalled Invoke-DotfilesPSReadLineStartupAction -Times 1 -ParameterFilter {
      $Name -eq 'psfzf-chords'
    }
    Assert-MockCalled Set-PsFzfOption -Times 1 -ParameterFilter {
      $PSReadlineChordProvider -eq 'Ctrl+t' -and
      $PSReadlineChordReverseHistory -eq 'Ctrl+r'
    }
  }

  It 'falls back to direct PSReadLine chord setup when the startup helper is unavailable' {
    function Set-PsFzfOption {
      param(
        [string]$PSReadlineChordProvider,
        [string]$PSReadlineChordReverseHistory
      )
    }

    Mock Get-Command { [pscustomobject]@{ Name = 'fzf' } } -ParameterFilter {
      $Name -eq 'fzf'
    }
    Mock Get-Command { $null } -ParameterFilter {
      $Name -eq 'Invoke-DotfilesPSReadLineStartupAction'
    }
    Mock Get-Module { [pscustomobject]@{ Name = 'PSFzf' } } -ParameterFilter {
      $Name -eq 'PSFzf' -and $ListAvailable
    }
    Mock Get-Module { [pscustomobject]@{ Name = 'PSReadLine' } } -ParameterFilter {
      $Name -eq 'PSReadLine' -and -not $ListAvailable
    }
    Mock Import-Module { }
    Mock Set-PsFzfOption { }

    . $script:Subject

    Assert-MockCalled Set-PsFzfOption -Times 1 -ParameterFilter {
      $PSReadlineChordProvider -eq 'Ctrl+t' -and
      $PSReadlineChordReverseHistory -eq 'Ctrl+r'
    }
  }
}

Describe 'VS Code chord skip' {

  BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $envScript = Join-Path (
      (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
    ) '00-env.ps1'
    $script:OriginalSkipInit = $env:DOTFILES_TEST_PSREADLINE_SKIP_INIT
    $env:DOTFILES_TEST_PSREADLINE_SKIP_INIT = '1'
    . $envScript
  }

  BeforeEach {
    $script:savedTermProgram = $env:TERM_PROGRAM
  }

  AfterEach {
    $env:TERM_PROGRAM = $script:savedTermProgram
    Remove-Item Function:\Set-PsFzfOption -ErrorAction SilentlyContinue
  }

  AfterAll {
    $env:DOTFILES_TEST_PSREADLINE_SKIP_INIT = $script:OriginalSkipInit

    foreach ($name in @(
      'Test-DotfilesPSReadLineInteractive'
      'Test-DotfilesVSCodeTerminal'
      'Get-DotfilesPSReadLineModule'
      'Test-DotfilesPSReadLineDeferredHost'
      'Test-DotfilesPSReadLineReady'
      'Get-DotfilesPSReadLineSettings'
      'Set-DotfilesPSReadLineSettings'
      'Register-DotfilesPSReadLineOnIdleAction'
      'Invoke-DotfilesPSReadLineStartupAction'
      'Initialize-DotfilesPSReadLineOptions'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }

    Remove-Variable DotfilesPSReadLineOnIdleActions -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable DotfilesPSReadLineOnIdleRegistered -Scope Global -ErrorAction SilentlyContinue
  }

  It 'sets $skipChords to $true when in VS Code terminal' {
    $env:TERM_PROGRAM = 'vscode'
    (Test-DotfilesVSCodeTerminal) | Should -BeTrue
  }

  It 'sets $skipChords to $false when not in VS Code terminal' {
    $env:TERM_PROGRAM = $null
    (Test-DotfilesVSCodeTerminal) | Should -BeFalse
  }

  It 'skips chord bindings when running inside VS Code' {
    $env:TERM_PROGRAM = 'vscode'

    function Set-PsFzfOption {
      param(
        [string]$PSReadlineChordProvider,
        [string]$PSReadlineChordReverseHistory
      )
    }

    Mock Get-Command { [pscustomobject]@{ Name = 'fzf' } } -ParameterFilter {
      $Name -eq 'fzf'
    }
    Mock Get-Module { [pscustomobject]@{ Name = 'PSFzf' } } -ParameterFilter {
      $Name -eq 'PSFzf' -and $ListAvailable
    }
    Mock Import-Module { }
    Mock Set-PsFzfOption { }

    . $script:Subject

    Assert-MockCalled Set-PsFzfOption -Times 0
  }
}
