# Tests for the PowerShell git profile generator script.
# Exercises: directory creation, profile file content, GPG sections,
# orphan removal, preservation of valid files, and idempotency.

BeforeAll {
  $script:Fixture = Join-Path $PSScriptRoot 'fixtures/generate-git-profiles.ps1'
}

Describe 'generate-git-profiles' {

  BeforeEach {
    # Isolate every test: point PROFILES_DIR at a fresh TestDrive path.
    $env:PROFILES_DIR = 'TestDrive:\profiles'
  }

  AfterEach {
    $env:PROFILES_DIR = $null
  }

  # -------------------------------------------------------------------------
  # Directory creation
  # -------------------------------------------------------------------------

  Context 'directory creation' {
    It 'creates the profiles directory when absent' {
      & $script:Fixture
      'TestDrive:\profiles' | Should -Exist
    }

    It 'succeeds when the profiles directory already exists' {
      New-Item -ItemType Directory -Path 'TestDrive:\profiles' -Force | Out-Null
      { & $script:Fixture } | Should -Not -Throw
    }
  }

  # -------------------------------------------------------------------------
  # Profile file creation
  # -------------------------------------------------------------------------

  Context 'profile file creation' {
    BeforeAll {
      # BeforeAll runs before any BeforeEach, so set PROFILES_DIR explicitly
      # rather than relying on the outer BeforeEach.
      $env:PROFILES_DIR = 'TestDrive:\profiles-content'
      & $script:Fixture
    }

    AfterAll {
      $env:PROFILES_DIR = $null
    }

    It 'creates the personal profile file' {
      'TestDrive:\profiles-content\personal' | Should -Exist
    }

    It 'personal profile contains the correct email' {
      Get-Content 'TestDrive:\profiles-content\personal' | Should -Contain '  email = "personal@example.com"'
    }

    It 'personal profile contains the correct name' {
      Get-Content 'TestDrive:\profiles-content\personal' | Should -Contain '  name = "Personal User"'
    }

    It 'personal profile has no GPG signing fields' {
      Get-Content 'TestDrive:\profiles-content\personal' | Should -Not -Contain 'gpgsign = true'
    }

    It 'creates the work profile file' {
      'TestDrive:\profiles-content\work' | Should -Exist
    }

    It 'work profile contains the correct email' {
      Get-Content 'TestDrive:\profiles-content\work' | Should -Contain '  email = "work@example.com"'
    }

    It 'work profile contains the correct name' {
      Get-Content 'TestDrive:\profiles-content\work' | Should -Contain '  name = "Work User"'
    }

    It 'work profile contains the signingkey' {
      Get-Content 'TestDrive:\profiles-content\work' | Should -Contain '  signingkey = "ABCD1234ABCD1234"'
    }

    It 'work profile has GPG commit signing enabled' {
      Get-Content 'TestDrive:\profiles-content\work' | Should -Contain '  gpgsign = true'
    }
  }

  # -------------------------------------------------------------------------
  # Orphan removal
  # -------------------------------------------------------------------------

  Context 'orphan removal' {
    It 'removes orphaned profile files' {
      New-Item -ItemType Directory -Path 'TestDrive:\profiles' -Force | Out-Null
      New-Item -ItemType File -Path 'TestDrive:\profiles\orphan' -Force | Out-Null
      & $script:Fixture
      'TestDrive:\profiles\orphan' | Should -Not -Exist
    }

    It 'does not remove valid profile files' {
      & $script:Fixture
      'TestDrive:\profiles\personal' | Should -Exist
      'TestDrive:\profiles\work'     | Should -Exist
    }
  }

  # -------------------------------------------------------------------------
  # Idempotency
  # -------------------------------------------------------------------------

  Context 'idempotency' {
    It 'running twice produces identical file contents' {
      & $script:Fixture
      $personal1 = Get-Content 'TestDrive:\profiles\personal' -Raw
      $work1     = Get-Content 'TestDrive:\profiles\work'     -Raw

      & $script:Fixture
      Get-Content 'TestDrive:\profiles\personal' -Raw | Should -Be $personal1
      Get-Content 'TestDrive:\profiles\work'     -Raw | Should -Be $work1
    }

    It 'orphaned files from a prior run are still removed on the second run' {
      New-Item -ItemType Directory -Path 'TestDrive:\profiles' -Force | Out-Null
      New-Item -ItemType File -Path 'TestDrive:\profiles\stale' -Force | Out-Null
      & $script:Fixture
      & $script:Fixture
      'TestDrive:\profiles\stale' | Should -Not -Exist
    }
  }
}
