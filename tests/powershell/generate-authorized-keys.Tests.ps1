# Tests for the PowerShell authorized_keys generator script.
# Exercises: managed-block content generation, preservation of
# foreign out-of-band lines, block replacement, idempotency, and the
# Windows ACL required for LocalSystem sshd reads.

BeforeAll {
  $script:Fixture = Join-Path $PSScriptRoot 'fixtures/generate-authorized-keys.ps1'
  $script:BeginMarker = '# >>> chezmoi managed keys >>>'
  $script:EndMarker = '# <<< chezmoi managed keys <<<'
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

    $script:SshDir = New-Item -ItemType Directory -Path (Join-Path $script:HomeDir '.ssh') -Force
    $script:Authorized = Join-Path $script:SshDir.FullName 'authorized_keys'
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    $env:AUTHORIZED_KEYS_HOME = $script:OriginalAuthorizedKeysHome
    $env:USERNAME = $script:OriginalUserName
    Remove-Item Function:\icacls -ErrorAction SilentlyContinue
  }

  It 'creates a managed block from the available public keys' {
    'ssh-ed25519 AAAA primary@test' |
      Set-Content -Path (Join-Path $script:SshDir.FullName 'primary.pub') -Encoding utf8NoBOM
    'ssh-ed25519 BBBB secondary@test' |
      Set-Content -Path (Join-Path $script:SshDir.FullName 'secondary.pub') -Encoding utf8NoBOM

    & $script:Fixture

    $content = Get-Content $script:Authorized
    $content | Should -Contain $script:BeginMarker
    $content | Should -Contain $script:EndMarker
    $content | Should -Contain 'ssh-ed25519 AAAA primary@test'
    $content | Should -Contain 'ssh-ed25519 BBBB secondary@test'
    $global:DotfilesTestIcaclsArgs | Should -Contain '*S-1-5-18:(R)'
    $global:DotfilesTestIcaclsArgs | Should -Contain 'sample-user:(F)'
  }

  It 'skips missing public keys and keeps the remaining file content' {
    'ssh-ed25519 BBBB secondary@test' |
      Set-Content -Path (Join-Path $script:SshDir.FullName 'secondary.pub') -Encoding utf8NoBOM

    & $script:Fixture

    $content = Get-Content $script:Authorized
    $content | Should -Contain 'ssh-ed25519 BBBB secondary@test'
    $content | Should -Not -Contain 'ssh-ed25519 AAAA primary@test'
  }

  It 'creates an authorized_keys file with an empty managed block when no public keys exist' {
    & $script:Fixture

    $script:Authorized | Should -Exist
    $content = Get-Content $script:Authorized
    $content | Should -Contain $script:BeginMarker
    $content | Should -Contain $script:EndMarker
  }

  It 'preserves a foreign line that predates the managed block' {
    'ssh-rsa FOREIGN from-cloud-provider' | Set-Content -Path $script:Authorized -Encoding utf8NoBOM
    'ssh-ed25519 AAAA primary@test' |
      Set-Content -Path (Join-Path $script:SshDir.FullName 'primary.pub') -Encoding utf8NoBOM

    & $script:Fixture

    $content = Get-Content $script:Authorized
    $content | Should -Contain 'ssh-rsa FOREIGN from-cloud-provider'
    $content | Should -Contain 'ssh-ed25519 AAAA primary@test'
  }

  It 'preserves foreign lines on both sides of an existing managed block' {
    'ssh-ed25519 AAAA primary@test' |
      Set-Content -Path (Join-Path $script:SshDir.FullName 'primary.pub') -Encoding utf8NoBOM
    & $script:Fixture

    $existing = Get-Content $script:Authorized
    @('ssh-rsa FOREIGN-BEFORE ssh-copy-id') + $existing + @('ssh-rsa FOREIGN-AFTER manually-added') |
      Set-Content -Path $script:Authorized -Encoding utf8NoBOM

    'ssh-ed25519 BBBB secondary@test' |
      Set-Content -Path (Join-Path $script:SshDir.FullName 'secondary.pub') -Encoding utf8NoBOM
    & $script:Fixture

    $content = Get-Content $script:Authorized
    $content[0] | Should -Be 'ssh-rsa FOREIGN-BEFORE ssh-copy-id'
    $content[-1] | Should -Be 'ssh-rsa FOREIGN-AFTER manually-added'
    $content | Should -Contain 'ssh-ed25519 AAAA primary@test'
    $content | Should -Contain 'ssh-ed25519 BBBB secondary@test'
  }

  It 'removes a key from the managed block when it disappears from config' {
    'ssh-ed25519 AAAA primary@test' |
      Set-Content -Path (Join-Path $script:SshDir.FullName 'primary.pub') -Encoding utf8NoBOM
    'ssh-ed25519 BBBB secondary@test' |
      Set-Content -Path (Join-Path $script:SshDir.FullName 'secondary.pub') -Encoding utf8NoBOM
    & $script:Fixture

    Remove-Item (Join-Path $script:SshDir.FullName 'primary.pub')
    & $script:Fixture

    $content = Get-Content $script:Authorized
    $content | Should -Not -Contain 'ssh-ed25519 AAAA primary@test'
    $content | Should -Contain 'ssh-ed25519 BBBB secondary@test'
  }

  It 'produces no diff when re-run with unchanged keys' {
    'ssh-ed25519 AAAA primary@test' |
      Set-Content -Path (Join-Path $script:SshDir.FullName 'primary.pub') -Encoding utf8NoBOM
    & $script:Fixture
    $before = Get-Content $script:Authorized -Raw

    & $script:Fixture
    $after = Get-Content $script:Authorized -Raw

    $after | Should -Be $before
  }

  It 'falls back to append instead of dropping content when the end marker is missing' {
    @('ssh-rsa FOREIGN untouched', $script:BeginMarker, 'ssh-rsa STALE stale-key') |
      Set-Content -Path $script:Authorized -Encoding utf8NoBOM
    'ssh-ed25519 AAAA primary@test' |
      Set-Content -Path (Join-Path $script:SshDir.FullName 'primary.pub') -Encoding utf8NoBOM

    & $script:Fixture

    $content = Get-Content $script:Authorized
    $content | Should -Contain 'ssh-rsa FOREIGN untouched'
    $content | Should -Contain 'ssh-rsa STALE stale-key'
    $content | Should -Contain 'ssh-ed25519 AAAA primary@test'
  }

  It 'falls back to append instead of guessing when markers are duplicated' {
    @(
      $script:BeginMarker, 'ssh-rsa OLD1 old', $script:EndMarker,
      'ssh-rsa FOREIGN between-blocks',
      $script:BeginMarker, 'ssh-rsa OLD2 old', $script:EndMarker
    ) | Set-Content -Path $script:Authorized -Encoding utf8NoBOM
    'ssh-ed25519 AAAA primary@test' |
      Set-Content -Path (Join-Path $script:SshDir.FullName 'primary.pub') -Encoding utf8NoBOM

    & $script:Fixture

    $content = Get-Content $script:Authorized
    $content | Should -Contain 'ssh-rsa FOREIGN between-blocks'
    $content | Should -Contain 'ssh-ed25519 AAAA primary@test'
  }
}
