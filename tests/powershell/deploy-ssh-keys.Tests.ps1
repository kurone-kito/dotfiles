# Tests for the PowerShell SSH key deployment script.
# Exercises: BOM-less UTF-8 encoding (PS5.1-compatible), exact byte
# preservation (no added trailing newline), skip-if-exists behavior,
# and the Windows ACL restriction applied to private keys only.

BeforeAll {
  $script:Fixture = Join-Path $PSScriptRoot 'fixtures/deploy-ssh-keys.ps1'
}

Describe 'deploy-ssh-keys' {

  BeforeEach {
    $script:OriginalHome = $HOME
    $script:OriginalUserName = $env:USERNAME
    $script:HomeDir = 'TestDrive:\home'
    if (Test-Path $script:HomeDir) {
      Remove-Item $script:HomeDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $script:HomeDir -Force | Out-Null
    Set-Variable -Name HOME -Value $script:HomeDir -Scope Global -Force
    $env:USERNAME = 'sample-user'
    $global:DotfilesTestIcaclsCalls = @()

    function global:icacls {
      $global:DotfilesTestIcaclsCalls += , @($args)
      $global:LASTEXITCODE = 0
    }

    $script:SshDirReal = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
      (Join-Path $script:HomeDir '.ssh'))
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    $env:USERNAME = $script:OriginalUserName
    Remove-Item Function:\icacls -ErrorAction SilentlyContinue
  }

  It 'writes both key files with no BOM' {
    & $script:Fixture | Out-Null

    $privateBytes = [System.IO.File]::ReadAllBytes((Join-Path $script:SshDirReal 'id_secondary'))
    $publicBytes = [System.IO.File]::ReadAllBytes((Join-Path $script:SshDirReal 'id_secondary.pub'))

    # A UTF-8 BOM is the 3-byte sequence EF BB BF; neither file should
    # start with it.
    ($privateBytes.Length -ge 3 -and $privateBytes[0] -eq 0xEF -and
      $privateBytes[1] -eq 0xBB -and $privateBytes[2] -eq 0xBF) | Should -BeFalse
    ($publicBytes.Length -ge 3 -and $publicBytes[0] -eq 0xEF -and
      $publicBytes[1] -eq 0xBB -and $publicBytes[2] -eq 0xBF) | Should -BeFalse
  }

  It 'writes exact byte-for-byte content with no added trailing newline' {
    & $script:Fixture | Out-Null

    $expectedPrivate = 'TEST-ONLY-PRIVATE-KEY-CONTENT-secondary'
    $expectedPublic = 'ssh-ed25519 AAAASECONDARY secondary@test'
    $expectedPrivateBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($expectedPrivate)
    $expectedPublicBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($expectedPublic)

    $actualPrivateBytes = [System.IO.File]::ReadAllBytes((Join-Path $script:SshDirReal 'id_secondary'))
    $actualPublicBytes = [System.IO.File]::ReadAllBytes((Join-Path $script:SshDirReal 'id_secondary.pub'))

    [System.Linq.Enumerable]::SequenceEqual($actualPrivateBytes, $expectedPrivateBytes) | Should -BeTrue
    [System.Linq.Enumerable]::SequenceEqual($actualPublicBytes, $expectedPublicBytes) | Should -BeTrue
  }

  It 'preserves embedded newlines in multi-line key content exactly' {
    & $script:Fixture | Out-Null

    $expected = "TEST-ONLY-PRIVATE-KEY-CONTENT-primary`nline two"
    $expectedBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($expected)
    $actualBytes = [System.IO.File]::ReadAllBytes((Join-Path $script:SshDirReal 'id_primary'))

    [System.Linq.Enumerable]::SequenceEqual($actualBytes, $expectedBytes) | Should -BeTrue
  }

  It 'writes both key pairs for multiple configured keys' {
    & $script:Fixture | Out-Null

    Join-Path $script:SshDirReal 'id_primary' | Should -Exist
    Join-Path $script:SshDirReal 'id_primary.pub' | Should -Exist
    Join-Path $script:SshDirReal 'id_secondary' | Should -Exist
    Join-Path $script:SshDirReal 'id_secondary.pub' | Should -Exist
  }

  It 'restricts private key permissions to the current user via icacls' {
    & $script:Fixture | Out-Null

    # @(...) forces array semantics: Where-Object unwraps a single
    # matching element when that element is itself an array, which
    # would otherwise make .Count report the inner args count instead
    # of the number of matching icacls calls.
    $privateCalls = @($global:DotfilesTestIcaclsCalls |
      Where-Object { $_ -contains (Join-Path $script:SshDirReal 'id_primary') })
    $privateCalls.Count | Should -Be 1
    $privateCalls[0] | Should -Contain 'sample-user:(F)'
  }

  It 'does not run icacls against the public key' {
    & $script:Fixture | Out-Null

    $publicCalls = @($global:DotfilesTestIcaclsCalls |
      Where-Object { $_ -contains (Join-Path $script:SshDirReal 'id_primary.pub') })
    $publicCalls.Count | Should -Be 0
  }

  It 'skips writing a key that already exists' {
    New-Item -ItemType Directory -Path $script:SshDirReal -Force | Out-Null
    $existingPath = Join-Path $script:SshDirReal 'id_primary'
    [System.IO.File]::WriteAllText($existingPath, 'PRE-EXISTING-CONTENT',
      [System.Text.UTF8Encoding]::new($false))

    & $script:Fixture | Out-Null

    $content = [System.IO.File]::ReadAllText($existingPath)
    $content | Should -Be 'PRE-EXISTING-CONTENT'
  }

  It 'produces no diff when re-run with keys already deployed' {
    & $script:Fixture | Out-Null
    $before = [System.IO.File]::ReadAllBytes((Join-Path $script:SshDirReal 'id_primary'))

    & $script:Fixture | Out-Null
    $after = [System.IO.File]::ReadAllBytes((Join-Path $script:SshDirReal 'id_primary'))

    [System.Linq.Enumerable]::SequenceEqual($before, $after) | Should -BeTrue
  }
}
