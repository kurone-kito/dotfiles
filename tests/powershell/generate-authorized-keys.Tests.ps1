# Tests for the PowerShell authorized_keys generator script.
# Exercises: file content generation, missing key handling, and the
# Windows ACL required for LocalSystem sshd reads.

BeforeAll {
  $script:Fixture = Join-Path $PSScriptRoot 'fixtures/generate-authorized-keys.ps1'
}

Describe 'generate-authorized-keys' {

  BeforeEach {
    $script:OriginalHome = $HOME
    $script:OriginalAuthorizedKeysHome = $env:AUTHORIZED_KEYS_HOME
    $script:OriginalUserName = $env:USERNAME
    $script:HomeDir = 'TestDrive:\home'
    if (Test-Path $script:HomeDir) {
      Remove-Item $script:HomeDir -Recurse -Force
    }
    $env:AUTHORIZED_KEYS_HOME = $script:HomeDir
    $env:USERNAME = 'sample-user'
    Set-Variable -Name HOME -Value $env:AUTHORIZED_KEYS_HOME -Scope Global -Force
    $global:DotfilesTestIcaclsArgs = $null

    function global:icacls {
      $global:DotfilesTestIcaclsArgs = @($args)
    }
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    $env:AUTHORIZED_KEYS_HOME = $script:OriginalAuthorizedKeysHome
    $env:USERNAME = $script:OriginalUserName
    Remove-Item Function:\icacls -ErrorAction SilentlyContinue
  }

  It 'creates authorized_keys from the available public keys' {
    $sshDir = New-Item -ItemType Directory -Path (Join-Path $script:HomeDir '.ssh') -Force
    'ssh-ed25519 AAAA primary@test' |
      Set-Content -Path (Join-Path $sshDir.FullName 'primary.pub') -Encoding utf8NoBOM
    'ssh-ed25519 BBBB secondary@test' |
      Set-Content -Path (Join-Path $sshDir.FullName 'secondary.pub') -Encoding utf8NoBOM

    & $script:Fixture

    Get-Content (Join-Path $sshDir.FullName 'authorized_keys') -Raw |
      Should -Be "ssh-ed25519 AAAA primary@test`nssh-ed25519 BBBB secondary@test"
    $global:DotfilesTestIcaclsArgs | Should -Contain '*S-1-5-18:(R)'
    $global:DotfilesTestIcaclsArgs | Should -Contain 'sample-user:(F)'
  }

  It 'skips missing public keys and keeps the remaining file content' {
    $sshDir = New-Item -ItemType Directory -Path (Join-Path $script:HomeDir '.ssh') -Force
    'ssh-ed25519 BBBB secondary@test' |
      Set-Content -Path (Join-Path $sshDir.FullName 'secondary.pub') -Encoding utf8NoBOM

    & $script:Fixture

    Get-Content (Join-Path $sshDir.FullName 'authorized_keys') -Raw |
      Should -Be 'ssh-ed25519 BBBB secondary@test'
  }

  It 'creates an empty authorized_keys file when no public keys exist' {
    New-Item -ItemType Directory -Path (Join-Path $script:HomeDir '.ssh') -Force | Out-Null

    & $script:Fixture

    (Join-Path $script:HomeDir '.ssh\authorized_keys') | Should -Exist
    Get-Content (Join-Path $script:HomeDir '.ssh\authorized_keys') -Raw |
      Should -BeNullOrEmpty
  }
}
