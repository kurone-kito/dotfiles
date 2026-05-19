# Tests for the OpenSSH administrator authorized_keys sync helper.
# Exercises: admin elevation helper reuse, source path resolution,
# destination creation, copy flow, and ACL resets.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/dot_local/bin/executable_sync-openssh-authorized-keys.ps1'
}

Describe 'sync-openssh-authorized-keys' -Skip:($IsWindows -eq $false) {

  BeforeEach {
    $script:OriginalSkip = $env:DOTFILES_TEST_OPENSSH_AUTHORIZED_KEYS_SKIP_MAIN
    $script:OriginalHome = $HOME
    $env:DOTFILES_TEST_OPENSSH_AUTHORIZED_KEYS_SKIP_MAIN = '1'
    Set-Variable -Name HOME -Value 'TestDrive:\home' -Scope Global -Force
    $global:DotfilesTestIcaclsArgs = $null
    . $script:Subject

    function global:icacls {
      $global:DotfilesTestIcaclsArgs = @($args)
      $global:LASTEXITCODE = 0
    }
  }

  AfterEach {
    $env:DOTFILES_TEST_OPENSSH_AUTHORIZED_KEYS_SKIP_MAIN = $script:OriginalSkip
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force

    foreach ($name in @(
      'Test-DotfilesAdminElevation'
      'Get-DotfilesAuthorizedKeysSource'
      'Sync-DotfilesAdministratorsAuthorizedKeys'
      'icacls'
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

  It 'Get-DotfilesAuthorizedKeysSource uses the default per-user path' {
    Get-DotfilesAuthorizedKeysSource |
      Should -Be 'TestDrive:\home\.ssh\authorized_keys'
  }

  It 'Sync-DotfilesAdministratorsAuthorizedKeys copies the file and resets ACLs' {
    Mock Test-Path { $true } -ParameterFilter {
      $LiteralPath -eq 'TestDrive:\home\.ssh\authorized_keys' -and
      $PathType -eq 'Leaf'
    }
    Mock Test-Path { $false } -ParameterFilter {
      $LiteralPath -eq 'TestDrive:\ProgramData\ssh' -and
      $PathType -eq 'Container'
    }
    Mock New-Item { }
    Mock Copy-Item { }

    Sync-DotfilesAdministratorsAuthorizedKeys `
      -SourcePath 'TestDrive:\home\.ssh\authorized_keys' `
      -DestinationPath 'TestDrive:\ProgramData\ssh\administrators_authorized_keys' |
      Should -Be 'TestDrive:\ProgramData\ssh\administrators_authorized_keys'

    Assert-MockCalled New-Item -Times 1 -ParameterFilter {
      $ItemType -eq 'Directory' -and
      $Path -eq 'TestDrive:\ProgramData\ssh'
    }
    Assert-MockCalled Copy-Item -Times 1 -ParameterFilter {
      $LiteralPath -eq 'TestDrive:\home\.ssh\authorized_keys' -and
      $Destination -eq 'TestDrive:\ProgramData\ssh\administrators_authorized_keys' -and
      $Force
    }
    $global:DotfilesTestIcaclsArgs | Should -Contain '*S-1-5-32-544:(F)'
    $global:DotfilesTestIcaclsArgs | Should -Contain '*S-1-5-18:(F)'
  }

  It 'Sync-DotfilesAdministratorsAuthorizedKeys throws when the source file is missing' {
    Mock Test-Path { $false } -ParameterFilter {
      $LiteralPath -eq 'TestDrive:\home\.ssh\authorized_keys' -and
      $PathType -eq 'Leaf'
    }

    {
      Sync-DotfilesAdministratorsAuthorizedKeys `
        -SourcePath 'TestDrive:\home\.ssh\authorized_keys'
    } | Should -Throw 'Source authorized_keys not found: TestDrive:\home\.ssh\authorized_keys'
  }
}
