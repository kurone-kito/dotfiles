# Tests for the Zellij Web ensure script.
# Exercises: command lookup, fallback resolution, and idempotent start flow.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot 'fixtures/ensure-zellij-web.ps1'
}

Describe 'ensure-zellij-web' {

  BeforeEach {
    $script:OriginalSkipInit = $env:DOTFILES_TEST_ZELLIJ_WEB_SKIP_INIT
    $script:OriginalLocalAppData = $env:LOCALAPPDATA
    $env:DOTFILES_TEST_ZELLIJ_WEB_SKIP_INIT = '1'
    . $script:Subject
  }

  AfterEach {
    $env:DOTFILES_TEST_ZELLIJ_WEB_SKIP_INIT = $script:OriginalSkipInit
    $env:LOCALAPPDATA = $script:OriginalLocalAppData

    foreach ($name in @(
      'Get-DotfilesZellijCommand'
      'Test-DotfilesZellijWebRunning'
      'Start-DotfilesZellijWeb'
      'Ensure-DotfilesZellijWeb'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  It 'prefers the zellij command from PATH' {
    Mock Get-Command {
      [pscustomobject]@{ Path = 'TestDrive:\zellij.exe' }
    } -ParameterFilter { $Name -eq 'zellij' }

    Get-DotfilesZellijCommand | Should -Be 'TestDrive:\zellij.exe'
  }

  It 'falls back to the WinGet-installed zellij path when PATH lookup fails' {
    $env:LOCALAPPDATA = 'TestDrive:\LocalAppData'
    $fallback = Join-Path $env:LOCALAPPDATA 'Zellij\zellij.exe'
    New-Item -ItemType Directory -Path (Split-Path $fallback) -Force | Out-Null
    New-Item -ItemType File -Path $fallback -Force | Out-Null

    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'zellij' }

    Get-DotfilesZellijCommand | Should -Be $fallback
  }

  It 'does not start zellij web when it is already running' {
    Set-Item Function:\Get-DotfilesZellijCommand {
      'TestDrive:\zellij.exe'
    }
    Set-Item Function:\Test-DotfilesZellijWebRunning {
      param([string]$ZellijCommand)
      $true
    }
    Set-Item Function:\Start-DotfilesZellijWeb {
      throw 'should not start'
    }

    Ensure-DotfilesZellijWeb | Should -BeFalse
  }

  It 'starts zellij web when it is offline and verifies health afterwards' {
    $script:StatusChecks = 0
    $script:StartCalls = 0

    Set-Item Function:\Get-DotfilesZellijCommand {
      'TestDrive:\zellij.exe'
    }
    Set-Item Function:\Test-DotfilesZellijWebRunning {
      param([string]$ZellijCommand)
      $script:StatusChecks++
      return ($script:StatusChecks -ge 2)
    }
    Set-Item Function:\Start-DotfilesZellijWeb {
      param([string]$ZellijCommand)
      $script:StartCalls++
    }

    Ensure-DotfilesZellijWeb | Should -BeTrue
    $script:StartCalls | Should -Be 1
    $script:StatusChecks | Should -Be 2
  }
}
