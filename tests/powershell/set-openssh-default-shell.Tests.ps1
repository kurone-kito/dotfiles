# Tests for the OpenSSH default shell configuration script.
# Exercises: admin elevation check, registry set/reset operations, main-block
# guard behaviour, and the [data.ssh.server].defaultShell resolution table.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot 'fixtures/set-openssh-default-shell.ps1'
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
      'Test-DotfilesReparsePoint'
      'Resolve-DotfilesOpenSSHShellChoice'
      'Test-DotfilesExplicitShellPath'
      'Set-DotfilesOpenSSHDefaultShell'
      'Reset-DotfilesOpenSSHDefaultShell'
      'Restart-DotfilesSshdService'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  It 'Test-DotfilesAdminElevation returns false for non-elevated session' -Skip:(
    [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT -and
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator)
  ) {
    Test-DotfilesAdminElevation | Should -BeFalse
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

    Should -Invoke New-Item -Times 1
    Should -Invoke New-ItemProperty -Times 1 -ParameterFilter {
      $Name -eq 'DefaultShell' -and $Value -eq 'C:\pwsh.exe'
    }
    Should -Invoke New-ItemProperty -Times 1 -ParameterFilter {
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

    Should -Invoke New-Item -Times 0
    Should -Invoke New-ItemProperty -Times 2
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

    Should -Invoke Remove-ItemProperty -Times 1 -ParameterFilter {
      $Name -eq 'DefaultShell'
    }
    Should -Invoke Remove-ItemProperty -Times 1 -ParameterFilter {
      $Name -eq 'DefaultShellCommandOption'
    }
  }

  It 'Reset-DotfilesOpenSSHDefaultShell does nothing when key is absent' {
    Mock Test-Path { $false } -ParameterFilter {
      $LiteralPath -eq 'HKLM:\SOFTWARE\OpenSSH'
    }
    Mock Remove-ItemProperty { }

    Reset-DotfilesOpenSSHDefaultShell

    Should -Invoke Remove-ItemProperty -Times 0
  }
}

