# Tests for the PowerShell environment configuration script.
# Exercises: preserved PSReadLine defaults, startup-action flow,
# deferred OnIdle registration, and duplicate-registration guards.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '00-env.ps1'
}

Describe '00-env' {

  BeforeEach {
    $script:OriginalSkipInit = $env:DOTFILES_TEST_PSREADLINE_SKIP_INIT
    $env:DOTFILES_TEST_PSREADLINE_SKIP_INIT = '1'
    . $script:Subject
  }

  AfterEach {
    $env:DOTFILES_TEST_PSREADLINE_SKIP_INIT = $script:OriginalSkipInit

    foreach ($name in @(
      'Test-DotfilesPSReadLineInteractive'
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

  It 'uses the preserved Emacs edit mode and History prediction for PSReadLine 2.2+' {
    $settings = Get-DotfilesPSReadLineSettings -Module ([pscustomobject]@{
      Version = [version]'2.4.5'
    })

    $settings.EditMode | Should -Be 'Emacs'
    $settings.HistoryNoDuplicates | Should -BeTrue
    $settings.PredictionSource | Should -Be 'History'
  }

  It 'omits PredictionSource for PSReadLine older than 2.2' {
    $settings = Get-DotfilesPSReadLineSettings -Module ([pscustomobject]@{
      Version = [version]'2.1.0'
    })

    $settings.PredictionSource | Should -BeNullOrEmpty
  }

  It 'applies startup actions immediately in a ready non-psmux host' {
    $script:ImmediateCalls = 0
    $script:DeferredCalls = @()

    Set-Item Function:\Test-DotfilesPSReadLineInteractive {
      $true
    }
    Set-Item Function:\Get-DotfilesPSReadLineModule {
      [pscustomobject]@{ Version = [version]'2.4.5' }
    }
    Set-Item Function:\Test-DotfilesPSReadLineDeferredHost {
      $false
    }
    Set-Item Function:\Test-DotfilesPSReadLineReady {
      $true
    }
    Set-Item Function:\Register-DotfilesPSReadLineOnIdleAction {
      param([string]$Name, [scriptblock]$Action)
      $script:DeferredCalls += $Name
      $true
    }

    $applied = Invoke-DotfilesPSReadLineStartupAction -Name 'options' -Action {
      $script:ImmediateCalls++
      $true
    }

    $applied | Should -BeTrue
    $script:ImmediateCalls | Should -Be 1
    $script:DeferredCalls | Should -HaveCount 0
  }

  It 'registers deferred startup actions when PSReadLine is not ready yet' {
    $script:ImmediateCalls = 0
    $script:DeferredCalls = @()

    Set-Item Function:\Test-DotfilesPSReadLineInteractive {
      $true
    }
    Set-Item Function:\Get-DotfilesPSReadLineModule {
      [pscustomobject]@{ Version = [version]'2.4.5' }
    }
    Set-Item Function:\Test-DotfilesPSReadLineDeferredHost {
      $false
    }
    Set-Item Function:\Test-DotfilesPSReadLineReady {
      $false
    }
    Set-Item Function:\Register-DotfilesPSReadLineOnIdleAction {
      param([string]$Name, [scriptblock]$Action)
      $script:DeferredCalls += $Name
      $true
    }

    $applied = Invoke-DotfilesPSReadLineStartupAction -Name 'options' -Action {
      $script:ImmediateCalls++
      $true
    }

    $applied | Should -BeFalse
    $script:ImmediateCalls | Should -Be 0
    $script:DeferredCalls | Should -HaveCount 1
  }

  It 'registers deferred startup actions for psmux even after immediate apply' {
    $script:ImmediateCalls = 0
    $script:DeferredCalls = @()

    Set-Item Function:\Test-DotfilesPSReadLineInteractive {
      $true
    }
    Set-Item Function:\Get-DotfilesPSReadLineModule {
      [pscustomobject]@{ Version = [version]'2.4.5' }
    }
    Set-Item Function:\Test-DotfilesPSReadLineDeferredHost {
      $true
    }
    Set-Item Function:\Test-DotfilesPSReadLineReady {
      $true
    }
    Set-Item Function:\Register-DotfilesPSReadLineOnIdleAction {
      param([string]$Name, [scriptblock]$Action)
      $script:DeferredCalls += $Name
      $true
    }

    $applied = Invoke-DotfilesPSReadLineStartupAction -Name 'options' -Action {
      $script:ImmediateCalls++
      $true
    }

    $applied | Should -BeTrue
    $script:ImmediateCalls | Should -Be 1
    $script:DeferredCalls | Should -HaveCount 1
  }

  It 'passes PSReadLine option settings through the startup helper' {
    $script:StartupName = $null
    $script:AppliedSettings = @()

    Set-Item Function:\Get-DotfilesPSReadLineModule {
      [pscustomobject]@{ Version = [version]'2.4.5' }
    }
    Set-Item Function:\Invoke-DotfilesPSReadLineStartupAction {
      param([string]$Name, [scriptblock]$Action)
      $script:StartupName = $Name
      & $Action | Out-Null
      $true
    }
    Set-Item Function:\Set-DotfilesPSReadLineSettings {
      param([pscustomobject]$Settings)
      $script:AppliedSettings += $Settings
      $true
    }

    Initialize-DotfilesPSReadLineOptions

    $script:StartupName | Should -Be 'options'
    $script:AppliedSettings | Should -HaveCount 1
    $script:AppliedSettings[0].EditMode | Should -Be 'Emacs'
    $script:AppliedSettings[0].PredictionSource | Should -Be 'History'
  }

  It 'reuses a single OnIdle subscription for multiple startup actions' {
    Mock Register-EngineEvent { }

    Register-DotfilesPSReadLineOnIdleAction -Name 'options' -Action { $true }
    Register-DotfilesPSReadLineOnIdleAction -Name 'psfzf-chords' -Action { $true }

    Assert-MockCalled Register-EngineEvent -Times 1
    $global:DotfilesPSReadLineOnIdleRegistered | Should -BeTrue
    $global:DotfilesPSReadLineOnIdleActions.Keys |
      Should -Be @('options', 'psfzf-chords')
  }
}
