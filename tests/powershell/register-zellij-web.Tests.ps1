# Tests for the Windows Zellij Web task registration script.
# Exercises: wrapper path resolution, shell lookup, logon-task registration,
# disable cleanup, and unsupported mode handling.

BeforeAll {
  $script:Fixture = Join-Path $PSScriptRoot 'fixtures/register-zellij-web.ps1'
}

Describe 'register-zellij-web' -Skip:($IsWindows -eq $false) {

  BeforeEach {
    $script:OriginalHome = $HOME
    $script:OriginalSkip = $env:DOTFILES_TEST_ZELLIJ_WEB_SKIP_REGISTER
    $env:DOTFILES_TEST_ZELLIJ_WEB_SKIP_REGISTER = '1'

    $homeRoot = (New-Item -ItemType Directory -Path 'TestDrive:\home' -Force).FullName
    Set-Variable -Name HOME -Value $homeRoot -Scope Global -Force

    . $script:Fixture
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    $env:DOTFILES_TEST_ZELLIJ_WEB_SKIP_REGISTER = $script:OriginalSkip

    foreach ($name in @(
      'Get-DotfilesZellijWebTaskName'
      'Get-DotfilesZellijWebCurrentUser'
      'Get-DotfilesPreferredPowerShell'
      'Get-DotfilesZellijWebWrapperPath'
      'Get-DotfilesZellijWebTaskDescription'
      'Invoke-DotfilesZellijWebTaskRegistration'
      'Register-DotfilesZellijWebTask'
      'Unregister-DotfilesZellijWebTaskIfPresent'
      'Set-DotfilesZellijWebTaskAutostart'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  It 'builds the wrapper path under ~/.local/bin' {
    Get-DotfilesZellijWebWrapperPath |
      Should -Be (Join-Path (Join-Path (Join-Path $HOME '.local') 'bin') 'ensure-zellij-web.ps1')
  }

  It 'prefers pwsh before Windows PowerShell' {
    Mock Get-Command {
      [pscustomobject]@{ Path = 'TestDrive:\pwsh.exe' }
    } -ParameterFilter { $Name -eq 'pwsh' }
    Mock Get-Command {
      [pscustomobject]@{ Path = 'TestDrive:\powershell.exe' }
    } -ParameterFilter { $Name -eq 'powershell' }

    Get-DotfilesPreferredPowerShell | Should -Be 'TestDrive:\pwsh.exe'
  }

  It 'registers an interactive logon task when autostart is enabled' {
    $wrapperPath = Join-Path (Join-Path (Join-Path $HOME '.local') 'bin') 'ensure-zellij-web.ps1'
    New-Item -ItemType Directory -Path (Split-Path $wrapperPath) -Force | Out-Null
    New-Item -ItemType File -Path $wrapperPath -Force | Out-Null

    Set-Item Function:\Get-DotfilesZellijWebCurrentUser { 'TEST\User' }
    Set-Item Function:\Get-DotfilesPreferredPowerShell { 'TestDrive:\pwsh.exe' }

    Mock New-ScheduledTaskAction {
      [pscustomobject]@{
        Execute = $Execute
        Argument = $Argument
      }
    }
    Mock New-ScheduledTaskTrigger {
      [pscustomobject]@{
        User = $User
      }
    }
    Mock New-ScheduledTaskPrincipal {
      [pscustomobject]@{
        UserId = $UserId
        LogonType = $LogonType
        RunLevel = $RunLevel
      }
    }
    Mock Invoke-DotfilesZellijWebTaskRegistration { }

    Set-DotfilesZellijWebTaskAutostart -AutostartMode 'onlogon'

    Assert-MockCalled New-ScheduledTaskTrigger -Times 1 -ParameterFilter {
      $User -eq 'TEST\User'
    }
    Assert-MockCalled New-ScheduledTaskPrincipal -Times 1 -ParameterFilter {
      $UserId -eq 'TEST\User' -and
      $LogonType -eq 'Interactive' -and
      $RunLevel -eq 'Limited'
    }
    Assert-MockCalled Invoke-DotfilesZellijWebTaskRegistration -Times 1 -ParameterFilter {
      $Action.Execute -eq 'TestDrive:\pwsh.exe' -and
      $Trigger.User -eq 'TEST\User' -and
      $Principal.UserId -eq 'TEST\User' -and
      $Principal.LogonType -eq 'Interactive' -and
      $Principal.RunLevel -eq 'Limited'
    }
  }

  It 'removes the task when autostart is disabled' {
    Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = 'dotfiles-zellij-web' } }
    Mock Unregister-ScheduledTask { }

    Set-DotfilesZellijWebTaskAutostart -AutostartMode 'disabled'

    Assert-MockCalled Unregister-ScheduledTask -Times 1 -ParameterFilter {
      $TaskName -eq 'dotfiles-zellij-web' -and
      $Confirm -eq $false
    }
  }

  It 'does nothing when disabling an already absent task' {
    Mock Get-ScheduledTask { throw 'missing' }
    Mock Unregister-ScheduledTask { }

    { Set-DotfilesZellijWebTaskAutostart -AutostartMode 'disabled' } | Should -Not -Throw
    Assert-MockCalled Unregister-ScheduledTask -Times 0
  }

  It 'throws for unsupported autostart modes' {
    { Set-DotfilesZellijWebTaskAutostart -AutostartMode 'boot' } |
      Should -Throw 'Unsupported zellij.web.windows.autostart mode: boot'
  }
}