Describe 'Resolve-DotfilesOpenSSHShellChoice' {
  # Only exercises Get-Command mocks -- no registry or WindowsIdentity
  # access, so this Describe intentionally carries no Windows skip. It
  # must set up its own skip-main + dot-source, independent of the
  # Windows-only Describe above (which never runs on this platform).

  BeforeEach {
    $script:OriginalSkip = $env:DOTFILES_TEST_OPENSSH_SHELL_SKIP_MAIN
    $env:DOTFILES_TEST_OPENSSH_SHELL_SKIP_MAIN = '1'
    . $script:Subject
    $script:DotfilesOpenSSHDefaultShellChoice = ''
    $script:DotfilesOpenSSHDefaultShellFallbackToLegacy = $false
  }

  AfterEach {
    $env:DOTFILES_TEST_OPENSSH_SHELL_SKIP_MAIN = $script:OriginalSkip

    foreach ($name in @(
      'Test-DotfilesAdminElevation'
      'Test-DotfilesReparsePoint'
      'Resolve-DotfilesOpenSSHShellChoice'
      'Test-DotfilesExplicitShellPath'
      'Set-DotfilesOpenSSHDefaultShell'
      'Reset-DotfilesOpenSSHDefaultShell'
      'Restart-DotfilesSshdService'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  It 'resolves to a no-op when defaultShell is absent' {
    $script:DotfilesOpenSSHDefaultShellChoice = ''

    (Resolve-DotfilesOpenSSHShellChoice).Action | Should -Be 'NoOp'
  }

  It 'resolves "cmd" to a reset action' {
    $script:DotfilesOpenSSHDefaultShellChoice = 'cmd'

    (Resolve-DotfilesOpenSSHShellChoice).Action | Should -Be 'Reset'
  }

  It 'resolves "legacy-powershell" to powershell.exe when found' {
    Mock Get-Command {
      [pscustomobject]@{ Source = 'TestDrive:\powershell.exe' }
    } -ParameterFilter { $Name -eq 'powershell' }

    $script:DotfilesOpenSSHDefaultShellChoice = 'legacy-powershell'
    $resolution = Resolve-DotfilesOpenSSHShellChoice

    $resolution.Action | Should -Be 'Set'
    $resolution.ShellPath | Should -Be 'TestDrive:\powershell.exe'
  }

  It 'throws when "legacy-powershell" is requested but powershell.exe is missing' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'powershell' }

    $script:DotfilesOpenSSHDefaultShellChoice = 'legacy-powershell'

    { Resolve-DotfilesOpenSSHShellChoice } | Should -Throw '*powershell.exe*'
  }

  It 'resolves "modern-powershell" to pwsh.exe when found' {
    Mock Get-Command {
      [pscustomobject]@{ Source = 'TestDrive:\pwsh.exe' }
    } -ParameterFilter { $Name -eq 'pwsh' }

    $script:DotfilesOpenSSHDefaultShellChoice = 'modern-powershell'
    $resolution = Resolve-DotfilesOpenSSHShellChoice

    $resolution.Action | Should -Be 'Set'
    $resolution.ShellPath | Should -Be 'TestDrive:\pwsh.exe'
  }

  It 'throws when "modern-powershell" is requested, pwsh.exe is missing, and fallback is disabled' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'pwsh' }

    $script:DotfilesOpenSSHDefaultShellChoice = 'modern-powershell'
    $script:DotfilesOpenSSHDefaultShellFallbackToLegacy = $false

    { Resolve-DotfilesOpenSSHShellChoice } | Should -Throw '*pwsh.exe*'
  }

  It 'falls back to powershell.exe when "modern-powershell" is missing and fallback is enabled' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'pwsh' }
    Mock Get-Command {
      [pscustomobject]@{ Source = 'TestDrive:\powershell.exe' }
    } -ParameterFilter { $Name -eq 'powershell' }

    $script:DotfilesOpenSSHDefaultShellChoice = 'modern-powershell'
    $script:DotfilesOpenSSHDefaultShellFallbackToLegacy = $true
    $resolution = Resolve-DotfilesOpenSSHShellChoice

    $resolution.Action | Should -Be 'Set'
    $resolution.ShellPath | Should -Be 'TestDrive:\powershell.exe'
  }

  It 'throws when "modern-powershell" falls back but powershell.exe is also missing' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'pwsh' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'powershell' }

    $script:DotfilesOpenSSHDefaultShellChoice = 'modern-powershell'
    $script:DotfilesOpenSSHDefaultShellFallbackToLegacy = $true

    { Resolve-DotfilesOpenSSHShellChoice } | Should -Throw '*pwsh.exe*powershell.exe*'
  }

  It 'rejects a reparse-point pwsh.exe and throws when "modern-powershell" fallback is disabled' {
    Mock Get-Command {
      [pscustomobject]@{ Source = 'TestDrive:\pwsh.exe' }
    } -ParameterFilter { $Name -eq 'pwsh' }
    Mock Test-DotfilesReparsePoint { $true }

    $script:DotfilesOpenSSHDefaultShellChoice = 'modern-powershell'
    $script:DotfilesOpenSSHDefaultShellFallbackToLegacy = $false

    { Resolve-DotfilesOpenSSHShellChoice } |
      Should -Throw '*TestDrive:\pwsh.exe*App Execution Alias*setup.windows#147*'
  }

  It 'falls back to powershell.exe when the resolved "modern-powershell" pwsh.exe is a reparse point and fallback is enabled' {
    Mock Get-Command {
      [pscustomobject]@{ Source = 'TestDrive:\pwsh.exe' }
    } -ParameterFilter { $Name -eq 'pwsh' }
    Mock Get-Command {
      [pscustomobject]@{ Source = 'TestDrive:\powershell.exe' }
    } -ParameterFilter { $Name -eq 'powershell' }
    Mock Test-DotfilesReparsePoint { $true }

    $script:DotfilesOpenSSHDefaultShellChoice = 'modern-powershell'
    $script:DotfilesOpenSSHDefaultShellFallbackToLegacy = $true
    $resolution = Resolve-DotfilesOpenSSHShellChoice

    $resolution.Action | Should -Be 'Set'
    $resolution.ShellPath | Should -Be 'TestDrive:\powershell.exe'
  }

  It 'Test-DotfilesExplicitShellPath rejects a path that resolves to a reparse point' {
    Mock Test-Path { $true } -ParameterFilter {
      $LiteralPath -eq 'TestDrive:\pwsh.exe'
    }
    Mock Test-DotfilesReparsePoint { $true }

    $validation = Test-DotfilesExplicitShellPath -ShellPath 'TestDrive:\pwsh.exe'

    $validation.Valid | Should -BeFalse
    $validation.ErrorMessage |
      Should -BeLike '*TestDrive:\pwsh.exe*App Execution Alias*setup.windows#147*'
  }

  It 'throws listing all valid choices for an unrecognized defaultShell value' {
    $script:DotfilesOpenSSHDefaultShellChoice = 'bogus'

    { Resolve-DotfilesOpenSSHShellChoice } |
      Should -Throw '*cmd*legacy-powershell*modern-powershell*'
  }
}
