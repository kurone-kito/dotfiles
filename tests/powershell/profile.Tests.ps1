# Tests for the PowerShell profile conf.d loader and prompt setup.
# Uses a controlled, empty conf.d directory (via a $HOME override) so
# real conf.d scripts never run — only profile.ps1's own prompt/zoxide
# wiring below the loader loop is exercised.
# Exercises: the PSReadLine-readiness gate around the Starship
# transient-prompt function, and the zoxide-after-Starship init order.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell'
  ) 'profile.ps1'
}

Describe 'profile.ps1 prompt setup' {

  BeforeEach {
    $script:OriginalHome = $HOME
    $script:CallOrder = @()

    # An empty HOME means .config/powershell/conf.d does not exist,
    # so profile.ps1 skips real conf.d scripts and only its own
    # prompt/zoxide logic runs.
    $homeRoot = (New-Item -ItemType Directory -Path 'TestDrive:\home' -Force).FullName
    Set-Variable -Name HOME -Value $homeRoot -Scope Global -Force

    Set-Item Function:\starship {
      param([Parameter(ValueFromRemainingArguments = $true)][object[]] $Arguments)
      $script:CallOrder += 'starship'
      ''
    }
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force

    foreach ($name in @(
      'starship'
      'zoxide'
      'Test-DotfilesPSReadLineReady'
      'Invoke-Starship-TransientFunction'
      'Enable-TransientPrompt'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  It 'defines the transient-prompt function when the readiness helper reports ready' {
    Set-Item Function:\Test-DotfilesPSReadLineReady { $true }

    . $script:Subject

    Get-Command Invoke-Starship-TransientFunction -ErrorAction SilentlyContinue |
      Should -Not -BeNullOrEmpty
  }

  It 'does not define the transient-prompt function when the readiness helper reports not ready' {
    Set-Item Function:\Test-DotfilesPSReadLineReady { $false }

    . $script:Subject

    Get-Command Invoke-Starship-TransientFunction -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
  }

  It 'does not define the transient-prompt function when the readiness helper is unavailable and PSReadLine is not loaded' {
    Remove-Module PSReadLine -ErrorAction SilentlyContinue

    . $script:Subject

    Get-Command Invoke-Starship-TransientFunction -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
  }

  It 'initializes zoxide after Starship (Starship replaces $function:prompt, so zoxide must hook after)' {
    Set-Item Function:\zoxide {
      param([Parameter(ValueFromRemainingArguments = $true)][object[]] $Arguments)
      $script:CallOrder += 'zoxide'
      ''
    }
    Set-Item Function:\Test-DotfilesPSReadLineReady { $false }

    . $script:Subject

    $script:CallOrder | Should -Be @('starship', 'zoxide')
  }

  It 'skips zoxide initialization when zoxide is not installed' {
    Set-Item Function:\Test-DotfilesPSReadLineReady { $false }

    . $script:Subject

    $script:CallOrder | Should -Be @('starship')
  }
}
