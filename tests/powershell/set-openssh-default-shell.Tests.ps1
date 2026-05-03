# Tests for the OpenSSH default shell configuration script.
# Exercises: admin elevation check, preferred shell lookup,
# registry set/reset operations, and main-block guard behaviour.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/dot_local/bin/executable_set-openssh-default-shell.ps1'
}

Describe 'set-openssh-default-shell' -Skip:($IsWindows -eq $false) {

  BeforeEach {
    $script:OriginalSkip = $env:DOTFILES_TEST_OPENSSH_SHELL_SKIP_MAIN
    $env:DOTFILES_TEST_OPENSSH_SHELL_SKIP_MAIN = '1'
    . $script:Subject
  }

  AfterEach {
    $env:DOTFILES_TEST_OPENSSH_SHELL_SKIP_MAIN = $script:OriginalSkip

    foreach ($name in @(
      'Test-DotfilesAdminElevation'
      'Get-DotfilesPreferredShell'
      'Set-DotfilesOpenSSHDefaultShell'
      'Reset-DotfilesOpenSSHDefaultShell'
      'Restart-DotfilesSshdService'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  It 'Test-DotfilesAdminElevation returns false for non-elevated session' {
    Test-DotfilesAdminElevation | Should -BeFalse
  }

  It 'Get-DotfilesPreferredShell finds pwsh when available' {
    Mock Get-Command {
      [pscustomobject]@{ Source = 'TestDrive:\pwsh.exe' }
    } -ParameterFilter { $Name -eq 'pwsh' }

    Get-DotfilesPreferredShell | Should -Be 'TestDrive:\pwsh.exe'
  }

  It 'Get-DotfilesPreferredShell falls back to powershell when pwsh unavailable' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'pwsh' }
    Mock Get-Command {
      [pscustomobject]@{ Source = 'TestDrive:\powershell.exe' }
    } -ParameterFilter { $Name -eq 'powershell' }

    Get-DotfilesPreferredShell | Should -Be 'TestDrive:\powershell.exe'
  }

  It 'Get-DotfilesPreferredShell throws when no shell available' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'pwsh' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'powershell' }

    { Get-DotfilesPreferredShell } |
      Should -Throw 'Neither pwsh nor powershell found on this system.'
  }

  It 'Set-DotfilesOpenSSHDefaultShell creates key and sets registry values' {
    Mock Test-Path { $false } -ParameterFilter {
      $LiteralPath -eq 'HKLM:\SOFTWARE\OpenSSH'
    }
    Mock New-Item { } -ParameterFilter {
      $Path -eq 'HKLM:\SOFTWARE\OpenSSH'
    }
    Mock New-ItemProperty { }

    Set-DotfilesOpenSSHDefaultShell -ShellPath 'C:\pwsh.exe'

    Assert-MockCalled New-Item -Times 1
    Assert-MockCalled New-ItemProperty -Times 1 -ParameterFilter {
      $Name -eq 'DefaultShell' -and $Value -eq 'C:\pwsh.exe'
    }
    Assert-MockCalled New-ItemProperty -Times 1 -ParameterFilter {
      $Name -eq 'DefaultShellCommandOption' -and
      $Value -eq '-NoLogo -NoProfile'
    }
  }

  It 'Set-DotfilesOpenSSHDefaultShell skips key creation when it exists' {
    Mock Test-Path { $true } -ParameterFilter {
      $LiteralPath -eq 'HKLM:\SOFTWARE\OpenSSH'
    }
    Mock New-Item { }
    Mock New-ItemProperty { }

    Set-DotfilesOpenSSHDefaultShell -ShellPath 'C:\pwsh.exe'

    Assert-MockCalled New-Item -Times 0
    Assert-MockCalled New-ItemProperty -Times 2
  }

  It 'Reset-DotfilesOpenSSHDefaultShell removes registry values' {
    Mock Test-Path { $true } -ParameterFilter {
      $LiteralPath -eq 'HKLM:\SOFTWARE\OpenSSH'
    }
    Mock Get-Item {
      $mock = [pscustomobject]@{}
      $mock | Add-Member -MemberType ScriptMethod -Name GetValue -Value {
        param($name, $default)
        if ($name -eq 'DefaultShell') { return 'C:\pwsh.exe' }
        if ($name -eq 'DefaultShellCommandOption') { return '-NoLogo' }
        return $default
      }
      return $mock
    } -ParameterFilter {
      $LiteralPath -eq 'HKLM:\SOFTWARE\OpenSSH'
    }
    Mock Remove-ItemProperty { }

    Reset-DotfilesOpenSSHDefaultShell

    Assert-MockCalled Remove-ItemProperty -Times 1 -ParameterFilter {
      $Name -eq 'DefaultShell'
    }
    Assert-MockCalled Remove-ItemProperty -Times 1 -ParameterFilter {
      $Name -eq 'DefaultShellCommandOption'
    }
  }

  It 'Reset-DotfilesOpenSSHDefaultShell does nothing when key is absent' {
    Mock Test-Path { $false } -ParameterFilter {
      $LiteralPath -eq 'HKLM:\SOFTWARE\OpenSSH'
    }
    Mock Remove-ItemProperty { }

    Reset-DotfilesOpenSSHDefaultShell

    Assert-MockCalled Remove-ItemProperty -Times 0
  }
}
